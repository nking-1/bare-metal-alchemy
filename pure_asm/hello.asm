;
; hello.asm — Pure AArch64 assembly, NO C runtime
;
; Calls Win32 API directly:
;   GetStdHandle(-11)  →  get console handle
;   WriteFile(...)     →  write bytes to console
;   ExitProcess(0)     →  clean exit
;
; This is as low-level as you can go on Windows without writing
; a kernel driver. There is zero C code involved.
;
; ┌────────────────────────────────────────────────────────────┐
; │  Win64 ARM64 calling convention:                           │
; │    x0-x7   = arguments / return value                      │
; │    x9-x15  = volatile (caller-saved scratch)               │
; │    x19-x28 = non-volatile (callee-saved)                   │
; │    x29     = frame pointer                                 │
; │    x30     = link register (return address)                │
; │    sp      = stack pointer (16-byte aligned)               │
; │                                                             │
; │  ARM64 Windows does NOT use x64-style shadow space.        │
; │  Args 0-7 go in x0-x7. Args 8+ go on the stack.           │
; │                                                             │
; │  ADDRESS LOADING:                                           │
; │  MSVC armasm64 doesn't support GNU-style :lo12: syntax.    │
; │  We use "ldr x0, =label" which emits a literal pool entry  │
; │  containing the full 64-bit address. The assembler places   │
; │  these entries at LTORG directives or at END. The CPU does  │
; │  a PC-relative load to grab the address — one instruction   │
; │  instead of two, and it Just Works across sections.         │
; └────────────────────────────────────────────────────────────┘

    AREA |.data|, DATA, ALIGN=3

banner  DCB "==================================", 0x0D, 0x0A
        DCB "  Pure AArch64 Assembly on Win64  ", 0x0D, 0x0A
        DCB "  No C runtime. Just raw machine  ", 0x0D, 0x0A
        DCB "  code and Windows API calls.     ", 0x0D, 0x0A
        DCB "==================================", 0x0D, 0x0A
        DCB 0x0D, 0x0A
banner_end

fizz    DCB "Fizz", 0x0D, 0x0A
fizz_end
buzz    DCB "Buzz", 0x0D, 0x0A
buzz_end
fizzbuzz DCB "FizzBuzz", 0x0D, 0x0A
fizzbuzz_end

done_msg DCB 0x0D, 0x0A
         DCB "Done. FizzBuzz 1-30 in pure AArch64 asm.", 0x0D, 0x0A
         DCB "No C. No runtime. Just vibes.", 0x0D, 0x0A
done_msg_end

    AREA |.text|, CODE, READONLY, ALIGN=3

    ; Win32 API imports — the linker resolves these from kernel32.lib
    IMPORT GetStdHandle
    IMPORT WriteFile
    IMPORT ExitProcess

    ; Entry point — replaces main/WinMain entirely
    EXPORT mainCRTStartup

;================================================================
; mainCRTStartup — the OS jumps straight here. No CRT init.
;================================================================
mainCRTStartup PROC
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    ; ── Get stdout handle ──
    ; STD_OUTPUT_HANDLE = (DWORD)-11
    movn    w0, #10                 ; w0 = ~10 = -11 (0xFFFFFFF5)
    bl      GetStdHandle
    mov     x19, x0                 ; x19 = stdout handle

    ; ── Print banner ──
    ; "ldr x1, =banner" loads the address of banner from a literal pool.
    ; The assembler auto-generates a nearby data slot holding the 64-bit
    ; address, and emits a PC-relative LDR to fetch it.
    ldr     x1, =banner
    ldr     x2, =banner_end
    sub     x2, x2, x1             ; length = end - start
    bl      write_stdout

    ; ── FizzBuzz 1..30 ──
    mov     w20, #1                 ; counter
    mov     w21, #30                ; limit

