// ═══════════════════════════════════════════════════════════════════
// minimal.s — Simplest possible scene: floor, sphere, one light
// ═══════════════════════════════════════════════════════════════════
.include "defs.s"

// ─── Scene title ──────────────────────────────────────────────────
.section __TEXT,__cstring,cstring_literals
.globl _scene_title
_scene_title:   .asciz "Metal Ray Tracer — Minimal"

// ─── Scene counts ─────────────────────────────────────────────────
.section __TEXT,__const
.p2align 2

.globl _scene_num_shapes
_scene_num_shapes:  .long 2

.globl _scene_num_lights
_scene_num_lights:  .long 1

// ─── Camera ───────────────────────────────────────────────────────
.p2align 4
.globl _scene_camera
_scene_camera:
    .single 0.0, 2.0, 4.0, 0.0             // pos
    .single 0.0, 0.5, 0.0, 1.2             // look_at, fov=1.2

// ─── Shapes (2 × 64 bytes) ───────────────────────────────────────
.p2align 4
.globl _scene_shapes
_scene_shapes:
    // 0: Floor
    .single 2.0, 0.7, 0.2, 0.0             // plane, slightly rough, mild reflection
    .single 0.0, 0.0, 0.0, 0.0
    .single 0.0, 1.0, 0.0, 0.0
    .single 0.4, 0.4, 0.45, 0.0

    // 1: Sphere
    .single 0.0, 0.2, 0.5, 0.0             // sphere, smooth-ish, reflective
    .single 0.0, 1.0, 0.0, 0.0
    .single 1.0, 0.0, 0.0, 0.0             // radius = 1.0
    .single 0.8, 0.2, 0.2, 0.0             // red

// ─── Lights (1 × 64 bytes, LightDef format) ──────────────────────
.p2align 4
.globl _scene_lights
_scene_lights:
    // Single static light, overhead
    .single 1.0, 1.0, 1.0, 2.0             // white, intensity=2.0
    .single 2.0, 4.0, 3.0, 0.0             // position
    .single 0.0, 0.0, 0.0, 0.0             // STATIC
    .single 0.0, 0.0, 0.0, 0.0

.end
