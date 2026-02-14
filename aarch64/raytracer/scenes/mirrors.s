// ═══════════════════════════════════════════════════════════════════
// mirrors.s — Hall of mirrors: reflective walls, shiny spheres
// ═══════════════════════════════════════════════════════════════════
.include "defs.s"

// ─── Scene title ──────────────────────────────────────────────────
.section __TEXT,__cstring,cstring_literals
.globl _scene_title
_scene_title:   .asciz "Metal Ray Tracer — Mirrors"

// ─── Scene counts ─────────────────────────────────────────────────
.section __TEXT,__const
.p2align 2

.globl _scene_num_shapes
_scene_num_shapes:  .long 10

.globl _scene_num_lights
_scene_num_lights:  .long 2

// ─── Camera ───────────────────────────────────────────────────────
.p2align 4
.globl _scene_camera
_scene_camera:
    .single 0.0, 2.0, 3.0, 0.0             // pos: centered, eye height, close
    .single 0.0, 1.5, -5.0, 1.0            // look_at: down the hall, fov=1.0

// ─── Shapes (10 × 64 bytes) ──────────────────────────────────────
.p2align 4
.globl _scene_shapes
_scene_shapes:
    // 0: Floor — dark, reflective
    .single 2.0, 0.3, 0.6, 0.0             // plane, smooth, very reflective
    .single 0.0, 0.0, 0.0, 0.0
    .single 0.0, 1.0, 0.0, 0.0
    .single 0.15, 0.15, 0.18, 0.0          // dark charcoal

    // 1: Ceiling
    .single 2.0, 0.9, 0.05, 0.0
    .single 0.0, 6.0, 0.0, 0.0
    .single 0.0, -1.0, 0.0, 0.0
    .single 0.2, 0.2, 0.2, 0.0

    // 2: Back wall — mirror
    .single 2.0, 0.05, 0.9, 0.0            // near-perfect mirror
    .single 0.0, 0.0, -12.0, 0.0
    .single 0.0, 0.0, 1.0, 0.0
    .single 0.9, 0.9, 0.95, 0.0

    // 3: Left wall — mirror, warm tint
    .single 2.0, 0.05, 0.85, 0.0
    .single -5.0, 0.0, 0.0, 0.0
    .single 1.0, 0.0, 0.0, 0.0
    .single 0.95, 0.85, 0.8, 0.0

    // 4: Right wall — mirror, cool tint
    .single 2.0, 0.05, 0.85, 0.0
    .single 5.0, 0.0, 0.0, 0.0
    .single -1.0, 0.0, 0.0, 0.0
    .single 0.8, 0.85, 0.95, 0.0

    // 5: Front wall (behind camera)
    .single 2.0, 0.05, 0.9, 0.0
    .single 0.0, 0.0, 4.0, 0.0
    .single 0.0, 0.0, -1.0, 0.0
    .single 0.9, 0.9, 0.95, 0.0

    // 6: Chrome sphere (center)
    .single 0.0, 0.02, 0.95, 0.0           // near-perfect mirror ball
    .single 0.0, 1.8, -5.0, 0.0
    .single 1.8, 0.0, 0.0, 0.0
    .single 0.95, 0.95, 0.98, 0.0

    // 7: Gold sphere (left)
    .single 0.0, 0.1, 0.8, 0.0
    .single -2.5, 1.0, -3.0, 0.0
    .single 1.0, 0.0, 0.0, 0.0
    .single 1.0, 0.84, 0.0, 0.0            // gold

    // 8: Ruby sphere (right)
    .single 0.0, 0.15, 0.7, 0.0
    .single 2.5, 1.0, -7.0, 0.0
    .single 1.0, 0.0, 0.0, 0.0
    .single 0.9, 0.1, 0.15, 0.0            // deep red

    // 9: Small glass sphere (foreground)
    .single 0.0, 0.05, 0.9, 0.0
    .single 1.5, 0.6, -1.5, 0.0
    .single 0.6, 0.0, 0.0, 0.0
    .single 0.85, 0.92, 1.0, 0.0           // bluish crystal

// ─── Lights (2 × 64 bytes, LightDef format) ──────────────────────
.p2align 4
.globl _scene_lights
_scene_lights:
    // Light A: slow orbit overhead (bright white)
    .single 1.0, 0.95, 0.9, 2.5            // color, intensity=2.5
    .single 0.0, 4.5, -5.0, 0.0            // orbit center
    .single 1.0, 0.4, 3.0, 0.0             // ORBIT, speed=0.4, radius=3.0
    .single 0.0, 0.0, 0.0, 0.0

    // Light B: gentle bob (warm accent)
    .single 1.0, 0.8, 0.5, 1.5             // warm, intensity=1.5
    .single -2.0, 3.0, -8.0, 0.0           // back-left
    .single 2.0, 0.5, 1.0, 1.57            // BOB, speed=0.5, amplitude=1.0, phase=pi/2
    .single 0.0, 0.0, 0.0, 0.0

.end
