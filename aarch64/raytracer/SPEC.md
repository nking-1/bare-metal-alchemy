# Metal Ray Tracing Demo — Bare Assembly on AArch64/macOS

## Project Summary

A real-time ray tracing demo written in bare AArch64 assembly (no C/C++ host code), rendering a room scene with geometric shapes and moving lights. The GPU work is done via Metal compute shaders (MSL, pre-compiled to a `.metallib`). The CPU-side assembly drives everything through `objc_msgSend` calls into Metal, AppKit, and QuartzCore frameworks.

Fixed camera. Moving lights. The point is to see hardware-accelerated ray tracing happening live on an M3 Max.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                   main.s (AArch64 asm)              │
│                                                     │
│  ┌───────────┐  ┌──────────┐  ┌──────────────────┐ │
│  │ App Setup │  │ Metal    │  │ Render Loop      │ │
│  │ (AppKit)  │  │ Init     │  │ (per-frame)      │ │
│  │           │  │          │  │                  │ │
│  │ NSApp     │  │ Device   │  │ Update uniforms  │ │
│  │ Window    │  │ Queue    │  │ Encode compute   │ │
│  │ Metal     │  │ Pipeline │  │ Blit to drawable │ │
│  │ Layer     │  │ Buffers  │  │ Present & commit │ │
│  └───────────┘  └──────────┘  └──────────────────┘ │
│                                                     │
│  All ObjC calls via: objc_msgSend(receiver, sel, …) │
│  Syscalls via: libSystem.dylib (not raw svc)        │
└──────────────────────┬──────────────────────────────┘
                       │ loads
          ┌────────────▼────────────┐
          │   raytrace.metallib     │
          │   (pre-compiled MSL)    │
          │                         │
          │  Compute kernel:        │
          │  - Per-pixel ray cast   │
          │  - Scene intersection   │
          │  - Phong/Blinn shading  │
          │  - Shadow rays          │
          │  - Writes to texture    │
          └─────────────────────────┘
```

---

## Components

### 1. `main.s` — Host-side AArch64 Assembly

This is the entire CPU-side program. It does the following, all via `objc_msgSend`:

**App bootstrap:**
- Call `NSApplicationLoad()` or `[NSApplication sharedApplication]`
- Create an `NSWindow` (fixed size, e.g. 1280×720)
- Create a `CAMetalLayer`, set pixel format (`bgra8Unorm`), attach to window's content view

**Metal initialization:**
- `MTLCreateSystemDefaultDevice()` → device
- `[device newCommandQueue]` → command queue
- `[device newLibraryWithURL:error:]` → load `raytrace.metallib` from disk
- `[library newFunctionWithName:@"raytrace_kernel"]` → kernel function
- `[device newComputePipelineStateWithFunction:error:]` → pipeline
- `[device newBufferWithLength:options:]` → uniforms buffer (camera, lights, time)
- `[device newBufferWithLength:options:]` → scene buffer (shape definitions)

**Render loop (driven by `CVDisplayLink` or a simple timer/loop):**
1. Update uniforms buffer: increment time, compute light positions (sin/cos orbit)
2. `[metalLayer nextDrawable]` → get drawable
3. `[commandQueue commandBuffer]` → command buffer
4. `[commandBuffer computeCommandEncoder]` → encoder
5. `[encoder setComputePipelineState:]`
6. `[encoder setBuffer:offset:atIndex:]` for uniforms + scene
7. `[encoder setTexture:atIndex:]` → drawable's texture
8. `[encoder dispatchThreads:threadsPerThreadgroup:]`
9. `[encoder endEncoding]`
10. `[commandBuffer presentDrawable:]`
11. `[commandBuffer commit]`

**Data layout (in `.data` / `.rodata` sections):**
- ObjC selector strings (null-terminated): `"sharedApplication"`, `"newCommandQueue"`, etc.
- NSString-compatible CFString constants for Metal function names, metallib path
- Scene definition: array of shape structs (type, position, radius/size, color, material)
- Initial uniform values

### 2. `raytrace.metal` — Metal Shading Language Compute Kernel

Pre-compiled to `raytrace.metallib` using command-line tools. This is the only non-assembly source file, and it produces a binary asset (not linked C/C++ code).

**Compilation (done once, offline):**
```bash
xcrun -sdk macosx metal -c raytrace.metal -o raytrace.air
xcrun -sdk macosx metallib raytrace.air -o raytrace.metallib
```

**Kernel signature:**
```metal
kernel void raytrace_kernel(
    texture2d<float, access::write> output [[texture(0)]],
    constant Uniforms& uniforms          [[buffer(0)]],
    constant Shape* shapes               [[buffer(1)]],
    uint2 gid                            [[thread_position_in_grid]]
)
```

**Uniforms struct (shared between asm and MSL):**
```metal
struct Uniforms {
    float time;            // elapsed seconds
    uint  frame_count;     // frame number
    uint  num_shapes;      // shape count
    uint  num_lights;      // light count
    float2 resolution;     // viewport size
    float3 camera_pos;     // fixed camera position
    float3 camera_look_at; // fixed look-at point
    float  camera_fov;     // field of view in radians
    Light  lights[4];      // max 4 moving lights
};

