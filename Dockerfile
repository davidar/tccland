FROM ubuntu:22.04 AS build
RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y \
        autoconf \
        automake \
        autopoint \
        build-essential \
        gdb \
        git \
        pkgconf \
        wget

COPY make /src/make
WORKDIR /src/make
RUN ./bootstrap --force

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

RUN echo "GROUP ( /usr/local/musl/lib/libc.a /usr/local/lib/tcc/libtcc1.a )" > /libc.ld

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

COPY byacc /src/byacc
WORKDIR /src/byacc
RUN ./configure
RUN make CC=tcc \
    CFLAGS="-nostdinc -I/usr/local/musl/include" \
    LDFLAGS="-nostdlib -static" \
    LIBS="/usr/local/musl/lib/crt1.o /libc.ld"
RUN make DESTDIR=/dest install
RUN make clean


FROM scratch
COPY --from=build /dest/usr /usr
COPY --from=build /src /src
COPY cc.sh /usr/bin/cc
COPY ar.sh /usr/bin/ar
COPY ranlib.sh /usr/bin/ranlib

SHELL ["/usr/local/bin/dash", "-c"]
# CMD ["/usr/local/bin/dash"]
ENV CC=/usr/bin/cc

RUN mkdir -p /bin /usr/lib /tmp
RUN ln -sv /usr/local/musl/include /usr/include
RUN ln -sv /usr/local/bin/dash /bin/sh
RUN ln -sv /usr/local/musl/lib /usr/lib/x86_64-linux-gnu

COPY tcc-boot.sh /src/tcc/boot.sh
WORKDIR /src/tcc
RUN ./boot.sh

COPY sbase /src/sbase
WORKDIR /src/sbase
RUN bmake
RUN bmake install PREFIX=/usr/local/sbase
RUN ln -sv /usr/local/sbase/bin/expr /usr/bin/expr
RUN ln -sv /usr/local/sbase/bin/tr /usr/bin/tr

COPY awk /src/awk
WORKDIR /src/awk
RUN bmake YACC="yacc -d -b awkgram"
RUN cp a.out /usr/bin/awk

WORKDIR /src/make
RUN ./configure --disable-dependency-tracking LD=cc
RUN ./build.sh
RUN ./make MAKEINFO=true
RUN ./make MAKEINFO=true install

WORKDIR /src/musl
RUN rm -rf /usr/local/musl
RUN ./configure CC=tcc
RUN make -j$(nproc) CFLAGS=-g
RUN make install

COPY bash /src/bash
WORKDIR /src/bash
RUN ./configure --without-bash-malloc LD=cc
RUN make -j$(nproc)
RUN make install
RUN ln -sv /usr/local/bin/bash /bin/bash

CMD ["/bin/bash"]

COPY hello.c /src/hello.c
WORKDIR /src
