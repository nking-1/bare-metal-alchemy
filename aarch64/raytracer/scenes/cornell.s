// ═══════════════════════════════════════════════════════════════════
// cornell.s — Cornell Box scene: room, 2 spheres, box, 3 lights
// ═══════════════════════════════════════════════════════════════════
.include "defs.s"

// ─── Scene title ──────────────────────────────────────────────────
.section __TEXT,__cstring,cstring_literals
.globl _scene_title
_scene_title:   .asciz "Metal Ray Tracer"

// ─── Scene counts ─────────────────────────────────────────────────
.section __TEXT,__const
.p2align 2

.globl _scene_num_shapes
_scene_num_shapes:  .long 9

.globl _scene_num_lights
_scene_num_lights:  .long 3

// ─── Camera (2 × float4 = 32 bytes) ──────────────────────────────
// [0] camera_pos   (.xyz)
// [1] camera_look_at (.xyz, .w = fov)
.p2align 4
.globl _scene_camera
_scene_camera:
    .single 0.0, 2.5, 1.0, 0.0             // pos
    .single 0.0, 1.0, -4.0, 1.2            // look_at, fov=1.2 rad

// ─── Shapes (9 × 64 bytes) ───────────────────────────────────────
// Each shape: type_info, position, size, color (4 × float4)
.p2align 4
.globl _scene_shapes
_scene_shapes:
    // 0: Floor (plane at y=0, normal up)
    .single 2.0, 0.8, 0.15, 0.0
    .single 0.0, 0.0, 0.0, 0.0
    .single 0.0, 1.0, 0.0, 0.0
    .single 0.5, 0.5, 0.5, 0.0

    // 1: Ceiling (y=5, normal down)
    .single 2.0, 0.95, 0.0, 0.0
    .single 0.0, 5.0, 0.0, 0.0
    .single 0.0, -1.0, 0.0, 0.0
    .single 0.8, 0.8, 0.8, 0.0

    // 2: Back wall (z=-10, normal toward camera)
    .single 2.0, 0.9, 0.0, 0.0
    .single 0.0, 0.0, -10.0, 0.0
    .single 0.0, 0.0, 1.0, 0.0
    .single 0.7, 0.7, 0.7, 0.0

    // 3: Left wall (x=-6, normal right, red tint)
    .single 2.0, 0.85, 0.0, 0.0
    .single -6.0, 0.0, 0.0, 0.0
    .single 1.0, 0.0, 0.0, 0.0
    .single 0.8, 0.2, 0.2, 0.0

    // 4: Right wall (x=6, normal left, green tint)
    .single 2.0, 0.85, 0.0, 0.0
    .single 6.0, 0.0, 0.0, 0.0
    .single -1.0, 0.0, 0.0, 0.0
    .single 0.2, 0.8, 0.2, 0.0

    // 5: Front wall (z=2, behind camera)
    .single 2.0, 0.9, 0.0, 0.0
    .single 0.0, 0.0, 2.0, 0.0
    .single 0.0, 0.0, -1.0, 0.0
    .single 0.7, 0.7, 0.7, 0.0

    // 6: Large sphere (center, reflective)
    .single 0.0, 0.1, 0.8, 0.0
    .single 0.0, 1.5, -4.0, 0.0
    .single 1.5, 0.0, 0.0, 0.0
    .single 0.9, 0.9, 0.95, 0.0

    // 7: Small sphere (offset, matte orange)
    .single 0.0, 0.7, 0.05, 0.0
    .single -2.5, 0.8, -2.5, 0.0
    .single 0.8, 0.0, 0.0, 0.0
    .single 0.9, 0.3, 0.1, 0.0

    // 8: Box (right side, blue)
    .single 1.0, 0.3, 0.4, 0.0
    .single 3.0, 1.0, -5.0, 0.0
    .single 1.0, 1.0, 1.0, 0.0
    .single 0.3, 0.5, 0.9, 0.0

// ─── Lights (3 × 64 bytes, LightDef format) ──────────────────────
// Each: color (.w=intensity), base_pos, anim_params, anim_extra
.p2align 4
.globl _scene_lights
_scene_lights:
    // Light A: horizontal orbit (warm white)
    // Orbits around (0, 3.5, -4) with radius 4
    .single 1.0, 0.9, 0.7, 2.0             // color, intensity=2.0
    .single 0.0, 3.5, -4.0, 0.0            // base_pos (orbit center)
    .single 1.0, 1.0, 4.0, 0.0             // ORBIT, speed=1, radius=4, phase=0
    .single 0.0, 0.0, 0.0, 0.0             // (unused)

    // Light B: vertical bob (cool blue)
    // Bobs around (-3, 2, -5) with amplitude 1.5
    .single 0.5, 0.7, 1.0, 1.5             // color, intensity=1.5
    .single -3.0, 2.0, -5.0, 0.0           // base_pos
    .single 2.0, 0.7, 1.5, 0.0             // BOB, speed=0.7, amplitude=1.5, phase=0
    .single 0.0, 0.0, 0.0, 0.0             // (unused)

    // Light C: figure-8 near ceiling (amber)
    // Figure-8 around (0, 4.5, -4)
    .single 1.0, 0.8, 0.4, 1.0             // color, intensity=1.0
    .single 0.0, 4.5, -4.0, 0.0            // base_pos
    .single 3.0, 0.9, 4.0, 0.0             // FIGURE8, z_speed=0.9, z_radius=4, phase=0
    .single 1.3, 3.0, 0.0, 0.0             // x_speed=1.3, x_radius=3.0

.end
