
## aarch64 — Apple Silicon

**Prerequisites:** macOS on Apple Silicon + Xcode Command Line Tools (`xcode-select --install`)

### Building

Each project builds independently from its own directory:

```bash
cd aarch64/sieve && make
cd aarch64/neon_uppercase && make
cd aarch64/pure_asm && make
cd aarch64/fractal && make
```

### Demos

#### 1. Sieve of Eratosthenes (`aarch64/sieve`)

Classic prime-finding algorithm with the core sieve loop written in AArch64 assembly.

```
cd aarch64/sieve && make
./primes              # primes up to 100 (default)
./primes 500          # primes up to 500
./primes 10000        # primes up to 10,000
```

**Files:**
- `sieve.s` — the sieve algorithm in pure AArch64 assembly
- `sieve_main.c` — C wrapper that allocates memory, calls the sieve, and prints results

**Concepts demonstrated:**
- AArch64 calling convention (callee-saved registers, stack frame)
- Byte-level memory access (`ldrb`/`strb`)
- Loop constructs and conditional branches (`cbz`, `b.gt`)
- The zero register (`wzr`) as a free source of zeros

#### 2. NEON SIMD Uppercase (`aarch64/neon_uppercase`)

Converts strings to uppercase using ARM's NEON vector engine — processing **16 characters simultaneously** in 128-bit registers. Includes a scalar version for comparison.

```
cd aarch64/neon_uppercase && make
./neon_demo
```

**Files:**
- `neon_upper.s` — both NEON (vectorized) and scalar implementations, heavily commented
- `neon_main.c` — visual demo + speed benchmark (1 MB x 1000 iterations)

**Concepts demonstrated:**
- NEON/AdvSIMD 128-bit registers (`v0`–`v5`) treated as 16 x uint8 lanes (`.16b`)
- `movi` — broadcast an immediate to all 16 lanes
- `cmhs` — unsigned compare across all lanes simultaneously
- Bitwise masking to selectively transform only lowercase bytes
- The ASCII trick: `'a'` and `'A'` differ by exactly one bit (bit 5 = 0x20)

#### 3. Pure Assembly FizzBuzz (`aarch64/pure_asm`)

**Zero C code.** FizzBuzz 1–30 written entirely in AArch64 assembly, using raw macOS syscalls (`write`, `exit`). The OS jumps straight into our `_start` — no C runtime initialization at all.

```
cd aarch64/pure_asm && make
./hello
```

**Files:**
- `hello.s` — everything: entry point, FizzBuzz logic, number-to-ASCII conversion, raw syscalls

**Concepts demonstrated:**
- Replacing the C runtime entirely — `_start` as raw entry point
- Raw macOS syscalls from assembly (`svc #0x80` with syscall number in `x16`)
- Address loading with `adrp`/`add` and `@PAGE`/`@PAGEOFF` relocations
- Integer-to-ASCII conversion on the stack using `UDIV` + `MSUB` (modulo)
- Mach-O assembly syntax differences from ELF and MSVC `armasm64`

#### 4. Fractal Viewer (`aarch64/fractal`)

**Zero C code. Zero external dependencies.** A fully interactive Mandelbrot/Julia set viewer written entirely in AArch64 assembly, using native macOS Cocoa/AppKit via the Objective-C runtime. NEON SIMD kernels compute fractal rows in parallel using `float64x2` vectorization.

```
cd aarch64/fractal && make

# Mandelbrot (default)
./cocoa_viewer

# Lightning Julia
./cocoa_viewer -j -0.8,0.156

# Seahorse valley Julia
./cocoa_viewer -j -0.75,0.11

# Spiral Julia
./cocoa_viewer -j 0.285,0.01

# Custom window size and iterations
./cocoa_viewer -w 1280 -h 960 -i 512
```

**Controls:**

| Input | Action |
|---|---|
| Left-click drag | Pan |
| Scroll wheel | Zoom in/out (centered on cursor) |
| Right-click | Switch to Julia set using clicked point as c |
| Space | Switch back to Mandelbrot |
| +/- | Double/halve max iterations |
| S | Save current view as PPM |
| R | Reset view |
| Q / Escape | Quit |

**Files:**
- `app.s` — `_main` entry point, Cocoa bootstrap (NSApplication, NSWindow, custom NSView/AppDelegate classes created via ObjC runtime)
- `events.s` — all event handlers (drawRect, mouse, keyboard, scroll, timer) and PPM save
- `render.s` — compute view bounds, render fractal rows, RGB24→ARGB32 conversion (NEON `ld3`/`st4`)
- `state.s` — global state struct, string constants, ObjC type encodings
- `state_defs.s` — struct offset equates (`.include`d by other files)
- `mandelbrot.s` — Mandelbrot NEON kernel (2 complex points per iteration via `float64x2`)
- `julia.s` — Julia NEON kernel
- `colormap.s` — iteration-to-RGB colormap

**Concepts demonstrated:**
- Calling Objective-C from pure assembly (`objc_getClass`, `sel_registerName`, `objc_msgSend`)
- Creating custom ObjC classes at runtime (`objc_allocateClassPair`, `class_addMethod`, `objc_registerClassPair`)
- CGRect as a Homogeneous Floating-point Aggregate (HFA) — passed in `d0`–`d3`, not on the stack
- CoreGraphics bitmap pipeline: `CGBitmapContextCreate` → `CGBitmapContextCreateImage` → `CGContextDrawImage`
- Progressive rendering (coarse 1/4 res preview, then full resolution)
- Apple ARM64 variadic calling convention (`snprintf` args on the stack)
- Callee-saved FP register discipline (`d8`–`d15` must be preserved across calls)
- NEON SIMD for both fractal math (`float64x2`) and pixel format conversion (`ld3`/`st4`)

## AArch64 Quick Reference

| Register | Purpose |
|---|---|
| `x0`–`x7` | Function arguments and return value |
| `x19`–`x28` | Callee-saved (must preserve across calls) |
| `x29` | Frame pointer |
| `x30` | Link register (return address) |
| `xzr`/`wzr` | Hardwired zero register |
| `v0`–`v31` | 128-bit NEON/SIMD registers |
| `d8`–`d15` | Callee-saved (lower 64 bits of `v8`–`v15`) |
| `sp` | Stack pointer (must stay 16-byte aligned) |
