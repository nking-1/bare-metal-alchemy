CC = clang

hello: hello.s
	$(CC) -nostdlib -lSystem -Wl,-e,_start -o $@ $<

clean:
	rm -f hello
	rm -rf *.dSYM

.PHONY: clean
