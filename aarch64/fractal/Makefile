CC = clang
CFLAGS = -O2 -Wall

KERNEL_ASM = mandelbrot.s julia.s colormap.s
COCOA_ASM = state.s render.s events.s app.s

cocoa_viewer: $(COCOA_ASM) $(KERNEL_ASM)
	$(CC) $(CFLAGS) -framework Cocoa -framework CoreGraphics -o $@ $^

clean:
	rm -f cocoa_viewer
	rm -rf *.dSYM

.PHONY: clean
