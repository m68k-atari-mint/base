# docker buildx build --progress plain .

ARG TARGET=m68k-atari-mintelf
ARG INSTALL_DIR=/usr
ARG BUILD_DIR=/build
ARG JOBS=8

# always latest LTS
FROM ubuntu:latest AS build
RUN apt -y update && apt -y upgrade
RUN apt -y install binutils bison bzip2 file flex gawk gcc g++ m4 make patch texinfo wget
RUN ln -s bash /bin/sh.bash && mv /bin/sh.bash /bin/sh
WORKDIR /src
COPY gcc-atari.patch .

# renew the arguments
ARG TARGET
ARG INSTALL_DIR
ARG BUILD_DIR
ARG JOBS

# used at a few places
ENV VERSION_BINUTILS	2.41
ENV VERSION_GCC		    13.2.0

# binutils download
ENV REPOSITORY_BINUTILS	m68k-atari-mint-binutils-gdb
ENV BRANCH_BINUTILS		binutils-2_41-mintelf
ENV GITHUB_URL_BINUTILS	https://github.com/freemint/${REPOSITORY_BINUTILS}/archive/refs/heads/${BRANCH_BINUTILS}.tar.gz
ENV FOLDER_BINUTILS		${REPOSITORY_BINUTILS}-${BRANCH_BINUTILS}
RUN wget -q -O - ${GITHUB_URL_BINUTILS} | tar xzf -

# gcc download
ENV REPOSITORY_GCC		m68k-atari-mint-gcc
ENV BRANCH_GCC		    gcc-13-mintelf
ENV GITHUB_URL_GCC		https://github.com/freemint/${REPOSITORY_GCC}/archive/refs/heads/${BRANCH_GCC}.tar.gz
ENV FOLDER_GCC		    ${REPOSITORY_GCC}-${BRANCH_GCC}
RUN wget -q -O - ${GITHUB_URL_GCC} | tar xzf -
RUN cd ${FOLDER_GCC} \
    && ./contrib/download_prerequisites \
    && patch -p1 < ../gcc-atari.patch

# binutils build
RUN mkdir build-binutils \
    && cd build-binutils \
    && ../${FOLDER_BINUTILS}/configure \
        --target=${TARGET} \
        --prefix=${INSTALL_DIR} \
        --disable-nls \
        --disable-werror \
        --enable-gprofng=no \
        --disable-gdb --disable-libdecnumber --disable-readline --disable-sim \
    && make -j${JOBS}

# binutils install into ${BUILD_DIR}-tmp for gcc preliminary build as they need to be together
RUN cd build-binutils \
    && make install-strip DESTDIR=${BUILD_DIR}-tmp

# gcc preliminary build
RUN mkdir build-gcc-preliminary \
    && cd build-gcc-preliminary \
    && ../${FOLDER_GCC}/configure \
        # prefix must be pointing to where binutils are installed (also, PATH is not required to be set then...)
        --prefix=${BUILD_DIR}-tmp${INSTALL_DIR} \
        --target=${TARGET} \
        # sys-root must be set where the libraries will go otherwise projects requiring mintlib (e.g. fdlibm) will fail
        --with-sysroot=${BUILD_DIR}${INSTALL_DIR}/${TARGET}/sys-root \
        --disable-nls \
        --disable-shared \
        --without-headers \
        --with-newlib \
        --disable-decimal-float \
        --disable-libgomp \
        --disable-libmudflap \
        --disable-libssp \
        --disable-libatomic \
        --disable-libquadmath \
        --disable-threads \
        --enable-languages=c \
        --disable-multilib \
        --disable-lto \
    && make -j${JOBS} all-gcc all-target-libgcc \
    && make install-gcc install-target-libgcc

# mintlib download
ENV REPOSITORY_MINTLIB	mintlib
ENV BRANCH_MINTLIB		master
ENV GITHUB_URL_MINTLIB	https://github.com/freemint/${REPOSITORY_MINTLIB}/archive/refs/heads/${BRANCH_MINTLIB}.tar.gz
ENV FOLDER_MINTLIB		${REPOSITORY_MINTLIB}-${BRANCH_MINTLIB}
RUN wget -q -O - ${GITHUB_URL_MINTLIB} | tar xzf -

