ZX#!/bin/bash

set -x
set -e

FFMPEG_VERSION=ffmpeg-4.1
LAME_VERSION=3.100
PKGCONF_VERSION=pkgconf-1.1.0
OPUS_VERSION=opus-1.3
X264_VERSION=latest
OGG_VERSION=1.3.2
VORBIS_VERSION=1.3.5

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

cd $ROOT_DIR

export TOOLCHAIN_DIR=${ROOT_DIR}/toolchain
export OUTPUT_DIR=${ROOT_DIR}/output

export PATH=${TOOLCHAIN_DIR}/bin:$PATH

source config.sh

export LDFLAGS="$LDFLAGS -L${TOOLCHAIN_DIR}/lib"
export CFLAGS="$CFLAGS -I${TOOLCHAIN_DIR}/include"
export CPPFLAGS="$CFLAGS"

strip_stuff() {
strip -S --strip-unneeded --remove-section=.note.gnu.gold-version --remove-section=.comment --remove-section=.note --remove-section=.note.gnu.build-id --remove-section=.note.ABI-tag -s -g --strip-all -x -X $1
}

FFMPEG_CONFIGURE_ARGS="--target-os=linux --arch=${TARGET_ARCH} --enable-cross-compile --cross-prefix=${TARGET_TRIPLE}- --prefix=${TOOLCHAIN_DIR} --enable-static --disable-shared --enable-small --pkg-config=pkgconf --disable-asm --disable-htmlpages --disable-manpages  --disable-doc --enable-bsfs --disable-all --enable-avcodec --enable-avformat --enable-avfilter --enable-swresample --enable-protocol=file" 

# Enable the FFMpeg program
if $CONF_FFMPEG; then
FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-ffmpeg"
fi

# Enable the FFProbe program
if $CONF_FFPROBE; then
FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-ffprobe"
fi


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

# Enable some video utils for ffmpeg when any video/image codec is enabled.
if $CONF_PNG || $CONF_MJPEG || $CONF_X264 || $CONF_VPX; then
FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-muxer=rawvideo --enable-demuxer=rawvideo --enable-filter=scale --enable-swscale"
fi

# Enable some audio utils for ffmpeg when any audio codec is enabled.
if $CONF_OPUS || $CONF_AAC || $CONF_FLAC || $CONF_MP3 || $CONF_OGG || $CONF_VORBIS; then
FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-swresample --enable-filter=aresample"
fi


# These codecs require the GPL setting
if $CONF_X264; then
FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-gpl"
fi


if $CONF_ZLIB; then
	if [ ! -d sources/zlib-ng ]; then
		echo "Downloading ZLib source."
		git clone "https://github.com/zlib-ng/zlib-ng" --depth=1 sources/zlib-ng
	fi
	if [ ! -f ${TOOLCHAIN_DIR}/lib/libz.a ]; then
		cd sources/zlib-ng
		CC=${TARGET_TRIPLE}-gcc ./configure --prefix=${TOOLCHAIN_DIR} --zlib-compat --static
		make -j5
		cp ${ROOT_DIR}/files/zlib.pc .
		make install -j5
		cp LICENSE.md ${OUTPUT_DIR}/licenses/zlib
		cd ${ROOT_DIR}
	fi
	FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-zlib"
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

# x264 support from libx264
if $CONF_X264; then
	if [ ! -d sources/x264 ]; then
		echo "Extracting x264 source."
		git clone --depth=1 https://git.videolan.org/git/x264.git sources/x264
		
	fi
	
	if [ ! -f ${TOOLCHAIN_DIR}/lib/libx264.a ]; then
		cd sources/x264
		./configure --host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --enable-static --disable-asm --cross-prefix=${TARGET_TRIPLE}-  --disable-opencl
		make install -j5
		cp COPYING ${OUTPUT_DIR}/licenses/libx264
		cd ${ROOT_DIR}
	fi
	FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-libx264 --enable-decoder=h264 --enable-encoder=libx264 --enable-parser=h264"
fi

