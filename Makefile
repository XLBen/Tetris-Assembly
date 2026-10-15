SDK := $(shell xcrun --sdk macosx --show-sdk-path)

SRCS := $(wildcard src/*.s)
OBJS := $(SRCS:src/%.s=build/%.o)

tetris: $(OBJS)
	ld -arch arm64 -e _main -o $@ $(OBJS) -syslibroot $(SDK) -l System

build/%.o: src/%.s | build
	as -arch arm64 -o $@ $<

build:
	mkdir -p build

clean:
	rm -rf tetris build

.PHONY: clean
