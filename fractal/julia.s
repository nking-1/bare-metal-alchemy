//
// julia.s — Scalar + NEON Julia set row kernels (AArch64 / macOS)
//
// void julia_row_scalar(uint32_t *iter_out, uint32_t width,
//                       double x_min, double x_step, double y,
//                       double jr, double ji, uint32_t max_iter);
//
// void julia_row_neon(uint32_t *iter_out, uint32_t width,
//                     double x_min, double x_step, double y,
//                     double jr, double ji, uint32_t max_iter);
//
// Arguments (AArch64 calling convention):
//   x0  = iter_out     (uint32_t*)
//   w1  = width         (uint32_t)
//   d0  = x_min         (double)
//   d1  = x_step        (double)
//   d2  = y             (double)
//   d3  = jr            (double)   ← Julia c real part
//   d4  = ji            (double)   ← Julia c imag part
//   w2  = max_iter      (uint32_t)
//
// Difference from Mandelbrot:
//   z starts at (pixel_x, y) instead of (0, 0)
//   c = (jr, ji) is constant instead of (pixel_x, y)
//

.text
.globl _julia_row_scalar
.globl _julia_row_neon
.p2align 4

// ══════════════════════════════════════════════════════════
//  SCALAR — one pixel at a time
// ══════════════════════════════════════════════════════════
//
//  Callee-saved:
//    x19  iter_out pointer
//    w20  remaining pixel count
//    w21  max_iter
//    w22  inner loop counter
//    d8   current pixel_x (advances by x_step)
//    d9   x_step
//    d10  y
//    d11  jr  (c real, constant)
//    d12  ji  (c imag, constant)
//    d13  4.0 (escape radius²)

