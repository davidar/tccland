#!/bin/sh

tcc "$@" -static /usr/lib/libc.ld