# VPX support from libvpx
if $CONF_VPX; then
	if [ ! -d sources/libvpx ]; then
		echo "Extracting x264 source."
		git clone --depth=1 https://chromium.googlesource.com/webm/libvpx -b v1.8.0 sources/libvpx
		
	fi

	if [ ! -f ${TOOLCHAIN_DIR}/lib/libvpx.a ]; then
		cd sources/libvpx
		CC=${TARGET_TRIPLE}-gcc CXX=${TARGET_TRIPLE}-g++ LD=${TARGET_TRIPLE}-gcc ./configure --target=${TARGET_ARCH}-linux-gcc --prefix=${TOOLCHAIN_DIR} --enable-vp8 --enable-vp9 --enable-static --disable-mmx --disable-sse --disable-sse2 --disable-sse3 --disable-ssse3 --disable-sse4_1 --disable-runtime_cpu_detect
		make install -j5 V=1
		cp LICENSE ${OUTPUT_DIR}/licenses/libvpx
		cd ${ROOT_DIR}
	fi
	FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-libvpx --enable-decoder=libvpx_vp8,libvpx_vp9 --enable-encoder=vp9,libvpx_vp9 --enable-encoder=vp8,libvpx_vp8 --enable-parser=vp8 --enable-parser=vp9"
fi

# OGG support from libogg, needed for libvorbis
if $CONF_OGG; then
	if [ ! -f sources/libogg-${OGG_VERSION}.tar.gz ]; then
		echo "Downloading OGG source."
		wget "http://downloads.xiph.org/releases/ogg/libogg-${OGG_VERSION}.tar.gz" -O sources/libogg-${OGG_VERSION}.tar.gz
	fi
	if [ ! -d sources/libogg-${OGG_VERSION} ]; then
		echo "Extracting OGG source."
		tar xf "sources/libogg-${OGG_VERSION}.tar.gz" -C "sources/"
	fi
	

	if [ ! -f ${TOOLCHAIN_DIR}/lib/libogg.a ]; then
		cd sources/libogg-${OGG_VERSION}
		./configure --host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --disable-shared --enable-static
		make install -j5 V=1
		cp COPYING ${OUTPUT_DIR}/licenses/libogg
		cd ${ROOT_DIR}
	fi
fi

# Vorbis support from libvorbis
if $CONF_VORBIS; then
	if [ ! -f sources/libvorbis-${VORBIS_VERSION}.tar.gz ]; then
		echo "Downloading libvorbis source."
		wget "http://downloads.xiph.org/releases/vorbis/libvorbis-${VORBIS_VERSION}.tar.gz" -O sources/libvorbis-${VORBIS_VERSION}.tar.gz
	fi
	if [ ! -d sources/libogg-${VORBIS_VERSION} ]; then
		echo "Extracting libvorbis source."
		tar xf "sources/libvorbis-${VORBIS_VERSION}.tar.gz" -C "sources/"
	fi
	

	if [ ! -f ${TOOLCHAIN_DIR}/lib/libvorbis.a ]; then
		cd sources/libvorbis-${VORBIS_VERSION}
		./configure --host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --disable-shared --enable-static
		make install -j5 V=1
		cp COPYING ${OUTPUT_DIR}/licenses/libvorbis
		cd ${ROOT_DIR}
	fi
	FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-libvorbis --enable-encoder=libvorbis --enable-decoder=libvorbis"
fi

# PNG support
if $CONF_PNG && $CONF_ZLIB; then
	FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-encoder=png --enable-decoder=png"
fi

# MJPEG support
if $CONF_MJPEG; then
	FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-decoder=mjpeg"
fi

# FLAC support
if $CONF_FLAC; then
	FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-decoder=flac --enable-encoder=flac --enable-muxer=flac --enable-demuxer=flac"
fi

# AAC support
if $CONF_AAC; then
	FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-decoder=aac --enable-encoder=aac --enable-demuxer=aac"
fi

# MKV support
if $CONF_MKV; then
	FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-muxer=matroska --enable-demuxer=matroska"
fi

# WebM support
if $CONF_WEBM; then
	FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-muxer=webm"
fi

# MOV support
if $CONF_MOV; then
	FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-muxer=mov  --enable-demuxer=mov"
fi

# MP4 support
if $CONF_MP4; then
	FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-muxer=mp4"
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

