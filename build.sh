#!/bin/bash
set -e
set -x
set -o pipefail

# For coloured text.
source bash_colors.sh
#set -x

HOST_ARCH=`uname -p`
NON_FREE=false
LICENSE=LGPL

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

cd $ROOT_DIR

export OLDPATH=$PATH


export HOST_CC=/usr/bin/gcc
export HOST_LD=/usr/bin/gcc
export HOST_CXX=/usr/bin/g++
export HOST_AR=/usr/bin/ar
export HOST_NM=/usr/bin/nm
export HOST_RANLIB=/usr/bin/ranlib

export STATE_DIR=${ROOT_DIR}/state
export SOURCES_DIR=${ROOT_DIR}/sources
export OUTPUT_DIR=${ROOT_DIR}/output
export LOGS_DIR=${ROOT_DIR}/logs
export SYSROOT=${ROOT_DIR}/toolchain

export OLDPATH=$PATH
export PATH=${SYSROOT}/bin:$PATH

source config.sh
source functions.sh

export LDFLAGS="$LDFLAGS -L${SYSROOT}/lib"
export CFLAGS="$CFLAGS -I${SYSROOT}/include"
export CPPFLAGS="$CFLAGS"
export CXXFLAGS="$CXXFLAGS"
export CC="/usr/bin/ccache ${SYSROOT}/bin/${TARGET_TRIPLE}-gcc"
export CXX="/usr/bin/ccache ${SYSROOT}/bin/${TARGET_TRIPLE}-g++"
export LD="${SYSROOT}/bin/${TARGET_TRIPLE}-gcc"
export NM="${SYSROOT}/bin/${TARGET_TRIPLE}-gcc-nm"
export RANLIB="${SYSROOT}/bin/${TARGET_TRIPLE}-gcc-ranlib"
export AR="${SYSROOT}/bin/${TARGET_TRIPLE}-gcc-ar"
export ARCH=`echo ${TARGET_TRIPLE} | sed s/.*-//`
export CROSS_COMPILE=${TARGET_TRIPLE}-

FFMPEG_CONFIGURE_ARGS="--target-os=linux --arch=${TARGET_ARCH} --enable-cross-compile --cross-prefix=${TARGET_TRIPLE}- --prefix=${SYSROOT} --libdir=${SYSROOT}/lib --enable-static --disable-shared --pkg-config=pkg-config --disable-htmlpages --disable-manpages --disable-doc --enable-optimizations --disable-debug"
export COMMON_CONFIGURE="--host=${TARGET_TRIPLE} --prefix=${SYSROOT} --disable-shared --enable-static --sysconfdir=/etc --localstatedir=/var"
export FUSSY_CONFIGURE="--host=${TARGET_TRIPLE} --prefix=${SYSROOT} --disable-shared --enable-static"


# Enable the FFMpeg program
if $CONF_FFMPEG; then
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-ffmpeg"
fi

# Enable the FFProbe program
if $CONF_FFPROBE; then
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-ffprobe"
fi

clr_blue "Making dirs"
mkdir -p logs output output/licenses sources logs state

