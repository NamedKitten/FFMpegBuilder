#!/bin/bash
set -e
#set -x
set -o pipefail

# For coloured text.
source bash_colors.sh
#set -x

HOST_ARCH=`uname -p`
NON_FREE=false
LICENSE=LGPL

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

cd $ROOT_DIR

export SOURCES_DIR=${ROOT_DIR}/sources
export TOOLCHAIN_DIR=${ROOT_DIR}/toolchain
export OUTPUT_DIR=${ROOT_DIR}/output
export LOGS_DIR=${ROOT_DIR}/logs
export PATH=${TOOLCHAIN_DIR}/bin:$PATH

source config.sh

function licenseFilepathOf() {
    echo `jq -r .$1.licenseFilepath $ROOT_DIR/meta.json`
}

function versionOf() {
    echo `jq -r .$1.version $ROOT_DIR/meta.json`
}

function folderOf() {
    echo `jq -r .$1.folder $ROOT_DIR/meta.json`
}

function filenameOf() {
    echo `jq -r .$1.filename $ROOT_DIR/meta.json`
}

function typeOf() {
    echo `jq -r .$1.type $ROOT_DIR/meta.json`
}

function urlOf() {
    echo `jq -r .$1.url $ROOT_DIR/meta.json`
}

function copyLicense() {
    if [ "`licenseFilepathOf $1`" == "null" ]; then
        return
    fi
    
    if [ ! -f ${OUTPUT_DIR}/licenses/$1 ]; then
        cp ${SOURCES_DIR}/`folderOf $1`/`licenseFilepathOf $1` ${OUTPUT_DIR}/licenses/$1
    fi
}

function downloadURL() {
    if [ "$TARBALL_DOWNLOADER" == "aria2c" ]; then
        aria2c $TARBALL_DOWNLOADER_ARGS $1
        elif [ "$TARBALL_DOWNLOADER" == "curl" ]; then
        curl -L $TARBALL_DOWNLOADER_ARGS $1
    fi
}

function dlThing() {
    thing=$1
    folder=`folderOf $thing`
    if [ -d $SOURCES_DIR/$folder ]; then
        return
    fi
    url=` urlOf $thing`
    type=`typeOf $thing`
    version=`versionOf $thing`
    cd $SOURCES_DIR
    if [ "$type" == "tarball" ]; then
        filename=`filenameOf $thing`
        if [ ! -f "$filename" ]; then
            clr_brown "Downloading $filename for $thing"
            downloadURL "$url"
        fi
        clr_brown "Extracting tarball for $thing"
        tar xf $filename
        clr_brown "Finished extracting tarball for $thing"
        elif [ "$type" == "git" ]; then
        clr_brown "Cloning repo for $thing"
        git clone --depth=1 -b $version $url $folder
    fi
    cd $ROOT_DIR
}

export LDFLAGS="$LDFLAGS -L${TOOLCHAIN_DIR}/lib"
export CFLAGS="$CFLAGS -I${TOOLCHAIN_DIR}/include"
export CPPFLAGS="$CFLAGS"
export SYSROOT=${TOOLCHAIN_DIR}
export CC="/usr/bin/ccache ${TOOLCHAIN_DIR}/bin/${TARGET_TRIPLE}-gcc"
export CXX="/usr/bin/ccache ${TOOLCHAIN_DIR}/bin/${TARGET_TRIPLE}-g++"
export LD="${TOOLCHAIN_DIR}/bin/${TARGET_TRIPLE}-gcc"
export NM="${TOOLCHAIN_DIR}/bin/${TARGET_TRIPLE}-nm"
export RANLIB="${TOOLCHAIN_DIR}/bin/${TARGET_TRIPLE}-ranlib"
export AR="${TOOLCHAIN_DIR}/bin/${TARGET_TRIPLE}-ar"
export ARCH=`echo ${TARGET_TRIPLE} | sed s/.*-//`
export CROSS_COMPILE=${TARGET_TRIPLE}-


strip_stuff() {
    strip --strip-all $1
}

function log() {
    thing=$1
    stage=$2
    
    if $DEBUG; then
        cat | tee ${LOGS_DIR}/${thing}-${stage}.log
    else
        cat > ${LOGS_DIR}/${thing}-${stage}.log
    fi
    
}

