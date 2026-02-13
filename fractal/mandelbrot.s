//
// mandelbrot.s — Scalar + NEON Mandelbrot row kernels (AArch64 / macOS)
//
// void mandelbrot_row_scalar(uint32_t *iter_out, uint32_t width,
//                            double x_min, double x_step, double y,
//                            uint32_t max_iter);
//
// void mandelbrot_row_neon(uint32_t *iter_out, uint32_t width,
//                          double x_min, double x_step, double y,
//                          uint32_t max_iter);
//
// Arguments (AArch64 calling convention):
//   x0  = iter_out     (uint32_t*)
//   w1  = width         (uint32_t)
//   d0  = x_min         (double)
//   d1  = x_step        (double)
//   d2  = y             (double)
//   w2  = max_iter      (uint32_t)
//

.text
.globl _mandelbrot_row_scalar
.globl _mandelbrot_row_neon
.p2align 4

// ══════════════════════════════════════════════════════════
//  SCALAR — one pixel at a time
// ══════════════════════════════════════════════════════════
//
//  Callee-saved registers:
//    x19  iter_out pointer (advances by 4 per pixel)
//    w20  remaining pixel count
//    w21  max_iter
//    w22  inner loop iteration counter
//    d8   current cr (real part of c, advances by x_step)
//    d9   x_step
//    d10  y (imaginary part of c, constant for row)
//    d11  4.0 (escape radius²)

