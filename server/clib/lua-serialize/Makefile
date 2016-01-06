LIBNAME = serialize
LUADIR = /usr/local/include

COPT = -O2
# COPT = -DLPEG_DEBUG -g

CWARNS = -Wall -Wextra -pedantic \
	-Waggregate-return \
	-Wcast-align \
	-Wcast-qual \
	-Wdisabled-optimization \
	-Wpointer-arith \
	-Wshadow \
	-Wsign-compare \
	-Wundef \
	-Wwrite-strings \
	-Wbad-function-cast \
	-Wdeclaration-after-statement \
	-Wmissing-prototypes \
	-Wnested-externs \
	-Wstrict-prototypes \
# -Wunreachable-code \

SRC =\
serialize.c\

CFLAGS = $(CWARNS) $(COPT) -std=c99 -I$(LUADIR) -fPIC
CC = gcc

FILES = serialize.o

# For Linux
linux:
	make serialize.so "DLLFLAGS = -shared -fPIC"

# For Mac OS
macosx:
	make serialize.so "DLLFLAGS = -bundle -undefined dynamic_lookup"

serialize.so: $(FILES)
	env $(CC) $(DLLFLAGS) $(FILES) -o serialize.so

$(FILES): Makefile

clean:
	rm -f $(FILES) serialize.so

serialize.o: serialize.c
