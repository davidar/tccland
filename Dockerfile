FROM ubuntu:22.04 AS stage-0
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

COPY src/tcc /src/tcc
WORKDIR /src/tcc
RUN ./configure
RUN make -j$(nproc)
RUN make install
RUN make clean

COPY src/musl /src/musl
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

COPY src/toybox /src/toybox
COPY src/toybox.config /src/toybox/.config
WORKDIR /src/toybox
# RUN make defconfig
RUN make -j$(nproc) NOSTRIP=1 CC=tcc \
    CFLAGS="-nostdinc -nostdlib -I/usr/local/musl/include -I/usr/include -I/usr/include/x86_64-linux-gnu -g" \
    LDFLAGS="-nostdlib /usr/local/musl/lib/crt1.o /libc.ld -static"
# RUN PREFIX=/dest/usr/local/bin make install_flat
# RUN make clean
RUN rm generated/obj/main.o

COPY src/dash /src/dash
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

# COPY bmake /src/bmake
# RUN CC=tcc \
#     CFLAGS="-nostdinc -I/usr/local/musl/include" \
#     LDFLAGS="-nostdlib -static" \
#     LIBS="/usr/local/musl/lib/crt1.o /libc.ld" \
#     BROKEN_TESTS="directive-export directive-export-gmake dotwait varname-dot-make-jobs" \
#     /src/bmake/boot-strap --prefix=/usr/local --install-destdir=/dest --install

# COPY byacc /src/byacc
# WORKDIR /src/byacc
# RUN ./configure
# RUN make CC=tcc \
#     CFLAGS="-nostdinc -I/usr/local/musl/include" \
#     LDFLAGS="-nostdlib -static" \
#     LIBS="/usr/local/musl/lib/crt1.o /libc.ld"
# RUN make DESTDIR=/dest install
# RUN make clean

# COPY src/oksh /src/oksh
# WORKDIR /src/oksh
# RUN ./configure --cc=tcc --cflags="-nostdinc -I/usr/local/musl/include -g" --no-strip
# RUN make -j$(nproc)
# RUN make DESTDIR=/dest install
# RUN make clean


FROM scratch AS stage-1
COPY --from=stage-0 /dest/usr /usr
COPY --from=stage-0 /src /src

SHELL ["/usr/local/bin/dash", "-c"]

RUN mkdir -p /bin /usr/lib /tmp
RUN ln -sv /usr/local/bin/dash /bin/sh
RUN ln -sv /usr/local/musl/include /usr/include
RUN ln -sv /usr/local/musl/lib /usr/lib/x86_64-linux-gnu
RUN ln -sv /usr/local/bin/tcc /bin/cc

CMD ["/bin/sh"]

COPY src/tcc-boot.sh /src/tcc/boot.sh
WORKDIR /src/tcc
RUN ./boot.sh

# COPY sbase /src/sbase
# WORKDIR /src/sbase
# RUN bmake
# RUN bmake install PREFIX=/usr/local/sbase
# RUN ln -sv /usr/local/sbase/bin/expr /usr/bin/expr
# RUN ln -sv /usr/local/sbase/bin/tr /usr/bin/tr

# COPY awk /src/awk
# WORKDIR /src/awk
# RUN bmake YACC="yacc -d -b awkgram"
# RUN cp a.out /usr/bin/awk

RUN for cmd in grep sed awk rm mkdir cp echo true chmod ls; do \
        printf '#!/bin/sh\nexec %s "$@"' "$cmd" > /usr/local/bin/$cmd; \
        chmod +x /usr/local/bin/$cmd; \
    done

ADD https://ftp.gnu.org/gnu/make/make-4.4.tar.gz /src/make-4.4.tar.gz
WORKDIR /src
RUN tar -xf make-4.4.tar.gz
WORKDIR /src/make-4.4
RUN ./configure --disable-dependency-tracking LD=cc AR="tcc -ar"
RUN ./build.sh
RUN ./make MAKEINFO=true
RUN ./make MAKEINFO=true install

WORKDIR /src/musl
RUN rm -rf /usr/local/musl
RUN ./configure CC=tcc AR="tcc -ar" RANLIB=echo
RUN make -j$(nproc) CFLAGS=-g
RUN make install

ADD https://ftp.gnu.org/gnu/bash/bash-5.2.21.tar.gz /src/bash-5.2.21.tar.gz
WORKDIR /src
RUN tar -xf bash-5.2.21.tar.gz
WORKDIR /src/bash-5.2.21
RUN ./configure --without-bash-malloc LD=cc AR="tcc -ar"
RUN make -j$(nproc)
RUN make install
RUN ln -sv /usr/local/bin/bash /bin/bash

RUN for cmd in sort xargs readlink tr uname cmp dirname basename head wc cat egrep fold tee gzip od ln; do \
        printf '#!/bin/sh\nexec %s "$@"' "$cmd" > /usr/local/bin/$cmd; \
        chmod +x /usr/local/bin/$cmd; \
    done

WORKDIR /src/toybox
RUN make clean
RUN make -j$(nproc)
# RUN PREFIX=/usr/local/toybox/bin make install_flat
# RUN cp -f /usr/local/toybox/bin/toybox /usr/local/bin/toybox
RUN rm generated/obj/main.o

# WORKDIR /src/oksh
# RUN ./configure
# RUN make -j$(nproc)
# RUN make install

