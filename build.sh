#!/bin/bash
FFMPEG_VERSION=ffmpeg-4.1
LAME_VERSION=3.100
PKGCONF_VERSION=pkgconf-1.1.0
OPUS_VERSION=opus-1.3

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

cd $ROOT_DIR

export TOOLCHAIN_DIR=${ROOT_DIR}/toolchain
export OUTPUT_DIR=${ROOT_DIR}/output

export PATH=${TOOLCHAIN_DIR}/bin:$PATH

source config.sh

FFMPEG_CONFIGURE_ARGS="--target-os=linux --arch=${TARGET_ARCH} --enable-cross-compile --cross-prefix=${TARGET_TRIPLE}- --prefix=${TOOLCHAIN_DIR} --enable-static --disable-shared --enable-small --pkg-config=pkgconf --disable-asm --disable-htmlpages --disable-manpages --disable-bsfs --disable-decoders --disable-demuxers --disable-encoders --disable-filters --disable-indevs --disable-muxers --disable-network --disable-outdevs --disable-parsers --disable-protocols --enable-filter=aresample --enable-filter=scale --enable-protocol=file --enable-swscale --disable-doc"



if [ ! -d output ]; then 
	echo "Making output dir."
	mkdir output
	mkdir output/licenses
fi

if [ ! -d sources ]; then 
	echo "Making sources dir."
	mkdir sources
fi

if [ ! -f sources/${TARGET_TRIPLE}-cross.tgz ]; then 
	echo "Downloading toolchain."
	wget "http://musl.cc/{TARGET_TRIPLE}-cross.tgz" -O "sources/${TARGET_TRIPLE}-cross.tgz"
fi

if [ ! -d toolchain ]; then 
	echo "Extracting toolchain."
	mkdir toolchain
	tar xf "sources/${TARGET_TRIPLE}-cross.tgz" -C toolchain/ --strip-components=2
fi

if [ ! -f sources/${PKGCONF_VERSION}.tar.xz ]; then
	echo "Downloading pkgconf source."
	wget "https://distfiles.dereferenced.org/pkgconf/${PKGCONF_VERSION}.tar.xz" -O "sources/${PKGCONF_VERSION}.tar.xz"
fi

if [ ! -d sources/${PKGCONF_VERSION} ]; then
	echo "Extracting pkgconf source."
	tar xf "sources/${PKGCONF_VERSION}.tar.xz" -C "sources/"
fi

if [ ! -f toolchain/bin/pkgconf ]; then
	echo "Building pkgconf."
	cd sources/${PKGCONF_VERSION}
	./configure --prefix=${TOOLCHAIN_DIR} --enable-static --disable-shared
	make install -j5
	ln -sf ${TOOLCHAIN_DIR}/bin/pkgconf ${TOOLCHAIN_DIR}/bin/${TARGET_TRIPLE}-pkgconf
	ln -sf ${TOOLCHAIN_DIR}/bin/pkgconf ${TOOLCHAIN_DIR}/bin/${TARGET_TRIPLE}-pkg-config
	ln -sf ${TOOLCHAIN_DIR}/bin/pkgconf ${TOOLCHAIN_DIR}/bin/pkg-config
	cd $ROOT_DIR
fi


if $CONF_PNG; then
	# PNG support depends on ZLIB
	if [ ! -d sources/zlib-ng ]; then
		echo "Downloading ZLib source."
		git clone "https://github.com/zlib-ng/zlib-ng" --depth=1 sources/zlib-ng
	fi
	if [ ! -f ${TOOLCHAIN_DIR}/lib/libz.a ]; then
		cd sources/zlib-ng
		CC=${TARGET_TRIPLE}-gcc ./configure --prefix=${TOOLCHAIN_DIR} --zlib-compat --static
		make -j5
		cp ${ROOT_DIR}/zlib.pc .
		make install -j5
		cp LICENSE.md ${OUTPUT_DIR}/licenses/zlib
		cd ${ROOT_DIR}
	fi
	FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-decoder=png --enable-encoder=png"
