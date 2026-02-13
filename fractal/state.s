//
// state.s — Global viewer state, string constants, equates (AArch64 / macOS)
//
// Foundation for the pure-assembly Cocoa fractal viewer.
// Contains ViewerState struct layout, ObjC class/selector strings,
// type encoding strings, and global pointers.
//

.include "fractal/state_defs.s"

// ══════════════════════════════════════════════════════════════
//  DATA SECTION — mutable globals
// ══════════════════════════════════════════════════════════════

.data
.p2align 3

// ── ViewerState instance ────────────────────────────────────

.globl _g_state
_g_state:
    .long   800                 // VS_WIN_W
    .long   600                 // VS_WIN_H
    .double -0.5                // VS_CENTER_X
    .double  0.0                // VS_CENTER_Y
    .double  1.0                // VS_ZOOM
    .long   256                 // VS_MAX_ITER
    .long   0                   // VS_JULIA_MODE
    .double  0.0                // VS_JR
    .double  0.0                // VS_JI
    .long   1                   // VS_NEEDS_RENDER (start dirty)
    .long   0                   // VS_PHASE
    .double  0.0                // VS_LAST_MS
    .long   0                   // VS_DRAGGING
    .long   0                   // VS_DRAG_X
    .long   0                   // VS_DRAG_Y
    .long   0                   // padding to align VS_DRAG_CX
    .double  0.0                // VS_DRAG_CX
    .double  0.0                // VS_DRAG_CY

// ── Global pointers ─────────────────────────────────────────

.globl _g_view
_g_view:        .quad 0         // FractalView* instance

.globl _g_window
_g_window:      .quad 0         // NSWindow* instance

.globl _g_nsapp
_g_nsapp:       .quad 0         // NSApplication* instance

// Render buffers
.globl _g_iter_buf
_g_iter_buf:    .quad 0         // uint32_t* — full-res iteration buffer

.globl _g_rgb_buf
_g_rgb_buf:     .quad 0         // uint8_t* — full-res RGB buffer

.globl _g_iter_small
_g_iter_small:  .quad 0         // uint32_t* — coarse iteration buffer

.globl _g_rgb_small
_g_rgb_small:   .quad 0         // uint8_t* — coarse RGB buffer

.globl _g_argb_buf
_g_argb_buf:    .quad 0         // uint32_t* — ARGB32 buffer for CGBitmapContext

// ══════════════════════════════════════════════════════════════
//  TEXT SECTION — read-only string constants
// ══════════════════════════════════════════════════════════════

.section __TEXT,__cstring,cstring_literals

// ── ObjC class names ────────────────────────────────────────

.globl _str_NSApplication
_str_NSApplication:         .asciz "NSApplication"
.globl _str_NSWindow
_str_NSWindow:              .asciz "NSWindow"
.globl _str_NSView
_str_NSView:                .asciz "NSView"
.globl _str_NSObject
_str_NSObject:              .asciz "NSObject"
.globl _str_NSTimer
_str_NSTimer:               .asciz "NSTimer"
.globl _str_NSColor
_str_NSColor:               .asciz "NSColor"
.globl _str_NSGraphicsContext
_str_NSGraphicsContext:     .asciz "NSGraphicsContext"
.globl _str_NSString
_str_NSString:              .asciz "NSString"

// Custom class names
.globl _str_FractalView
_str_FractalView:           .asciz "FractalView"
.globl _str_AppDelegate
_str_AppDelegate:           .asciz "AppDelegate"

// ── ObjC selector names ─────────────────────────────────────

.globl _str_sharedApplication
_str_sharedApplication:                     .asciz "sharedApplication"
.globl _str_setActivationPolicy
_str_setActivationPolicy:                   .asciz "setActivationPolicy:"
.globl _str_alloc
_str_alloc:                                 .asciz "alloc"
.globl _str_init
_str_init:                                  .asciz "init"
.globl _str_initWithContentRect
_str_initWithContentRect:                   .asciz "initWithContentRect:styleMask:backing:defer:"
.globl _str_initWithFrame
_str_initWithFrame:                         .asciz "initWithFrame:"
.globl _str_setContentView
_str_setContentView:                        .asciz "setContentView:"
.globl _str_setDelegate
_str_setDelegate:                           .asciz "setDelegate:"
.globl _str_setTitle
_str_setTitle:                              .asciz "setTitle:"
.globl _str_makeKeyAndOrderFront
_str_makeKeyAndOrderFront:                  .asciz "makeKeyAndOrderFront:"
.globl _str_activateIgnoringOtherApps
_str_activateIgnoringOtherApps:             .asciz "activateIgnoringOtherApps:"
.globl _str_run
_str_run:                                   .asciz "run"
.globl _str_setNeedsDisplay
_str_setNeedsDisplay:                       .asciz "setNeedsDisplay:"
.globl _str_drawRect
_str_drawRect:                              .asciz "drawRect:"
.globl _str_isFlipped
_str_isFlipped:                             .asciz "isFlipped"
.globl _str_acceptsFirstResponder
_str_acceptsFirstResponder:                 .asciz "acceptsFirstResponder"
.globl _str_mouseDown
_str_mouseDown:                             .asciz "mouseDown:"
.globl _str_mouseUp
_str_mouseUp:                               .asciz "mouseUp:"
.globl _str_mouseDragged
_str_mouseDragged:                          .asciz "mouseDragged:"
.globl _str_rightMouseDown
_str_rightMouseDown:                        .asciz "rightMouseDown:"
.globl _str_scrollWheel
_str_scrollWheel:                           .asciz "scrollWheel:"
.globl _str_keyDown
_str_keyDown:                               .asciz "keyDown:"
.globl _str_timerFired
_str_timerFired:                            .asciz "timerFired:"
.globl _str_applicationDidFinishLaunching
_str_applicationDidFinishLaunching:         .asciz "applicationDidFinishLaunching:"
.globl _str_appShouldTerminate
_str_appShouldTerminate:                    .asciz "applicationShouldTerminateAfterLastWindowClosed:"
.globl _str_terminate
_str_terminate:                             .asciz "terminate:"

