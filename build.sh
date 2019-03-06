#!/bin/bash
set -e

# For coloured text.
source bash_colors.sh


FFMPEG_VERSION=ffmpeg-4.1
LAME_VERSION=3.100
PKGCONF_VERSION=pkgconf-1.1.0
OPUS_VERSION=opus-1.3
X264_VERSION=latest
OGG_VERSION=1.3.2
VORBIS_VERSION=1.3.5

NON_FREE=false
LICENSE=LGPL

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

cd $ROOT_DIR

export TOOLCHAIN_DIR=${ROOT_DIR}/toolchain
export OUTPUT_DIR=${ROOT_DIR}/output
export LOGS_DIR=${ROOT_DIR}/logs

export PATH=${TOOLCHAIN_DIR}/bin:$PATH

source config.sh

export LDFLAGS="$LDFLAGS -L${TOOLCHAIN_DIR}/lib"
export CFLAGS="$CFLAGS -I${TOOLCHAIN_DIR}/include"
export CPPFLAGS="$CFLAGS"

export CC="/usr/bin/ccache ${TOOLCHAIN_DIR}/bin/${TARGET_TRIPLE}-gcc"
export CXX="/usr/bin/ccache ${TOOLCHAIN_DIR}/bin/${TARGET_TRIPLE}-g++"
export LD="${TOOLCHAIN_DIR}/bin/${TARGET_TRIPLE}-gcc"

strip_stuff() {
strip -S --strip-unneeded --remove-section=.note.gnu.gold-version --remove-section=.comment --remove-section=.note --remove-section=.note.gnu.build-id --remove-section=.note.ABI-tag -s -g --strip-all -x -X $1
}

FFMPEG_CONFIGURE_ARGS="--target-os=linux --arch=${TARGET_ARCH} --enable-cross-compile --cross-prefix=${TARGET_TRIPLE}- --prefix=${TOOLCHAIN_DIR} --enable-static --disable-shared --pkg-config=pkgconf --enable-asm --disable-htmlpages --disable-manpages --disable-doc" 

# Enable the FFMpeg program
if $CONF_FFMPEG; then
FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-ffmpeg"
fi

# Enable the FFProbe program
if $CONF_FFPROBE; then
FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-ffprobe"
fi


if [ ! -d logs ]; then 
	clr_blue "Making output dir"
	mkdir logs
fi

if [ ! -d output/licenses ]; then 
	clr_blue "Making output dir"
	mkdir output
fi

if [ ! -d output/licenses ]; then 
	clr_blue "Making output/licenses dir"
	mkdir output/licenses
fi

if [ ! -d sources ]; then 
	clr_blue "Making sources dir"
	mkdir sources
fi

if [ ! -d logs ]; then 
  clr_blue "Making logs dir"
  mkdir logs
fi


if [ ! -f sources/${TARGET_TRIPLE}-cross.tgz ]; then 
	clr_brown "Downloading toolchain"
	cp ../sources/${TARGET_TRIPLE}-cross.tgz  "sources/${TARGET_TRIPLE}-cross.tgz"
	#wget -q "http://musl.cc/${TARGET_TRIPLE}-cross.tgz" -O "sources/${TARGET_TRIPLE}-cross.tgz"
fi

if [ ! -d toolchain ]; then 
	clr_brown "Extracting toolchain"
	mkdir toolchain
	tar xf "sources/${TARGET_TRIPLE}-cross.tgz" -C toolchain/ --strip-components=2  &>/dev/null
fi

if [ ! -f sources/${PKGCONF_VERSION}.tar.xz ]; then
	clr_brown "Downloading pkgconf source"
	wget -q "https://distfiles.dereferenced.org/pkgconf/${PKGCONF_VERSION}.tar.xz" -O "sources/${PKGCONF_VERSION}.tar.xz"
fi

if [ ! -d sources/${PKGCONF_VERSION} ]; then
	clr_brown "Extracting pkgconf source"
	tar xf "sources/${PKGCONF_VERSION}.tar.xz" -C "sources/"
fi

if [ ! -f toolchain/bin/pkgconf ]; then
	cd sources/${PKGCONF_VERSION}
	clr_green "Configuring pkgconf"
	CC=gcc CXX=g++ LD=gcc ./configure --prefix=${TOOLCHAIN_DIR} --enable-static --disable-shared &> ${LOGS_DIR}/pkgconf-configure.log
	clr_green "Building and installing pkgconf"
	make install -j5 &> ${LOGS_DIR}/pkgconf-build.log
	clr_green "Making symlinks for pkgconf"
	ln -sf ${TOOLCHAIN_DIR}/bin/pkgconf ${TOOLCHAIN_DIR}/bin/${TARGET_TRIPLE}-pkgconf
	ln -sf ${TOOLCHAIN_DIR}/bin/pkgconf ${TOOLCHAIN_DIR}/bin/${TARGET_TRIPLE}-pkg-config
	ln -sf ${TOOLCHAIN_DIR}/bin/pkgconf ${TOOLCHAIN_DIR}/bin/pkg-config
	cd $ROOT_DIR
