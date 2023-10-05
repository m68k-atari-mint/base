#!/bin/bash -ex
# -e: Exit immediately if a command exits with a non-zero status.
# -x: Display expanded script commands

export CFLAGS="$CFLAGS -O2 -fomit-frame-pointer"
export CXXFLAGS="$CXXFLAGS -O2 -fomit-frame-pointer"
export PREFIX="$($TOOL_PREFIX-gcc -print-sysroot)/usr"

export CONFIGURE_FLAGS="$CONFIGURE_FLAGS --disable-ipv6 --disable-shared --enable-static --host=$(TOOL_PREFIX) --prefix=$PREFIX"

./configure $CONFIGURE_FLAGS && make && make install && \
(make distclean || make clean) && \
\
CFLAGS="$CFLAGS -m68020-60" CXXFLAGS="$CXXFLAGS -m68020-60" ./configure $CONFIGURE_FLAGS --bindir=$PREFIX/bin/m68020-60 --sbindir=$PREFIX/sbin/m68020-60 --libdir=$PREFIX/lib/m68020-60 && make && make install && \
(make distclean || make clean) && \
\
CFLAGS="$CFLAGS -mcpu=5475" CXXFLAGS="$CXXFLAGS -mcpu=5475" ./configure $CONFIGURE_FLAGS --bindir=$PREFIX/bin/m5475 --sbindir=$PREFIX/sbin/m5475 --libdir=$PREFIX/lib/m5475 && make && make install && \
(make distclean || make clean)
