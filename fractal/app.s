//
// app.s — Pure-assembly Cocoa fractal viewer entry point (AArch64 / macOS)
//
// Bootstrap sequence:
//   1. Parse command-line args
//   2. Allocate render buffers
//   3. Create NSApplication
//   4. Create AppDelegate (custom ObjC class)
//   5. Create NSWindow
//   6. Create FractalView (custom NSView subclass)
//   7. Show window, set first responder
//   8. Create NSTimer for progressive rendering
//   9. [NSApp run] — never returns
//

.include "fractal/state_defs.s"

.text
.p2align 4

// ══════════════════════════════════════════════════════════════
//  _main — entry point
// ══════════════════════════════════════════════════════════════

.globl _main
_main:
    stp     x29, x30, [sp, #-112]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    stp     x27, x28, [sp, #80]

    mov     w19, w0                     // argc
    mov     x20, x1                     // argv

    // ── 1. Parse command-line args ──────────────────────────

    adrp    x21, _g_state@PAGE
    add     x21, x21, _g_state@PAGEOFF

    // Walk argv[1..argc-1] looking for flags
    mov     w22, #1                     // i = 1
    mov     w23, #0                     // center_x_set flag

.Larg_loop:
    cmp     w22, w19
    b.ge    .Larg_done

    // Load argv[i]
    ldr     x0, [x20, x22, lsl #3]

    // Check if it starts with '-'
    ldrb    w8, [x0]
    cmp     w8, #'-'
    b.ne    .Larg_next

    // Get flag character
    ldrb    w8, [x0, #1]

    cmp     w8, #'w'
    b.eq    .Larg_w
    cmp     w8, #'h'
    b.eq    .Larg_h
    cmp     w8, #'j'
    b.eq    .Larg_j
    cmp     w8, #'i'
    b.eq    .Larg_i
    cmp     w8, #'x'
    b.eq    .Larg_x
    cmp     w8, #'y'
    b.eq    .Larg_y
    cmp     w8, #'z'
    b.eq    .Larg_z
    b       .Larg_next

.Larg_w:
    add     w22, w22, #1
    cmp     w22, w19
    b.ge    .Larg_done
    ldr     x0, [x20, x22, lsl #3]
    bl      _atoi
    str     w0, [x21, #VS_WIN_W]
    b       .Larg_next

.Larg_h:
    add     w22, w22, #1
    cmp     w22, w19
    b.ge    .Larg_done
    ldr     x0, [x20, x22, lsl #3]
    bl      _atoi
    str     w0, [x21, #VS_WIN_H]
    b       .Larg_next

.Larg_j:
    // -j jr,ji  — Julia mode
    add     w22, w22, #1
    cmp     w22, w19
    b.ge    .Larg_done
    ldr     x24, [x20, x22, lsl #3]    // "jr,ji" string

    // Parse jr with strtod
    sub     sp, sp, #16
    mov     x0, x24
    mov     x1, sp                      // endptr
    bl      _strtod
    str     d0, [x21, #VS_JR]

    // Skip the comma, parse ji
    ldr     x0, [sp]                    // endptr
    ldrb    w8, [x0]
    cmp     w8, #','
    b.ne    .Larg_j_end
    add     x0, x0, #1                  // skip ','
    mov     x1, sp
    bl      _strtod
    str     d0, [x21, #VS_JI]

.Larg_j_end:
    add     sp, sp, #16
    mov     w8, #1
    str     w8, [x21, #VS_JULIA_MODE]
    b       .Larg_next

.Larg_i:
    add     w22, w22, #1
    cmp     w22, w19
    b.ge    .Larg_done
    ldr     x0, [x20, x22, lsl #3]
    bl      _atoi
    str     w0, [x21, #VS_MAX_ITER]
    b       .Larg_next

.Larg_x:
    add     w22, w22, #1
    cmp     w22, w19
    b.ge    .Larg_done
    ldr     x0, [x20, x22, lsl #3]
    mov     x1, #0
    bl      _strtod
    str     d0, [x21, #VS_CENTER_X]
    mov     w23, #1                     // center_x_set = true
    b       .Larg_next

.Larg_y:
    add     w22, w22, #1
    cmp     w22, w19
    b.ge    .Larg_done
    ldr     x0, [x20, x22, lsl #3]
    mov     x1, #0
    bl      _strtod
    str     d0, [x21, #VS_CENTER_Y]
    b       .Larg_next

.Larg_z:
    add     w22, w22, #1
    cmp     w22, w19
    b.ge    .Larg_done
    ldr     x0, [x20, x22, lsl #3]
    mov     x1, #0
    bl      _strtod
    str     d0, [x21, #VS_ZOOM]
    b       .Larg_next

.Larg_next:
    add     w22, w22, #1
    b       .Larg_loop

.Larg_done:
    // If julia mode and center_x not explicitly set, use 0.0
    ldr     w8, [x21, #VS_JULIA_MODE]
    cbz     w8, .Larg_center_done
    cbnz    w23, .Larg_center_done
    fmov    d0, xzr
    str     d0, [x21, #VS_CENTER_X]
.Larg_center_done:

    // ── 2. Allocate render buffers ──────────────────────────

    ldr     w24, [x21, #VS_WIN_W]      // w
    ldr     w25, [x21, #VS_WIN_H]      // h

    // Full: w * h * 4 (iter_buf, uint32_t)
    umull   x0, w24, w25
    lsl     x0, x0, #2
    bl      _malloc
    adrp    x8, _g_iter_buf@PAGE
    str     x0, [x8, _g_iter_buf@PAGEOFF]

    // Full: w * h * 3 (rgb_buf)
    umull   x0, w24, w25
    mov     x1, #3
    mul     x0, x0, x1
    bl      _malloc
    adrp    x8, _g_rgb_buf@PAGE
    str     x0, [x8, _g_rgb_buf@PAGEOFF]

    // Coarse: (w/4) * (h/4) * 4
    lsr     w26, w24, #2               // cw
    lsr     w27, w25, #2               // ch
    umull   x0, w26, w27
    lsl     x0, x0, #2
    bl      _malloc
    adrp    x8, _g_iter_small@PAGE
    str     x0, [x8, _g_iter_small@PAGEOFF]

    // Coarse: (w/4) * (h/4) * 3
    umull   x0, w26, w27
    mov     x1, #3
    mul     x0, x0, x1
    bl      _malloc
    adrp    x8, _g_rgb_small@PAGE
    str     x0, [x8, _g_rgb_small@PAGEOFF]

    // ARGB32: w * h * 4 (for CGBitmapContext — use full size always)
    umull   x0, w24, w25
    lsl     x0, x0, #2
    bl      _malloc
    adrp    x8, _g_argb_buf@PAGE
    str     x0, [x8, _g_argb_buf@PAGEOFF]

    // ── 3. Create NSApplication ─────────────────────────────

    // [NSApplication sharedApplication]
    adrp    x0, _str_NSApplication@PAGE
    add     x0, x0, _str_NSApplication@PAGEOFF
    bl      _objc_getClass
    mov     x22, x0                     // NSApplication class

    adrp    x0, _str_sharedApplication@PAGE
    add     x0, x0, _str_sharedApplication@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x22
    bl      _objc_msgSend               // NSApp
    mov     x23, x0                     // save NSApp

    adrp    x8, _g_nsapp@PAGE
    str     x23, [x8, _g_nsapp@PAGEOFF]

    // [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular]
    adrp    x0, _str_setActivationPolicy@PAGE
    add     x0, x0, _str_setActivationPolicy@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x23
    mov     x2, #NSApplicationActivationPolicyRegular
    bl      _objc_msgSend

    // ── 4. Create AppDelegate ───────────────────────────────

    // superclass = objc_getClass("NSObject")
    adrp    x0, _str_NSObject@PAGE
    add     x0, x0, _str_NSObject@PAGEOFF
    bl      _objc_getClass
    mov     x24, x0                     // NSObject class

    // cls = objc_allocateClassPair(NSObject, "AppDelegate", 0)
    mov     x0, x24
    adrp    x1, _str_AppDelegate@PAGE
    add     x1, x1, _str_AppDelegate@PAGEOFF
    mov     x2, #0
    bl      _objc_allocateClassPair
    mov     x25, x0                     // AppDelegate class

    // class_addMethod(cls, sel, imp, types)
    // applicationDidFinishLaunching:
    mov     x0, x25
    adrp    x8, _str_applicationDidFinishLaunching@PAGE
    add     x8, x8, _str_applicationDidFinishLaunching@PAGEOFF
    mov     x9, x8
    mov     x0, x25
    // Get SEL
    mov     x0, x9
    bl      _sel_registerName
    mov     x26, x0                     // sel

    mov     x0, x25                     // cls
    mov     x1, x26                     // sel
    adrp    x2, _ad_applicationDidFinishLaunching@PAGE
    add     x2, x2, _ad_applicationDidFinishLaunching@PAGEOFF  // imp
    adrp    x3, _enc_event@PAGE
    add     x3, x3, _enc_event@PAGEOFF  // "v@:@"
    bl      _class_addMethod

    // Register class
    mov     x0, x25
    bl      _objc_registerClassPair

    // [[AppDelegate alloc] init]
    adrp    x0, _str_alloc@PAGE
    add     x0, x0, _str_alloc@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x25                     // AppDelegate class
    bl      _objc_msgSend               // alloc
    mov     x26, x0

    adrp    x0, _str_init@PAGE
    add     x0, x0, _str_init@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x26
    bl      _objc_msgSend               // init
    mov     x26, x0                     // delegate instance

    // [NSApp setDelegate:delegate]
    adrp    x0, _str_setDelegate@PAGE
    add     x0, x0, _str_setDelegate@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x23                     // NSApp
    mov     x2, x26                     // delegate
    bl      _objc_msgSend

    // ── 5. Create NSWindow ──────────────────────────────────

    // [NSWindow alloc]
    adrp    x0, _str_NSWindow@PAGE
    add     x0, x0, _str_NSWindow@PAGEOFF
    bl      _objc_getClass
    mov     x24, x0                     // NSWindow class

    adrp    x0, _str_alloc@PAGE
    add     x0, x0, _str_alloc@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x24
    bl      _objc_msgSend               // NSWindow alloc
    mov     x25, x0                     // uninitialized window

    // [window initWithContentRect:rect styleMask:mask backing:type defer:NO]
    // CGRect in d0-d3, styleMask in x2, backing in x3, defer in x4
    adrp    x0, _str_initWithContentRect@PAGE
    add     x0, x0, _str_initWithContentRect@PAGEOFF
    bl      _sel_registerName
    mov     x27, x0                     // save SEL

    adrp    x8, _g_state@PAGE
    add     x8, x8, _g_state@PAGEOFF
    ldr     w9, [x8, #VS_WIN_W]
    ldr     w10, [x8, #VS_WIN_H]

    mov     x0, x25                     // self = window
    mov     x1, x27                     // SEL
    fmov    d0, xzr                     // origin.x = 0
    fmov    d1, xzr                     // origin.y = 0
    ucvtf   d2, w9                      // size.width
    ucvtf   d3, w10                     // size.height
    mov     x2, #WINDOW_STYLE           // styleMask = 0xF
    mov     x3, #NSBackingStoreBuffered // backing = 2
    mov     x4, #0                      // defer = NO
    bl      _objc_msgSend
    mov     x25, x0                     // initialized window

    adrp    x8, _g_window@PAGE
    str     x25, [x8, _g_window@PAGEOFF]

    // ── 6. Create FractalView ───────────────────────────────

    // Get NSView class
    adrp    x0, _str_NSView@PAGE
    add     x0, x0, _str_NSView@PAGEOFF
    bl      _objc_getClass
    mov     x24, x0                     // NSView class

    // objc_allocateClassPair(NSView, "FractalView", 0)
    mov     x0, x24
    adrp    x1, _str_FractalView@PAGE
    add     x1, x1, _str_FractalView@PAGEOFF
    mov     x2, #0
    bl      _objc_allocateClassPair
    mov     x26, x0                     // FractalView class

    // Add methods to FractalView
    // drawRect:
    adrp    x0, _str_drawRect@PAGE
    add     x0, x0, _str_drawRect@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x26
    adrp    x2, _fv_drawRect@PAGE
    add     x2, x2, _fv_drawRect@PAGEOFF
    adrp    x3, _enc_drawRect@PAGE
    add     x3, x3, _enc_drawRect@PAGEOFF
    bl      _class_addMethod

    // isFlipped
    adrp    x0, _str_isFlipped@PAGE
    add     x0, x0, _str_isFlipped@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x26
    adrp    x2, _fv_isFlipped@PAGE
    add     x2, x2, _fv_isFlipped@PAGEOFF
    adrp    x3, _enc_bool@PAGE
    add     x3, x3, _enc_bool@PAGEOFF
    bl      _class_addMethod

    // acceptsFirstResponder
    adrp    x0, _str_acceptsFirstResponder@PAGE
    add     x0, x0, _str_acceptsFirstResponder@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x26
    adrp    x2, _fv_acceptsFirstResponder@PAGE
    add     x2, x2, _fv_acceptsFirstResponder@PAGEOFF
    adrp    x3, _enc_bool@PAGE
    add     x3, x3, _enc_bool@PAGEOFF
    bl      _class_addMethod

    // mouseDown:
    adrp    x0, _str_mouseDown@PAGE
    add     x0, x0, _str_mouseDown@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x26
    adrp    x2, _fv_mouseDown@PAGE
    add     x2, x2, _fv_mouseDown@PAGEOFF
    adrp    x3, _enc_event@PAGE
    add     x3, x3, _enc_event@PAGEOFF
    bl      _class_addMethod

    // mouseUp:
    adrp    x0, _str_mouseUp@PAGE
    add     x0, x0, _str_mouseUp@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x26
    adrp    x2, _fv_mouseUp@PAGE
    add     x2, x2, _fv_mouseUp@PAGEOFF
    adrp    x3, _enc_event@PAGE
    add     x3, x3, _enc_event@PAGEOFF
    bl      _class_addMethod

    // mouseDragged:
    adrp    x0, _str_mouseDragged@PAGE
    add     x0, x0, _str_mouseDragged@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x26
    adrp    x2, _fv_mouseDragged@PAGE
    add     x2, x2, _fv_mouseDragged@PAGEOFF
    adrp    x3, _enc_event@PAGE
    add     x3, x3, _enc_event@PAGEOFF
    bl      _class_addMethod

    // rightMouseDown:
    adrp    x0, _str_rightMouseDown@PAGE
    add     x0, x0, _str_rightMouseDown@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x26
    adrp    x2, _fv_rightMouseDown@PAGE
    add     x2, x2, _fv_rightMouseDown@PAGEOFF
    adrp    x3, _enc_event@PAGE
    add     x3, x3, _enc_event@PAGEOFF
    bl      _class_addMethod

    // scrollWheel:
    adrp    x0, _str_scrollWheel@PAGE
    add     x0, x0, _str_scrollWheel@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x26
    adrp    x2, _fv_scrollWheel@PAGE
    add     x2, x2, _fv_scrollWheel@PAGEOFF
    adrp    x3, _enc_event@PAGE
    add     x3, x3, _enc_event@PAGEOFF
    bl      _class_addMethod

    // keyDown:
    adrp    x0, _str_keyDown@PAGE
    add     x0, x0, _str_keyDown@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x26
    adrp    x2, _fv_keyDown@PAGE
    add     x2, x2, _fv_keyDown@PAGEOFF
    adrp    x3, _enc_event@PAGE
    add     x3, x3, _enc_event@PAGEOFF
    bl      _class_addMethod

    // timerFired:
    adrp    x0, _str_timerFired@PAGE
    add     x0, x0, _str_timerFired@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x26
    adrp    x2, _fv_timerFired@PAGE
    add     x2, x2, _fv_timerFired@PAGEOFF
    adrp    x3, _enc_event@PAGE
    add     x3, x3, _enc_event@PAGEOFF
    bl      _class_addMethod

    // Register FractalView class
    mov     x0, x26
    bl      _objc_registerClassPair

    // [[FractalView alloc] initWithFrame:windowRect]
    adrp    x0, _str_alloc@PAGE
    add     x0, x0, _str_alloc@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x26                     // FractalView class
    bl      _objc_msgSend               // alloc
    mov     x27, x0

    // initWithFrame: — CGRect in d0-d3
    adrp    x0, _str_initWithFrame@PAGE
    add     x0, x0, _str_initWithFrame@PAGEOFF
    bl      _sel_registerName
    mov     x28, x0                     // save SEL

    adrp    x8, _g_state@PAGE
    add     x8, x8, _g_state@PAGEOFF
    ldr     w9, [x8, #VS_WIN_W]
    ldr     w10, [x8, #VS_WIN_H]

    mov     x0, x27                     // self = view
    mov     x1, x28                     // SEL
    fmov    d0, xzr                     // 0.0
    fmov    d1, xzr                     // 0.0
    ucvtf   d2, w9                      // width
    ucvtf   d3, w10                     // height
    bl      _objc_msgSend
    mov     x27, x0                     // initialized view

    adrp    x8, _g_view@PAGE
    str     x27, [x8, _g_view@PAGEOFF]

    // [window setContentView:view]
    adrp    x0, _str_setContentView@PAGE
    add     x0, x0, _str_setContentView@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x25                     // window
    mov     x2, x27                     // view
    bl      _objc_msgSend

    // ── 7. Show window ──────────────────────────────────────

    // [window setTitle:@"Fractal Viewer"]
    // First create NSString
    adrp    x0, _str_NSString@PAGE
    add     x0, x0, _str_NSString@PAGEOFF
    bl      _objc_getClass
    mov     x24, x0

    adrp    x0, _str_stringWithUTF8String@PAGE
    add     x0, x0, _str_stringWithUTF8String@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x24
    adrp    x2, _str_fractal_viewer@PAGE
    add     x2, x2, _str_fractal_viewer@PAGEOFF
    bl      _objc_msgSend
    mov     x24, x0                     // NSString* title

    adrp    x0, _str_setTitle@PAGE
    add     x0, x0, _str_setTitle@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x25                     // window
    mov     x2, x24                     // title
    bl      _objc_msgSend

    // [window makeKeyAndOrderFront:nil]
    adrp    x0, _str_makeKeyAndOrderFront@PAGE
    add     x0, x0, _str_makeKeyAndOrderFront@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x25
    mov     x2, #0                      // nil
    bl      _objc_msgSend

    // [window makeFirstResponder:view]
    adrp    x0, _str_makeFirstResponder@PAGE
    add     x0, x0, _str_makeFirstResponder@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x25                     // window
    mov     x2, x27                     // view
    bl      _objc_msgSend

    // [NSApp activateIgnoringOtherApps:YES]
    adrp    x0, _str_activateIgnoringOtherApps@PAGE
    add     x0, x0, _str_activateIgnoringOtherApps@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x23                     // NSApp
    mov     x2, #1                      // YES
    bl      _objc_msgSend

    // ── 8. Create NSTimer ───────────────────────────────────

    // [NSTimer scheduledTimerWithTimeInterval:0.016
    //          target:view selector:@selector(timerFired:)
    //          userInfo:nil repeats:YES]
    adrp    x0, _str_NSTimer@PAGE
    add     x0, x0, _str_NSTimer@PAGEOFF
    bl      _objc_getClass
    mov     x24, x0                     // NSTimer class

    adrp    x0, _str_scheduledTimerWithTimeInterval@PAGE
    add     x0, x0, _str_scheduledTimerWithTimeInterval@PAGEOFF
    bl      _sel_registerName
    mov     x28, x0                     // save SEL

    // Get timerFired: selector for the target
    adrp    x0, _str_timerFired@PAGE
    add     x0, x0, _str_timerFired@PAGEOFF
    bl      _sel_registerName
    mov     x26, x0                     // timerFired: SEL

    mov     x0, x24                     // NSTimer class
    mov     x1, x28                     // scheduledTimerWithTimeInterval:...
    adrp    x8, _const_0_016@PAGE
    ldr     d0, [x8, _const_0_016@PAGEOFF]  // interval = 0.016
    mov     x2, x27                     // target = view
    mov     x3, x26                     // selector = timerFired:
    mov     x4, #0                      // userInfo = nil
    mov     x5, #1                      // repeats = YES
    bl      _objc_msgSend

    // ── 9. Run event loop ───────────────────────────────────

    // [NSApp run]
    adrp    x0, _str_run@PAGE
    add     x0, x0, _str_run@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x23                     // NSApp
    bl      _objc_msgSend               // never returns

    // Epilogue (unreachable)
    ldp     x27, x28, [x29, #80]
    ldp     x25, x26, [x29, #64]
    ldp     x23, x24, [x29, #48]
    ldp     x21, x22, [x29, #32]
    ldp     x19, x20, [x29, #16]
    ldp     x29, x30, [sp], #112
    mov     w0, #0
    ret