fi

if [ ! -d sources/nasm ]; then
	clr_brown "Cloning nasm repo"
	git clone -q --depth=1 "https://repo.or.cz/nasm.git" "sources/nasm"
fi

if [ ! -f toolchain/bin/nasm ]; then
	cd sources/nasm
	./autogen.sh &>/dev/null
	clr_green "Configuring nasm"
	CC=gcc CXX=g++ LD=gcc ./configure --host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --enable-static --disable-shared &> ${LOGS_DIR}/nasm-configure.log
	clr_green "Building nasm"
	make &> ${LOGS_DIR}/nasm-build.log
	clr_green "Installing nasm"
	make install -j5 &>> ${LOGS_DIR}/nasm-build.log || true
	cd $ROOT_DIR
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
NON_FREE=true
fi


if $CONF_ZLIB; then
	if [ ! -d sources/zlib-ng ]; then
		clr_brown "Downloading ZLib source"
		git clone -q "https://github.com/zlib-ng/zlib-ng" --depth=1 sources/zlib-ng
	fi
	if [ ! -f ${TOOLCHAIN_DIR}/lib/libz.a ]; then
		cd sources/zlib-ng
		clr_green "Configuring ZLib"
		CC=${TARGET_TRIPLE}-gcc ./configure --prefix=${TOOLCHAIN_DIR} --zlib-compat --static &> ${LOGS_DIR}/zlib-configure.log
		clr_green "Building ZLib"
		make -j5 &> ${LOGS_DIR}/zlib-build.log
		clr_green "Copying ZLib pkgconfig file over because the git repo seems to not build it properly"
		cp ${ROOT_DIR}/files/zlib.pc .
		clr_green "Installing ZLib"
		make install -j5 &>> ${LOGS_DIR}/zlib-build.log
		cd ${ROOT_DIR}
	fi
	FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-zlib"
	if [ ! -f ${OUTPUT_DIR}/licenses/zlib-ng ]; then
		clr_green "Copying license to output dir"
		cp ${ROOT_DIR}/sources/zlib-ng/LICENSE.md ${OUTPUT_DIR}/licenses/zlib-ng
	fi
fi

# MP3 support from libmp3lame
if $CONF_MP3; then
	if [ ! -f sources/lame-${LAME_VERSION}.tar.gz ]; then
		clr_brown "Downloading Lame source"
		wget -q "https://downloads.sourceforge.net/project/lame/lame/${LAME_VERSION}/lame-${LAME_VERSION}.tar.gz" -O sources/lame-${LAME_VERSION}.tar.gz
	fi
	if [ ! -d sources/lame-${LAME_VERSION} ]; then
		clr_brown "Extracting Lame source"
		tar xf "sources/lame-${LAME_VERSION}.tar.gz" -C "sources/"
	fi
	
	if [ ! -f ${TOOLCHAIN_DIR}/lib/libmp3lame.a ]; then
		cd sources/lame-${LAME_VERSION}
		clr_green "Configuring libmp3lame"
		./configure --host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --disable-shared --enable-static --disable-frontend --disable-decoder --enable-nasm &> ${LOGS_DIR}/libmp3lame-configure.log
		clr_green "Building and installing libmp3lame"
		make install -j5 &> ${LOGS_DIR}/libmp3lame-build.log
		cd ${ROOT_DIR}
	fi
	FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-decoder=mp3 --enable-demuxer=mp3 --enable-muxer=mp3 --enable-encoder=libmp3lame --enable-libmp3lame"
	if [ ! -f ${OUTPUT_DIR}/licenses/libmp3lame ]; then
		clr_green "Copying license to output dir"
		cp ${ROOT_DIR}/sources/lame-${LAME_VERSION}/LICENSE ${OUTPUT_DIR}/licenses/libmp3lame
	fi
fi

