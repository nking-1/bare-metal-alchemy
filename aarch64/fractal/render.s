//
// render.s — Compute, render, and convert functions (AArch64 / macOS)
//
// Pure computation — no ObjC calls. Reuses NEON kernels from mandelbrot.s
// and julia.s, plus colormap_apply from colormap.s.
//
// Functions:
//   _compute_view      — compute view bounds from state
//   _render_fractal    — render full image, return time in d0
//   _rgb24_to_argb32   — convert RGB24 buffer to ARGB32
//   _screen_to_complex — convert screen pixel to complex coordinate
//

.include "state_defs.s"

.text
.p2align 4

// ══════════════════════════════════════════════════════════════
//  _compute_view — compute view bounds from center/zoom
// ══════════════════════════════════════════════════════════════
//
// Args:
//   x0 = state_ptr (ViewerState*)
//   x1 = out_x_min (double*)
//   x2 = out_y_min (double*)
//   x3 = out_x_step (double*)
//   x4 = out_y_step (double*)
//   w5 = rw (uint32_t — render width)
//   w6 = rh (uint32_t — render height)
//
// Math:
//   aspect = rw / rh
//   half_h = 2.0 / zoom
//   half_w = half_h * aspect
//   x_min  = center_x - half_w
//   y_min  = center_y - half_h
//   x_step = (2.0 * half_w) / rw
//   y_step = (2.0 * half_h) / rh

