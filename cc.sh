#!/bin/sh

if echo "$@" | grep -q '\-o[[:space:]]\{1,\}[^[:space:]]*\.o' || [ "$1" = "-c" ]; then
    # -o *.o
    exec tcc "$@"
fi

mkdir -p /tmp
echo "GROUP ( /usr/local/musl/lib/libc.a /usr/local/lib/tcc/libtcc1.a )" > /tmp/libc.ld
exec tcc "$@" -static /tmp/libc.ld
