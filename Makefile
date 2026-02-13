CC = clang
CFLAGS = -O2 -Wall

# SDL2 detection (optional — viewer builds only if SDL2 is installed)
SDL2_CONFIG := $(shell which sdl2-config 2>/dev/null)
ifdef SDL2_CONFIG
    SDL2_CFLAGS := $(shell sdl2-config --cflags)
    SDL2_LIBS   := $(shell sdl2-config --libs)
    VIEWER_TARGET := fractal/viewer
else
    VIEWER_TARGET :=
endif

FRACTAL_ASM = fractal/mandelbrot.s fractal/julia.s fractal/colormap.s
COCOA_ASM = fractal/state.s fractal/render.s fractal/events.s fractal/app.s

all: sieve/primes neon_uppercase/neon_demo pure_asm/hello fractal/fractal $(VIEWER_TARGET) fractal/cocoa_viewer

sieve/primes: sieve/sieve_main.c sieve/sieve.s
	$(CC) $(CFLAGS) -o $@ $^

neon_uppercase/neon_demo: neon_uppercase/neon_main.c neon_uppercase/neon_upper.s
	$(CC) $(CFLAGS) -o $@ $^

pure_asm/hello: pure_asm/hello.s
	$(CC) -nostdlib -lSystem -Wl,-e,_start -o $@ $<

fractal/fractal: fractal/fractal_main.c $(FRACTAL_ASM)
	$(CC) $(CFLAGS) -o $@ $^

ifdef SDL2_CONFIG
fractal/viewer: fractal/viewer.c $(FRACTAL_ASM)
	$(CC) $(CFLAGS) $(SDL2_CFLAGS) -o $@ $^ $(SDL2_LIBS)
endif

fractal/cocoa_viewer: $(COCOA_ASM) $(FRACTAL_ASM)
	$(CC) $(CFLAGS) -framework Cocoa -framework CoreGraphics -o $@ $^

clean:
	rm -f sieve/primes neon_uppercase/neon_demo pure_asm/hello fractal/fractal fractal/viewer fractal/cocoa_viewer
	rm -rf *.dSYM */*.dSYM

.PHONY: all clean
