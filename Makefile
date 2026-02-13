CC = clang
CFLAGS = -O2 -Wall

FRACTAL_ASM = fractal/mandelbrot.s fractal/julia.s fractal/colormap.s
COCOA_ASM = fractal/state.s fractal/render.s fractal/events.s fractal/app.s

all: sieve/primes neon_uppercase/neon_demo pure_asm/hello fractal/cocoa_viewer

sieve/primes: sieve/sieve_main.c sieve/sieve.s
	$(CC) $(CFLAGS) -o $@ $^

neon_uppercase/neon_demo: neon_uppercase/neon_main.c neon_uppercase/neon_upper.s
	$(CC) $(CFLAGS) -o $@ $^

pure_asm/hello: pure_asm/hello.s
	$(CC) -nostdlib -lSystem -Wl,-e,_start -o $@ $<

fractal/cocoa_viewer: $(COCOA_ASM) $(FRACTAL_ASM)
	$(CC) $(CFLAGS) -framework Cocoa -framework CoreGraphics -o $@ $^

clean:
	rm -f sieve/primes neon_uppercase/neon_demo pure_asm/hello fractal/cocoa_viewer
	rm -rf *.dSYM */*.dSYM

.PHONY: all clean
