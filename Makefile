CC = clang
CFLAGS = -O2 -Wall

all: sieve/primes neon_uppercase/neon_demo pure_asm/hello

sieve/primes: sieve/sieve_main.c sieve/sieve.s
	$(CC) $(CFLAGS) -o $@ $^

neon_uppercase/neon_demo: neon_uppercase/neon_main.c neon_uppercase/neon_upper.s
	$(CC) $(CFLAGS) -o $@ $^

pure_asm/hello: pure_asm/hello.s
	$(CC) -nostdlib -lSystem -Wl,-e,_start -o $@ $<

clean:
	rm -f sieve/primes neon_uppercase/neon_demo pure_asm/hello
	rm -rf *.dSYM */*.dSYM

.PHONY: all clean
