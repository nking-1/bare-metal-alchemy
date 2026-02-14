// ═══════════════════════════════════════════════════════════════════
// defs.s — Constants, struct offsets, macros for Metal RT demo
// ═══════════════════════════════════════════════════════════════════
// Safe to .include from any file (no .globl labels)

// ─── Window ─────────────────────────────────────────────────────────
.equ WIN_W,         1280
.equ WIN_H,         720

// ─── Light struct (32 bytes) ────────────────────────────────────────
// float4 position (.xyz = pos, .w = intensity)
// float4 color    (.xyz = color, .w = unused)
.equ LIGHT_POS,         0
.equ LIGHT_COLOR,       16
.equ LIGHT_STRIDE,      32

// ─── Uniforms struct (192 bytes) ────────────────────────────────────
// Must match Metal's Uniforms layout exactly.
//
//   float  time             @ 0
//   uint   frame_count      @ 4
//   uint   num_shapes       @ 8
//   uint   num_lights       @ 12
//   float4 resolution       @ 16  (.xy = w,h)
//   float4 camera_pos       @ 32  (.xyz)
//   float4 camera_look_at   @ 48  (.xyz, .w = fov)
//   Light  lights[4]        @ 64  (4 × 32 = 128)
//                            = 192 total
.equ UNI_TIME,              0
.equ UNI_FRAME_COUNT,       4
.equ UNI_NUM_SHAPES,        8
.equ UNI_NUM_LIGHTS,        12
.equ UNI_RESOLUTION,        16
.equ UNI_CAMERA_POS,        32
.equ UNI_CAMERA_LOOK_AT,    48
.equ UNI_CAMERA_FOV,        60
.equ UNI_LIGHTS,            64
.equ UNIFORMS_SIZE,         192

// ─── Shape struct (64 bytes) ────────────────────────────────────────
// float4 type_info  (.x = type as float, .y = roughness, .z = reflectivity)
// float4 position   (.xyz)
// float4 size       (.xyz)
// float4 color      (.xyz)
.equ SHAPE_TYPE_INFO,   0
.equ SHAPE_POSITION,    16
.equ SHAPE_SIZE,        32
.equ SHAPE_COLOR,       48
.equ SHAPE_STRIDE,      64

// Scene: 6 planes + 2 spheres + 1 box = 9 shapes
.equ NUM_SCENE_SHAPES,  9
.equ MAX_SHAPES,        16

// ─── LOAD_SEL macro ─────────────────────────────────────────────────
// Registers a selector from a string label. Result in x1 (ready for msgSend).
// Clobbers x0.
.macro LOAD_SEL label
    adrp    x0, \label@PAGE
    add     x0, x0, \label@PAGEOFF
    bl      _sel_registerName
    mov     x1, x0
.endm
