//
// events.s — ObjC method implementations for FractalView + AppDelegate
//            (AArch64 / macOS)
//
// These are the IMP functions registered via class_addMethod in app.s.
// Each receives (id self, SEL _cmd, ...) per ObjC calling convention.
//

.include "fractal/state_defs.s"

.text
.p2align 4

// ══════════════════════════════════════════════════════════════
//  _fv_isFlipped — return YES so origin is top-left
// ══════════════════════════════════════════════════════════════
//  BOOL isFlipped  →  (id self, SEL _cmd) → char
//  Returns 1 (YES)

.globl _fv_isFlipped
_fv_isFlipped:
    mov     w0, #1
    ret


// ══════════════════════════════════════════════════════════════
//  _fv_acceptsFirstResponder — return YES for key events
// ══════════════════════════════════════════════════════════════

.globl _fv_acceptsFirstResponder
_fv_acceptsFirstResponder:
    mov     w0, #1
    ret


// ══════════════════════════════════════════════════════════════
//  _fv_drawRect — render fractal and blit to screen
// ══════════════════════════════════════════════════════════════
//  void drawRect:(CGRect)rect
//  (id self, SEL _cmd, d0=x, d1=y, d2=w, d3=h)

.globl _fv_drawRect
_fv_drawRect:
    stp     x29, x30, [sp, #-160]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    stp     x27, x28, [sp, #80]
    stp     d8, d9, [sp, #96]
    stp     d10, d11, [sp, #112]
    stp     d12, d13, [sp, #128]
    stp     d14, d15, [sp, #144]

    // Load global state pointer
    adrp    x19, _g_state@PAGE
    add     x19, x19, _g_state@PAGEOFF

    // Load window dimensions
    ldr     w20, [x19, #VS_WIN_W]      // rw (full)
    ldr     w21, [x19, #VS_WIN_H]      // rh (full)

    // Check progressive phase
    ldr     w22, [x19, #VS_PHASE]      // 0=coarse, 1=full

    // Compute render dimensions
    cbnz    w22, .Ldraw_full

    // Coarse: 1/4 resolution
    lsr     w23, w20, #2               // cw = rw/4
    lsr     w24, w21, #2               // ch = rh/4

    // Load coarse buffers
    adrp    x8, _g_iter_small@PAGE
    ldr     x1, [x8, _g_iter_small@PAGEOFF]
    adrp    x8, _g_rgb_small@PAGE
    ldr     x2, [x8, _g_rgb_small@PAGEOFF]
    b       .Ldraw_render

.Ldraw_full:
    mov     w23, w20                    // rw
    mov     w24, w21                    // rh

    // Load full buffers
    adrp    x8, _g_iter_buf@PAGE
    ldr     x1, [x8, _g_iter_buf@PAGEOFF]
    adrp    x8, _g_rgb_buf@PAGE
    ldr     x2, [x8, _g_rgb_buf@PAGEOFF]

.Ldraw_render:
    // render_fractal(state, iter_buf, rgb_buf, rw, rh)
    mov     x0, x19
    // x1, x2 already set
    mov     w3, w23
    mov     w4, w24
    bl      _render_fractal
    fmov    d8, d0                      // save render time

    // Store render time
    str     d8, [x19, #VS_LAST_MS]

    // Convert rgb24 → argb32
    adrp    x8, _g_argb_buf@PAGE
    ldr     x0, [x8, _g_argb_buf@PAGEOFF]
    mov     w1, #0                      // stride (unused — contiguous)
    adrp    x8, _g_rgb_buf@PAGE
    ldr     x2, [x8, _g_rgb_buf@PAGEOFF]
    cbnz    w22, .Ldraw_conv_full
    adrp    x8, _g_rgb_small@PAGE
    ldr     x2, [x8, _g_rgb_small@PAGEOFF]
.Ldraw_conv_full:
    mov     w3, w23
    mov     w4, w24
    bl      _rgb24_to_argb32

    // Create CGColorSpace (sRGB)
    bl      _CGColorSpaceCreateDeviceRGB
    mov     x19, x0                     // save colorspace (reuse x19, state no longer needed)

    // Reload state pointer since we clobbered x19
    // Actually, save it differently. Let me use the stack.
    // We need: colorspace, render dims, argb_buf pointer
    // Let's re-derive what we need from globals
    mov     x25, x0                     // colorspace

    // Create CGBitmapContext
    adrp    x8, _g_argb_buf@PAGE
    ldr     x0, [x8, _g_argb_buf@PAGEOFF]   // data
    mov     x1, x23                     // width (render width)
    mov     x2, x24                     // height (render height)
    mov     w3, #8                      // bitsPerComponent
    lsl     w4, w23, #2                 // bytesPerRow = width * 4
    mov     x5, x25                     // colorspace
    mov     w6, #BITMAP_INFO            // bitmapInfo
    bl      _CGBitmapContextCreate
    mov     x26, x0                     // save bitmap context

    // Create CGImage from context
    mov     x0, x26
    bl      _CGBitmapContextCreateImage
    mov     x27, x0                     // save CGImage

    // Release colorspace
    mov     x0, x25
    bl      _CGColorSpaceRelease

    // Get current NSGraphicsContext → CGContext
    adrp    x0, _str_NSGraphicsContext@PAGE
    add     x0, x0, _str_NSGraphicsContext@PAGEOFF
    bl      _objc_getClass
    mov     x20, x0                     // NSGraphicsContext class

    adrp    x0, _str_currentContext@PAGE
    add     x0, x0, _str_currentContext@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x20
    bl      _objc_msgSend               // [NSGraphicsContext currentContext]
    mov     x20, x0                     // graphicsContext instance

    adrp    x0, _str_CGContext@PAGE
    add     x0, x0, _str_CGContext@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x20
    bl      _objc_msgSend               // [ctx CGContext]
    mov     x28, x0                     // CGContextRef

    // Draw image: CGContextDrawImage(ctx, rect, image)
    //   rect = (0, 0, win_w, win_h) in d0-d3
    adrp    x8, _g_state@PAGE
    add     x8, x8, _g_state@PAGEOFF
    ldr     w9, [x8, #VS_WIN_W]
    ldr     w10, [x8, #VS_WIN_H]

    mov     x0, x28                     // CGContext
    fmov    d0, xzr                     // origin.x = 0.0
    fmov    d1, xzr                     // origin.y = 0.0
    ucvtf   d2, w9                      // size.width = win_w
    ucvtf   d3, w10                     // size.height = win_h
    mov     x1, x27                     // CGImage
    bl      _CGContextDrawImage

    // Release CGImage and bitmap context
    mov     x0, x27
    bl      _CGImageRelease
    mov     x0, x26
    bl      _CGContextRelease

    // If coarse phase, advance to full and schedule redisplay
    adrp    x8, _g_state@PAGE
    add     x8, x8, _g_state@PAGEOFF
    ldr     w9, [x8, #VS_PHASE]
    cbnz    w9, .Ldraw_done

    // Set phase = 1
    mov     w9, #1
    str     w9, [x8, #VS_PHASE]

    // [g_view setNeedsDisplay:YES]
    adrp    x8, _g_view@PAGE
    ldr     x0, [x8, _g_view@PAGEOFF]
    adrp    x8, _str_setNeedsDisplay@PAGE
    add     x8, x8, _str_setNeedsDisplay@PAGEOFF
    mov     x9, x8
    mov     x0, x0                      // self = g_view (reload)
    // Need to get selector first
    adrp    x0, _str_setNeedsDisplay@PAGE
    add     x0, x0, _str_setNeedsDisplay@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0                      // SEL
    adrp    x8, _g_view@PAGE
    ldr     x0, [x8, _g_view@PAGEOFF]  // self
    mov     w2, #1                      // YES
    bl      _objc_msgSend

.Ldraw_done:
    // Update window title
    bl      _update_window_title

    // Epilogue
    ldp     d14, d15, [x29, #144]
    ldp     d12, d13, [x29, #128]
    ldp     d10, d11, [x29, #112]
    ldp     d8, d9, [x29, #96]
    ldp     x27, x28, [x29, #80]
    ldp     x25, x26, [x29, #64]
    ldp     x23, x24, [x29, #48]
    ldp     x21, x22, [x29, #32]
    ldp     x19, x20, [x29, #16]
    ldp     x29, x30, [sp], #160
    ret


// ══════════════════════════════════════════════════════════════
//  _update_window_title — format and set window title
// ══════════════════════════════════════════════════════════════

.globl _update_window_title
_update_window_title:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    adrp    x19, _g_state@PAGE
    add     x19, x19, _g_state@PAGEOFF

    // Allocate title buffer on stack
    sub     sp, sp, #272                // 256 bytes for title + alignment

    ldr     w8, [x19, #VS_JULIA_MODE]
    cbnz    w8, .Ltitle_julia

    // Mandelbrot title
    // snprintf(buf, 256, fmt, center_x, center_y, zoom, max_iter, last_ms)
    // ARM64 variadic: first named args in regs, variadic args on stack
    mov     x0, sp                      // buf
    mov     x1, #256                    // size
    adrp    x2, _fmt_title_mandel@PAGE
    add     x2, x2, _fmt_title_mandel@PAGEOFF  // format

    // Variadic doubles/ints go on the stack for ARM64
    ldr     d0, [x19, #VS_CENTER_X]
    ldr     d1, [x19, #VS_CENTER_Y]
    ldr     d2, [x19, #VS_ZOOM]
    ldr     w3, [x19, #VS_MAX_ITER]
    ldr     d4, [x19, #VS_LAST_MS]

    // For snprintf variadic, we pass doubles in d-regs and ints in x-regs
    // snprintf format: (buf, size, fmt, ...) — first 3 are named
    // Remaining args: center_x(d), center_y(d), zoom(d), max_iter(uint), last_ms(d)
    // These go in d0, d1, d2, w3, d3 after the named args
    // Actually snprintf named args: x0=buf, x1=size, x2=fmt
    // Then variadic args follow — on ARM64 variadic floats go on STACK
    // Let me put them on the stack properly

    // For ARM64 variadic: all variadic args go on the stack
    sub     sp, sp, #64
    str     d0, [sp, #0]               // center_x
    str     d1, [sp, #8]               // center_y
    str     d2, [sp, #16]              // zoom
    // max_iter as uint32 but stack slots are 8 bytes
    str     x3, [sp, #24]              // max_iter (widened to 64-bit)
    str     d4, [sp, #32]              // last_ms

    // Named args for snprintf
    add     x0, sp, #64                // buf (above the variadic area)
    mov     x1, #256
    adrp    x2, _fmt_title_mandel@PAGE
    add     x2, x2, _fmt_title_mandel@PAGEOFF
    bl      _snprintf

    add     sp, sp, #64                // pop variadic area
    b       .Ltitle_set

.Ltitle_julia:
    // Julia title: jr, ji, center_x, center_y, zoom, max_iter, last_ms
    ldr     d0, [x19, #VS_JR]
    ldr     d1, [x19, #VS_JI]
    ldr     d2, [x19, #VS_CENTER_X]
    ldr     d3, [x19, #VS_CENTER_Y]
    ldr     d4, [x19, #VS_ZOOM]
    ldr     w8, [x19, #VS_MAX_ITER]
    ldr     d5, [x19, #VS_LAST_MS]

    sub     sp, sp, #80
    str     d0, [sp, #0]               // jr
    str     d1, [sp, #8]               // ji
    str     d2, [sp, #16]              // center_x
    str     d3, [sp, #24]              // center_y
    str     d4, [sp, #32]              // zoom
    str     x8, [sp, #40]              // max_iter
    str     d5, [sp, #48]              // last_ms

    add     x0, sp, #80                // buf
    mov     x1, #256
    adrp    x2, _fmt_title_julia@PAGE
    add     x2, x2, _fmt_title_julia@PAGEOFF
    bl      _snprintf

    add     sp, sp, #80

.Ltitle_set:
    // Create NSString from title buffer
    // [NSString stringWithUTF8String:buf]
    adrp    x0, _str_NSString@PAGE
    add     x0, x0, _str_NSString@PAGEOFF
    bl      _objc_getClass
    mov     x20, x0

    adrp    x0, _str_stringWithUTF8String@PAGE
    add     x0, x0, _str_stringWithUTF8String@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x20
    mov     x2, sp                      // buf pointer (the title on stack)
    bl      _objc_msgSend
    mov     x20, x0                     // NSString* title

    // [g_window setTitle:nsstring]
    adrp    x0, _str_setTitle@PAGE
    add     x0, x0, _str_setTitle@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    adrp    x8, _g_window@PAGE
    ldr     x0, [x8, _g_window@PAGEOFF]
    mov     x2, x20
    bl      _objc_msgSend

    add     sp, sp, #272                // free title buffer

    ldp     x19, x20, [x29, #16]
    ldp     x29, x30, [sp], #80
    ret


// ══════════════════════════════════════════════════════════════
//  _fv_mouseDown — start drag
// ══════════════════════════════════════════════════════════════
//  void mouseDown:(NSEvent*)event
//  (id self, SEL _cmd, id event)

.globl _fv_mouseDown
_fv_mouseDown:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x2                     // save event

    // Get mouse location: [event locationInWindow] returns NSPoint in d0,d1
    adrp    x0, _str_locationInWindow@PAGE
    add     x0, x0, _str_locationInWindow@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x19                     // event
    bl      _objc_msgSend               // d0=x, d1=y (Cocoa coords, origin bottom-left)

    // Convert to top-left origin: screen_y = win_h - cocoa_y
    adrp    x8, _g_state@PAGE
    add     x8, x8, _g_state@PAGEOFF

    fcvtzs  w9, d0                      // mouse x (int)
    fcvtzs  w10, d1                     // mouse y (int, raw Cocoa coords)

    // Set dragging state
    mov     w11, #1
    str     w11, [x8, #VS_DRAGGING]
    str     w9, [x8, #VS_DRAG_X]
    str     w10, [x8, #VS_DRAG_Y]
    ldr     d0, [x8, #VS_CENTER_X]
    str     d0, [x8, #VS_DRAG_CX]
    ldr     d0, [x8, #VS_CENTER_Y]
    str     d0, [x8, #VS_DRAG_CY]

    ldp     x21, x22, [x29, #32]
    ldp     x19, x20, [x29, #16]
    ldp     x29, x30, [sp], #64
    ret


// ══════════════════════════════════════════════════════════════
//  _fv_mouseUp — end drag
// ══════════════════════════════════════════════════════════════

.globl _fv_mouseUp
_fv_mouseUp:
    adrp    x8, _g_state@PAGE
    add     x8, x8, _g_state@PAGEOFF
    str     wzr, [x8, #VS_DRAGGING]
    ret


// ══════════════════════════════════════════════════════════════
//  _fv_mouseDragged — pan view
// ══════════════════════════════════════════════════════════════

.globl _fv_mouseDragged
_fv_mouseDragged:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x2                     // save event

    adrp    x20, _g_state@PAGE
    add     x20, x20, _g_state@PAGEOFF

    // Check if dragging
    ldr     w8, [x20, #VS_DRAGGING]
    cbz     w8, .Ldrag_done

    // Get mouse location
    adrp    x0, _str_locationInWindow@PAGE
    add     x0, x0, _str_locationInWindow@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x19
    bl      _objc_msgSend               // d0=cocoa_x, d1=cocoa_y

    // Current mouse pos as int (raw Cocoa coords — flip cancels in delta)
    fcvtzs  w9, d0                      // mx
    fcvtzs  w10, d1                     // my

    // Compute delta in complex plane
    // dx = (mx - drag_start_x) / win_w * 2 * half_w
    // dy = (my - drag_start_y) / win_h * 2 * half_h
    ldr     w11, [x20, #VS_DRAG_X]
    ldr     w12, [x20, #VS_DRAG_Y]
    sub     w9, w9, w11                 // pixel dx
    sub     w10, w10, w12               // pixel dy

    ldr     w11, [x20, #VS_WIN_W]
    ldr     w12, [x20, #VS_WIN_H]
    ldr     d4, [x20, #VS_ZOOM]

    // half_h = 2.0 / zoom
    fmov    d5, #2.0
    fdiv    d6, d5, d4                  // half_h

    // half_w = half_h * aspect
    ucvtf   d7, w11                     // (double)win_w
    ucvtf   d16, w12                    // (double)win_h
    fdiv    d17, d7, d16                // aspect
    fmul    d18, d6, d17               // half_w

    // dx_complex = pixel_dx / win_w * 2 * half_w
    scvtf   d0, w9                      // (double)pixel_dx
    fdiv    d0, d0, d7                  // / win_w
    fadd    d19, d18, d18              // 2*half_w
    fmul    d0, d0, d19                // * 2*half_w

    // dy_complex = pixel_dy / win_h * 2 * half_h
    scvtf   d1, w10
    fdiv    d1, d1, d16                // / win_h
    fadd    d20, d6, d6                // 2*half_h
    fmul    d1, d1, d20               // * 2*half_h

    // center = drag_start_center - delta
    ldr     d2, [x20, #VS_DRAG_CX]
    ldr     d3, [x20, #VS_DRAG_CY]
    fsub    d2, d2, d0
    fsub    d3, d3, d1
    str     d2, [x20, #VS_CENTER_X]
    str     d3, [x20, #VS_CENTER_Y]

    // Mark dirty
    mov     w8, #1
    str     w8, [x20, #VS_NEEDS_RENDER]
    str     wzr, [x20, #VS_PHASE]

    // [g_view setNeedsDisplay:YES]
    bl      _trigger_redisplay

.Ldrag_done:
    ldp     x19, x20, [x29, #16]
    ldp     x29, x30, [sp], #48
    ret


// ══════════════════════════════════════════════════════════════
//  _fv_rightMouseDown — enter Julia mode
// ══════════════════════════════════════════════════════════════

.globl _fv_rightMouseDown
_fv_rightMouseDown:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x2                     // save event

    adrp    x20, _g_state@PAGE
    add     x20, x20, _g_state@PAGEOFF

    // Only switch if currently in Mandelbrot mode
    ldr     w8, [x20, #VS_JULIA_MODE]
    cbnz    w8, .Lright_done

    // Get mouse location
    adrp    x0, _str_locationInWindow@PAGE
    add     x0, x0, _str_locationInWindow@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x19
    bl      _objc_msgSend               // d0=cocoa_x, d1=cocoa_y

    // Flip Y
    ldr     w8, [x20, #VS_WIN_H]
    ucvtf   d2, w8
    fsub    d1, d2, d1

    // Convert to int screen coords
    fcvtzs  w1, d0
    fcvtzs  w2, d1

    // screen_to_complex(state, sx, sy) → d0=re, d1=im
    mov     x0, x20
    bl      _screen_to_complex

    // Set Julia parameters
    str     d0, [x20, #VS_JR]
    str     d1, [x20, #VS_JI]
    mov     w8, #1
    str     w8, [x20, #VS_JULIA_MODE]

    // Reset view for Julia
    fmov    d2, xzr                     // center_x = 0.0
    str     d2, [x20, #VS_CENTER_X]
    str     d2, [x20, #VS_CENTER_Y]    // center_y = 0.0
    fmov    d2, #1.0
    str     d2, [x20, #VS_ZOOM]        // zoom = 1.0

    // Mark dirty
    mov     w8, #1
    str     w8, [x20, #VS_NEEDS_RENDER]
    str     wzr, [x20, #VS_PHASE]

    bl      _trigger_redisplay

.Lright_done:
    ldp     x19, x20, [x29, #16]
    ldp     x29, x30, [sp], #48
    ret


// ══════════════════════════════════════════════════════════════
//  _fv_scrollWheel — zoom in/out centered on cursor
// ══════════════════════════════════════════════════════════════

.globl _fv_scrollWheel
_fv_scrollWheel:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     d8, d9, [sp, #32]
    stp     d10, d11, [sp, #48]
    stp     d12, d13, [sp, #64]

    mov     x19, x2                     // event

    adrp    x20, _g_state@PAGE
    add     x20, x20, _g_state@PAGEOFF

    // Get deltaY: [event deltaY] → d0
    adrp    x0, _str_deltaY@PAGE
    add     x0, x0, _str_deltaY@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x19
    bl      _objc_msgSend               // d0 = deltaY
    fmov    d8, d0                      // save deltaY

    // Get mouse location for cursor-centered zoom
    adrp    x0, _str_locationInWindow@PAGE
    add     x0, x0, _str_locationInWindow@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x19
    bl      _objc_msgSend               // d0=cocoa_x, d1=cocoa_y
    fmov    d9, d0                      // cocoa_x
    // Flip Y
    ldr     w8, [x20, #VS_WIN_H]
    ucvtf   d2, w8
    fsub    d10, d2, d1                 // screen_y

    // Convert mouse to int screen coords
    fcvtzs  w1, d9                      // sx
    fcvtzs  w2, d10                     // sy

    // Get complex coords under cursor before zoom
    mov     x0, x20
    bl      _screen_to_complex          // d0=cx, d1=cy
    fmov    d11, d0                     // cx (point under cursor)
    fmov    d12, d1                     // cy

    // Determine zoom factor
    fcmp    d8, #0.0
    b.le    .Lscroll_out

    // Scroll up → zoom in, factor = 1.3
    adrp    x8, _const_1_3@PAGE
    ldr     d0, [x8, _const_1_3@PAGEOFF]
    b       .Lscroll_apply

.Lscroll_out:
    // Scroll down → zoom out, factor = 1/1.3
    adrp    x8, _const_inv_1_3@PAGE
    ldr     d0, [x8, _const_inv_1_3@PAGEOFF]

.Lscroll_apply:
    // zoom *= factor
    ldr     d1, [x20, #VS_ZOOM]
    fmul    d1, d1, d0

    // Clamp zoom: [0.1, 1e14]
    adrp    x8, _const_0_1@PAGE
    ldr     d2, [x8, _const_0_1@PAGEOFF]
    fcmp    d1, d2
    fcsel   d1, d2, d1, lt

    adrp    x8, _const_1e14@PAGE
    ldr     d2, [x8, _const_1e14@PAGEOFF]
    fcmp    d1, d2
    fcsel   d1, d2, d1, gt

    str     d1, [x20, #VS_ZOOM]

    // Adjust center so (cx, cy) stays under cursor
    // new_half_h = 2.0 / new_zoom
    fmov    d2, #2.0
    fdiv    d3, d2, d1                  // new_half_h

    // new_half_w = new_half_h * aspect
    ldr     w8, [x20, #VS_WIN_W]
    ldr     w9, [x20, #VS_WIN_H]
    ucvtf   d4, w8                      // win_w
    ucvtf   d5, w9                      // win_h
    fdiv    d6, d4, d5                  // aspect
    fmul    d7, d3, d6                  // new_half_w

    // fx = mx / win_w,  fy = my / win_h
    fdiv    d8, d9, d4                  // fx = cocoa_x / win_w
    fdiv    d9, d10, d5                 // fy = screen_y / win_h

    // center_x = cx - new_half_w * (2*fx - 1)
    fadd    d13, d8, d8                 // 2*fx
    fmov    d14, #1.0
    fsub    d13, d13, d14              // 2*fx - 1
    fmul    d13, d7, d13               // half_w * (2*fx-1)
    fsub    d0, d11, d13               // cx - ...
    str     d0, [x20, #VS_CENTER_X]

    // center_y = cy - new_half_h * (2*fy - 1)
    fadd    d13, d9, d9                 // 2*fy
    fsub    d13, d13, d14              // 2*fy - 1
    fmul    d13, d3, d13               // half_h * (2*fy-1)
    fsub    d0, d12, d13
    str     d0, [x20, #VS_CENTER_Y]

    // Mark dirty
    mov     w8, #1
    str     w8, [x20, #VS_NEEDS_RENDER]
    str     wzr, [x20, #VS_PHASE]

    bl      _trigger_redisplay

    ldp     d12, d13, [x29, #64]
    ldp     d10, d11, [x29, #48]
    ldp     d8, d9, [x29, #32]
    ldp     x19, x20, [x29, #16]
    ldp     x29, x30, [sp], #80
    ret


// ══════════════════════════════════════════════════════════════
//  _fv_keyDown — handle keyboard input
// ══════════════════════════════════════════════════════════════
//  void keyDown:(NSEvent*)event

.globl _fv_keyDown
_fv_keyDown:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x2                     // save event

    adrp    x20, _g_state@PAGE
    add     x20, x20, _g_state@PAGEOFF

    // Get keyCode: [event keyCode] → w0
    adrp    x0, _str_keyCode@PAGE
    add     x0, x0, _str_keyCode@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    mov     x0, x19
    bl      _objc_msgSend
    // keyCode in w0 (unsigned short, returned in x0)
    mov     w9, w0

    // Dispatch on keyCode
    cmp     w9, #0x0C                   // Q
    b.eq    .Lkey_quit
    cmp     w9, #0x35                   // Escape
    b.eq    .Lkey_quit
    cmp     w9, #0x31                   // Space
    b.eq    .Lkey_space
    cmp     w9, #0x18                   // = / +
    b.eq    .Lkey_plus
    cmp     w9, #0x1B                   // -
    b.eq    .Lkey_minus
    cmp     w9, #0x0F                   // R
    b.eq    .Lkey_reset
    cmp     w9, #0x01                   // S
    b.eq    .Lkey_save
    b       .Lkey_done

.Lkey_quit:
    // [NSApp terminate:nil]
    adrp    x8, _g_nsapp@PAGE
    ldr     x0, [x8, _g_nsapp@PAGEOFF]
    adrp    x8, _str_terminate@PAGE
    add     x8, x8, _str_terminate@PAGEOFF
    mov     x9, x8
    mov     x0, x0
    // Get selector
    adrp    x0, _str_terminate@PAGE
    add     x0, x0, _str_terminate@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    adrp    x8, _g_nsapp@PAGE
    ldr     x0, [x8, _g_nsapp@PAGEOFF]
    mov     x2, #0                      // nil
    bl      _objc_msgSend
    b       .Lkey_done

.Lkey_space:
    // Switch to Mandelbrot, reset
    str     wzr, [x20, #VS_JULIA_MODE]
    adrp    x8, _const_neg0_5@PAGE
    ldr     d0, [x8, _const_neg0_5@PAGEOFF]
    str     d0, [x20, #VS_CENTER_X]
    fmov    d0, xzr
    str     d0, [x20, #VS_CENTER_Y]
    fmov    d0, #1.0
    str     d0, [x20, #VS_ZOOM]
    b       .Lkey_dirty

.Lkey_plus:
    // Double max_iter (cap at 65536)
    ldr     w8, [x20, #VS_MAX_ITER]
    lsl     w8, w8, #1
    mov     w9, #65536
    cmp     w8, w9
    csel    w8, w9, w8, hi
    str     w8, [x20, #VS_MAX_ITER]
    b       .Lkey_dirty

.Lkey_minus:
    // Halve max_iter (min 16)
    ldr     w8, [x20, #VS_MAX_ITER]
    lsr     w8, w8, #1
    cmp     w8, #16
    mov     w9, #16
    csel    w8, w9, w8, lo
    str     w8, [x20, #VS_MAX_ITER]
    b       .Lkey_dirty

.Lkey_reset:
    // Reset view
    ldr     w8, [x20, #VS_JULIA_MODE]
    cbnz    w8, .Lreset_julia
    adrp    x8, _const_neg0_5@PAGE
    ldr     d0, [x8, _const_neg0_5@PAGEOFF]
    str     d0, [x20, #VS_CENTER_X]
    b       .Lreset_common
.Lreset_julia:
    fmov    d0, xzr
    str     d0, [x20, #VS_CENTER_X]
.Lreset_common:
    fmov    d0, xzr
    str     d0, [x20, #VS_CENTER_Y]
    fmov    d0, #1.0
    str     d0, [x20, #VS_ZOOM]
    mov     w8, #256
    str     w8, [x20, #VS_MAX_ITER]
    b       .Lkey_dirty

.Lkey_save:
    bl      _save_current_ppm
    b       .Lkey_done

.Lkey_dirty:
    mov     w8, #1
    str     w8, [x20, #VS_NEEDS_RENDER]
    str     wzr, [x20, #VS_PHASE]
    bl      _trigger_redisplay

.Lkey_done:
    ldp     x19, x20, [x29, #16]
    ldp     x29, x30, [sp], #48
    ret


// ══════════════════════════════════════════════════════════════
//  _ad_shouldTerminateAfterLastWindowClosed — return YES
// ══════════════════════════════════════════════════════════════

.globl _ad_shouldTerminateAfterLastWindowClosed
_ad_shouldTerminateAfterLastWindowClosed:
    mov     w0, #1
    ret


// ══════════════════════════════════════════════════════════════
//  _ad_applicationDidFinishLaunching — initial setup
// ══════════════════════════════════════════════════════════════

.globl _ad_applicationDidFinishLaunching
_ad_applicationDidFinishLaunching:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Print controls
    adrp    x0, _fmt_controls@PAGE
    add     x0, x0, _fmt_controls@PAGEOFF
    bl      _printf

    // Mark needs render and trigger
    adrp    x8, _g_state@PAGE
    add     x8, x8, _g_state@PAGEOFF
    mov     w9, #1
    str     w9, [x8, #VS_NEEDS_RENDER]
    str     wzr, [x8, #VS_PHASE]

    bl      _trigger_redisplay

    ldp     x29, x30, [sp], #16
    ret


// ══════════════════════════════════════════════════════════════
//  _fv_timerFired — periodic check for redisplay
// ══════════════════════════════════════════════════════════════

.globl _fv_timerFired
_fv_timerFired:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x8, _g_state@PAGE
    add     x8, x8, _g_state@PAGEOFF
    ldr     w9, [x8, #VS_NEEDS_RENDER]
    cbz     w9, .Ltimer_done

    bl      _trigger_redisplay

.Ltimer_done:
    ldp     x29, x30, [sp], #16
    ret


// ══════════════════════════════════════════════════════════════
//  _trigger_redisplay — [g_view setNeedsDisplay:YES]
// ══════════════════════════════════════════════════════════════

.globl _trigger_redisplay
_trigger_redisplay:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x0, _str_setNeedsDisplay@PAGE
    add     x0, x0, _str_setNeedsDisplay@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
    adrp    x8, _g_view@PAGE
    ldr     x0, [x8, _g_view@PAGEOFF]
    cbz     x0, .Ltrigger_done         // guard if view not yet created
    mov     w2, #1                      // YES
    bl      _objc_msgSend

.Ltrigger_done:
    ldp     x29, x30, [sp], #16
    ret


// ══════════════════════════════════════════════════════════════
//  _save_current_ppm — save current full-res render to PPM
// ══════════════════════════════════════════════════════════════

.globl _save_current_ppm
_save_current_ppm:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    adrp    x19, _g_state@PAGE
    add     x19, x19, _g_state@PAGEOFF

    // First render full res to make sure we have current data
    adrp    x8, _g_iter_buf@PAGE
    ldr     x1, [x8, _g_iter_buf@PAGEOFF]
    adrp    x8, _g_rgb_buf@PAGE
    ldr     x2, [x8, _g_rgb_buf@PAGEOFF]
    ldr     w3, [x19, #VS_WIN_W]
    ldr     w4, [x19, #VS_WIN_H]
    mov     x0, x19
    bl      _render_fractal

    // Generate filename: snprintf(buf, 128, "fractal_%ld.ppm", time(NULL))
    mov     x0, #0
    bl      _time                       // returns time_t in x0
    mov     x20, x0                     // save timestamp

    sub     sp, sp, #144                // 128 for filename + align
    mov     x0, sp
    mov     x1, #128
    adrp    x2, _fmt_save@PAGE
    add     x2, x2, _fmt_save@PAGEOFF
    mov     x3, x20                     // timestamp
    bl      _snprintf

    // Open file: fopen(filename, "wb")
    mov     x0, sp
    adrp    x1, _str_wb@PAGE
    add     x1, x1, _str_wb@PAGEOFF
    bl      _fopen
    cbz     x0, .Lsave_fail
    mov     x21, x0                     // FILE*

    // Write PPM header
    ldr     w8, [x19, #VS_WIN_W]
    ldr     w9, [x19, #VS_WIN_H]

    // fprintf(f, "P6\n%u %u\n255\n", w, h)
    mov     x0, x21                     // FILE*
    adrp    x1, _fmt_ppm_header@PAGE
    add     x1, x1, _fmt_ppm_header@PAGEOFF
    mov     w2, w8                      // width
    mov     w3, w9                      // height
    bl      _fprintf

    // fwrite(rgb, 3, w*h, f)
    adrp    x8, _g_rgb_buf@PAGE
    ldr     x0, [x8, _g_rgb_buf@PAGEOFF]
    mov     x1, #3
    ldr     w2, [x19, #VS_WIN_W]
    ldr     w3, [x19, #VS_WIN_H]
    umull   x2, w2, w3                  // count = w * h
    mov     x3, x21                     // FILE*
    bl      _fwrite

    // fclose(f)
    mov     x0, x21
    bl      _fclose

    // Print message
    ldr     w20, [x19, #VS_WIN_W]
    ldr     w21, [x19, #VS_WIN_H]
    adrp    x0, _fmt_saved_msg@PAGE
    add     x0, x0, _fmt_saved_msg@PAGEOFF
    mov     x1, sp                      // filename
    mov     w2, w20                     // width
    mov     w3, w21                     // height
    bl      _printf

.Lsave_fail:
    add     sp, sp, #144

    ldp     x21, x22, [x29, #32]
    ldp     x19, x20, [x29, #16]
    ldp     x29, x30, [sp], #64
    ret


// ── String constants used only here ─────────────────────────

.section __TEXT,__cstring,cstring_literals

_str_wb:    .asciz "wb"