RUN for cmd in comm expr touch uniq mv; do \
        printf '#!/bin/sh\nexec %s "$@"' "$cmd" > /usr/local/bin/$cmd; \
        chmod +x /usr/local/bin/$cmd; \
    done

COPY ports/lang/perl5 /src/perl5
COPY ports/lang/perl5.patch /tmp/perl5.patch
WORKDIR /src/perl5
RUN patch -p1 < /tmp/perl5.patch
RUN ./Configure -des -Uusenm -Uusedl -DEBUGGING=both
RUN make -j$(nproc) AR="tcc -ar"
# RUN make test
RUN make install

ADD https://ftp.gnu.org/gnu/m4/m4-1.4.19.tar.gz /src/m4-1.4.19.tar.gz
WORKDIR /src
RUN tar -xf m4-1.4.19.tar.gz
WORKDIR /src/m4-1.4.19
RUN ./configure LD=cc AR="tcc -ar"
RUN make
RUN make install

ADD https://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.gz /src/autoconf-2.69.tar.gz
WORKDIR /src
RUN tar -xf autoconf-2.69.tar.gz
WORKDIR /src/autoconf-2.69
RUN ./configure
RUN make
RUN make install

ADD https://ftp.gnu.org/gnu/automake/automake-1.16.5.tar.gz /src/automake-1.16.5.tar.gz
WORKDIR /src
RUN tar -xf automake-1.16.5.tar.gz
WORKDIR /src/automake-1.16.5
RUN ./configure
RUN make
RUN make install

ADD https://ftp.gnu.org/gnu/libtool/libtool-2.4.7.tar.gz /src/libtool-2.4.7.tar.gz
WORKDIR /src
RUN tar -xf libtool-2.4.7.tar.gz
WORKDIR /src/libtool-2.4.7
RUN ./configure --disable-shared LD=cc AR="tcc -ar"
RUN make
RUN make install

RUN for cmd in env; do \
        printf '#!/bin/sh\nexec %s "$@"' "$cmd" > /usr/local/bin/$cmd; \
        chmod +x /usr/local/bin/$cmd; \
    done

RUN mkdir -p /usr/bin
RUN ln -sv /usr/local/bin/env /usr/bin/env

# WORKDIR /src/dash
# RUN ./autogen.sh
# RUN ./configure
# RUN sed -i '/HAVE_ALIAS_ATTRIBUTE/d' config.h
# RUN make -j$(nproc)
# RUN make install

ADD https://ftp.gnu.org/gnu/gawk/gawk-5.3.0.tar.gz /src/gawk-5.3.0.tar.gz
WORKDIR /src
RUN tar -xf gawk-5.3.0.tar.gz
WORKDIR /src/gawk-5.3.0
RUN ./configure --disable-shared LD=cc AR="tcc -ar"
RUN make
RUN make install

ADD https://ftp.gnu.org/gnu/binutils/binutils-2.39.tar.gz /src/binutils-2.39.tar.gz
WORKDIR /src
RUN tar -xf binutils-2.39.tar.gz
WORKDIR /src/binutils-2.39
RUN ./configure --disable-gprofng CFLAGS='-O2 -D__LITTLE_ENDIAN__=1' AR="tcc -ar"
RUN make MAKEINFO=true
RUN make MAKEINFO=true install

RUN ln -s /usr/lib/x86_64-linux-gnu /usr/lib64

RUN for cmd in bzcat; do \
        printf '#!/bin/sh\nexec %s "$@"' "$cmd" > /usr/local/bin/$cmd; \
        chmod +x /usr/local/bin/$cmd; \
    done

ADD https://ftp.gnu.org/gnu/gcc/gcc-4.6.4/gcc-4.6.4.tar.gz /src/gcc-4.6.4.tar.gz
ADD https://gcc.gnu.org/pub/gcc/infrastructure/mpfr-2.4.2.tar.bz2 /src/mpfr-2.4.2.tar.bz2
ADD https://gcc.gnu.org/pub/gcc/infrastructure/gmp-4.3.2.tar.bz2 /src/gmp-4.3.2.tar.bz2
ADD https://gcc.gnu.org/pub/gcc/infrastructure/mpc-0.8.1.tar.gz /src/mpc-0.8.1.tar.gz
WORKDIR /src
RUN tar -xf gcc-4.6.4.tar.gz
WORKDIR /src/gcc-4.6.4
RUN tar -xf ../mpfr-2.4.2.tar.bz2
RUN tar -xf ../gmp-4.3.2.tar.bz2
RUN tar -xf ../mpc-0.8.1.tar.gz
RUN ln -sf mpfr-2.4.2 mpfr
RUN ln -sf gmp-4.3.2 gmp
RUN ln -sf mpc-0.8.1 mpc
RUN ./configure CFLAGS=-O2 CFLAGS_FOR_TARGET=-O2 \
    --enable-languages=c \
    --disable-bootstrap \
    --disable-libquadmath --disable-decimal-float --disable-fixed-point \
    --disable-lto \
    --disable-libgomp \
    --disable-multilib \
    --disable-multiarch \
    --disable-libmudflap \
    --disable-libssp \
    --disable-nls \
    --host x86_64-linux --build x86_64-linux
# RUN ./configure --prefix=/usr/local/gcc-4.6.4 --enable-languages=c,c++ --disable-multilib
RUN make
RUN make install

COPY src/test.c /src/test.c
WORKDIR /src
RUN gcc -o test test.c -static
RUN ./test
