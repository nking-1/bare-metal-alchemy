CC = clang
CFLAGS = -O2 -Wall
SCENE ?= cornell

.PHONY: all clean run shader

all: raytrace.metallib metal_rt_demo

shader: raytrace.metallib

raytrace.metallib: raytrace.metal
	xcrun -sdk macosx metal -c raytrace.metal -o raytrace.air
	xcrun -sdk macosx metallib raytrace.air -o raytrace.metallib
	rm -f raytrace.air

metal_rt_demo: main.s defs.s scenes/$(SCENE).s
	$(CC) $(CFLAGS) -o $@ main.s scenes/$(SCENE).s \
		-framework Metal \
		-framework AppKit \
		-framework QuartzCore \
		-framework CoreGraphics \
		-framework Foundation

run: all
	./metal_rt_demo

clean:
	rm -f raytrace.air raytrace.metallib metal_rt_demo
	rm -rf *.dSYM
