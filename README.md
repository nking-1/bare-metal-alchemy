# ARM64 Assembly Experiments

Hands-on AArch64 assembly demos running **natively** on ARM64 Windows (e.g. Parallels on Apple Silicon). Built with MSVC's `armasm64` assembler and `cl` compiler.

## Prerequisites

- **Windows on ARM64** (e.g. Parallels VM on Apple Silicon Mac)
- **Visual Studio 2022** with the "Desktop development with C++" workload (needs the ARM64 build tools)

## Building

```
build.bat
```

This invokes `vcvarsall.bat arm64` to set up the native ARM64 toolchain, then assembles and links both demos.

## Demos

### 1. Sieve of Eratosthenes (`primes.exe`)

Classic prime-finding algorithm with the core sieve loop written in AArch64 assembly.

```
.\sieve\primes.exe          # primes up to 100 (default)
.\sieve\primes.exe 500      # primes up to 500
.\sieve\primes.exe 10000    # primes up to 10,000
```

**Files:**
- `sieve\sieve.asm` — the sieve algorithm in pure AArch64 assembly
- `sieve\sieve_main.c` — C wrapper that allocates memory, calls the sieve, and prints results

**Concepts demonstrated:**
- AArch64 calling convention (callee-saved registers, stack frame)
- Byte-level memory access (`ldrb`/`strb`)
- Loop constructs and conditional branches (`cbz`, `b.gt`)
- The zero register (`wzr`) as a free source of zeros

### 2. NEON SIMD Uppercase (`neon_demo.exe`)

Converts strings to uppercase using ARM's NEON vector engine — processing **16 characters simultaneously** in 128-bit registers. Includes a scalar version for comparison.

```
.\neon_uppercase\neon_demo.exe
```

**Files:**
- `neon_uppercase\neon_upper.asm` — both NEON (vectorized) and scalar implementations, heavily commented
- `neon_uppercase\neon_main.c` — visual demo + speed benchmark (1 MB × 1000 iterations)

**Concepts demonstrated:**
- NEON/AdvSIMD 128-bit registers (`v0`–`v5`) treated as 16 × uint8 lanes (`.16b`)
- `movi` — broadcast an immediate to all 16 lanes
- `cmhs` — unsigned compare across all lanes simultaneously
- Bitwise masking to selectively transform only lowercase bytes
- The ASCII trick: `'a'` and `'A'` differ by exactly one bit (bit 5 = 0x20)
- Speedup from SIMD: ~**9–10x** faster than scalar on the same CPU

## Project Structure

```
arm_experiments/
├── build.bat                      # build script (sets up MSVC ARM64 toolchain)
├── README.md                      # this file
├── sieve/
│   ├── sieve.asm                  # Sieve of Eratosthenes — AArch64 assembly
│   └── sieve_main.c               # C driver for sieve demo
└── neon_uppercase/
    ├── neon_upper.asm             # NEON SIMD uppercase — AArch64 assembly
    └── neon_main.c                # C driver for NEON demo
```

## AArch64 Quick Reference

| Register | Purpose |
|---|---|
| `x0`–`x7` | Function arguments and return value |
| `x19`–`x28` | Callee-saved (must preserve across calls) |
| `x29` | Frame pointer |
| `x30` | Link register (return address) |
| `xzr`/`wzr` | Hardwired zero register |
| `v0`–`v31` | 128-bit NEON/SIMD registers |
| `q0`–`q31` | Same registers, 128-bit name (used with `ldr`/`str`) |
| `sp` | Stack pointer (must stay 16-byte aligned) |