fi

# MP3 support from libmp3lame
if $CONF_MP3; then
	if [ ! -f sources/lame-${LAME_VERSION}.tar.gz ]; then
		echo "Downloading Lame source."
		wget "https://downloads.sourceforge.net/project/lame/lame/${LAME_VERSION}/lame-${LAME_VERSION}.tar.gz" -O sources/lame-${LAME_VERSION}.tar.gz
	fi
	if [ ! -d sources/lame-${LAME_VERSION} ]; then
		echo "Extracting Lame source."
		tar xf "sources/lame-${LAME_VERSION}.tar.gz" -C "sources/"
	fi
	
	if [ ! -f ${TOOLCHAIN_DIR}/lib/libmp3lame.a ]; then
		cd sources/lame-${LAME_VERSION}
		./configure --host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --disable-shared --enable-static --disable-frontend --disable-decoder
		make install -j5
		cp LICENSE ${OUTPUT_DIR}/licenses/libmp3lame
		cd ${ROOT_DIR}
	fi
	FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-decoder=mp3 --enable-demuxer=mp3 --enable-muxer=mp3 --enable-encoder=libmp3lame --enable-libmp3lame"
fi

# Opus support from libopus
if $CONF_OPUS; then
	if [ ! -f sources/${OPUS_VERSION}.tar.gz ]; then
		echo "Downloading Opus source."
		wget "https://archive.mozilla.org/pub/opus/${OPUS_VERSION}.tar.gz" -O sources/${OPUS_VERSION}.tar.gz
	fi
	if [ ! -d sources/${OPUS_VERSION} ]; then
		echo "Extracting Opus source."
		tar xf "sources/${OPUS_VERSION}.tar.gz" -C "sources/"
	fi
	
	if [ ! -f ${TOOLCHAIN_DIR}/lib/libopus.a ]; then
		cd sources/${OPUS_VERSION}
		./configure --host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --disable-shared --enable-static --disable-frontend --disable-decoder
		make install -j5
		cp COPYING ${OUTPUT_DIR}/licenses/libmp3lame
		cd ${ROOT_DIR}
	fi
	FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-decoder=opus --enable-encoder=libopus --enable-libopus --enable-muxer=opus"
fi

# MJPEG support
if $CONF_MJPEG; then
	FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-decoder=mjpeg"
fi

# FLAC support
if $CONF_FLAC; then
	FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-decoder=flac --enable-encoder=flac --enable-demuxer=flac"
fi

# AAC support
if $CONF_AAC; then
	FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-decoder=aac --enable-encoder=aac --enable-demuxer=aac"
fi


# Finally, FFMPEG
if [ ! -f sources/${FFMPEG_VERSION}.tar.bz2 ]; then
	echo "Downloading FFMPEG source."
	wget "http://ffmpeg.org/releases/${FFMPEG_VERSION}.tar.bz2" -O sources/${FFMPEG_VERSION}.tar.bz2
fi
if [ ! -d sources/${FFMPEG_VERSION} ]; then
	echo "Extracting FFMPEG source."
	tar xf "sources/${FFMPEG_VERSION}.tar.bz2" -C "sources/"
fi

if [ ! -f ${OUTPUT_DIR}/ffmpeg ]; then
	cd sources/${FFMPEG_VERSION}
	./configure ${FFMPEG_CONFIGURE_ARGS[@]} --extra-cflags="-I${TOOLCHAIN_DIR}/include ${CFLAGS}" --extra-ldflags="-static -L${TOOLCHAIN_DIR}/lib ${LDFLAGS}"
	make -j5
	cp LICENSE.md ${OUTPUT_DIR}/licenses/ffmpeg
	cp ffmpeg ${OUTPUT_DIR}/ffmpeg
	cp ${ROOT_DIR}/README.out ${OUTPUT_DIR}/README
	cd ${ROOT_DIR}
fi