CURRENT_ARCH=$(gcc -dumpmachine | sed s/-*//)

TOOLCHAIN_TYPE=cross

set -x
if [ $CURRENT_ARCH != "x86_64" ]; then
    if [ $TARGET_ARCH != $CURRENT_ARCH ]; then 
        TOOLCHAIN_TYPE=native
    else
        echo "no"
        exit
    fi
fi
set +x


if [ ! -f sources/${TARGET_TRIPLE}-${TOOLCHAIN_TYPE}.tgz ]; then
    clr_brown "Downloading toolchain"
    pushd sources
    downloadURL "http://musl.cc/${TARGET_TRIPLE}-${TOOLCHAIN_TYPE}.tgz"
    popd
fi

if [ ! -d toolchain ]; then
    clr_brown "Extracting toolchain"
    mkdir toolchain
    tar xf "sources/${TARGET_TRIPLE}-${TOOLCHAIN_TYPE}.tgz" -C toolchain/ --strip-components=2  &>/dev/null
fi

ln -sf ${SYSROOT}/bin/${TARGET_TRIPLE}-gcc-ar ${SYSROOT}/bin/${TARGET_TRIPLE}-ar
ln -sf ${SYSROOT}/bin/${TARGET_TRIPLE}-gcc-nm ${SYSROOT}/bin/${TARGET_TRIPLE}-nm
ln -sf ${SYSROOT}/bin/${TARGET_TRIPLE}-gcc-ranlib ${SYSROOT}/bin/${TARGET_TRIPLE}-ranlib
ln -sf ${SYSROOT}/bin/strip ${SYSROOT}/bin/${TARGET_TRIPLE}-strip
mkdir -p ${STATE_DIR}/installed
mkdir -p ${STATE_DIR}/configured

if [ $TOOLCHAIN_TYPE = "native" ]; then
if [ ! -f ${SYSROOT}/bin/${TARGET_TRIPLE}-strings ]; then
ln -sf /usr/bin/strings ${SYSROOT}/bin/${TARGET_TRIPLE}-strings
fi
fi

function markInstalled() {
    thing=$1
    touch ${STATE_DIR}/installed/$thing
}

function isInstalled() {
    thing=$1
    [ -f "${STATE_DIR}/installed/${thing}" ]
}


function markConfigured() {
    thing=$1
    touch ${STATE_DIR}/configured/$thing
}

function unmarkConfigured() {
    thing=$1
    rm -f ${STATE_DIR}/configured/$thing
}

function isConfigured() {
    thing=$1
    [ -f "${STATE_DIR}/configured/${thing}" ]
}


CC="$HOST_CC" CXX="$HOST_CXX" LD="$HOST_LD" AR=$HOST_AR RANLIB=$HOST_RANLIB PATH=$OLDPATH LDFLAGS="" CFLAGS="" CXXFLAGS="" CPPFLAGS="" buildThing pkgconf "--prefix=${SYSROOT} --enable-static --disable-shared"
if [ ! -f toolchain/bin/${TARGET_TRIPLE}-pkgconf ]; then
    ln -sf ${SYSROOT}/bin/pkgconf ${SYSROOT}/bin/${TARGET_TRIPLE}-pkgconf
    ln -sf ${SYSROOT}/bin/pkgconf ${SYSROOT}/bin/${TARGET_TRIPLE}-pkg-config
    ln -sf ${SYSROOT}/bin/pkgconf ${SYSROOT}/bin/pkg-config
fi

# These codecs require the GPL setting
if $CONF_X264 || $CONF_FDK_AAC; then
    clr_bold clr_red "Using the GPL license"
    LICENSE=GPL
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-gpl"
fi

# These codecs make the binarys non-redistributable.
if $CONF_FDK_AAC; then
    clr_bold clr_red "The resulting binaries from this build are now non-redistributable. You may not share the compiled binaries produced by this build as it is prohibited by the GPL license!"
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-nonfree --enable-libfdk-aac"
    NON_FREE=true
fi

if $CONF_MP3; then
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-decoder=mp3 --enable-demuxer=mp3 --enable-muxer=mp3 --enable-encoder=libmp3lame --enable-libmp3lame"
fi

if $CONF_ZLIB || $CONF_PNG; then
    buildThing zlib "--prefix=${SYSROOT} --zlib-compat --static"
    FREETYPE_CONFIG="$FREETYPE_CONFIG --with-zlib=yes"
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-zlib"
fi

if $CONF_PNG; then
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-encoder=png --enable-decoder=png"
fi

# MP3 support from libmp3lame
if $CONF_MP3; then
    buildThing lame "${COMMON_CONFIGURE} --disable-shared --enable-static --disable-frontend --disable-decoder --enable-nasm"
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-decoder=mp3 --enable-demuxer=mp3 --enable-muxer=mp3 --enable-encoder=libmp3lame --enable-libmp3lame"
fi

# Opus support from libopus
if $CONF_OPUS; then
    buildThing opus "${COMMON_CONFIGURE} --disable-shared --enable-static --disable-frontend --disable-decoder --disable-extra-programs"
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-decoder=opus --enable-encoder=libopus --enable-libopus --enable-muxer=opus"
fi

# x264 support from libx264
if $CONF_X264; then
    buildThing x264 "${COMMON_CONFIGURE} --enable-static --cross-prefix=${TARGET_TRIPLE}- --disable-opencl"
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-libx264 --enable-decoder=h264 --enable-encoder=libx264 --enable-parser=h264"
fi

# VPX support from libvpx
if $CONF_VPX; then
    buildThing vpx "--target=${TARGET_ARCH}-linux-gcc --prefix=${SYSROOT} --enable-vp8 --enable-vp9 --enable-static --disable-unit-tests --disable-tools --as=yasm --enable-runtime-cpu-detect"
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-libvpx --enable-decoder=libvpx_vp8,libvpx_vp9 --enable-encoder=vp9,libvpx_vp9 --enable-encoder=vp8,libvpx_vp8 --enable-parser=vp8 --enable-parser=vp9"
fi

# OGG support from libogg, also needed for libvorbis
if $CONF_OGG; then
    buildThing libogg "${COMMON_CONFIGURE} --disable-shared --enable-static"
fi

# Vorbis support from libvorbis
if $CONF_VORBIS; then
    buildThing libvorbis "${COMMON_CONFIGURE} --disable-shared --enable-static"
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-libvorbis --enable-encoder=libvorbis --enable-decoder=libvorbis"
fi

# AAC encoding support from libfdk-aac
if $CONF_FDK_AAC; then
    buildThing fdk_aac " ${COMMON_CONFIGURE} --disable-shared --enable-static"
fi

# libsndfile for mpv
if $CONF_LIBSNDFILE; then
    buildThing libsndfile "${COMMON_CONFIGURE} --disable-shared --enable-static --disable-tests"
fi

# alsa-lib for mpv
if $CONF_ALSA_LIB; then
    buildThing alsalib "${COMMON_CONFIGURE} --disable-shared --enable-static --with-libdl=no"
fi

if $CONF_LIBJPEG; then
    buildThing libjpeg "${COMMON_CONFIGURE} --disable-shared --enable-static"
fi

if $CONF_LIBPNG; then
    FREETYPE_CONFIG="$FREETYPE_CONFIG --with-png=yes"
    buildThing libpng "${COMMON_CONFIGURE} --disable-shared --enable-static --with-sysroot=${SYSROOT} --with-zlib-prefix=${SYSROOT}"
fi

if $CONF_LIBCACA; then
    CPPFLAGS="$CPPFLAGS -P" buildThing ncurses "--host=${TARGET_TRIPLE}  --prefix=${SYSROOT} --enable-shared=no --enable-static=yes --disable-shared --enable-static --with-pc-files"
    buildThing libcaca "--host=${TARGET_TRIPLE}  --prefix=${SYSROOT} --disable-kernel --disable-slang --disable-win32 --disable-conio --disable-x11 --disable-gl --disable-cocoa --disable-network --disable-vga --disable-csharp --disable-java --disable-cxx --disable-python --disable-ruby --disable-imlib2 --disable-profiling --disable-plugins --disable-doc"
    sed "s/-lcaca/-lcaca -lncurses/" -i toolchain/lib/pkgconfig/caca.pc
fi

if $CONF_SSL; then
    buildThing libressl "--host=${TARGET_TRIPLE}  --prefix=${SYSROOT} --enable-shared=no --enable-static=yes"
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-openssl"
fi


buildThing ffmpeg


if $CONF_LUA; then
    buildThing lua
    
cat <<boop > ${SYSROOT}/lib/pkgconfig/lua.pc
prefix=${SYSROOT}
exec_prefix=${SYSROOT}
libdir=${SYSROOT}/lib
includedir=${SYSROOT}/include

Name: Lua
Description: An Extensible Extension Language
Version: `versionOf lua`
Requires:
Libs: -L${libdir} -llua -lm
Cflags: -I${includedir}
boop
    
    MPV_CONFIGURE_ARGS="$MPV_CONFIGURE_ARGS --lua=52"
fi

if $CONF_LIBASS; then
    buildThing libass "${COMMON_CONFIGURE}  --enable-shared=no --disable-shared  --enable-static"
else
    MPV_CONFIGURE_ARGS="$MPV_CONFIGURE_ARGS --disable-libass"
fi

if $CONF_MPV; then
    MPV_LDFLAGS="$LDFLAGS $MPV_LDFLAGS" PKG_CONFIG="pkg-config --static" buildThing mpv "--enable-static-build --disable-cplugins --target=${TARGET_TRIPLE}  ${MPV_CONFIGURE_ARGS[@]}"
fi



# FFMpegThumbnailer
if $CONF_FFMPEGTHUMBNAILER; then
    buildThing ffmpegthumbnailer
fi

# Copy readme with license name and information to the output folder.
cp ${ROOT_DIR}/README.out ${OUTPUT_DIR}/README
sed -i "s/LICENSE_NAME/${LICENSE}/" ${OUTPUT_DIR}/README

if $NON_FREE; then
    sed -i "s/^IF_NONFREE //" ${OUTPUT_DIR}/README
else
    sed -i "s/^IF_NONFREE.*//" ${OUTPUT_DIR}/README
fi