# Opus support from libopus
if $CONF_OPUS; then
	if [ ! -f sources/${OPUS_VERSION}.tar.gz ]; then
		clr_brown "Downloading Opus source"
		wget -q "https://archive.mozilla.org/pub/opus/${OPUS_VERSION}.tar.gz" -O sources/${OPUS_VERSION}.tar.gz
	fi
	if [ ! -d sources/${OPUS_VERSION} ]; then
		clr_brown "Extracting Opus source"
		tar xf "sources/${OPUS_VERSION}.tar.gz" -C "sources/"
	fi
	
	if [ ! -f ${TOOLCHAIN_DIR}/lib/libopus.a ]; then
		cd sources/${OPUS_VERSION}
		clr_green "Configuring libopus"
		./configure --host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --disable-shared --enable-static --disable-frontend --disable-decoder &> ${LOGS_DIR}/libopus-configure.log
		clr_green "Building and installing libopus"
		make install -j5 &> ${LOGS_DIR}/libopus-build.log
		cd ${ROOT_DIR}
	fi
	FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-decoder=opus --enable-encoder=libopus --enable-libopus --enable-muxer=opus"
	if [ ! -f ${OUTPUT_DIR}/licenses/libopus ]; then
		clr_green "Copying license to output dir"
		cp ${ROOT_DIR}/sources/${OPUS_VERSION}/COPYING ${OUTPUT_DIR}/licenses/libopus
	fi
fi

# x264 support from libx264
if $CONF_X264; then
	if [ ! -d sources/x264 ]; then
		clr_brown "Extracting x264 source"
		git clone -q --depth=1 https://git.videolan.org/git/x264.git sources/x264
	fi
	
	if [ ! -f ${TOOLCHAIN_DIR}/lib/libx264.a ]; then
		cd sources/x264
		clr_green "Configuring libx264"
		./configure --host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --enable-static --cross-prefix=${TARGET_TRIPLE}- --disable-opencl &> ${LOGS_DIR}/libx264-configure.log
		clr_green "Building and installing libx264"
		make install -j5 &> ${LOGS_DIR}/libx264-build.log
		cd ${ROOT_DIR}
	fi
	FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-libx264 --enable-decoder=h264 --enable-encoder=libx264 --enable-parser=h264"
	if [ ! -f ${OUTPUT_DIR}/licenses/libx264 ]; then
		clr_green "Copying license to output dir"
		cp ${ROOT_DIR}/sources/x264/COPYING ${OUTPUT_DIR}/licenses/libx264
	fi
fi

# VPX support from libvpx
if $CONF_VPX; then
	if [ ! -d sources/libvpx ]; then
		clr_brown "Extracting libvpx source"
		git clone -q --depth=1 https://chromium.googlesource.com/webm/libvpx -b v1.8.0 sources/libvpx &>/dev/null
	fi

	if [ ! -f ${TOOLCHAIN_DIR}/lib/libvpx.a ]; then
		cd sources/libvpx
		clr_green "Configuring libvpx"
		./configure --target=${TARGET_ARCH}-linux-gcc --prefix=${TOOLCHAIN_DIR} --enable-vp8 --enable-vp9 --enable-static --disable-unit-tests --disable-tools --as=nasm --enable-runtime-cpu-detect &> ${LOGS_DIR}/libvpx-configure.log
		clr_green "Building and installing libvpx"
		make install -j5 &> ${LOGS_DIR}/libvpx-build.log
		cd ${ROOT_DIR}
	fi
	FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-libvpx --enable-decoder=libvpx_vp8,libvpx_vp9 --enable-encoder=vp9,libvpx_vp9 --enable-encoder=vp8,libvpx_vp8 --enable-parser=vp8 --enable-parser=vp9"
	if [ ! -f ${OUTPUT_DIR}/licenses/libvpx ]; then
		clr_green "Copying license to output dir"
		cp ${ROOT_DIR}/sources/libvpx/LICENSE ${OUTPUT_DIR}/licenses/libvpx
	fi
fi

# OGG support from libogg, also needed for libvorbis
if $CONF_OGG; then
	if [ ! -f sources/libogg-${OGG_VERSION}.tar.gz ]; then
		clr_brown "Downloading OGG source"
		wget -q "http://downloads.xiph.org/releases/ogg/libogg-${OGG_VERSION}.tar.gz" -O sources/libogg-${OGG_VERSION}.tar.gz
	fi
	if [ ! -d sources/libogg-${OGG_VERSION} ]; then
		clr_brown "Extracting OGG source"
		tar xf "sources/libogg-${OGG_VERSION}.tar.gz" -C "sources/"
	fi

	if [ ! -f ${TOOLCHAIN_DIR}/lib/libogg.a ]; then
		cd sources/libogg-${OGG_VERSION}
		clr_green "Configuring libogg"
		./configure --host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --disable-shared --enable-static &> ${LOGS_DIR}/libogg-configure.log
		clr_green "Building and installing libogg"
		make install -j5 &> ${LOGS_DIR}/libogg-build.log
		cd ${ROOT_DIR}
	fi
	if [ ! -f ${OUTPUT_DIR}/licenses/libogg ]; then
		clr_green "Copying license to output dir"
		cp ${ROOT_DIR}/sources/libogg-${OGG_VERSION}/COPYING ${OUTPUT_DIR}/licenses/libogg
	fi
