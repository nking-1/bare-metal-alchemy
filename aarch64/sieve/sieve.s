//
// sieve.s — Sieve of Eratosthenes in AArch64 assembly (macOS)
//
// void sieve(uint8_t *buffer, uint32_t limit)
//
// On return, buffer[i] == 1 means i is prime (for i in [0..limit]).
//

.text
.globl _sieve
.p2align 3

// ── Register map ──────────────────────────────────
//   x19  buffer base pointer
//   x20  limit
//   x21  outer loop index  i
//   x22  inner loop index  j  (also holds i*i)
//   x23  scratch
// ──────────────────────────────────────────────────

_sieve:
    // ── prologue ──
    stp     x19, x20, [sp, #-48]!
    stp     x21, x22, [sp, #16]
    stp     x23, x30, [sp, #32]

    mov     x19, x0                 // buffer
    mov     w20, w1                 // limit  (zero-extends into x20)

    // ── 1. fill buffer[0 .. limit] with 1 ──
    mov     x21, #0
fill_loop:
    cmp     x21, x20
    b.gt    fill_done
    mov     w23, #1
    strb    w23, [x19, x21]
    add     x21, x21, #1
    b       fill_loop
fill_done:

    // ── 2. 0 and 1 are not prime ──
    strb    wzr, [x19]              // buffer[0] = 0
    strb    wzr, [x19, #1]          // buffer[1] = 0

    // ── 3. sieve: for each i from 2 while i*i <= limit ──
    mov     x21, #2
sieve_outer:
    mul     x22, x21, x21          // j = i * i
    cmp     x22, x20
    b.gt    sieve_done              // i*i > limit → finished

    ldrb    w23, [x19, x21]        // is i still marked prime?
    cbz     w23, sieve_skip         // no → next i

    // mark composites: j = i*i, i*i+i, i*i+2i, …
mark_composites:
    cmp     x22, x20
    b.gt    sieve_skip
    strb    wzr, [x19, x22]        // buffer[j] = 0  (composite)
    add     x22, x22, x21          // j += i
    b       mark_composites

sieve_skip:
    add     x21, x21, #1
    b       sieve_outer

sieve_done:
    // ── epilogue ──
    ldp     x23, x30, [sp, #32]
    ldp     x21, x22, [sp, #16]
    ldp     x19, x20, [sp], #48
    ret
