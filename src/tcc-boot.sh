#!/bin/sh

set -ex

CC=tcc
AR='tcc -ar'
CFLAGS='-DCONFIG_TRIPLET="x86_64-linux-gnu" -DTCC_TARGET_X86_64 -DONE_SOURCE=0 -Wall -O2 -Wdeclaration-after-statement -fno-strict-aliasing -Wno-pointer-sign -Wno-sign-compare -Wno-unused-result -Wno-format-truncation -Wno-stringop-truncation -I.'
PREFIX=/boot/usr/local

$CC -o tcc.o -c tcc.c $CFLAGS
$CC -o libtcc.o -c libtcc.c $CFLAGS
$CC -DC2STR conftest.c -o c2str.exe && ./c2str.exe include/tccdefs.h tccdefs_.h
$CC -o tccpp.o -c tccpp.c $CFLAGS
$CC -o tccgen.o -c tccgen.c $CFLAGS
$CC -o tccdbg.o -c tccdbg.c $CFLAGS
$CC -o tccelf.o -c tccelf.c $CFLAGS
$CC -o tccasm.o -c tccasm.c $CFLAGS
$CC -o tccrun.o -c tccrun.c $CFLAGS
$CC -o x86_64-gen.o -c x86_64-gen.c $CFLAGS
$CC -o x86_64-link.o -c x86_64-link.c $CFLAGS
$CC -o i386-asm.o -c i386-asm.c $CFLAGS
$AR rcs libtcc.a libtcc.o tccpp.o tccgen.o tccdbg.o tccelf.o tccasm.o tccrun.o x86_64-gen.o x86_64-link.o i386-asm.o
$CC -o tcc tcc.o libtcc.a -lm -ldl -lpthread  

cd lib
../tcc -c libtcc1.c -o libtcc1.o -B.. -I..
../tcc -c alloca.S -o alloca.o -B.. -I..
../tcc -c alloca-bt.S -o alloca-bt.o -B.. -I..
../tcc -c stdatomic.c -o stdatomic.o -B.. -I..
../tcc -c atomic.S -o atomic.o -B.. -I..
../tcc -c builtin.c -o builtin.o -B.. -I..
../tcc -c tcov.c -o tcov.o -B.. -I..
../tcc -c va_list.c -o va_list.o -B.. -I..
../tcc -c dsohandle.c -o dsohandle.o -B.. -I..
../tcc -ar rcs ../libtcc1.a libtcc1.o alloca.o alloca-bt.o stdatomic.o atomic.o builtin.o tcov.o va_list.o dsohandle.o
../tcc -c bt-exe.c -o ../bt-exe.o -B.. -I..
../tcc -c bt-log.c -o ../bt-log.o -B.. -I..
../tcc -c runmain.c -o ../runmain.o -B.. -I..
# ../tcc -c bcheck.c -o ../bcheck.o -B.. -I.. -bt
cd ..

mkdir -p "$PREFIX/bin" && install -m755  tcc "$PREFIX/bin"
# mkdir -p "$PREFIX/lib/tcc" && install -m644 libtcc1.a runmain.o bt-exe.o bt-log.o bcheck.o "$PREFIX/lib/tcc"
mkdir -p "$PREFIX/lib/tcc" && install -m644 libtcc1.a runmain.o bt-exe.o bt-log.o "$PREFIX/lib/tcc"
mkdir -p "$PREFIX/lib/tcc/include" && install -m644 ./include/*.h ./tcclib.h "$PREFIX/lib/tcc/include"
mkdir -p "$PREFIX/lib" && install -m644 libtcc.a "$PREFIX/lib"
mkdir -p "$PREFIX/include" && install -m644 ./libtcc.h "$PREFIX/include"