function buildThing() {
    set -e
    thing=$1
    configureArgs=$2
    
    if isInstalled $thing && [[ $REBUILD == *${thing}* ]]; then
        clr_red "Force (re)building $thing"
        elif isInstalled $thing; then
        clr_green "Already built $thing"
        return 0
    else
        clr_magenta "Now on $thing"
    fi

    dlThing $thing
    
    
    cd sources/`folderOf $thing`
    
    if [ "$thing" == "berkeleydb" ]; then
        cd build_unix
    fi


    clr_blue "Applying patches for $thing"
    case $thing in
        libxcb )
            sed s/pthread-stubs// -i configure
        ;;
        libX11 )
            git apply ${ROOT_DIR}/files/x11.diff || true
            autoreconf -f -i
        ;;
        libXt )
            git apply ${ROOT_DIR}/files/libXt.diff
        ;;
        zlib )
            cp ${ROOT_DIR}/files/zlib.pc .
        ;;
    esac
    
    clr_blue "Configuring $thing"
    case $thing in
        berkeleydb )
            ../dist/configure ${configureArgs[@]} |& log $thing configure
        ;;
        ffmpeg )
            PKG_CONFIG="pkg-config --static"  ./configure ${FFMPEG_CONFIGURE_ARGS[@]}  --cc="$CC" --cxx="$CXX"  --ld=$LD --extra-cflags="-I${TOOLCHAIN_DIR}/include ${CFLAGS}" --extra-ldflags="-static -L${TOOLCHAIN_DIR}/lib ${LDFLAGS}" --pkg-config-flags="--static" |& log $thing configure
        ;;
        mpv )
            ./bootstrap.py 2>&1 >/dev/null
            ./waf configure ${configureArgs[@]} |& log $thing configure
        ;;
        lua )
        ;;
        * )
            if [ ! -f configure ]; then
                autoreconf -i
            fi
            ./configure ${configureArgs[@]} |& log $thing configure
        ;;
    esac
    
    clr_blue "Building $thing"
    case $thing in
        lua )
            make -j12 V=1 generic CC=${TARGET_TRIPLE}-gcc AR="${TARGET_TRIPLE}-ar rcu" RANLIB=${TARGET_TRIPLE}-ranlib  |& log $thing build
        ;;
        mpv )
            if [ ! -f ${TOOLCHAIN_DIR}/${TARGET_TRIPLE}/lib/libc.so ]; then
                mv ${TOOLCHAIN_DIR}/${TARGET_TRIPLE}/lib/libc.so.bak ${TOOLCHAIN_DIR}/${TARGET_TRIPLE}/lib/libc.so
            fi
            mv ${TOOLCHAIN_DIR}/${TARGET_TRIPLE}/lib/libc.so ${TOOLCHAIN_DIR}/${TARGET_TRIPLE}/lib/libc.so.bak
            ./waf build -j12 V=1 |& log $thing build
            mv ${TOOLCHAIN_DIR}/${TARGET_TRIPLE}/lib/libc.so.bak ${TOOLCHAIN_DIR}/${TARGET_TRIPLE}/lib/libc.so
        ;;
        * )
            make -j12 V=1 |& log $thing build
        ;;
    esac
    
    clr_blue "Installing $thing"
    case $thing in
        ffmpeg )
            sudo env PATH=$PATH make install V=1 |& log $thing install
            if $CONF_FFMPEG; then cp ffmpeg ${OUTPUT_DIR}/ffmpeg; fi
            if $CONF_FFPROBE; then cp ffprobe ${OUTPUT_DIR}/ffprobe; fi
        ;;
        utillinux )
            sudo env PATH=$PATH make install |& log $thing install
        ;;
        mpv )
            cp build/mpv  ${OUTPUT_DIR}/mpv
        ;;
        lua )
            make install INSTALL_TOP=${TOOLCHAIN_DIR} |& log $thing install
        ;;
        * )
            make install |& log $thing install
        ;;
    esac
    
    clr_blue "Copying license for $thing"
    case $thing in
        * )
            copyLicense $thing
        ;;
    esac
    
    markInstalled $thing
    
    cd $ROOT_DIR
}

FFMPEG_CONFIGURE_ARGS="--target-os=linux --arch=${TARGET_ARCH} --enable-cross-compile --cross-prefix=${TARGET_TRIPLE}- --prefix=${TOOLCHAIN_DIR} --libdir=${TOOLCHAIN_DIR}/lib --enable-static --disable-shared --pkg-config=pkgconf --disable-htmlpages --disable-manpages --disable-doc"

# Enable the FFMpeg program
if $CONF_FFMPEG; then
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-ffmpeg"
fi

# Enable the FFProbe program
if $CONF_FFPROBE; then
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-ffprobe"
fi

clr_blue "Making dirs"
mkdir -p logs output output/licenses sources logs