fi

# Vorbis support from libvorbis
if $CONF_VORBIS; then
	if [ ! -f sources/libvorbis-${VORBIS_VERSION}.tar.gz ]; then
		clr_brown "Downloading libvorbis source"
		wget -q "http://downloads.xiph.org/releases/vorbis/libvorbis-${VORBIS_VERSION}.tar.gz" -O sources/libvorbis-${VORBIS_VERSION}.tar.gz
	fi
	if [ ! -d sources/libvorbis-${VORBIS_VERSION} ]; then
		clr_brown "Extracting libvorbis source"
		tar xf "sources/libvorbis-${VORBIS_VERSION}.tar.gz" -C "sources/"
	fi
	

	if [ ! -f ${TOOLCHAIN_DIR}/lib/libvorbis.a ]; then
		cd sources/libvorbis-${VORBIS_VERSION}
		clr_green "Configuring libvorbis"
		./configure --host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --disable-shared --enable-static &> ${LOGS_DIR}/libvorbis-configure.log
		clr_green "Building and installing libvorbis"
		make install -j5 V=1 &> ${LOGS_DIR}/libvorbis-build.log
		cd ${ROOT_DIR}
	fi
	FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-libvorbis --enable-encoder=libvorbis --enable-decoder=libvorbis"
	if [ ! -f ${OUTPUT_DIR}/licenses/libvorbis ]; then
		clr_green "Copying license to output dir"
		cp ${ROOT_DIR}/sources/libvorbis-${VORBIS_VERSION}/COPYING ${OUTPUT_DIR}/licenses/libvorbis
	fi
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
	clr_brown "Downloading FFMPEG source"
	wget -q "http://ffmpeg.org/releases/${FFMPEG_VERSION}.tar.bz2" -O sources/${FFMPEG_VERSION}.tar.bz2
fi
if [ ! -d sources/${FFMPEG_VERSION} ]; then
	clr_brown "Extracting FFMPEG source"
	tar xf "sources/${FFMPEG_VERSION}.tar.bz2" -C "sources/"
fi

if [ ! -f ${TOOLCHAIN_DIR}/lib/libavutil.a ] || [ ! -z "${REBUILD_FFMPEG}" ]; then
	cd sources/${FFMPEG_VERSION}
	clr_green "Configuring FFMpeg"
	./configure  ${FFMPEG_CONFIGURE_ARGS[@]} --extra-cflags="-I${TOOLCHAIN_DIR}/include ${CFLAGS}" --extra-ldflags="-static -L${TOOLCHAIN_DIR}/lib ${LDFLAGS}" --pkg-config-flags="--static" &> ${LOGS_DIR}/ffmpeg-configure.log
	clr_green "Building and installing FFMpeg binaries and libraries"
	make -j8 &> ${LOGS_DIR}/ffmpeg-build.log
	make install &>> ${LOGS_DIR}/ffmpeg-build.log
	if $CONF_FFMPEG; then cp ffmpeg ${OUTPUT_DIR}/ffmpeg; fi
	if $CONF_FFPROBE; then cp ffprobe ${OUTPUT_DIR}/ffprobe; fi
	cd ${ROOT_DIR}
fi

if [ ! -f ${OUTPUT_DIR}/licenses/ffmpeg ]; then
	clr_green "Copying license to output dir"
	cp ${ROOT_DIR}/sources/${FFMPEG_VERSION}/LICENSE.md ${OUTPUT_DIR}/licenses/ffmpeg
fi


# libJPEG is only used for FFMpegThumbnailer so only build when it is enabled to save time.
if $CONF_LIBJPEG && $CONF_FFMPEGTHUMBNAILER; then
	if [ ! -d sources/libjpeg ]; then
		clr_brown "Cloning libjpeg repo"
		git clone -q "https://github.com/LuaDist/libjpeg" "sources/libjpeg" --depth=1
	fi

	if [ ! -f ${TOOLCHAIN_DIR}/lib/libjpeg.a ]; then
		cd sources/libjpeg
		clr_green "Configuring libjpeg"
		./configure --host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --disable-shared --enable-static &> ${LOGS_DIR}/libjpeg-configure.log
		clr_green "Building and installing libjpeg"
		make -j8 VERBOSE=1 install &> ${LOGS_DIR}/libjpeg-build.log
		cd ${ROOT_DIR}
	fi
	if [ ! -f ${OUTPUT_DIR}/licenses/libjpeg ]; then
		clr_green "Copying license to output dir"
		cp ${ROOT_DIR}/sources/libjpeg/README ${OUTPUT_DIR}/licenses/libjpeg
	fi
