# Assembly Experiments

Hands-on assembly demos — starting with AArch64 on Apple Silicon, with room for more architectures.

## Repository Structure

Each architecture gets its own top-level folder. Each project within is self-contained with its own Makefile.

```
assembly_experiments/
├── README.md
└── aarch64/                         # Apple Silicon (M1/M2/M3/M4) — macOS
    ├── README.md                    # README for aarch64 projects
    ├── sieve/                       # Prime sieve
    ├── neon_uppercase/              # NEON SIMD uppercase
    ├── pure_asm/                    # FizzBuzz — zero C, raw syscalls
    └── fractal/                     # Mandelbrot/Julia viewer — zero C, Cocoa from assembly
```