if [ ! -f sources/${TARGET_TRIPLE}-cross.tgz ]; then
    clr_brown "Downloading toolchain"
    wget -q "http://musl.cc/${TARGET_TRIPLE}-cross.tgz" -O "sources/${TARGET_TRIPLE}-cross.tgz"
fi

if [ ! -d toolchain ]; then
    clr_brown "Extracting toolchain"
    mkdir toolchain
    tar xf "sources/${TARGET_TRIPLE}-cross.tgz" -C toolchain/ --strip-components=2  &>/dev/null
fi

mkdir -p ${TOOLCHAIN_DIR}/installed

function markInstalled() {
    thing=$1
    touch ${TOOLCHAIN_DIR}/installed/$thing
}

function isInstalled() {
    thing=$1
    [ -f "${TOOLCHAIN_DIR}/installed/${thing}" ]
}


CC=gcc CXX=g++ LD=gcc buildThing pkgconf "--prefix=${TOOLCHAIN_DIR} --enable-static --disable-shared"
if [ ! -f toolchain/bin/${TARGET_TRIPLE}-pkgconf ]; then
    ln -sf ${TOOLCHAIN_DIR}/bin/pkgconf ${TOOLCHAIN_DIR}/bin/${TARGET_TRIPLE}-pkgconf
    ln -sf ${TOOLCHAIN_DIR}/bin/pkgconf ${TOOLCHAIN_DIR}/bin/${TARGET_TRIPLE}-pkg-config
    ln -sf ${TOOLCHAIN_DIR}/bin/pkgconf ${TOOLCHAIN_DIR}/bin/pkg-config
fi


CC=gcc CXX=g++ LD=gcc buildThing nasm "--host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --enable-static --disable-shared"

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

if $CONF_MJPEG; then
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-decoder=mjpeg"
fi
if $CONF_FLAC; then
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-decoder=flac --enable-encoder=flac --enable-muxer=flac --enable-demuxer=flac"
fi
if $CONF_AAC; then
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-decoder=aac --enable-encoder=aac --enable-demuxer=aac"
fi
if $CONF_MKV; then
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-muxer=matroska --enable-demuxer=matroska"
fi
if $CONF_WEBM; then
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-muxer=webm"
fi
if $CONF_MOV; then
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-muxer=mov  --enable-demuxer=mov"
fi
if $CONF_MP4; then
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-muxer=mp4"
fi
if $CONF_MP3; then
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-decoder=mp3 --enable-demuxer=mp3 --enable-muxer=mp3 --enable-encoder=libmp3lame --enable-libmp3lame"
fi

if $CONF_ZLIB || $CONF_PNG; then
    buildThing zlib "--prefix=${TOOLCHAIN_DIR} --zlib-compat --static"
    FREETYPE_CONFIG="$FREETYPE_CONFIG --with-zlib=yes"
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-zlib"
fi

if $CONF_PNG; then
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-encoder=png --enable-decoder=png"
fi



# MP3 support from libmp3lame
if $CONF_MP3; then
    buildThing lame "--host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --disable-shared --enable-static --disable-frontend --disable-decoder --enable-nasm"
fi

# Opus support from libopus
if $CONF_OPUS; then
    buildThing opus "--host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --disable-shared --enable-static --disable-frontend --disable-decoder"
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-decoder=opus --enable-encoder=libopus --enable-libopus --enable-muxer=opus"
fi

# x264 support from libx264
if $CONF_X264; then
    buildThing x264 "--host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --enable-static --cross-prefix=${TARGET_TRIPLE}- --disable-opencl"
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-libx264 --enable-decoder=h264 --enable-encoder=libx264 --enable-parser=h264"
fi

# VPX support from libvpx
if $CONF_VPX; then
    buildThing vpx "--target=${TARGET_ARCH}-linux-gcc --prefix=${TOOLCHAIN_DIR} --enable-vp8 --enable-vp9 --enable-static --disable-unit-tests --disable-tools --as=yasm --enable-runtime-cpu-detect"
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-libvpx --enable-decoder=libvpx_vp8,libvpx_vp9 --enable-encoder=vp9,libvpx_vp9 --enable-encoder=vp8,libvpx_vp8 --enable-parser=vp8 --enable-parser=vp9"
fi

# OGG support from libogg, also needed for libvorbis
if $CONF_OGG; then
    buildThing libogg "--host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --disable-shared --enable-static"
fi

# Vorbis support from libvorbis
if $CONF_VORBIS; then
    buildThing libvorbis "--host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --disable-shared --enable-static"
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-libvorbis --enable-encoder=libvorbis --enable-decoder=libvorbis"
fi