# fdlibm download
ENV REPOSITORY_FDLIBM	fdlibm
ENV BRANCH_FDLIBM		master
ENV GITHUB_URL_FDLIBM	https://github.com/freemint/${REPOSITORY_FDLIBM}/archive/refs/heads/${BRANCH_FDLIBM}.tar.gz
ENV FOLDER_FDLIBM		${REPOSITORY_FDLIBM}-${BRANCH_FDLIBM}
RUN wget -q -O - ${GITHUB_URL_FDLIBM} | tar xzf -

# mintbin download
ENV REPOSITORY_MINTBIN	mintbin
ENV BRANCH_MINTBIN		master
ENV GITHUB_URL_MINTBIN	https://github.com/freemint/${REPOSITORY_MINTBIN}/archive/refs/heads/${BRANCH_MINTBIN}.tar.gz
ENV FOLDER_MINTBIN		${REPOSITORY_MINTBIN}-${BRANCH_MINTBIN}
RUN wget -q -O - ${GITHUB_URL_MINTBIN} | tar xzf -

# this is where preliminary binutils+gcc are installed
ENV TMP_PATH "${BUILD_DIR}-tmp${INSTALL_DIR}/bin"

# mintlib build & install into ${BUILD_DIR}
RUN cd ${FOLDER_MINTLIB} \
    && PATH="${TMP_PATH}:$PATH" make toolprefix=${TARGET}- CROSS=yes WITH_DEBUG_LIB=no \
    && make WITH_DEBUG_LIB=no prefix="${BUILD_DIR}${INSTALL_DIR}/${TARGET}/sys-root/usr" install

# fdlibm build & install into ${BUILD_DIR}
RUN cd ${FOLDER_FDLIBM} \
    && PATH="${TMP_PATH}:$PATH" ./configure --host=${TARGET} --prefix="${INSTALL_DIR}/${TARGET}/sys-root/usr" \
    && PATH="${TMP_PATH}:$PATH" make \
    && make install DESTDIR=${BUILD_DIR}

# binutils install into ${INSTALL_DIR} for gcc build as they need to be together
RUN cd build-binutils \
    && make install-strip

# gcc build
RUN mkdir build-gcc \
    && cd build-gcc \
    && ../${FOLDER_GCC}/configure \
        # we want to keep ${INSTALL_DIR} as prefix therefore binutils must be installed to the same location
        --prefix=${INSTALL_DIR} \
        --target=${TARGET} \
        --with-sysroot=${INSTALL_DIR}/${TARGET}/sys-root \
        --with-build-sysroot=${BUILD_DIR}${INSTALL_DIR}/${TARGET}/sys-root \
        --disable-nls \
        --disable-shared \
        --without-newlib \
        --disable-decimal-float \
        --disable-libgomp \
        --enable-languages="c,c++,lto" \
        --disable-libstdcxx-pch \
        --with-libstdcxx-zoneinfo=no \
        --disable-sjlj-exceptions \
        --disable-libcc1 \
    && make -j${JOBS} \
    && make install-strip

###############################################################
# at this point, we have a full gcc in ${INSTALL_DIR} available
###############################################################

# mintbin build & install into ${BUILD_DIR}
RUN cd ${FOLDER_MINTBIN} \
    && ./configure --target=${TARGET} --prefix=${INSTALL_DIR} --disable-nls \
    && make \
    && make install DESTDIR=${BUILD_DIR}

# binutils install into ${BUILD_DIR}
RUN cd build-binutils \
   && make install-strip DESTDIR=${BUILD_DIR}

# gcc install into ${BUILD_DIR}
RUN cd build-gcc \
    && make install-strip DESTDIR=${BUILD_DIR}

RUN cd "${BUILD_DIR}${INSTALL_DIR}/lib/gcc/${TARGET}/${VERSION_GCC}/include-fixed" && \
    for f in $(find . -type f); \
    do \
        case "$f" in \
            ./README | ./limits.h | ./syslimits.h) ;; \
            *) echo "Removing fixed include file $f"; rm "$f" ;; \
        esac \
    done && \
    for d in $(find . -depth -type d); \
    do \
        test "$d" = "." || rmdir "$d"; \
    done

# final build
FROM ubuntu:latest
RUN apt -y update && apt -y upgrade

# renew the arguments
ARG TARGET
ARG INSTALL_DIR
ARG BUILD_DIR
ARG JOBS

COPY --from=build ${BUILD_DIR}/* ${INSTALL_DIR}

ENV TOOL_PREFIX ${TARGET}
