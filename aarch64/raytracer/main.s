// ═══════════════════════════════════════════════════════════════════
// Metal Ray Tracing Demo — Pure AArch64 Assembly on macOS
// ═══════════════════════════════════════════════════════════════════
//
// No C code. All Cocoa/Metal interaction via objc_msgSend.
// Loads raytrace.metallib for the GPU compute kernel.
//
// Build:  cd aarch64/raytracer && make
// Run:    ./metal_rt_demo

.include "defs.s"

// ─── Text Section ───────────────────────────────────────────────────
.section __TEXT,__text,regular,pure_instructions
.p2align 2

.globl _main

// ════════════════════════════════════════════════════════════════════
// _main — App bootstrap, Metal init, window creation, run loop
// ════════════════════════════════════════════════════════════════════
_main:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x23, x24, [sp, #-16]!
    stp     x25, x26, [sp, #-16]!
    stp     x27, x28, [sp, #-16]!

    // ════════════════════════════════════════════════════════════
    // 1. NSApplication setup
    // ════════════════════════════════════════════════════════════
    adrp    x0, _str_NSApplication@PAGE
    add     x0, x0, _str_NSApplication@PAGEOFF
    bl      _objc_getClass
    mov     x19, x0                             // x19 = NSApplication class

    LOAD_SEL _str_sharedApplication
    mov     x0, x19
    bl      _objc_msgSend
    mov     x20, x0                             // x20 = NSApp

    adrp    x8, _g_nsapp@PAGE
    str     x20, [x8, _g_nsapp@PAGEOFF]

    // [NSApp setActivationPolicy:0 (Regular)]
    LOAD_SEL _str_setActivationPolicy
    mov     x0, x20
    mov     x2, #0
    bl      _objc_msgSend

    // ════════════════════════════════════════════════════════════
    // 2. Create AppDelegate custom class
    //    Must add ALL methods BEFORE objc_registerClassPair
    // ════════════════════════════════════════════════════════════
    adrp    x0, _str_NSObject@PAGE
    add     x0, x0, _str_NSObject@PAGEOFF
    bl      _objc_getClass
    mov     x21, x0                             // NSObject class

    mov     x0, x21
    adrp    x1, _str_AppDelegate@PAGE
    add     x1, x1, _str_AppDelegate@PAGEOFF
    mov     x2, #0
    bl      _objc_allocateClassPair
    mov     x22, x0                             // x22 = AppDelegate class

    // Add applicationDidFinishLaunching:
    adrp    x0, _str_applicationDidFinishLaunching@PAGE
    add     x0, x0, _str_applicationDidFinishLaunching@PAGEOFF
    bl      _sel_registerName
    mov     x23, x0                             // save SEL
    mov     x0, x22
    mov     x1, x23
    adrp    x2, _ad_didFinishLaunching@PAGE
    add     x2, x2, _ad_didFinishLaunching@PAGEOFF
    adrp    x3, _enc_event@PAGE
    add     x3, x3, _enc_event@PAGEOFF
    bl      _class_addMethod

    // Add applicationShouldTerminateAfterLastWindowClosed:
    adrp    x0, _str_appShouldTerminate@PAGE
    add     x0, x0, _str_appShouldTerminate@PAGEOFF
    bl      _sel_registerName
    mov     x23, x0
    mov     x0, x22
    mov     x1, x23
    adrp    x2, _ad_shouldTerminate@PAGE
    add     x2, x2, _ad_shouldTerminate@PAGEOFF
    adrp    x3, _enc_bool@PAGE
    add     x3, x3, _enc_bool@PAGEOFF
    bl      _class_addMethod

    // Add renderFrame: — timer callback lives on the delegate
    adrp    x0, _str_renderFrame@PAGE
    add     x0, x0, _str_renderFrame@PAGEOFF
    bl      _sel_registerName
    mov     x23, x0
    mov     x0, x22
    mov     x1, x23
    adrp    x2, _render_frame@PAGE
    add     x2, x2, _render_frame@PAGEOFF
    adrp    x3, _enc_event@PAGE
    add     x3, x3, _enc_event@PAGEOFF
    bl      _class_addMethod

    // Register the class
    mov     x0, x22
    bl      _objc_registerClassPair

    // [[AppDelegate alloc] init]
    LOAD_SEL _str_alloc
    mov     x0, x22
    bl      _objc_msgSend
    mov     x21, x0

    LOAD_SEL _str_init
    mov     x0, x21
    bl      _objc_msgSend
    mov     x21, x0                             // x21 = delegate instance

    // [NSApp setDelegate:delegate]
    LOAD_SEL _str_setDelegate
    mov     x0, x20
    mov     x2, x21
    bl      _objc_msgSend

    // ════════════════════════════════════════════════════════════
    // 3. Create NSWindow (1280×720)
    // ════════════════════════════════════════════════════════════
    adrp    x0, _str_NSWindow@PAGE
    add     x0, x0, _str_NSWindow@PAGEOFF
    bl      _objc_getClass
    mov     x22, x0

    LOAD_SEL _str_alloc
    mov     x0, x22
    bl      _objc_msgSend
    mov     x22, x0                             // alloc'd window

    adrp    x0, _str_initWithContentRect@PAGE
    add     x0, x0, _str_initWithContentRect@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x22
    // CGRect(0, 0, WIN_W, WIN_H) in d0-d3 (HFA)
    fmov    d0, xzr
    fmov    d1, xzr
    mov     w8, #WIN_W
    ucvtf   d2, w8
    mov     w8, #WIN_H
    ucvtf   d3, w8
    mov     x2, #0xF                            // titled|closable|mini|resize
    mov     x3, #2                              // NSBackingStoreBuffered
    mov     x4, #0                              // defer = NO
    bl      _objc_msgSend
    mov     x22, x0                             // x22 = window

    adrp    x8, _g_window@PAGE
    str     x22, [x8, _g_window@PAGEOFF]

    // ════════════════════════════════════════════════════════════
    // 4. Attach CAMetalLayer to window's contentView
    // ════════════════════════════════════════════════════════════
    LOAD_SEL _str_contentView
    mov     x0, x22
    bl      _objc_msgSend
    mov     x23, x0                             // x23 = contentView

    // [contentView setWantsLayer:YES]
    LOAD_SEL _str_setWantsLayer
    mov     x0, x23
    mov     x2, #1
    bl      _objc_msgSend

    // [CAMetalLayer layer]
    adrp    x0, _str_CAMetalLayer@PAGE
    add     x0, x0, _str_CAMetalLayer@PAGEOFF
    bl      _objc_getClass
    mov     x24, x0

    LOAD_SEL _str_layer
    mov     x0, x24
    bl      _objc_msgSend
    mov     x24, x0                             // x24 = metalLayer

    adrp    x8, _g_metal_layer@PAGE
    str     x24, [x8, _g_metal_layer@PAGEOFF]

    // [contentView setLayer:metalLayer]
    LOAD_SEL _str_setLayer
    mov     x0, x23
    mov     x2, x24
    bl      _objc_msgSend

    // ════════════════════════════════════════════════════════════
    // 5. Metal device + command queue
    // ════════════════════════════════════════════════════════════
    bl      _MTLCreateSystemDefaultDevice
    mov     x25, x0                             // x25 = device

    adrp    x8, _g_device@PAGE
    str     x25, [x8, _g_device@PAGEOFF]

    // [metalLayer setDevice:device]
    LOAD_SEL _str_setDevice
    mov     x0, x24
    mov     x2, x25
    bl      _objc_msgSend

    // [metalLayer setPixelFormat:80 (BGRA8Unorm)]
    LOAD_SEL _str_setPixelFormat
    mov     x0, x24
    mov     x2, #80
    bl      _objc_msgSend

    // [metalLayer setFramebufferOnly:NO] — required for compute shader writes
    LOAD_SEL _str_setFramebufferOnly
    mov     x0, x24
    mov     x2, #0
    bl      _objc_msgSend

    // [metalLayer setDrawableSize:CGSize(WIN_W, WIN_H)]
    LOAD_SEL _str_setDrawableSize
    mov     x0, x24
    mov     w8, #WIN_W
    ucvtf   d0, w8
    mov     w8, #WIN_H
    ucvtf   d1, w8
    bl      _objc_msgSend

    // [device newCommandQueue]
    LOAD_SEL _str_newCommandQueue
    mov     x0, x25
    bl      _objc_msgSend
    mov     x26, x0                             // x26 = commandQueue

    adrp    x8, _g_cmd_queue@PAGE
    str     x26, [x8, _g_cmd_queue@PAGEOFF]

    // ════════════════════════════════════════════════════════════
    // 6. Load metallib, create compute pipeline
    // ════════════════════════════════════════════════════════════

    // NSString from metallib path
    adrp    x0, _str_NSString@PAGE
    add     x0, x0, _str_NSString@PAGEOFF
    bl      _objc_getClass
    mov     x23, x0                             // NSString class

    LOAD_SEL _str_stringWithUTF8String
    mov     x0, x23
    adrp    x2, _str_metallib_path@PAGE
    add     x2, x2, _str_metallib_path@PAGEOFF
    bl      _objc_msgSend
    mov     x23, x0                             // path NSString

    // [NSURL fileURLWithPath:]
    adrp    x0, _str_NSURL@PAGE
    add     x0, x0, _str_NSURL@PAGEOFF
    bl      _objc_getClass
    mov     x24, x0

    LOAD_SEL _str_fileURLWithPath
    mov     x0, x24
    mov     x2, x23
    bl      _objc_msgSend
    mov     x23, x0                             // x23 = URL

    // [device newLibraryWithURL:url error:nil]
    LOAD_SEL _str_newLibraryWithURL
    mov     x0, x25                             // device
    mov     x2, x23                             // URL
    mov     x3, #0                              // error = nil
    bl      _objc_msgSend
    mov     x23, x0                             // x23 = library

    // NSString for kernel function name
    adrp    x0, _str_NSString@PAGE
    add     x0, x0, _str_NSString@PAGEOFF
    bl      _objc_getClass
    mov     x24, x0

    LOAD_SEL _str_stringWithUTF8String
    mov     x0, x24
    adrp    x2, _str_kernel_name@PAGE
    add     x2, x2, _str_kernel_name@PAGEOFF
    bl      _objc_msgSend
    mov     x24, x0                             // kernel name NSString

    // [library newFunctionWithName:]
    LOAD_SEL _str_newFunctionWithName
    mov     x0, x23                             // library
    mov     x2, x24
    bl      _objc_msgSend
    mov     x23, x0                             // x23 = kernel function

    // [device newComputePipelineStateWithFunction:error:]
    LOAD_SEL _str_newComputePipelineState
    mov     x0, x25                             // device
    mov     x2, x23                             // function
    mov     x3, #0                              // error = nil
    bl      _objc_msgSend
    mov     x27, x0                             // x27 = pipeline

    adrp    x8, _g_pipeline@PAGE
    str     x27, [x8, _g_pipeline@PAGEOFF]

    // ════════════════════════════════════════════════════════════
    // 7. Create Metal buffers (uniforms + scene)
    // ════════════════════════════════════════════════════════════
    // Uniforms buffer
    LOAD_SEL _str_newBufferWithLength
    mov     x0, x25                             // device
    mov     x2, #UNIFORMS_SIZE
    mov     x3, #0                              // StorageModeShared
    bl      _objc_msgSend
    mov     x23, x0                             // uniforms MTLBuffer

    adrp    x8, _g_uniforms_buf@PAGE
    str     x23, [x8, _g_uniforms_buf@PAGEOFF]

    // Scene buffer
    LOAD_SEL _str_newBufferWithLength
    mov     x0, x25                             // device
    mov     x2, #(SHAPE_STRIDE * MAX_SHAPES)
    mov     x3, #0
    bl      _objc_msgSend
    mov     x24, x0                             // scene MTLBuffer

    adrp    x8, _g_scene_buf@PAGE
    str     x24, [x8, _g_scene_buf@PAGEOFF]

    // ════════════════════════════════════════════════════════════
    // 8. Initialize uniforms
    // ════════════════════════════════════════════════════════════
    LOAD_SEL _str_contents
    mov     x0, x23                             // uniforms buffer
    bl      _objc_msgSend
    mov     x23, x0                             // raw pointer

    // Zero the buffer
    mov     x0, x23
    mov     x1, #0
    mov     x2, #UNIFORMS_SIZE
    bl      _memset

    // time = 0 (already zeroed)
    // frame_count = 0 (already zeroed)

    // num_shapes
    mov     w8, #NUM_SCENE_SHAPES
    str     w8, [x23, #UNI_NUM_SHAPES]

    // num_lights = 3
    mov     w8, #3
    str     w8, [x23, #UNI_NUM_LIGHTS]

    // resolution.xy as float4 (.xy = w, h)
    mov     w8, #WIN_W
    scvtf   s0, w8
    str     s0, [x23, #UNI_RESOLUTION]
    mov     w8, #WIN_H
    scvtf   s0, w8
    str     s0, [x23, #UNI_RESOLUTION + 4]

    // camera_pos = (0, 2.5, 4, 0)
    adrp    x8, _camera_pos@PAGE
    add     x8, x8, _camera_pos@PAGEOFF
    ldr     q0, [x8]
    str     q0, [x23, #UNI_CAMERA_POS]

    // camera_look_at = (0, 1.5, -3, fov=1.0)
    adrp    x8, _camera_look_at@PAGE
    add     x8, x8, _camera_look_at@PAGEOFF
    ldr     q0, [x8]
    str     q0, [x23, #UNI_CAMERA_LOOK_AT]

    // ════════════════════════════════════════════════════════════
    // 9. Initialize scene data
    // ════════════════════════════════════════════════════════════
    LOAD_SEL _str_contents
    adrp    x8, _g_scene_buf@PAGE
    ldr     x0, [x8, _g_scene_buf@PAGEOFF]
    bl      _objc_msgSend
    mov     x24, x0                             // scene raw pointer

    mov     x0, x24
    adrp    x1, _scene_data@PAGE
    add     x1, x1, _scene_data@PAGEOFF
    mov     x2, #(SHAPE_STRIDE * NUM_SCENE_SHAPES)
    bl      _memcpy

    // ════════════════════════════════════════════════════════════
    // 10. Show window
    // ════════════════════════════════════════════════════════════
    // Window title
    adrp    x0, _str_NSString@PAGE
    add     x0, x0, _str_NSString@PAGEOFF
    bl      _objc_getClass
    mov     x23, x0

    LOAD_SEL _str_stringWithUTF8String
    mov     x0, x23
    adrp    x2, _str_window_title@PAGE
    add     x2, x2, _str_window_title@PAGEOFF
    bl      _objc_msgSend
    mov     x23, x0                             // title NSString

    LOAD_SEL _str_setTitle
    adrp    x8, _g_window@PAGE
    ldr     x0, [x8, _g_window@PAGEOFF]
    mov     x2, x23
    bl      _objc_msgSend

    // [window center]
    LOAD_SEL _str_center
    adrp    x8, _g_window@PAGE
    ldr     x0, [x8, _g_window@PAGEOFF]
    bl      _objc_msgSend

    // [window makeKeyAndOrderFront:nil]
    LOAD_SEL _str_makeKeyAndOrderFront
    adrp    x8, _g_window@PAGE
    ldr     x0, [x8, _g_window@PAGEOFF]
    mov     x2, #0
    bl      _objc_msgSend

    // [NSApp activateIgnoringOtherApps:YES]
    LOAD_SEL _str_activateIgnoringOtherApps
    adrp    x8, _g_nsapp@PAGE
    ldr     x0, [x8, _g_nsapp@PAGEOFF]
    mov     x2, #1
    bl      _objc_msgSend

    // ════════════════════════════════════════════════════════════
    // 11. Create timer (120 Hz) targeting delegate's renderFrame:
    // ════════════════════════════════════════════════════════════
    // Get renderFrame: selector
    adrp    x0, _str_renderFrame@PAGE
    add     x0, x0, _str_renderFrame@PAGEOFF
    bl      _sel_registerName
    mov     x27, x0                             // x27 = sel_renderFrame

    // Get NSTimer class
    adrp    x0, _str_NSTimer@PAGE
    add     x0, x0, _str_NSTimer@PAGEOFF
    bl      _objc_getClass
    mov     x23, x0                             // NSTimer class

    // Get scheduledTimer... selector
    adrp    x0, _str_scheduledTimerWithTimeInterval@PAGE
    add     x0, x0, _str_scheduledTimerWithTimeInterval@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0                              // SEL

    mov     x0, x23                             // NSTimer class
    adrp    x8, _const_timer_interval@PAGE
    ldr     d0, [x8, _const_timer_interval@PAGEOFF]    // 1/120
    mov     x2, x21                             // target = delegate
    mov     x3, x27                             // selector = renderFrame:
    mov     x4, #0                              // userInfo = nil
    mov     x5, #1                              // repeats = YES
    bl      _objc_msgSend
    // Timer is retained by run loop, we don't need to keep it

    // ════════════════════════════════════════════════════════════
    // 12. [NSApp run] — enters run loop, never returns
    // ════════════════════════════════════════════════════════════
    LOAD_SEL _str_run
    adrp    x8, _g_nsapp@PAGE
    ldr     x0, [x8, _g_nsapp@PAGEOFF]
    bl      _objc_msgSend

    // Unreachable
    mov     x0, #0
    ldp     x27, x28, [sp], #16
    ldp     x25, x26, [sp], #16
    ldp     x23, x24, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

// ════════════════════════════════════════════════════════════════════
// _ad_didFinishLaunching — AppDelegate method (no-op)
// ════════════════════════════════════════════════════════════════════
_ad_didFinishLaunching:
    ret

// ════════════════════════════════════════════════════════════════════
// _ad_shouldTerminate — returns YES (1)
// ════════════════════════════════════════════════════════════════════
_ad_shouldTerminate:
    mov     x0, #1
    ret

// ════════════════════════════════════════════════════════════════════
// _render_frame — Timer fires: update lights, encode compute, present
// (x0 = self, x1 = _cmd, x2 = timer)
// ════════════════════════════════════════════════════════════════════
.globl _render_frame
_render_frame:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x23, x24, [sp, #-16]!
    stp     x25, x26, [sp, #-16]!
    stp     d8, d9, [sp, #-16]!

    // ── Get uniforms raw pointer ────────────────────────────────
    LOAD_SEL _str_contents
    adrp    x8, _g_uniforms_buf@PAGE
    ldr     x0, [x8, _g_uniforms_buf@PAGEOFF]
    bl      _objc_msgSend
    mov     x19, x0                             // x19 = uniforms ptr

    // ── Update time (float, +dt each frame) ─────────────────────
    ldr     s0, [x19, #UNI_TIME]
    adrp    x8, _const_dt@PAGE
    ldr     s1, [x8, _const_dt@PAGEOFF]
    fadd    s0, s0, s1
    str     s0, [x19, #UNI_TIME]
    fcvt    d8, s0                              // d8 = time as double (for sin/cos)

    ldr     w8, [x19, #UNI_FRAME_COUNT]
    add     w8, w8, #1
    str     w8, [x19, #UNI_FRAME_COUNT]

    // ── Light A: horizontal orbit (warm white) ──────────────────
    // pos = (cos(t)*4, 3.5, sin(t)*4 - 4, intensity=2.0)
    fmov    d0, d8
    bl      _cos
    fmov    d9, d0                              // cos(t)
    fmov    d0, d8
    bl      _sin
    // d0 = sin(t), d9 = cos(t)

    fcvt    s1, d9
    adrp    x8, _const_4f@PAGE
    ldr     s2, [x8, _const_4f@PAGEOFF]
    fmul    s1, s1, s2                          // cos(t)*4
    str     s1, [x19, #UNI_LIGHTS + 0*LIGHT_STRIDE + 0]    // pos.x

    adrp    x8, _const_3_5f@PAGE
    ldr     s1, [x8, _const_3_5f@PAGEOFF]
    str     s1, [x19, #UNI_LIGHTS + 0*LIGHT_STRIDE + 4]    // pos.y = 3.5

    fcvt    s1, d0
    adrp    x8, _const_4f@PAGE
    ldr     s2, [x8, _const_4f@PAGEOFF]
    fmul    s1, s1, s2                          // sin(t)*4
    adrp    x8, _const_neg4f@PAGE
    ldr     s2, [x8, _const_neg4f@PAGEOFF]
    fadd    s1, s1, s2                          // -4
    str     s1, [x19, #UNI_LIGHTS + 0*LIGHT_STRIDE + 8]    // pos.z

    adrp    x8, _const_2f@PAGE
    ldr     s1, [x8, _const_2f@PAGEOFF]
    str     s1, [x19, #UNI_LIGHTS + 0*LIGHT_STRIDE + 12]   // pos.w = intensity 2.0

    // Light A color = (1.0, 0.9, 0.7, 0)
    adrp    x8, _light_a_color@PAGE
    add     x8, x8, _light_a_color@PAGEOFF
    ldr     q0, [x8]
    str     q0, [x19, #UNI_LIGHTS + 0*LIGHT_STRIDE + LIGHT_COLOR]

    // ── Light B: bobs up/down (cool blue) ───────────────────────
    // pos = (-3, 2+sin(t*0.7)*1.5, -5, intensity=1.5)
    fmov    d0, d8
    adrp    x8, _const_0_7@PAGE
    ldr     d1, [x8, _const_0_7@PAGEOFF]
    fmul    d0, d0, d1
    bl      _sin
    fcvt    s0, d0                              // sin(t*0.7)
    adrp    x8, _const_1_5f@PAGE
    ldr     s1, [x8, _const_1_5f@PAGEOFF]
    fmul    s0, s0, s1                          // *1.5
    adrp    x8, _const_2f@PAGE
    ldr     s1, [x8, _const_2f@PAGEOFF]
    fadd    s0, s0, s1                          // 2 + ...

    adrp    x8, _const_neg3f@PAGE
    ldr     s1, [x8, _const_neg3f@PAGEOFF]
    str     s1, [x19, #UNI_LIGHTS + 1*LIGHT_STRIDE + 0]    // x = -3
    str     s0, [x19, #UNI_LIGHTS + 1*LIGHT_STRIDE + 4]    // y
    adrp    x8, _const_neg5f@PAGE
    ldr     s1, [x8, _const_neg5f@PAGEOFF]
    str     s1, [x19, #UNI_LIGHTS + 1*LIGHT_STRIDE + 8]    // z = -5
    adrp    x8, _const_1_5f@PAGE
    ldr     s1, [x8, _const_1_5f@PAGEOFF]
    str     s1, [x19, #UNI_LIGHTS + 1*LIGHT_STRIDE + 12]   // intensity = 1.5

    // Light B color
    adrp    x8, _light_b_color@PAGE
    add     x8, x8, _light_b_color@PAGEOFF
    ldr     q0, [x8]
    str     q0, [x19, #UNI_LIGHTS + 1*LIGHT_STRIDE + LIGHT_COLOR]

    // ── Light C: figure-8 near ceiling (amber) ──────────────────
    // pos = (sin(t*1.3)*3, 4.5, sin(t*0.9)*cos(t*0.9)*4 - 4, intensity=1.0)
    fmov    d0, d8
    adrp    x8, _const_1_3@PAGE
    ldr     d1, [x8, _const_1_3@PAGEOFF]
    fmul    d0, d0, d1
    bl      _sin
    fcvt    s0, d0
    adrp    x8, _const_3f@PAGE
    ldr     s1, [x8, _const_3f@PAGEOFF]
    fmul    s0, s0, s1                          // sin(t*1.3)*3
    str     s0, [x19, #UNI_LIGHTS + 2*LIGHT_STRIDE + 0]    // x

    adrp    x8, _const_4_5f@PAGE
    ldr     s0, [x8, _const_4_5f@PAGEOFF]
    str     s0, [x19, #UNI_LIGHTS + 2*LIGHT_STRIDE + 4]    // y = 4.5

    // z = sin(t*0.9)*cos(t*0.9)*4 - 4 = sin(2*t*0.9)/2 * 4 - 4
    // Just compute sin and cos separately
    fmov    d0, d8
    adrp    x8, _const_0_9@PAGE
    ldr     d1, [x8, _const_0_9@PAGEOFF]
    fmul    d0, d0, d1
    fmov    d9, d0                              // save t*0.9
    bl      _sin
    fmov    d8, d0                              // sin(t*0.9) — reuse d8, we're done with time
    fmov    d0, d9
    bl      _cos
    fmul    d0, d0, d8                          // sin*cos
    fcvt    s0, d0
    adrp    x8, _const_4f@PAGE
    ldr     s1, [x8, _const_4f@PAGEOFF]
    fmul    s0, s0, s1
    adrp    x8, _const_neg4f@PAGE
    ldr     s1, [x8, _const_neg4f@PAGEOFF]
    fadd    s0, s0, s1
    str     s0, [x19, #UNI_LIGHTS + 2*LIGHT_STRIDE + 8]    // z

    adrp    x8, _const_1f@PAGE
    ldr     s0, [x8, _const_1f@PAGEOFF]
    str     s0, [x19, #UNI_LIGHTS + 2*LIGHT_STRIDE + 12]   // intensity = 1.0

    // Light C color
    adrp    x8, _light_c_color@PAGE
    add     x8, x8, _light_c_color@PAGEOFF
    ldr     q0, [x8]
    str     q0, [x19, #UNI_LIGHTS + 2*LIGHT_STRIDE + LIGHT_COLOR]

    // ── Get next drawable ───────────────────────────────────────
    LOAD_SEL _str_nextDrawable
    adrp    x8, _g_metal_layer@PAGE
    ldr     x0, [x8, _g_metal_layer@PAGEOFF]
    bl      _objc_msgSend
    mov     x20, x0                             // x20 = drawable
    cbz     x20, .Lrender_done

    // ── Command buffer ──────────────────────────────────────────
    LOAD_SEL _str_commandBuffer
    adrp    x8, _g_cmd_queue@PAGE
    ldr     x0, [x8, _g_cmd_queue@PAGEOFF]
    bl      _objc_msgSend
    mov     x21, x0                             // x21 = cmdBuffer

    // ── Compute encoder ─────────────────────────────────────────
    LOAD_SEL _str_computeCommandEncoder
    mov     x0, x21
    bl      _objc_msgSend
    mov     x22, x0                             // x22 = encoder

    // [encoder setComputePipelineState:pipeline]
    LOAD_SEL _str_setComputePipelineState
    mov     x0, x22
    adrp    x8, _g_pipeline@PAGE
    ldr     x2, [x8, _g_pipeline@PAGEOFF]
    bl      _objc_msgSend

    // [encoder setBuffer:uniforms offset:0 atIndex:0]
    LOAD_SEL _str_setBuffer
    mov     x0, x22
    adrp    x8, _g_uniforms_buf@PAGE
    ldr     x2, [x8, _g_uniforms_buf@PAGEOFF]
    mov     x3, #0
    mov     x4, #0
    bl      _objc_msgSend

    // [encoder setBuffer:scene offset:0 atIndex:1]
    LOAD_SEL _str_setBuffer
    mov     x0, x22
    adrp    x8, _g_scene_buf@PAGE
    ldr     x2, [x8, _g_scene_buf@PAGEOFF]
    mov     x3, #0
    mov     x4, #1
    bl      _objc_msgSend

    // [drawable texture]
    LOAD_SEL _str_texture
    mov     x0, x20
    bl      _objc_msgSend
    mov     x23, x0                             // x23 = texture

    // [encoder setTexture:texture atIndex:0]
    LOAD_SEL _str_setTexture
    mov     x0, x22
    mov     x2, x23
    mov     x3, #0
    bl      _objc_msgSend

    // ── Dispatch threads ────────────────────────────────────────
    // MTLSize = 3 × NSUInteger = 24 bytes → passed by REFERENCE (>16 bytes)
    // Build two MTLSize structs on the stack, pass pointers in x2, x3
    sub     sp, sp, #64                         // room for 2 × MTLSize (48) + align
    mov     x8, #WIN_W
    str     x8, [sp, #0]                        // grid.width
    mov     x8, #WIN_H
    str     x8, [sp, #8]                        // grid.height
    mov     x8, #1
    str     x8, [sp, #16]                       // grid.depth
    mov     x8, #16
    str     x8, [sp, #32]                       // group.width
    str     x8, [sp, #40]                       // group.height
    mov     x8, #1
    str     x8, [sp, #48]                       // group.depth

    LOAD_SEL _str_dispatchThreads
    mov     x0, x22
    add     x2, sp, #0                          // ptr to grid MTLSize
    add     x3, sp, #32                         // ptr to group MTLSize
    bl      _objc_msgSend
    add     sp, sp, #64

    // [encoder endEncoding]
    LOAD_SEL _str_endEncoding
    mov     x0, x22
    bl      _objc_msgSend

    // [cmdBuffer presentDrawable:drawable]
    LOAD_SEL _str_presentDrawable
    mov     x0, x21
    mov     x2, x20
    bl      _objc_msgSend

    // [cmdBuffer commit]
    LOAD_SEL _str_commit
    mov     x0, x21
    bl      _objc_msgSend

.Lrender_done:
    ldp     d8, d9, [sp], #16
    ldp     x25, x26, [sp], #16
    ldp     x23, x24, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret


// ═══════════════════════════════════════════════════════════════════
// ─── DATA SECTIONS ─────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════

// ─── Mutable globals ────────────────────────────────────────────────
.section __DATA,__data
.p2align 3

_g_nsapp:           .quad 0
_g_window:          .quad 0
_g_device:          .quad 0
_g_metal_layer:     .quad 0
_g_cmd_queue:       .quad 0
_g_pipeline:        .quad 0
_g_uniforms_buf:    .quad 0
_g_scene_buf:       .quad 0

// ─── C strings ──────────────────────────────────────────────────────
.section __TEXT,__cstring,cstring_literals

// Class names
_str_NSApplication:     .asciz "NSApplication"
_str_NSWindow:          .asciz "NSWindow"
_str_NSObject:          .asciz "NSObject"
_str_NSString:          .asciz "NSString"
_str_NSURL:             .asciz "NSURL"
_str_NSTimer:           .asciz "NSTimer"
_str_CAMetalLayer:      .asciz "CAMetalLayer"
_str_AppDelegate:       .asciz "AppDelegate"

// Selectors
_str_sharedApplication:         .asciz "sharedApplication"
_str_setActivationPolicy:       .asciz "setActivationPolicy:"
_str_alloc:                     .asciz "alloc"
_str_init:                      .asciz "init"
_str_setDelegate:               .asciz "setDelegate:"
_str_run:                       .asciz "run"
_str_activateIgnoringOtherApps: .asciz "activateIgnoringOtherApps:"
_str_applicationDidFinishLaunching: .asciz "applicationDidFinishLaunching:"
_str_appShouldTerminate:        .asciz "applicationShouldTerminateAfterLastWindowClosed:"
_str_initWithContentRect:       .asciz "initWithContentRect:styleMask:backing:defer:"
_str_contentView:               .asciz "contentView"
_str_setWantsLayer:             .asciz "setWantsLayer:"
_str_layer:                     .asciz "layer"
_str_setLayer:                  .asciz "setLayer:"
_str_setDevice:                 .asciz "setDevice:"
_str_setPixelFormat:            .asciz "setPixelFormat:"
_str_setDrawableSize:           .asciz "setDrawableSize:"
_str_setFramebufferOnly:        .asciz "setFramebufferOnly:"
_str_newCommandQueue:           .asciz "newCommandQueue"
_str_fileURLWithPath:           .asciz "fileURLWithPath:"
_str_newLibraryWithURL:         .asciz "newLibraryWithURL:error:"
_str_newFunctionWithName:       .asciz "newFunctionWithName:"
_str_newComputePipelineState:   .asciz "newComputePipelineStateWithFunction:error:"
_str_newBufferWithLength:       .asciz "newBufferWithLength:options:"
_str_contents:                  .asciz "contents"
_str_setTitle:                  .asciz "setTitle:"
_str_center:                    .asciz "center"
_str_makeKeyAndOrderFront:      .asciz "makeKeyAndOrderFront:"
_str_scheduledTimerWithTimeInterval: .asciz "scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"
_str_nextDrawable:              .asciz "nextDrawable"
_str_commandBuffer:             .asciz "commandBuffer"
_str_computeCommandEncoder:     .asciz "computeCommandEncoder"
_str_setComputePipelineState:   .asciz "setComputePipelineState:"
_str_setBuffer:                 .asciz "setBuffer:offset:atIndex:"
_str_texture:                   .asciz "texture"
_str_setTexture:                .asciz "setTexture:atIndex:"
_str_dispatchThreads:           .asciz "dispatchThreads:threadsPerThreadgroup:"
_str_endEncoding:               .asciz "endEncoding"
_str_presentDrawable:           .asciz "presentDrawable:"
_str_commit:                    .asciz "commit"
_str_stringWithUTF8String:      .asciz "stringWithUTF8String:"
_str_renderFrame:               .asciz "renderFrame:"

// Type encodings
_enc_event:     .asciz "v@:@"
_enc_bool:      .asciz "c@:@"

// Paths / names
_str_metallib_path: .asciz "raytrace.metallib"
_str_kernel_name:   .asciz "raytrace_kernel"
_str_window_title:  .asciz "Metal Ray Tracer"

// ─── Float constants ────────────────────────────────────────────────
.section __TEXT,__literal4,4byte_literals
.p2align 2

_const_1f:      .single 1.0
_const_2f:      .single 2.0
_const_3f:      .single 3.0
_const_4f:      .single 4.0
_const_1_5f:    .single 1.5
_const_3_5f:    .single 3.5
_const_4_5f:    .single 4.5
_const_neg3f:   .single -3.0
_const_neg4f:   .single -4.0
_const_neg5f:   .single -5.0
_const_dt:      .single 0.016666666             // ~1/60s per frame tick

.section __TEXT,__literal8,8byte_literals
.p2align 3

_const_timer_interval:  .double 0.008333333     // ~120 Hz
_const_0_7:             .double 0.7
_const_0_9:             .double 0.9
_const_1_3:             .double 1.3

// ─── Float4 constants (16 bytes each) ───────────────────────────────
.section __TEXT,__const
.p2align 4

_light_a_color:     .single 1.0, 0.9, 0.7, 0.0     // warm white
_light_b_color:     .single 0.5, 0.7, 1.0, 0.0     // cool blue
_light_c_color:     .single 1.0, 0.8, 0.4, 0.0     // amber

_camera_pos:        .single 0.0, 2.5, 1.0, 0.0
_camera_look_at:    .single 0.0, 1.0, -4.0, 1.2    // .w = fov (1.2 rad ≈ 69°)

// ─── Scene data (9 shapes × 64 bytes each) ─────────────────────────
// Each shape is 4 × float4:
//   type_info: (type, roughness, reflectivity, 0)
//   position:  (x, y, z, 0)
//   size:      (sx, sy, sz, 0)    [radius/half-ext/normal]
//   color:     (r, g, b, 0)
.p2align 4

_scene_data:
    // 0: Floor (plane at y=0, normal up)
    .single 2.0, 0.8, 0.15, 0.0        // type=plane, rough, refl
    .single 0.0, 0.0, 0.0, 0.0         // point on plane
    .single 0.0, 1.0, 0.0, 0.0         // normal (up)
    .single 0.5, 0.5, 0.5, 0.0         // gray

    // 1: Ceiling (y=5, normal down)
    .single 2.0, 0.95, 0.0, 0.0
    .single 0.0, 5.0, 0.0, 0.0
    .single 0.0, -1.0, 0.0, 0.0
    .single 0.8, 0.8, 0.8, 0.0

    // 2: Back wall (z=-10, normal toward camera)
    .single 2.0, 0.9, 0.0, 0.0
    .single 0.0, 0.0, -10.0, 0.0
    .single 0.0, 0.0, 1.0, 0.0
    .single 0.7, 0.7, 0.7, 0.0

    // 3: Left wall (x=-6, normal right, red tint)
    .single 2.0, 0.85, 0.0, 0.0
    .single -6.0, 0.0, 0.0, 0.0
    .single 1.0, 0.0, 0.0, 0.0
    .single 0.8, 0.2, 0.2, 0.0

    // 4: Right wall (x=6, normal left, green tint)
    .single 2.0, 0.85, 0.0, 0.0
    .single 6.0, 0.0, 0.0, 0.0
    .single -1.0, 0.0, 0.0, 0.0
    .single 0.2, 0.8, 0.2, 0.0

    // 5: Front wall (z=2, behind camera)
    .single 2.0, 0.9, 0.0, 0.0
    .single 0.0, 0.0, 2.0, 0.0
    .single 0.0, 0.0, -1.0, 0.0
    .single 0.7, 0.7, 0.7, 0.0

    // 6: Large sphere (center, reflective)
    .single 0.0, 0.1, 0.8, 0.0         // type=sphere, smooth, very reflective
    .single 0.0, 1.5, -4.0, 0.0        // center
    .single 1.5, 0.0, 0.0, 0.0         // radius = 1.5
    .single 0.9, 0.9, 0.95, 0.0        // near-white

    // 7: Small sphere (offset, matte orange)
    .single 0.0, 0.7, 0.05, 0.0
    .single -2.5, 0.8, -2.5, 0.0
    .single 0.8, 0.0, 0.0, 0.0         // radius = 0.8
    .single 0.9, 0.3, 0.1, 0.0

    // 8: Box (right side, blue)
    .single 1.0, 0.3, 0.4, 0.0         // type=box
    .single 3.0, 1.0, -5.0, 0.0        // center
    .single 1.0, 1.0, 1.0, 0.0         // half-extents
    .single 0.3, 0.5, 0.9, 0.0         // blue

.end