# AAC encoding support from libfdk-aac
if $CONF_FDK_AAC; then
    buildThing fdk_aac " --host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --disable-shared --enable-static"
fi

# libsndfile for mpv
if $CONF_LIBSNDFILE; then
    buildThing libsndfile "--host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --disable-shared --enable-static --disable-tests"
fi

# alsa-lib for mpv
if $CONF_ALSA_LIB; then
    buildThing alsalib "--host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --disable-shared --enable-static --with-libdl=no"
fi

# jack audio
if $CONF_JACK; then
    buildThing berkeleydb "--host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --disable-shared --enable-static"
    buildThing jack1 "--host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --libdir=${TOOLCHAIN_DIR}/lib  --enable-force-install --disable-shared --enable-static --disable-tests"
fi

if $CONF_LIBJPEG; then
    buildThing libjpeg "--host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --disable-shared --enable-static"
fi

if $CONF_LIBPNG; then
    FREETYPE_CONFIG="$FREETYPE_CONFIG --with-png=yes"
    buildThing libpng "--host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --disable-shared --enable-static --with-sysroot=${TOOLCHAIN_DIR} --with-zlib-prefix=${TOOLCHAIN_DIR}"
fi


export XORG_CONFIG=""
export XORG_FULL_CONFIG="--host=${TARGET_TRIPLE}  --prefix=${TOOLCHAIN_DIR} --sysconfdir=/etc --localstatedir=/var --disable-shared --enable-static"
export XORG_FULL_CROSS_CONFIG="$XORG_FULL_CONFIG"



if $CONF_XORG; then
    buildThing xutilmacros  "--host=${TARGET_TRIPLE} ${XORG_FULL_CONFIG}"
    buildThing xorgproto "--host=${TARGET_TRIPLE} ${XORG_FULL_CONFIG}"
    buildThing libXau "--host=${TARGET_TRIPLE} ${XORG_FULL_CONFIG}"
    buildThing libXdmcp "--host=${TARGET_TRIPLE} ${XORG_FULL_CONFIG}"
    buildThing xcbproto "--host=${TARGET_TRIPLE} ${XORG_FULL_CONFIG}"
    buildThing libxcb "--host=${TARGET_TRIPLE} ${XORG_FULL_CONFIG}"
    buildThing freetype "--host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --enable-shared=no --enable-static=yes $FREETYPE_CONFIG"
    buildThing utillinux "--host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --enable-shared=no --enable-static=yes --disable-shared"
    buildThing expat "--host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --enable-shared=no --enable-static=yes --disable-shared"
    buildThing fontconfig "--host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --disable-docs --enable-shared=no --enable-static=yes --disable-shared --disable-tests"
    buildThing fribidi "--host=${TARGET_TRIPLE} --prefix=${TOOLCHAIN_DIR} --enable-shared=no --enable-static=yes --disable-shared --enable-static"
    #hhhhhhhhh
    buildThing xtrans "$XORG_FULL_CROSS_CONFIG"
    buildThing libX11 "$XORG_FULL_CROSS_CONFIG"
    buildThing libXext "$XORG_FULL_CROSS_CONFIG"
    buildThing libFS "$XORG_FULL_CROSS_CONFIG"
    buildThing libICE "$XORG_FULL_CROSS_CONFIG ICE_LIBS=-lpthread"
    buildThing libSM "$XORG_FULL_CROSS_CONFIG"
    buildThing libXScrnSaver "$XORG_FULL_CROSS_CONFIG"
    buildThing libXpm "$XORG_FULL_CROSS_CONFIG"
    buildThing libXfixes "$XORG_FULL_CROSS_CONFIG"
    buildThing libXrender "$XORG_FULL_CROSS_CONFIG"
    buildThing libXcursor "$XORG_FULL_CROSS_CONFIG"
    buildThing libXdamage "$XORG_FULL_CROSS_CONFIG"
    buildThing libfontenc "$XORG_FULL_CROSS_CONFIG"
    buildThing libXfont2 "$XORG_FULL_CROSS_CONFIG --disable-devel-docs"
    buildThing libXft "$XORG_FULL_CROSS_CONFIG"
    buildThing libXi "$XORG_FULL_CROSS_CONFIG"
    buildThing libXinerama "$XORG_FULL_CROSS_CONFIG"
    buildThing libXrandr "$XORG_FULL_CROSS_CONFIG"
    buildThing libXres "$XORG_FULL_CROSS_CONFIG"
    buildThing libXtst "$XORG_FULL_CROSS_CONFIG"
    buildThing libXv "$XORG_FULL_CROSS_CONFIG"
    buildThing libXvMC "$XORG_FULL_CROSS_CONFIG"
    buildThing libdmx "$XORG_FULL_CROSS_CONFIG"
    buildThing libpciaccess "$XORG_FULL_CROSS_CONFIG"
    buildThing libxkbfile "$XORG_FULL_CROSS_CONFIG"
    buildThing libxshmfence "$XORG_FULL_CROSS_CONFIG"
    buildThing pixman "--host=${TARGET_TRIPLE}  --prefix=${TOOLCHAIN_DIR}"
