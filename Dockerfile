FROM ubuntu:22.04 AS build
RUN apt-get update && apt-get install -y build-essential

COPY tinycc /src/tcc
WORKDIR /src/tcc
RUN ./configure
RUN make -j$(nproc)
RUN make install

COPY musl /src/musl
WORKDIR /src/musl
RUN ./configure --target=x86_64 CC='tcc' AR='tcc -ar' RANLIB='echo' LIBCC='/usr/local/lib/tcc/libtcc1.a' \
    --enable-wrapper=all
RUN make -j$(nproc) CFLAGS=-g
RUN make install
RUN make DESTDIR=/dest install

COPY libc.ld /

WORKDIR /src/tcc
RUN make clean
RUN ./configure \
    --extra-cflags="-nostdinc -nostdlib -I/usr/local/musl/include -DCONFIG_TCC_STATIC" \
    --extra-ldflags="-nostdlib /usr/local/musl/lib/crt1.o /libc.ld -static" \
    --config-ldl=no --config-debug=yes
RUN make -j$(nproc)
RUN make DESTDIR=/dest install

FROM scratch
COPY --from=build /dest/usr /usr
COPY libc.ld /usr/lib/libc.so
COPY hello.c /usr/bin/hello
CMD ["/usr/bin/hello"]
