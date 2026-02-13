;
; neon_upper.asm — NEON SIMD uppercase conversion
;
; Two implementations: NEON (16 chars/iteration) vs scalar (1 char/iteration)
;
; ┌─────────────────────────────────────────────────────────────┐
; │  KEY INSIGHT: In ASCII, 'a'=0x61 and 'A'=0x41.             │
; │  The ONLY difference is bit 5 (0x20 = 32).                 │
; │                                                             │
; │    'a' = 0110 0001                                         │
; │    'A' = 0100 0001                                         │
; │              ^                                              │
; │         this one bit!                                       │
; │                                                             │
; │  So: subtract 0x20 from lowercase → uppercase.              │
; │  With NEON, we do this for 16 chars simultaneously.         │
; └─────────────────────────────────────────────────────────────┘
;

    AREA |.text|, CODE, READONLY, ALIGN=3

    EXPORT neon_toupper
    EXPORT scalar_toupper

;================================================================
; void neon_toupper(char *str, uint64_t len)
;
; NEON version — processes 16 characters per loop iteration.
;
; NEON registers are 128 bits = 16 bytes wide.  We treat them
; as vectors of 16 uint8 lanes (the ".16b" suffix).
;
;   v0 = the 16 characters we're working on
;   v1 = [ 'a', 'a', 'a', ... ] (16 copies of 0x61)
;   v2 = [ 'z', 'z', 'z', ... ] (16 copies of 0x7A)
;   v3 = [ 32,  32,  32,  ... ] (16 copies of 0x20)
;   v4 = mask: 0xFF where lowercase, 0x00 elsewhere
;   v5 = scratch
;================================================================

neon_toupper PROC
    ; x0 = string pointer,  x1 = length

    ; ── Set up constant vectors ──
    ; MOVI replicates an immediate into every lane of a vector.
    ; One instruction fills all 16 bytes!
    movi    v1.16b, #0x61           ; v1 = 'a' in all 16 lanes
    movi    v2.16b, #0x7A           ; v2 = 'z' in all 16 lanes
    movi    v3.16b, #0x20           ; v3 = 32  in all 16 lanes

    ; How many full 16-byte chunks?
    lsr     x2, x1, #4             ; x2 = len >> 4  (len / 16)
    cbz     x2, neon_tail          ; no full chunks? handle leftovers

    ;────────────────────────────────────────────
    ; HOT LOOP: 5 real instructions per 16 chars
    ;────────────────────────────────────────────
neon_loop
    ldr     q0, [x0]               ; Load 16 bytes into v0
                                    ; q0 is the 128-bit name for v0

    ; ── Build a mask: which bytes are lowercase? ──
    ;
    ; CMHS = Compare unsigned Higher or Same (>=)
    ; It sets each byte lane to 0xFF (true) or 0x00 (false).
    ;
    ; Imagine v0 = ['H','e','l','l','o',' ','W','o','r','l','d','!',0,0,0,0]
    ;
    ;   cmhs v4, v0, v1  →  v4 = [ 0, FF, FF, FF, FF,  0,  0, FF, FF, FF, FF,  0, 0, 0, 0, 0]
    ;                                H≥a? e≥a? l≥a? ...          W≥a? o≥a? ...
    ;
    ;   cmhs v5, v2, v0  →  v5 = [FF, FF, FF, FF, FF, FF, FF, FF, FF, FF, FF, FF, 0, 0, 0, 0]
    ;                                z≥H? z≥e? z≥l? ...          z≥W? z≥o? ...

    cmhs    v4.16b, v0.16b, v1.16b  ; v4 = (ch >= 'a') per lane
    cmhs    v5.16b, v2.16b, v0.16b  ; v5 = (ch <= 'z') per lane
    and     v4.16b, v4.16b, v5.16b  ; v4 = 0xFF only if BOTH conditions met
                                    ;    = 0xFF for lowercase, 0x00 otherwise

    ; ── Apply the conversion ──
    ; Mask 0x20 so it only applies to lowercase bytes, then subtract.
    and     v5.16b, v3.16b, v4.16b  ; v5 = 0x20 where lowercase, 0x00 elsewhere
    sub     v0.16b, v0.16b, v5.16b  ; subtract 32 → uppercase!  (no-op where v5=0)

    str     q0, [x0], #16          ; Store 16 bytes back, advance pointer
    subs    x2, x2, #1             ; decrement chunk counter
    b.ne    neon_loop               ; loop until all chunks done

    ;────────────────────────────────────────────
    ; TAIL: handle the remaining 0–15 bytes
    ;────────────────────────────────────────────
neon_tail
    and     x2, x1, #0xF           ; remaining = len & 15
    cbz     x2, neon_done

neon_tail_loop
    ldrb    w3, [x0]               ; load one byte
    sub     w4, w3, #0x61           ; w4 = ch - 'a'
    cmp     w4, #25                 ; in range [0..25]?  (i.e. 'a'..'z')
    b.hi    neon_tail_skip          ; unsigned-higher → not lowercase
    sub     w3, w3, #0x20           ; uppercase it
neon_tail_skip
    strb    w3, [x0], #1
    subs    x2, x2, #1
    b.ne    neon_tail_loop

neon_done
    ret
    ENDP

;================================================================
; void scalar_toupper(char *str, uint64_t len)
;
; Scalar version — one character at a time.
; Same logic, just no vectors.
;================================================================

scalar_toupper PROC
    cbz     x1, scalar_done

scalar_loop
    ldrb    w2, [x0]               ; load one byte
    sub     w3, w2, #0x61           ; ch - 'a'
    cmp     w3, #25                 ; in ['a'..'z']?
    b.hi    scalar_skip
    sub     w2, w2, #0x20           ; → uppercase
scalar_skip
    strb    w2, [x0], #1
    subs    x1, x1, #1
    b.ne    scalar_loop

scalar_done
    ret
    ENDP

    END