_julia_row_scalar:
    sub     sp, sp, #80
    stp     x19, x20, [sp]
    stp     x21, x22, [sp, #16]
    stp     d8, d9, [sp, #32]
    stp     d10, d11, [sp, #48]
    stp     d12, d13, [sp, #64]

    mov     x19, x0
    mov     w20, w1
    mov     w21, w2
    fmov    d8, d0              // current pixel_x = x_min
    fmov    d9, d1              // x_step
    fmov    d10, d2             // y
    fmov    d11, d3             // jr
    fmov    d12, d4             // ji
    fmov    d13, #4.0

    cbz     w20, .Ljs_done

.Ljs_pixel:
    fmov    d0, d8              // zr = pixel_x
    fmov    d1, d10             // zi = y
    mov     w22, #0
    cbz     w21, .Ljs_store

.Ljs_iter:
    fmul    d2, d0, d0          // zr²
    fmul    d3, d1, d1          // zi²
    fadd    d4, d2, d3
    fcmp    d4, d13
    b.gt    .Ljs_store

    // new_zi = 2·zr·zi + ji
    fmul    d4, d0, d1
    fadd    d4, d4, d4
    fadd    d1, d4, d12

    // new_zr = zr² - zi² + jr
    fsub    d0, d2, d3
    fadd    d0, d0, d11

    add     w22, w22, #1
    cmp     w22, w21
    b.lo    .Ljs_iter

.Ljs_store:
    str     w22, [x19], #4
    fadd    d8, d8, d9
    subs    w20, w20, #1
    b.ne    .Ljs_pixel

.Ljs_done:
    ldp     d12, d13, [sp, #64]
    ldp     d10, d11, [sp, #48]
    ldp     d8, d9, [sp, #32]
    ldp     x21, x22, [sp, #16]
    ldp     x19, x20, [sp]
    add     sp, sp, #80
    ret


// ══════════════════════════════════════════════════════════
//  NEON — two pixels at a time (float64x2)
// ══════════════════════════════════════════════════════════
//
//  Callee-saved:
//    x19  iter_out pointer
//    w20  remaining pixel count
//    w21  max_iter
//    w22  inner loop counter
//    x23  scratch for mask check
//    d8   current pixel_x base (advances by 2·x_step)
//    d9   x_step
//    d10  y
//    d11  2·x_step
//    d12  jr
//    d13  ji
//
//  Inner loop (caller-saved):
//    v0   zr  (float64x2)  — starts at pixel position
//    v1   zi  (float64x2)  — starts at [y, y]
//    v2   cr  (float64x2)  — [jr, jr] constant
//    v3   ci  (float64x2)  — [ji, ji] constant
//    v4   4.0 (float64x2)
//    v5-v7  scratch
//    v16  active mask
//    v18  iteration counts
//    v20  offset vector [0, x_step]

_julia_row_neon:
    sub     sp, sp, #96
    stp     x19, x20, [sp]
    stp     x21, x22, [sp, #16]
    str     x23, [sp, #32]
    stp     d8, d9, [sp, #40]
    stp     d10, d11, [sp, #56]
    stp     d12, d13, [sp, #72]

    mov     x19, x0
    mov     w20, w1
    mov     w21, w2
    fmov    d8, d0              // pixel_x base = x_min
    fmov    d9, d1              // x_step
    fmov    d10, d2             // y
    fadd    d11, d1, d1         // 2·x_step
    fmov    d12, d3             // jr
    fmov    d13, d4             // ji

    // Constants that persist across pixel pairs
    fmov    d4, #4.0
    dup     v4.2d, v4.d[0]     // v4 = [4.0, 4.0]
    movi    v20.2d, #0
    ins     v20.d[1], v9.d[0]  // v20 = [0, x_step]
    dup     v2.2d, v12.d[0]    // v2 = cr = [jr, jr] (constant)
    dup     v3.2d, v13.d[0]    // v3 = ci = [ji, ji] (constant)

    cbz     w20, .Ljn_done

.Ljn_pixel:
    cmp     w20, #2
    b.lo    .Ljn_tail

    // z starts at pixel position
    dup     v0.2d, v8.d[0]
    fadd    v0.2d, v0.2d, v20.2d   // zr = [pixel_x, pixel_x + x_step]
    dup     v1.2d, v10.d[0]        // zi = [y, y]

    movi    v16.16b, #0xFF
    movi    v18.2d, #0
    mov     w22, #0
    cbz     w21, .Ljn_pair_done

.Ljn_iter:
    fmul    v5.2d, v0.2d, v0.2d
    fmul    v6.2d, v1.2d, v1.2d

    fadd    v7.2d, v5.2d, v6.2d
    fcmgt   v7.2d, v7.2d, v4.2d

    bic     v16.16b, v16.16b, v7.16b

    addp    d17, v16.2d
    fmov    x23, d17
    cbz     x23, .Ljn_pair_done

    sub     v18.2d, v18.2d, v16.2d

    fsub    v7.2d, v5.2d, v6.2d
    fadd    v7.2d, v7.2d, v2.2d

    fmul    v5.2d, v0.2d, v1.2d
    fadd    v5.2d, v5.2d, v5.2d
    fadd    v5.2d, v5.2d, v3.2d

    bit     v0.16b, v7.16b, v16.16b
    bit     v1.16b, v5.16b, v16.16b

    add     w22, w22, #1
    cmp     w22, w21
    b.lo    .Ljn_iter

.Ljn_pair_done:
    xtn     v18.2s, v18.2d
    str     d18, [x19], #8

    fadd    d8, d8, d11
    sub     w20, w20, #2
    b       .Ljn_pixel

.Ljn_tail:
    cbz     w20, .Ljn_done

    fmov    d0, d8              // zr = pixel_x
    fmov    d1, d10             // zi = y
    fmov    d5, #4.0
    mov     w22, #0
    cbz     w21, .Ljn_tail_store

.Ljn_tail_iter:
    fmul    d2, d0, d0
    fmul    d3, d1, d1
    fadd    d6, d2, d3
    fcmp    d6, d5
    b.gt    .Ljn_tail_store

    fmul    d6, d0, d1
    fadd    d6, d6, d6
    fadd    d1, d6, d13         // + ji

    fsub    d0, d2, d3
    fadd    d0, d0, d12         // + jr

    add     w22, w22, #1
    cmp     w22, w21
    b.lo    .Ljn_tail_iter

.Ljn_tail_store:
    str     w22, [x19]

.Ljn_done:
    ldp     d12, d13, [sp, #72]
    ldp     d10, d11, [sp, #56]
    ldp     d8, d9, [sp, #40]
    ldr     x23, [sp, #32]
    ldp     x21, x22, [sp, #16]
    ldp     x19, x20, [sp]
    add     sp, sp, #96
    ret