if [ ! -f ${TOOLCHAIN_DIR}/lib/libavutil.a ] || [ ! -z "${REBUILD_FFMPEG}" ]; then
	cd sources/${FFMPEG_VERSION}
	./configure  ${FFMPEG_CONFIGURE_ARGS[@]} --extra-cflags="-I${TOOLCHAIN_DIR}/include ${CFLAGS}" --extra-ldflags="-static -L${TOOLCHAIN_DIR}/lib ${LDFLAGS}" --pkg-config-flags="--static"
	make -j8 V=1
	make install
	cp LICENSE.md ${OUTPUT_DIR}/licenses/ffmpeg
	if $CONF_FFMPEG; then cp ffmpeg ${OUTPUT_DIR}/ffmpeg; fi
	if $CONF_FFPROBE; then cp ffprobe ${OUTPUT_DIR}/ffprobe; fi
	cp ${ROOT_DIR}/README.out ${OUTPUT_DIR}/README
	cd ${ROOT_DIR}
fi

# libJPEG is only used for FFMpegThumbnailer so only build when it is enabled to save time.
if $CONF_LIBJPEG && $CONF_FFMPEGTHUMBNAILER; then
	if [ ! -d sources/libjpeg ]; then
		echo "Cloning libjpeg repo."
		git clone "https://github.com/LuaDist/libjpeg" "sources/libjpeg" --depth=1
	fi

	if [ ! -f ${TOOLCHAIN_DIR}/lib/libjpeg.a ]; then
		cd sources/libjpeg
		./configure --host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --disable-shared --enable-static
		make -j8 VERBOSE=1 install
		cp LICENSE ${OUTPUT_DIR}/licenses/libjpeg
		cd ${ROOT_DIR}
	fi
fi

# libPNG is only used for FFMpegThumbnailer so only build when it is enabled to save time.
if $CONF_LIBPNG && $CONF_FFMPEGTHUMBNAILER; then
	if [ ! -d sources/libpng ]; then
		echo "Cloning libpng repo."
		git clone "https://github.com/glennrp/libpng" "sources/libpng" --depth=1
	fi

	if [ ! -f ${TOOLCHAIN_DIR}/lib/libpng.a ]; then
		cd sources/libpng
		./configure --host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --disable-shared --enable-static --with-sysroot=${TOOLCHAIN_DIR} --with-zlib-prefix=${TOOLCHAIN_DIR}
		make -j8 VERBOSE=1 install
		cp LICENSE ${OUTPUT_DIR}/licenses/libpng
		cd ${ROOT_DIR}
	fi
fi


# FFMpegThumbnailer
if $CONF_FFMPEGTHUMBNAILER; then
	if [ ! -d sources/ffmpegthumbnailer ]; then
		echo "Cloning ffmpegthumbnailer repo."
		git clone "https://github.com/dirkvdb/ffmpegthumbnailer" "sources/ffmpegthumbnailer" --depth=1
	fi

	if [ ! -f ${OUTPUT_DIR}/ffmpegthumbnailer ] || [ ! -z "${REBUILD_FFMPEGTHUMBNAILER}" ]; then
		cd sources/ffmpegthumbnailer
		cp ${ROOT_DIR}/files/ffmpegthumbnailer-CMakeLists.txt CMakeLists.txt
		cp ${ROOT_DIR}/files/fmt-config.h config.h.in
		rm -rf cmake
		cmake . -DCMAKE_C_COMPILER=${TOOLCHAIN_DIR}/bin/${TARGET_TRIPLE}-gcc -DCMAKE_CXX_COMPILER=${TOOLCHAIN_DIR}/bin/${TARGET_TRIPLE}-g++ -DCMAKE_FIND_ROOT_PATH=${TOOLCHAIN_DIR} -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSROOT=${TOOLCHAIN_DIR} -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DCMAKE_CXX_FLAGS="-static ${CFLAGS}"
		make -j8 VERBOSE=1
		cp COPYING ${OUTPUT_DIR}/licenses/ffmpegthumbnailer
		strip_stuff ffmpegthumbnailer
		cp ffmpegthumbnailer ${OUTPUT_DIR}/ffmpegthumbnailer
		cd ${ROOT_DIR}
	fi
fi
