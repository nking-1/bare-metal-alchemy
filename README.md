# ARM64 Assembly Experiments

Hands-on AArch64 assembly demos running **natively** on Apple Silicon (M1/M2/M3/M4). Built with `clang` and the system assembler — no VMs, no emulation, no cross-compilation.

## Prerequisites

- **macOS on Apple Silicon** (M1, M2, M3, M4, etc.)
- **Xcode Command Line Tools** (`xcode-select --install`)

## Building

```
make
```

## Demos

### 1. Sieve of Eratosthenes (`sieve/primes`)

Classic prime-finding algorithm with the core sieve loop written in AArch64 assembly.

```
./sieve/primes              # primes up to 100 (default)
./sieve/primes 500          # primes up to 500
./sieve/primes 10000        # primes up to 10,000
```

**Files:**
- `sieve/sieve.s` — the sieve algorithm in pure AArch64 assembly
- `sieve/sieve_main.c` — C wrapper that allocates memory, calls the sieve, and prints results

**Concepts demonstrated:**
- AArch64 calling convention (callee-saved registers, stack frame)
- Byte-level memory access (`ldrb`/`strb`)
- Loop constructs and conditional branches (`cbz`, `b.gt`)
- The zero register (`wzr`) as a free source of zeros

### 2. NEON SIMD Uppercase (`neon_uppercase/neon_demo`)

Converts strings to uppercase using ARM's NEON vector engine — processing **16 characters simultaneously** in 128-bit registers. Includes a scalar version for comparison.

```
./neon_uppercase/neon_demo
```

**Files:**
- `neon_uppercase/neon_upper.s` — both NEON (vectorized) and scalar implementations, heavily commented
- `neon_uppercase/neon_main.c` — visual demo + speed benchmark (1 MB x 1000 iterations)

**Concepts demonstrated:**
- NEON/AdvSIMD 128-bit registers (`v0`–`v5`) treated as 16 x uint8 lanes (`.16b`)
- `movi` — broadcast an immediate to all 16 lanes
- `cmhs` — unsigned compare across all lanes simultaneously
- Bitwise masking to selectively transform only lowercase bytes
- The ASCII trick: `'a'` and `'A'` differ by exactly one bit (bit 5 = 0x20)

### 3. Pure Assembly FizzBuzz (`pure_asm/hello`)

**Zero C code.** FizzBuzz 1–30 written entirely in AArch64 assembly, using raw macOS syscalls (`write`, `exit`). The OS jumps straight into our `_start` — no C runtime initialization at all.

```
./pure_asm/hello
```

**Files:**
- `pure_asm/hello.s` — everything: entry point, FizzBuzz logic, number-to-ASCII conversion, raw syscalls

**Concepts demonstrated:**
- Replacing the C runtime entirely — `_start` as raw entry point
- Raw macOS syscalls from assembly (`svc #0x80` with syscall number in `x16`)
- Address loading with `adrp`/`add` and `@PAGE`/`@PAGEOFF` relocations
- Integer-to-ASCII conversion on the stack using `UDIV` + `MSUB` (modulo)
- Mach-O assembly syntax differences from ELF and MSVC `armasm64`

## Project Structure

```
arm_experiments/
├── Makefile                       # build with `make`
├── README.md                      # this file
├── sieve/
│   ├── sieve.s                    # Sieve of Eratosthenes — AArch64 assembly
│   └── sieve_main.c              # C driver for sieve demo
├── neon_uppercase/
│   ├── neon_upper.s               # NEON SIMD uppercase — AArch64 assembly
│   └── neon_main.c               # C driver for NEON demo
└── pure_asm/
    └── hello.s                    # FizzBuzz — 100% assembly, no C at all
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