fb_loop
    ; i%15 == 0 → FizzBuzz  (check first: 15 = lcm(3,5))
    ; i%3  == 0 → Fizz
    ; i%5  == 0 → Buzz
    ; else      → print number
    ;
    ; Modulo without DIV instruction?  Nah, AArch64 has hardware
    ; UDIV.  We get the remainder via:  r = n - (n/d)*d  (MSUB).

    mov     w22, #15
    udiv    w23, w20, w22
    msub    w23, w23, w22, w20      ; w23 = i % 15
    cbz     w23, do_fizzbuzz

    mov     w22, #3
    udiv    w23, w20, w22
    msub    w23, w23, w22, w20      ; w23 = i % 3
    cbz     w23, do_fizz

    mov     w22, #5
    udiv    w23, w20, w22
    msub    w23, w23, w22, w20      ; w23 = i % 5
    cbz     w23, do_buzz

    ; ── Print the number as decimal ──
    bl      print_decimal
    b       fb_next

do_fizzbuzz
    ldr     x1, =fizzbuzz
    ldr     x2, =fizzbuzz_end
    sub     x2, x2, x1
    bl      write_stdout
    b       fb_next

do_fizz
    ldr     x1, =fizz
    ldr     x2, =fizz_end
    sub     x2, x2, x1
    bl      write_stdout
    b       fb_next

do_buzz
    ldr     x1, =buzz
    ldr     x2, =buzz_end
    sub     x2, x2, x1
    bl      write_stdout

fb_next
    add     w20, w20, #1
    cmp     w20, w21
    b.le    fb_loop

    ; ── Print done message ──
    ldr     x1, =done_msg
    ldr     x2, =done_msg_end
    sub     x2, x2, x1
    bl      write_stdout

    ; ── ExitProcess(0) — never returns ──
    mov     w0, #0
    bl      ExitProcess

    ; Literal pool — the assembler dumps all "=label" addresses here.
    ; Without this, they'd go at END, which might be too far away
    ; for the PC-relative LDR to reach (±1 MB range).
    LTORG

    ENDP

;================================================================
; write_stdout — write bytes to console
;   x19 = stdout handle (preserved across calls)
;   x1  = buffer pointer
;   x2  = byte count
;================================================================
write_stdout PROC
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    ; BOOL WriteFile(HANDLE, LPCVOID, DWORD nBytes, LPDWORD written, LPOVERLAPPED)
    mov     x0, x19                 ; hFile = stdout
    ;   x1 already = lpBuffer
    ;   x2 already = nNumberOfBytesToWrite
    str     xzr, [sp, #16]         ; bytesWritten slot
    add     x3, sp, #16            ; lpNumberOfBytesWritten
    mov     x4, #0                 ; lpOverlapped = NULL
    bl      WriteFile

    ldp     x29, x30, [sp], #32
    ret
    ENDP

;================================================================
; print_decimal — convert w20 to ASCII digits, print + CRLF
;   w20 = number (1-99)
;   x19 = stdout handle
;
;   We build the digit string on the stack — no writable data
;   section needed.  Stack is always writable.
;================================================================
print_decimal PROC
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    ; x1 = scratch buffer on stack (bytes at sp+16..sp+19)
    add     x1, sp, #16

    mov     w9, w20
    mov     w10, #10

    udiv    w11, w9, w10            ; tens digit
    msub    w12, w11, w10, w9       ; ones digit

    add     w12, w12, #0x30         ; → ASCII
    cbz     w11, pd_one_digit

    ; Two digits + CRLF
    add     w11, w11, #0x30
    strb    w11, [x1]
    strb    w12, [x1, #1]
    mov     w13, #0x0D
    strb    w13, [x1, #2]
    mov     w13, #0x0A
    strb    w13, [x1, #3]
    mov     x2, #4
    bl      write_stdout
    b       pd_done

pd_one_digit
    strb    w12, [x1]
    mov     w13, #0x0D
    strb    w13, [x1, #1]
    mov     w13, #0x0A
    strb    w13, [x1, #2]
    mov     x2, #3
    bl      write_stdout

pd_done
    ldp     x29, x30, [sp], #32
    ret
    ENDP

    END