.globl _compute_view
_compute_view:
    // Load state fields
    ldr     d4, [x0, #VS_CENTER_X]     // d4 = center_x
    ldr     d5, [x0, #VS_CENTER_Y]     // d5 = center_y
    ldr     d6, [x0, #VS_ZOOM]         // d6 = zoom

    // aspect = (double)rw / (double)rh
    ucvtf   d0, w5                      // d0 = (double)rw
    ucvtf   d1, w6                      // d1 = (double)rh
    fdiv    d2, d0, d1                  // d2 = aspect

    // half_h = 2.0 / zoom
    fmov    d3, #2.0
    fdiv    d7, d3, d6                  // d7 = half_h

    // half_w = half_h * aspect
    fmul    d16, d7, d2                 // d16 = half_w

    // x_min = center_x - half_w
    fsub    d17, d4, d16
    str     d17, [x1]                   // *out_x_min

    // y_min = center_y - half_h
    fsub    d17, d5, d7
    str     d17, [x2]                   // *out_y_min

    // x_step = (2.0 * half_w) / rw
    fadd    d17, d16, d16               // 2*half_w
    fdiv    d17, d17, d0                // / rw
    str     d17, [x3]                   // *out_x_step

    // y_step = (2.0 * half_h) / rh
    fadd    d17, d7, d7                 // 2*half_h
    fdiv    d17, d17, d1                // / rh
    str     d17, [x4]                   // *out_y_step

    ret


// ══════════════════════════════════════════════════════════════
//  _render_fractal — render full image using NEON kernels
// ══════════════════════════════════════════════════════════════
//
// Args:
//   x0 = state_ptr (ViewerState*)
//   x1 = iter_buf  (uint32_t*)
//   x2 = rgb_buf   (uint8_t*)
//   w3 = rw        (uint32_t — render width)
//   w4 = rh        (uint32_t — render height)
//
// Returns:
//   d0 = render time in milliseconds
//
// Uses callee-saved: x19-x28, d8-d14

.globl _render_fractal
_render_fractal:
    // Prologue — save callee-saved regs
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
    str     d14, [sp, #144]

    // Save args
    mov     x19, x0                     // state_ptr
    mov     x20, x1                     // iter_buf
    mov     x21, x2                     // rgb_buf
    mov     w22, w3                     // rw
    mov     w23, w4                     // rh

    // Compute view bounds — use stack for outputs
    sub     sp, sp, #48                 // 4 doubles + alignment
    mov     x0, x19                     // state
    add     x1, sp, #0                  // &x_min
    add     x2, sp, #8                  // &y_min
    add     x3, sp, #16                 // &x_step
    add     x4, sp, #24                 // &y_step
    mov     w5, w22                     // rw
    mov     w6, w23                     // rh
    bl      _compute_view

    // Load computed values
    ldr     d8, [sp, #0]               // d8  = x_min
    ldr     d9, [sp, #8]               // d9  = y_min
    ldr     d10, [sp, #16]             // d10 = x_step
    ldr     d11, [sp, #24]             // d11 = y_step
    add     sp, sp, #48

    // Get timing: clock_gettime(CLOCK_MONOTONIC, &ts)
    sub     sp, sp, #32                 // timespec (16 bytes) × 2
    mov     w0, #6                      // CLOCK_MONOTONIC_RAW on macOS = 4, CLOCK_MONOTONIC = 6
    add     x1, sp, #0                  // &t0
    bl      _clock_gettime
    // t0 is at [sp, #0..#15]

    // Load state fields for kernel dispatch
    ldr     w24, [x19, #VS_JULIA_MODE] // julia_mode
    ldr     w25, [x19, #VS_MAX_ITER]   // max_iter
    ldr     d12, [x19, #VS_JR]         // jr
    ldr     d13, [x19, #VS_JI]         // ji

    // Row loop: for row = 0 .. rh-1
    mov     w26, #0                     // row counter
    // Precompute row stride in bytes for iter_buf: rw * 4
    lsl     w27, w22, #2               // row_stride = rw * 4

.Lrow_loop:
    cmp     w26, w23
    b.ge    .Lrow_done

    // y = y_min + row * y_step
    ucvtf   d2, w26
    fmadd   d2, d2, d11, d9            // d2 = y

    // iter_out = iter_buf + row * rw
    umull   x28, w26, w22
    add     x0, x20, x28, lsl #2       // x0 = &iter_buf[row * rw]

    mov     w1, w22                     // width = rw
    fmov    d0, d8                      // x_min
    fmov    d1, d10                     // x_step
    // d2 already set to y

    cbz     w24, .Lrow_mandelbrot

    // Julia mode
    fmov    d3, d12                     // jr
    fmov    d4, d13                     // ji
    mov     w2, w25                     // max_iter
    bl      _julia_row_neon
    b       .Lrow_next

.Lrow_mandelbrot:
    mov     w2, w25                     // max_iter
    bl      _mandelbrot_row_neon

.Lrow_next:
    add     w26, w26, #1
    b       .Lrow_loop

.Lrow_done:
    // End timing
    mov     w0, #6                      // CLOCK_MONOTONIC
    add     x1, sp, #16                 // &t1
    bl      _clock_gettime

    // Compute elapsed ms: (t1.sec - t0.sec)*1000 + (t1.nsec - t0.nsec)/1e6
    ldr     x0, [sp, #16]              // t1.tv_sec
    ldr     x1, [sp, #0]               // t0.tv_sec
    sub     x0, x0, x1
    scvtf   d0, x0                      // (double)(sec diff)
    adrp    x8, _const_1000_0@PAGE
    ldr     d1, [x8, _const_1000_0@PAGEOFF]
    fmul    d0, d0, d1                  // * 1000.0

    ldr     x2, [sp, #24]              // t1.tv_nsec
    ldr     x3, [sp, #8]               // t0.tv_nsec
    sub     x2, x2, x3
    scvtf   d2, x2
    adrp    x8, _const_1e6@PAGE
    ldr     d3, [x8, _const_1e6@PAGEOFF]
    fdiv    d2, d2, d3                  // nsec diff / 1e6
    fadd    d14, d0, d2                 // d14 = total ms

    add     sp, sp, #32                 // free timespec space

    // Apply colormap: colormap_apply(rgb_buf, iter_buf, rw*rh, max_iter)
    mov     x0, x21                     // rgb_buf
    mov     x1, x20                     // iter_buf
    umull   x2, w22, w23               // rw * rh
    mov     w3, w25                     // max_iter
    bl      _colormap_apply

    // Return time in d0
    fmov    d0, d14

    // Epilogue
    ldr     d14, [x29, #144]
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
//  _rgb24_to_argb32 — convert RGB24 to ARGB8888
// ══════════════════════════════════════════════════════════════
//
// Args:
//   x0 = dst       (uint32_t*) — ARGB32 output, contiguous
//   w1 = dst_stride (int) — bytes per row (unused, we do contiguous)
//   x2 = src_rgb   (uint8_t*) — RGB24 input
//   w3 = width     (uint32_t)
//   w4 = height    (uint32_t)
//
// Layout: dst[y*width+x] = 0xFF000000 | (r<<16) | (g<<8) | b

.globl _rgb24_to_argb32
_rgb24_to_argb32:
    // Total pixels = width * height
    umull   x5, w3, w4                  // total pixels
    cbz     x5, .Largb_done

    // NEON loop: process 8 pixels at a time
    mov     x6, #8
    mov     x7, #0                      // pixel counter
    // Preload alpha = 0xFF in a vector
    movi    v3.8b, #0xFF               // alpha channel

    cmp     x5, x6
    b.lo    .Largb_scalar_loop

.Largb_neon_loop:
    sub     x8, x5, x7                 // remaining
    cmp     x8, #8
    b.lo    .Largb_scalar_loop

    // Load 8 pixels = 24 bytes as interleaved R,G,B
    ld3     {v0.8b, v1.8b, v2.8b}, [x2], #24   // v0=R, v1=G, v2=B

    // Rearrange to consecutive regs for st4: B,G,R,A in v4-v7
    mov     v4.8b, v2.8b               // B
    mov     v5.8b, v1.8b               // G
    mov     v6.8b, v0.8b               // R
    mov     v7.8b, v3.8b               // A (0xFF)

    // Store as interleaved B,G,R,A (little-endian ARGB32 = byte order B,G,R,A)
    st4     {v4.8b, v5.8b, v6.8b, v7.8b}, [x0], #32

    add     x7, x7, #8
    b       .Largb_neon_loop

.Largb_scalar_loop:
    cmp     x7, x5
    b.ge    .Largb_done

    ldrb    w8, [x2], #1               // R
    ldrb    w9, [x2], #1               // G
    ldrb    w10, [x2], #1              // B

    // ARGB32 little-endian: byte order is B, G, R, A
    orr     w11, w10, w9, lsl #8       // B | (G << 8)
    orr     w11, w11, w8, lsl #16      // | (R << 16)
    orr     w11, w11, #0xFF000000      // | (0xFF << 24)
    str     w11, [x0], #4

    add     x7, x7, #1
    b       .Largb_scalar_loop

.Largb_done:
    ret


// ══════════════════════════════════════════════════════════════
//  _screen_to_complex — convert screen pixel to complex coords
// ══════════════════════════════════════════════════════════════
//
// Args:
//   x0 = state_ptr (ViewerState*)
//   w1 = sx (int — screen x)
//   w2 = sy (int — screen y)
//
// Returns:
//   d0 = re (real part)
//   d1 = im (imaginary part)

.globl _screen_to_complex
_screen_to_complex:
    // Load state
    ldr     w3, [x0, #VS_WIN_W]        // win_w
    ldr     w4, [x0, #VS_WIN_H]        // win_h
    ldr     d2, [x0, #VS_CENTER_X]     // center_x
    ldr     d3, [x0, #VS_CENTER_Y]     // center_y
    ldr     d4, [x0, #VS_ZOOM]         // zoom

    // aspect = win_w / win_h
    ucvtf   d5, w3                      // (double)win_w
    ucvtf   d6, w4                      // (double)win_h
    fdiv    d7, d5, d6                  // aspect

    // half_h = 2.0 / zoom
    fmov    d16, #2.0
    fdiv    d17, d16, d4                // half_h

    // half_w = half_h * aspect
    fmul    d18, d17, d7               // half_w

    // re = center_x - half_w + (2.0 * half_w) * sx / win_w
    scvtf   d0, w1                      // (double)sx
    fadd    d19, d18, d18              // 2*half_w
    fmul    d0, d19, d0                // 2*half_w * sx
    fdiv    d0, d0, d5                 // / win_w
    fsub    d20, d2, d18               // center_x - half_w
    fadd    d0, d20, d0                // + offset

    // im = center_y - half_h + (2.0 * half_h) * sy / win_h
    scvtf   d1, w2                      // (double)sy
    fadd    d21, d17, d17              // 2*half_h
    fmul    d1, d21, d1                // 2*half_h * sy
    fdiv    d1, d1, d6                 // / win_h
    fsub    d22, d3, d17               // center_y - half_h
    fadd    d1, d22, d1                // + offset

    ret
