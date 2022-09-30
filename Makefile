all:
	zig build

release:
	zig build -Drelease-fast

notcurses:
	./build-notcurses.sh

