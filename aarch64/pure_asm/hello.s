//
// hello.s — Pure AArch64 assembly, NO C runtime (macOS Apple Silicon)
//
// Uses raw macOS syscalls directly:
//   write(1, buf, len)  →  write bytes to stdout
//   exit(0)             →  clean exit
//
// This is as low-level as you can go on macOS without writing
// a kernel extension. There is zero C code involved.
//
// ┌────────────────────────────────────────────────────────────┐
// │  macOS ARM64 syscall convention:                            │
// │    x16    = syscall number                                  │
// │    x0-x5  = arguments                                       │
// │    svc #0x80 to trap into the kernel                        │
// │                                                             │
// │  macOS ARM64 calling convention (AAPCS64):                  │
// │    x0-x7   = arguments / return value                       │
// │    x9-x15  = volatile (caller-saved scratch)                │
// │    x19-x28 = non-volatile (callee-saved)                    │
// │    x29     = frame pointer                                  │
// │    x30     = link register (return address)                 │
// │    sp      = stack pointer (16-byte aligned)                │
// │                                                             │
// │  ADDRESS LOADING:                                           │
// │  On macOS, we use adrp/add pairs with @PAGE/@PAGEOFF       │
// │  relocations. adrp loads the 4KB-aligned page address,      │
// │  add adds the offset within the page. Two instructions to   │
// │  reach any symbol in the binary.                            │
// └────────────────────────────────────────────────────────────┘

.data
.p2align 3

banner:
    .ascii "==================================\n"
    .ascii "  Pure AArch64 Assembly on macOS  \n"
    .ascii "  No C runtime. Just raw machine  \n"
    .ascii "  code and macOS syscalls.        \n"
    .ascii "==================================\n"
    .ascii "\n"
banner_end:

fizz:       .ascii "Fizz\n"
fizz_end:
buzz:       .ascii "Buzz\n"
buzz_end:
fizzbuzz:   .ascii "FizzBuzz\n"
fizzbuzz_end:

done_msg:
    .ascii "\n"
    .ascii "Done. FizzBuzz 1-30 in pure AArch64 asm.\n"
    .ascii "No C. No runtime. Just vibes.\n"
done_msg_end:

.text
.globl _start
.p2align 3

//================================================================
// _start — dyld jumps straight here. No CRT init.
//================================================================
_start:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x20, x21, [sp, #16]
    stp     x22, x23, [sp, #32]

    // ── Print banner ──
    adrp    x1, banner@PAGE
    add     x1, x1, banner@PAGEOFF
    adrp    x2, banner_end@PAGE
    add     x2, x2, banner_end@PAGEOFF
    sub     x2, x2, x1             // length = end - start
    bl      write_stdout

    // ── FizzBuzz 1..30 ──
    mov     w20, #1                 // counter
    mov     w21, #30                // limit

fb_loop:
    // i%15 == 0 → FizzBuzz  (check first: 15 = lcm(3,5))
    // i%3  == 0 → Fizz
    // i%5  == 0 → Buzz
    // else      → print number
    //
    // Modulo via hardware UDIV + MSUB:  r = n - (n/d)*d

    mov     w22, #15
    udiv    w23, w20, w22
    msub    w23, w23, w22, w20      // w23 = i % 15
    cbz     w23, do_fizzbuzz

    mov     w22, #3
    udiv    w23, w20, w22
    msub    w23, w23, w22, w20      // w23 = i % 3
    cbz     w23, do_fizz

    mov     w22, #5
    udiv    w23, w20, w22
    msub    w23, w23, w22, w20      // w23 = i % 5
    cbz     w23, do_buzz

    // ── Print the number as decimal ──
    bl      print_decimal
    b       fb_next

do_fizzbuzz:
    adrp    x1, fizzbuzz@PAGE
    add     x1, x1, fizzbuzz@PAGEOFF
    adrp    x2, fizzbuzz_end@PAGE
    add     x2, x2, fizzbuzz_end@PAGEOFF
    sub     x2, x2, x1
    bl      write_stdout
    b       fb_next

do_fizz:
    adrp    x1, fizz@PAGE
    add     x1, x1, fizz@PAGEOFF
    adrp    x2, fizz_end@PAGE
    add     x2, x2, fizz_end@PAGEOFF
    sub     x2, x2, x1
    bl      write_stdout
    b       fb_next

do_buzz:
    adrp    x1, buzz@PAGE
    add     x1, x1, buzz@PAGEOFF
    adrp    x2, buzz_end@PAGE
    add     x2, x2, buzz_end@PAGEOFF
    sub     x2, x2, x1
    bl      write_stdout

fb_next:
    add     w20, w20, #1
    cmp     w20, w21
    b.le    fb_loop

    // ── Print done message ──
    adrp    x1, done_msg@PAGE
    add     x1, x1, done_msg@PAGEOFF
    adrp    x2, done_msg_end@PAGE
    add     x2, x2, done_msg_end@PAGEOFF
    sub     x2, x2, x1
    bl      write_stdout

    // ── exit(0) — never returns ──
    mov     x0, #0
    mov     x16, #1                 // SYS_exit
    svc     #0x80

//================================================================
// write_stdout — write bytes to stdout via raw syscall
//   x1  = buffer pointer
//   x2  = byte count
//
// Trashes x0 and x16 only. The kernel preserves x1-x7.
//================================================================
write_stdout:
    mov     x0, #1                  // fd = STDOUT_FILENO
    // x1 = buffer (set by caller)
    // x2 = length (set by caller)
    mov     x16, #4                 // SYS_write
    svc     #0x80
    ret

//================================================================
// print_decimal — convert w20 to ASCII digits, print + newline
//   w20 = number (1-99)
//
// Builds the digit string on the stack — no writable data
// section needed.  Stack is always writable.
//================================================================
print_decimal:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    // scratch buffer on stack at sp+16
    add     x1, sp, #16

    mov     w9, w20
    mov     w10, #10

    udiv    w11, w9, w10            // tens digit
    msub    w12, w11, w10, w9       // ones digit

    add     w12, w12, #0x30         // → ASCII
    cbz     w11, pd_one_digit

    // Two digits + newline
    add     w11, w11, #0x30
    strb    w11, [x1]
    strb    w12, [x1, #1]
    mov     w13, #0x0A
    strb    w13, [x1, #2]
    mov     x2, #3
    bl      write_stdout
    b       pd_done

pd_one_digit:
    strb    w12, [x1]
    mov     w13, #0x0A
    strb    w13, [x1, #1]
    mov     x2, #2
    bl      write_stdout

pd_done:
    ldp     x29, x30, [sp], #32
    ret