_mandelbrot_row_scalar:
    // ── prologue ──
    sub     sp, sp, #64
    stp     x19, x20, [sp]
    stp     x21, x22, [sp, #16]
    stp     d8, d9, [sp, #32]
    stp     d10, d11, [sp, #48]

    mov     x19, x0
    mov     w20, w1
    mov     w21, w2
    fmov    d8, d0              // current cr = x_min
    fmov    d9, d1              // x_step
    fmov    d10, d2             // y
    fmov    d11, #4.0

    cbz     w20, .Lms_done

.Lms_pixel:
    fmov    d0, xzr             // zr = 0
    fmov    d1, xzr             // zi = 0
    mov     w22, #0
    cbz     w21, .Lms_store     // max_iter == 0 → store 0

.Lms_iter:
    // mag² = zr² + zi²
    fmul    d2, d0, d0          // zr²
    fmul    d3, d1, d1          // zi²
    fadd    d4, d2, d3
    fcmp    d4, d11
    b.gt    .Lms_store          // escaped

    // new_zi = 2·zr·zi + ci
    fmul    d4, d0, d1
    fadd    d4, d4, d4
    fadd    d1, d4, d10

    // new_zr = zr² - zi² + cr
    fsub    d0, d2, d3
    fadd    d0, d0, d8

    add     w22, w22, #1
    cmp     w22, w21
    b.lo    .Lms_iter

.Lms_store:
    str     w22, [x19], #4
    fadd    d8, d8, d9          // cr += x_step
    subs    w20, w20, #1
    b.ne    .Lms_pixel

.Lms_done:
    ldp     d10, d11, [sp, #48]
    ldp     d8, d9, [sp, #32]
    ldp     x21, x22, [sp, #16]
    ldp     x19, x20, [sp]
    add     sp, sp, #64
    ret


// ══════════════════════════════════════════════════════════
//  NEON — two pixels at a time (float64x2)
// ══════════════════════════════════════════════════════════
//
//  Callee-saved:
//    x19  iter_out pointer (advances by 8 per pair)
//    w20  remaining pixel count
//    w21  max_iter
//    w22  inner loop counter
//    x23  scratch for mask check
//    d8   cr_base (advances by 2·x_step per pair)
//    d9   x_step
//    d10  y
//    d11  2·x_step
//
//  Inner loop (caller-saved):
//    v0   zr  (float64x2)
//    v1   zi  (float64x2)
//    v2   cr  (float64x2)  — set per pair
//    v3   ci  (float64x2)  — constant for row
//    v4   4.0 (float64x2)  — escape threshold
//    v5-v7  scratch
//    v16  active mask  (uint64x2, all-1s = active)
//    v18  iteration counts (uint64x2)
//    v20  offset vector [0, x_step]

_mandelbrot_row_neon:
    sub     sp, sp, #80
    stp     x19, x20, [sp]
    stp     x21, x22, [sp, #16]
    str     x23, [sp, #32]
    stp     d8, d9, [sp, #40]
    stp     d10, d11, [sp, #56]

    mov     x19, x0
    mov     w20, w1
    mov     w21, w2
    fmov    d8, d0              // cr_base = x_min
    fmov    d9, d1              // x_step
    fmov    d10, d2             // y
    fadd    d11, d1, d1         // 2·x_step

    // Constants that persist across pixel pairs
    fmov    d4, #4.0
    dup     v4.2d, v4.d[0]     // v4 = [4.0, 4.0]
    movi    v20.2d, #0
    ins     v20.d[1], v9.d[0]  // v20 = [0, x_step]
    dup     v3.2d, v10.d[0]    // v3 = ci = [y, y]

    cbz     w20, .Lmn_done

.Lmn_pixel:
    cmp     w20, #2
    b.lo    .Lmn_tail

    // cr = [cr_base, cr_base + x_step]
    dup     v2.2d, v8.d[0]
    fadd    v2.2d, v2.2d, v20.2d

    // z = (0, 0)
    movi    v0.2d, #0
    movi    v1.2d, #0

    movi    v16.16b, #0xFF     // active mask = all active
    movi    v18.2d, #0         // iteration counts = 0
    mov     w22, #0
    cbz     w21, .Lmn_pair_done

    // ────────────────────────────────────────
    //  NEON inner loop: z = z² + c for 2 lanes
    // ────────────────────────────────────────
.Lmn_iter:
    // 1. zr², zi²
    fmul    v5.2d, v0.2d, v0.2d
    fmul    v6.2d, v1.2d, v1.2d

    // 2. escape check: mag² > 4.0?
    fadd    v7.2d, v5.2d, v6.2d
    fcmgt   v7.2d, v7.2d, v4.2d

    // 3. update active mask
    bic     v16.16b, v16.16b, v7.16b

    // 4. all lanes escaped?
    addp    d17, v16.2d
    fmov    x23, d17
    cbz     x23, .Lmn_pair_done

    // 5. increment iter for active lanes (mask = -1 → sub -1 = add 1)
    sub     v18.2d, v18.2d, v16.2d

    // 6. new_zr = zr² - zi² + cr
    fsub    v7.2d, v5.2d, v6.2d
    fadd    v7.2d, v7.2d, v2.2d

    // 7. new_zi = 2·zr·zi + ci
    fmul    v5.2d, v0.2d, v1.2d
    fadd    v5.2d, v5.2d, v5.2d
    fadd    v5.2d, v5.2d, v3.2d

    // 8. masked z update (only active lanes change)
    bit     v0.16b, v7.16b, v16.16b
    bit     v1.16b, v5.16b, v16.16b

    add     w22, w22, #1
    cmp     w22, w21
    b.lo    .Lmn_iter

.Lmn_pair_done:
    // narrow 64→32 bit counts and store 2 × uint32_t
    xtn     v18.2s, v18.2d
    str     d18, [x19], #8

    fadd    d8, d8, d11         // cr_base += 2·x_step
    sub     w20, w20, #2
    b       .Lmn_pixel

    // ── scalar tail for 1 remaining pixel ──
.Lmn_tail:
    cbz     w20, .Lmn_done

    fmov    d0, xzr
    fmov    d1, xzr
    fmov    d5, #4.0
    mov     w22, #0
    cbz     w21, .Lmn_tail_store

.Lmn_tail_iter:
    fmul    d2, d0, d0
    fmul    d3, d1, d1
    fadd    d6, d2, d3
    fcmp    d6, d5
    b.gt    .Lmn_tail_store

    fmul    d6, d0, d1
    fadd    d6, d6, d6
    fadd    d1, d6, d10

    fsub    d0, d2, d3
    fadd    d0, d0, d8

    add     w22, w22, #1
    cmp     w22, w21
    b.lo    .Lmn_tail_iter

.Lmn_tail_store:
    str     w22, [x19]

.Lmn_done:
    ldp     d10, d11, [sp, #56]
    ldp     d8, d9, [sp, #40]
    ldr     x23, [sp, #32]
    ldp     x21, x22, [sp, #16]
    ldp     x19, x20, [sp]
    add     sp, sp, #80
    ret