fi

if $CONF_LIBCACA; then
    CPPFLAGS="$CPPFLAGS -P" buildThing ncurses "--host=${TARGET_TRIPLE}  --prefix=${TOOLCHAIN_DIR} --enable-shared=no --enable-static=yes --disable-shared --enable-static --with-pc-files"
    buildThing libcaca "--host=${TARGET_TRIPLE}  --prefix=${TOOLCHAIN_DIR} --disable-kernel --disable-slang --disable-win32 --disable-conio --disable-x11 --disable-gl --disable-cocoa --disable-network --disable-vga --disable-csharp --disable-java --disable-cxx --disable-python --disable-ruby --disable-imlib2 --disable-profiling --disable-plugins --disable-doc"
    sed "s/-lcaca/-lcaca -lncurses/" -i toolchain/lib/pkgconfig/caca.pc
fi



if $CONF_SDL2; then
    CC="$CC -static --static" buildThing sdl2 "--with-sysroot=${SYSROOT} --host=${TARGET_TRIPLE}  --prefix=${TOOLCHAIN_DIR} --disable-pulseaudio --enable-video-x11-xrandr --disable-esd --disable-video-wayland --enable-shared=no --disable-shared --enable-static=yes --enable-static --disable-loadso --disable-sdl-dlopen --disable-video-wayland --disable-video-vulkan --disable-alsa-shared --disable-jack-shared --disable-esd-shared --disable-arts-shared --disable-nas-shared --disable-sndio-shared --disable-wayland-shared --disable-mir-shared --disable-x11-shared --disable-kmsdrm-shared --disable-video-opengl --disable-arts --disable-video-opengles1 --disable-video-opengles2 --disable-video-opengles --disable-ime --enable-events --disable-loadso --enable-video-x11 --x-includes=${SYSROOT}/include/X11 --x-libraries=${SYSROOT}/lib"
    MPV_CONFIGURE_ARGS="$MPV_CONFIGURE_ARGS --enable-sdl2"
    sed "s/-lX11/`pkg-config --static --libs xext x11 xfixes xrender`/"  -i toolchain/lib/pkgconfig/sdl2.pc
fi

if $CONF_SSL; then
    buildThing libressl "--host=${TARGET_TRIPLE}  --prefix=${TOOLCHAIN_DIR} --enable-shared=no --enable-static=yes"
    FFMPEG_CONFIGURE_ARGS="$FFMPEG_CONFIGURE_ARGS --enable-openssl"
fi




buildThing ffmpeg


if $CONF_LUA; then
    buildThing lua
    
cat <<boop > ${TOOLCHAIN_DIR}/lib/pkgconfig/lua.pc
prefix=${TOOLCHAIN_DIR}
exec_prefix=${TOOLCHAIN_DIR}
libdir=${TOOLCHAIN_DIR}/lib
includedir=${TOOLCHAIN_DIR}/include

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
    buildThing libass "--host=${TARGET_TRIPLE}  --prefix=${TOOLCHAIN_DIR}"
else
    MPV_CONFIGURE_ARGS="$MPV_CONFIGURE_ARGS --disable-libass"
fi



if $CONF_MPV; then
    PKG_CONFIG="pkg-config --static" buildThing mpv "--enable-static-build --disable-cplugins --target=${TARGET_TRIPLE}  --disable-gl ${MPV_CONFIGURE_ARGS[@]}"
    if true; then #; then
        clr_green "Copying MPV license to output dir"
        if [ "$LICENSE" == GPL ]; then
            cp ${ROOT_DIR}/sources/mpv/LICENSE.GPL ${OUTPUT_DIR}/licenses/mpv
        else
            cp ${ROOT_DIR}/sources/mpv/LICENSE.LGPL ${OUTPUT_DIR}/licenses/mpv
        fi
    fi
fi


echo hhhhhhhh
exit


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

