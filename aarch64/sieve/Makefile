CC = clang
CFLAGS = -O2 -Wall

primes: sieve_main.c sieve.s
	$(CC) $(CFLAGS) -o $@ $^

clean:
	rm -f primes
	rm -rf *.dSYM

.PHONY: clean
