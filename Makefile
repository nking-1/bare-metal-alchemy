CC = clang
CFLAGS = -O2 -Wall

all: sieve/primes neon_uppercase/neon_demo pure_asm/hello fractal/fractal

sieve/primes: sieve/sieve_main.c sieve/sieve.s
	$(CC) $(CFLAGS) -o $@ $^

neon_uppercase/neon_demo: neon_uppercase/neon_main.c neon_uppercase/neon_upper.s
	$(CC) $(CFLAGS) -o $@ $^

pure_asm/hello: pure_asm/hello.s
	$(CC) -nostdlib -lSystem -Wl,-e,_start -o $@ $<

fractal/fractal: fractal/fractal_main.c fractal/mandelbrot.s fractal/julia.s fractal/colormap.s
	$(CC) $(CFLAGS) -o $@ $^

clean:
	rm -f sieve/primes neon_uppercase/neon_demo pure_asm/hello fractal/fractal
	rm -rf *.dSYM */*.dSYM

.PHONY: all clean