struct Light {
    float3 position;
    float3 color;
    float  intensity;
};

struct Shape {
    uint   type;      // 0=sphere, 1=box, 2=plane
    float3 position;
    float3 size;      // radius for sphere, half-extents for box, normal for plane
    float3 color;
    float  roughness;
    float  reflectivity;
};
```

**Ray tracing approach for v1 (software intersection in the compute kernel):**
- Cast primary ray from camera through pixel
- Intersect against all shapes (loop over shapes buffer)
- On hit: compute Blinn-Phong shading from each light
- Cast shadow rays toward each light (binary occlusion)
- Simple reflection: one bounce for shapes with reflectivity > 0
- Write final color to output texture

> **Note on hardware RT:** For v1, we do manual intersection in the compute shader. This keeps the metallib simple and avoids needing to build Metal acceleration structures from assembly (which requires additional `objc_msgSend` choreography for `MTLAccelerationStructure`, `MTLInstanceAccelerationStructureDescriptor`, etc.). A v2 could add hardware-accelerated intersection using the `intersector` API.

### 3. `Makefile`

```makefile
.PHONY: all clean run

all: raytrace.metallib metal_rt_demo

raytrace.metallib: raytrace.metal
	xcrun -sdk macosx metal -c raytrace.metal -o raytrace.air
	xcrun -sdk macosx metallib raytrace.air -o raytrace.metallib

metal_rt_demo: main.s
	as -o main.o main.s
	ld -o metal_rt_demo main.o \
		-lSystem \
		-framework Metal \
		-framework AppKit \
		-framework QuartzCore \
		-framework CoreGraphics \
		-framework Foundation \
		-syslibroot $(shell xcrun --sdk macosx --show-sdk-path) \
		-e _main

run: all
	./metal_rt_demo

clean:
	rm -f main.o raytrace.air raytrace.metallib metal_rt_demo
```

---

## Scene Description (v1)

A simple room with enough geometric variety to show off lighting:

**Room (6 planes):**
- Floor: y = 0, gray, slight reflectivity
- Ceiling: y = 5
- Back wall: z = -10
- Left wall: x = -6, tinted red (Cornell box nod)
- Right wall: x = 6, tinted green (Cornell box nod)
- Front wall: z = 2 (behind camera, mostly not visible)

**Shapes:**
- 1 large sphere (center of room, shiny/reflective)
- 1 smaller sphere (offset, matte)
- 1 box (off to one side, moderate reflectivity)

**Lights (the moving part):**
- Light A: orbits horizontally around the room center (warm white)
- Light B: bobs up and down slowly (cool blue-ish)
- Light C (optional): figure-8 path near ceiling (soft amber)

All light positions are computed per-frame in assembly as `sin(time * speed) * radius` and written into the uniforms buffer.

---

## Key Implementation Details

### ObjC Selector Calling Convention

Every Objective-C method call from assembly follows this pattern:

```asm
// [receiver selectorWithArg1:val1 arg2:val2]
// becomes:
//   x0 = receiver
//   x1 = selector (from sel_registerName)
//   x2 = val1
//   x3 = val2
//   bl _objc_msgSend

// For methods returning floating point:
//   bl _objc_msgSend  (return in v0/d0)

// For methods returning structs (small):
//   bl _objc_msgSend  (return in x0/x1 or register pair)