// NSTimer selectors
.globl _str_scheduledTimerWithTimeInterval
_str_scheduledTimerWithTimeInterval:        .asciz "scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"

// NSGraphicsContext selectors
.globl _str_currentContext
_str_currentContext:                        .asciz "currentContext"
.globl _str_CGContext
_str_CGContext:                             .asciz "CGContext"

// NSColor selectors
.globl _str_blackColor
_str_blackColor:                            .asciz "blackColor"
.globl _str_set
_str_set:                                   .asciz "set"

// NSEvent selectors
.globl _str_locationInWindow
_str_locationInWindow:                      .asciz "locationInWindow"
.globl _str_deltaY
_str_deltaY:                                .asciz "deltaY"
.globl _str_keyCode
_str_keyCode:                               .asciz "keyCode"
.globl _str_buttonNumber
_str_buttonNumber:                          .asciz "buttonNumber"

// NSWindow selectors
.globl _str_makeFirstResponder
_str_makeFirstResponder:                    .asciz "makeFirstResponder:"
.globl _str_contentView
_str_contentView:                           .asciz "contentView"
.globl _str_frame
_str_frame:                                 .asciz "frame"

// NSString creation
.globl _str_stringWithUTF8String
_str_stringWithUTF8String:                  .asciz "stringWithUTF8String:"

// NSRect fill
.globl _str_NSRectFill
_str_NSRectFill:                            .asciz "NSRectFill"

// ── ObjC type encoding strings ──────────────────────────────

// void method(id self, SEL _cmd, CGRect rect)
.globl _enc_drawRect
_enc_drawRect:              .asciz "v@:{CGRect=dddd}"

// void method(id self, SEL _cmd, id event)
.globl _enc_event
_enc_event:                 .asciz "v@:@"

// BOOL method(id self, SEL _cmd)  — char return
.globl _enc_bool
_enc_bool:                  .asciz "c@:"

// BOOL method(id self, SEL _cmd, id arg)  — char return, one object param
.globl _enc_bool_obj
_enc_bool_obj:              .asciz "c@:@"

// void method(id self, SEL _cmd)
.globl _enc_void
_enc_void:                  .asciz "v@:"

// ── Format strings ──────────────────────────────────────────

.globl _fmt_title_mandel
_fmt_title_mandel:
    .asciz "Mandelbrot | (%.6f, %.6f) z=%.1f i=%u | %.1fms"

.globl _fmt_title_julia
_fmt_title_julia:
    .asciz "Julia c=(%.4f, %.4f) | (%.6f, %.6f) z=%.1f i=%u | %.1fms"

.globl _fmt_save
_fmt_save:
    .asciz "fractal_%ld.ppm"

.globl _fmt_ppm_header
_fmt_ppm_header:
    .asciz "P6\n%u %u\n255\n"

.globl _fmt_saved_msg
_fmt_saved_msg:
    .asciz "Saved %s (%ux%u)\n"

.globl _fmt_controls
_fmt_controls:
    .asciz "Controls: drag=pan  scroll=zoom  right-click=Julia  space=Mandelbrot  +/-=iters  S=save  R=reset  Q=quit\n"

.globl _fmt_julia_msg
_fmt_julia_msg:
    .asciz "Julia mode: c = (%.6f, %.6f)\n"

.globl _str_fractal_viewer
_str_fractal_viewer:
    .asciz "Fractal Viewer"

// ── Floating-point constants ────────────────────────────────

.section __DATA,__const
.p2align 3

.globl _const_2_0
_const_2_0:         .double 2.0

.globl _const_0_5
_const_0_5:         .double 0.5

.globl _const_1_0
_const_1_0:         .double 1.0

.globl _const_1_3
_const_1_3:         .double 1.3

.globl _const_inv_1_3
_const_inv_1_3:     .double 0.76923076923076923   // 1.0/1.3

.globl _const_0_1
_const_0_1:         .double 0.1

.globl _const_1e14
_const_1e14:        .double 1.0e14

.globl _const_4_0
_const_4_0:         .double 4.0

.globl _const_0_016
_const_0_016:       .double 0.016

.globl _const_1000_0
_const_1000_0:      .double 1000.0

.globl _const_1e6
_const_1e6:         .double 1000000.0

.globl _const_neg0_5
_const_neg0_5:      .double -0.5
