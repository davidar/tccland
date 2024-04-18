#!/bin/sh

if [ $1 = "--version" ]; then
    # https://github.com/landley/toybox/issues/461
    echo GNU
    exit 0
fi

exec /usr/local/sbase/bin/grep "$@"
