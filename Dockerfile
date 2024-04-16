FROM ubuntu:22.04 AS build
RUN apt-get update && apt-get install -y build-essential file automake gdb

COPY tinycc /src/tcc
WORKDIR /src/tcc
RUN ./configure
RUN make -j$(nproc)
RUN make install
RUN make clean

COPY musl /src/musl
WORKDIR /src/musl
RUN ./configure --target=x86_64 CC='tcc' AR='tcc -ar' RANLIB='echo' LIBCC='/usr/local/lib/tcc/libtcc1.a'
RUN make -j$(nproc) CFLAGS=-g
RUN make install
RUN make DESTDIR=/dest install
RUN make clean

COPY libc.ld /

WORKDIR /src/tcc
RUN make clean
RUN ./configure \
    --extra-cflags="-nostdinc -nostdlib -I/usr/local/musl/include -DCONFIG_TCC_STATIC" \
    --extra-ldflags="-nostdlib /usr/local/musl/lib/crt1.o /libc.ld -static" \
    --config-ldl=no --config-debug=yes
RUN make -j$(nproc)
RUN make install
RUN make DESTDIR=/dest install
RUN make clean

COPY toybox /src/toybox
COPY toybox.config /src/toybox/.config
WORKDIR /src/toybox
# RUN make defconfig
RUN make -j$(nproc) NOSTRIP=1 CC=tcc \
    CFLAGS="-nostdinc -nostdlib -I/usr/local/musl/include -I/usr/include -I/usr/include/x86_64-linux-gnu -g" \
    LDFLAGS="-nostdlib /usr/local/musl/lib/crt1.o /libc.ld -static"
RUN PREFIX=/dest/usr/local/bin make install_flat
RUN make clean

COPY dash /src/dash
WORKDIR /src/dash
RUN ./autogen.sh
RUN ./configure CC=tcc \
    CFLAGS="-nostdinc -I/usr/local/musl/include" \
    LDFLAGS="-nostdlib -static" \
    LIBS="/usr/local/musl/lib/crt1.o /libc.ld"
RUN sed -i '/HAVE_ALIAS_ATTRIBUTE/d' config.h
RUN make -j$(nproc)
RUN make DESTDIR=/dest install
RUN make clean

COPY bmake /src/bmake
RUN CC=tcc \
    CFLAGS="-nostdinc -I/usr/local/musl/include" \
    LDFLAGS="-nostdlib -static" \
    LIBS="/usr/local/musl/lib/crt1.o /libc.ld" \
    BROKEN_TESTS="directive-export directive-export-gmake varname-dot-make-jobs" \
    /src/bmake/boot-strap --prefix=/usr/local --install-destdir=/dest --install

FROM scratch
COPY --from=build /dest/usr /usr
COPY --from=build /src /src
COPY libc.ld /usr/lib/libc.ld
COPY hello.c /usr/bin/hello
COPY cc.sh /usr/bin/cc
SHELL ["/usr/local/bin/dash", "-c"]
RUN ln -sv /usr/local/musl/include /usr/include
RUN mkdir /bin
RUN ln -sv /usr/local/bin/dash /bin/sh
RUN ln -sv /usr/local/musl/lib /usr/lib/x86_64-linux-gnu
ENV CC=/usr/bin/cc
CMD ["/usr/local/bin/dash"]
