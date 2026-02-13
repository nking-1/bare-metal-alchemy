CC = clang
CFLAGS = -O2 -Wall

neon_demo: neon_main.c neon_upper.s
	$(CC) $(CFLAGS) -o $@ $^

clean:
	rm -f neon_demo
	rm -rf *.dSYM

.PHONY: clean
