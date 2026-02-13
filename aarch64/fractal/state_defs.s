//
// state_defs.s — Equates and constants only (no data, no labels)
//
// Safe to .include from multiple translation units.
//

// ── ViewerState struct offsets ──────────────────────────────

.equ VS_WIN_W,          0       // uint32_t — window width
.equ VS_WIN_H,          4       // uint32_t — window height
.equ VS_CENTER_X,       8       // double  — complex plane center X
.equ VS_CENTER_Y,       16      // double  — complex plane center Y
.equ VS_ZOOM,           24      // double  — zoom level
.equ VS_MAX_ITER,       32      // uint32_t — max iteration count
.equ VS_JULIA_MODE,     36      // int32_t — 0=Mandelbrot, 1=Julia
.equ VS_JR,             40      // double  — Julia constant (real)
.equ VS_JI,             48      // double  — Julia constant (imag)
.equ VS_NEEDS_RENDER,   56      // int32_t — dirty flag
.equ VS_PHASE,          60      // int32_t — 0=coarse, 1=full
.equ VS_LAST_MS,        64      // double  — last render time in ms
.equ VS_DRAGGING,       72      // int32_t — drag in progress
.equ VS_DRAG_X,         76      // int32_t — mouse start X
.equ VS_DRAG_Y,         80      // int32_t — mouse start Y
.equ VS_DRAG_CX,        88      // double  — center X at drag start
.equ VS_DRAG_CY,        96      // double  — center Y at drag start
.equ VS_SIZE,           104

// ── NSWindow style mask bits ────────────────────────────────

.equ NSWindowStyleMaskTitled,           1
.equ NSWindowStyleMaskClosable,         2
.equ NSWindowStyleMaskMiniaturizable,   4
.equ NSWindowStyleMaskResizable,        8
.equ WINDOW_STYLE, 0xF     // titled|closable|miniaturizable|resizable

// ── NSApplication activation policy ─────────────────────────

.equ NSApplicationActivationPolicyRegular, 0

// ── NSBackingStoreType ──────────────────────────────────────

.equ NSBackingStoreBuffered, 2

// ── CGBitmapInfo ────────────────────────────────────────────

.equ kCGImageAlphaNoneSkipFirst,    6
.equ kCGBitmapByteOrder32Little,    0x2000
.equ BITMAP_INFO, (kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little)
