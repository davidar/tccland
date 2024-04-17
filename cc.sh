#!/bin/sh

mkdir -p /tmp
echo "GROUP ( /usr/local/musl/lib/libc.a /usr/local/lib/tcc/libtcc1.a )" > /tmp/libc.ld
tcc "$@" -static /tmp/libc.ld
