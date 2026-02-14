# Metal Ray Tracer — Pure AArch64 Assembly

Real-time ray tracing on Apple Silicon, with zero C code. The CPU side is
entirely AArch64 assembly driving Metal, AppKit, and QuartzCore through
`objc_msgSend`. The GPU side is a Metal compute shader that does per-pixel
ray casting, Blinn-Phong shading, shadow rays, and single-bounce reflections.

![1280x720 window, ~120 Hz on Apple Silicon]

## Build & Run

```bash
make        # compiles shader + assembles host, default scene = cornell
make run    # build and launch
```

Requires macOS 14+, Apple Silicon, and Xcode Command Line Tools.

## Swappable Scenes

Scenes are standalone `.s` files in `scenes/`. Each exports a fixed set of
symbols (title, camera, shapes, lights) — the engine links against whichever
one you pick:

```bash
make SCENE=cornell      # room, 2 spheres, box, 3 animated lights (default)
make SCENE=mirrors      # reflective walls, chrome/gold/ruby spheres, 2 lights
make SCENE=minimal      # floor + 1 sphere + 1 static light
```

To make a new scene:

```bash
cp scenes/cornell.s scenes/myscene.s
# edit the floats
make clean && make SCENE=myscene
```

### Scene contract

A scene `.s` file must export these symbols:

| Symbol | Type | Description |
|---|---|---|
| `_scene_title` | `.asciz` | Window title string |
| `_scene_num_shapes` | `.long` | Number of shapes |
| `_scene_num_lights` | `.long` | Number of lights (max 4) |
| `_scene_camera` | 2 x float4 | `[0]` = position, `[1]` = look-at (`.w` = FOV) |
| `_scene_shapes` | N x 64 bytes | Array of Shape structs |
| `_scene_lights` | N x 64 bytes | Array of LightDef structs |

### Shape struct (64 bytes)

```
offset  field
  0     float4 type_info   .x = type (0=sphere, 1=box, 2=plane), .y = roughness, .z = reflectivity
 16     float4 position    .xyz
 32     float4 size        .xyz (radius / half-extents / plane normal)
 48     float4 color       .xyz RGB
```

### LightDef struct (64 bytes)

```
offset  field
  0     float4 color        .xyz = RGB, .w = intensity
 16     float4 base_pos     .xyz = center/anchor position
 32     float4 anim_params  .x = type (0-3), .y = speed, .z = radius/amplitude, .w = phase
 48     float4 anim_extra   figure-8: .x = x_speed, .y = x_radius (else unused)
```

Animation types:

| Type | Value | Motion |
|---|---|---|
| `ANIM_STATIC` | 0 | Fixed at `base_pos` |
| `ANIM_ORBIT` | 1 | Horizontal circle: x/z += cos/sin(t * speed + phase) * radius |
| `ANIM_BOB` | 2 | Vertical bounce: y += sin(t * speed + phase) * amplitude |
| `ANIM_FIGURE8` | 3 | Figure-8 in xz: x from `anim_extra`, z = sin * cos * radius |

## Files

```
raytracer/
  main.s              Engine: app bootstrap, Metal init, render loop
  defs.s              Shared constants and struct offsets (.include, no labels)
  raytrace.metal      Metal compute shader (ray casting + shading)
  Makefile            Build orchestration (SCENE variable)
  scenes/
    cornell.s         Cornell box — room, spheres, box, 3 animated lights
    mirrors.s         Hall of mirrors — reflective walls, 4 shiny spheres
    minimal.s         Simplest test — floor, 1 sphere, 1 static light
```

## How it works

**Startup (`_main`):** Creates an NSApplication, registers a custom
AppDelegate class (with `objc_allocateClassPair` / `class_addMethod`), builds
an NSWindow with a CAMetalLayer, initializes the Metal device + command queue,
loads `raytrace.metallib`, creates compute pipeline and Metal buffers, copies
scene shapes and camera from the linked scene file into GPU buffers, then
starts a 120 Hz NSTimer and enters `[NSApp run]`.

**Per frame (`_render_frame`):** Increments the time uniform, then loops over
`_scene_lights[]` — for each light, reads its animation type and parameters,
calls `sin`/`cos` to compute the animated position, and writes the result into
the uniforms buffer. Then acquires the next drawable, encodes a compute
dispatch (1280x720 threads, 16x16 groups), and presents.

**GPU (`raytrace_kernel`):** Each thread casts a ray from the camera through
its pixel. Intersects against all shapes (spheres, boxes, planes), computes
Blinn-Phong shading with shadow rays toward each light, does one reflection
bounce for reflective surfaces, then writes the tone-mapped result to the
output texture.

All ObjC calls follow the same pattern: load class with `objc_getClass`,
register selector with `sel_registerName`, call `objc_msgSend` with receiver
in x0, selector in x1, arguments in x2+.