fi

# libPNG is only used for FFMpegThumbnailer so only build when it is enabled to save time.
if $CONF_LIBPNG && $CONF_FFMPEGTHUMBNAILER; then
	if [ ! -d sources/libpng ]; then
		clr_brown "Cloning libpng repo"
		git clone -q "https://github.com/glennrp/libpng" "sources/libpng" --depth=1
	fi

	if [ ! -f ${TOOLCHAIN_DIR}/lib/libpng.a ]; then
		cd sources/libpng
		clr_green "Configuring libpng"
		./configure --host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --disable-shared --enable-static --with-sysroot=${TOOLCHAIN_DIR} --with-zlib-prefix=${TOOLCHAIN_DIR} &> ${LOGS_DIR}/libpng-configure.log
		clr_green "Building and installing libpng"
		make -j8 VERBOSE=1 install &> ${LOGS_DIR}/libpng-build.log
		cd ${ROOT_DIR}
	fi
	if [ ! -f ${OUTPUT_DIR}/licenses/libpng ]; then
		clr_green "Copying license to output dir"
		cp ${ROOT_DIR}/sources/libpng/LICENSE ${OUTPUT_DIR}/licenses/libpng
	fi
fi


# FFMpegThumbnailer
if $CONF_FFMPEGTHUMBNAILER; then
	if [ ! -d sources/ffmpegthumbnailer ]; then
		clr_brown "Cloning ffmpegthumbnailer repo"
		git clone -q "https://github.com/dirkvdb/ffmpegthumbnailer" "sources/ffmpegthumbnailer" --depth=1
	fi

	if [ ! -f ${OUTPUT_DIR}/ffmpegthumbnailer ] || [ ! -z "${REBUILD_FFMPEGTHUMBNAILER}" ]; then
		cd sources/ffmpegthumbnailer
		clr_green "Copying some modified build files to make ffmpegthumbnailer build properly"
		cp ${ROOT_DIR}/files/ffmpegthumbnailer-CMakeLists.txt CMakeLists.txt
		cp ${ROOT_DIR}/files/fmt-config.h config.h.in
		rm -rf cmake
		clr_green "Configuring ffmpegthumbnailer"
		cmake . -DCMAKE_C_COMPILER="${TOOLCHAIN_DIR}/bin/${TARGET_TRIPLE}-gcc" -DCMAKE_CXX_COMPILER="${TOOLCHAIN_DIR}/bin/${TARGET_TRIPLE}-g++" -DCMAKE_FIND_ROOT_PATH=${TOOLCHAIN_DIR} -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSROOT=${TOOLCHAIN_DIR} -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DCMAKE_CXX_FLAGS="-static ${CFLAGS}" &> ${LOGS_DIR}/ffmpegthumbnailer-configure.log
		clr_green "Building ffmpegthumbnailer"
		make -j8 &> ${LOGS_DIR}/ffmpegthumbnailer-build.log
		clr_green "Stripping ffmpegthumbnailer"
		strip_stuff ffmpegthumbnailer
		clr_green "Copying ffmpegthumbnailer binary to output folder"
		cp ffmpegthumbnailer ${OUTPUT_DIR}/ffmpegthumbnailer
		cd ${ROOT_DIR}
	fi
	if [ ! -f ${OUTPUT_DIR}/licenses/ffmpegthumbnailer ]; then
		clr_green "Copying license to output dir"
		cp ${ROOT_DIR}/sources/ffmpegthumbnailer/COPYING ${OUTPUT_DIR}/licenses/ffmpegthumbnailer
	fi
fi


# Copy readme with license name and information to the output folder.
cp ${ROOT_DIR}/README.out ${OUTPUT_DIR}/README
sed -i "s/LICENSE_NAME/${LICENSE}/" ${OUTPUT_DIR}/README

if $NON_FREE; then
	sed -i "s/^IF_NONFREE //" ${OUTPUT_DIR}/README
else
	sed -i "s/^IF_NONFREE.*//" ${OUTPUT_DIR}/README
fi

