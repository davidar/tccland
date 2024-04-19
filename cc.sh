#!/bin/sh

for arg do case "$arg" in -c) exec tcc "$@";; esac; done

echo "GROUP ( /usr/local/musl/lib/libc.a /usr/local/lib/tcc/libtcc1.a )" > /tmp/libc.ld
exec tcc "$@" -static /tmp/libc.ld