// For methods returning large structs:
//   bl _objc_msgSend_stret  (pointer in x8)
```

### CFString Constants (for NSString args)

Metal methods take `NSString*` arguments. In assembly, these can be created as compile-time `__CFString` constants:

```asm
.section __DATA,__cfstring
_func_name:
    .quad ___CFConstantStringClassReference  // isa
    .long 0x07C8                             // flags (UTF-8)
    .long 0x0000
    .quad _func_name_cstr                    // pointer to C string
    .quad 16                                 // length

.section __TEXT,__cstring
_func_name_cstr:
    .asciz "raytrace_kernel"
```

### Light Animation (in render loop)

```asm
// Pseudocode for light position update:
// light_a.x = cos(time * 1.0) * 4.0
// light_a.y = 3.5
// light_a.z = sin(time * 1.0) * 4.0 - 4.0
//
// In asm: load time from uniforms, use FMADD/FMUL with constants,
// call _sinf/_cosf from libSystem, store result back to buffer
```

### CVDisplayLink vs. Simple Loop

Two options for driving the render loop:

**Option A — CVDisplayLink (preferred, smooth):**
- Create a CVDisplayLink callback. This requires a C-callable function pointer, which is fine — the callback is just an assembly label with the right ABI.
- The callback fires at display refresh rate (120Hz on ProMotion).

**Option B — Simple while loop with `usleep` (simpler to implement):**
- Loop: update, render, `usleep(8333)` (~120fps target)
- Less precise but much easier to set up in assembly.

**Recommendation for v1: Option B.** Get it working first with a simple loop. Swap to CVDisplayLink in v2 if needed.

---

## File Inventory

| File | Language | Purpose |
|---|---|---|
| `main.s` | AArch64 asm | Entire host program |
| `raytrace.metal` | MSL | Ray tracing compute kernel |
| `raytrace.metallib` | Binary (compiled) | Pre-compiled GPU code |
| `Makefile` | Make | Build orchestration |

That's it. Four files total.

---

## Build & Run Requirements

- macOS 14+ (Sonoma or later)
- M3 Max (or any Apple Silicon; M3 family for hardware RT)
- Xcode Command Line Tools (provides `as`, `ld`, `xcrun`, `metal`, `metallib`)
- No Xcode project needed — pure command-line build

---

## Success Criteria for v1

1. **Window appears** with a rendered frame (not black, not garbage)
2. **Room geometry is visible** — floor, walls, ceiling, shapes recognizable
3. **Lighting is correct** — shapes have shading, not flat colored
4. **Shadows are cast** — occluded areas are darker
5. **Lights move** — visible change frame-to-frame, smooth animation
6. **Stable 30+ FPS** at 1280×720 (M3 Max should easily hit 60+)
7. **Clean exit** — Cmd+Q or window close terminates without crash

---

## Stretch Goals (v2+)

- **Hardware-accelerated RT:** Build `MTLAccelerationStructure` from assembly, use `intersector` API in MSL for massive perf gain
- **CVDisplayLink:** Replace usleep loop with proper display-synced callback
- **Reflections:** Multi-bounce reflections (2-3 bounces)
- **Soft shadows:** Multiple shadow rays per light for penumbra
- **Textured surfaces:** Checkerboard floor, procedural textures in MSL
- **Camera controls:** Mouse/keyboard input for camera movement (requires NSEvent handling from asm)
- **Tone mapping / gamma:** Proper HDR → SDR pipeline in the shader

---

## Known Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| `objc_msgSend` ABI subtlety (e.g. struct returns, tagged pointers) | Medium | Test each call individually; use `_objc_msgSend_stret` for large struct returns. Log intermediate values. |
| CFString layout wrong → crash on any NSString arg | Medium | Verify against `otool -s __DATA __cfstring` output of a known-good binary. |
| Metal pipeline creation fails silently | Medium | Always check `error` out-parameter (pass pointer, inspect after call). |
| Linker flags / SDK path issues | Low | Use `xcrun --sdk macosx --show-sdk-path` dynamically in Makefile. |
| `usleep` loop gives inconsistent frame timing | Low | Acceptable for v1; fix with CVDisplayLink in v2. |
| Thread/alignment issues in buffer writes | Low | Ensure 16-byte alignment on all Metal buffer contents. Use `.align 4` in data sections. |
