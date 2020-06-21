function log() {
    thing=$1
    stage=$2
    
    if [ "$DEBUG" == "true" ]; then
        cat | tee ${LOGS_DIR}/${thing}-${stage}.log
    else
        cat > ${LOGS_DIR}/${thing}-${stage}.log
    fi
    
}

function failed() {
    unmarkConfigured ${CURRENT_THING}
    clr_red "${CURRENT_THING} failed to build."
}

function buildThing() {
    set -e
    thing=$1
    configureArgs=$2
    export CURRENT_THING=$thing
    trap failed HUP INT TERM PIPE EXIT
    
    
    if isInstalled $thing && [[ $REBUILD == *${thing}* ]]; then
        clr_red "Force (re)building $thing"
        elif isInstalled $thing; then
        clr_green "Already built $thing"
        trap - HUP INT TERM PIPE EXIT
        
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
        zlib )
            cp ${ROOT_DIR}/files/zlib.pc .
        ;;
        mpv )
            git reset --hard
            sed "s/'x11', 'libdl', 'pthreads'/'x11', 'pthreads'/" -i wscript
            #sed "s/int x[LIBAVCODEC_VERSION_MICRO >= 100 ? -1 : 1]/return 1;/" -i wscript
            #sed "s/56.27.100/56.22.100/" -i wscript
        ;;
        ffmpegthumbnailer )
            cp ${ROOT_DIR}/files/ffmpegthumbnailer-CMakeLists.txt CMakeLists.txt
            cp ${ROOT_DIR}/files/fmt-config.h config.h.in
            rm -rf cmake
        ;;
    esac
    
    if ! isConfigured $thing; then
    clr_blue "Configuring $thing"
    case $thing in
        berkeleydb )
            ../dist/configure ${configureArgs[@]} |& log $thing configure
        ;;
        ffmpeg )
            PKG_CONFIG="pkg-config --static"  ./configure ${FFMPEG_CONFIGURE_ARGS[@]}  --cc="$CC" --cxx="$CXX"  --ld=$LD --extra-cflags="-I${SYSROOT}/include ${CFLAGS}" --extra-ldflags="-static -L${SYSROOT}/lib ${LDFLAGS}" --pkg-config-flags="--static" |& log $thing configure
        ;;
        mpv )
            ./bootstrap.py 2>&1 >/dev/null
            ./waf configure ${configureArgs[@]} |& log $thing configure
        ;;
        ffmpegthumbnailer )
            cmake . -DCMAKE_C_COMPILER="${SYSROOT}/bin/${TARGET_TRIPLE}-gcc" -DCMAKE_CXX_COMPILER="${SYSROOT}/bin/${TARGET_TRIPLE}-g++" -DCMAKE_FIND_ROOT_PATH=${SYSROOT} -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSROOT=${SYSROOT} -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DCMAKE_C_FLAGS="-static ${CFLAGS}" -DCMAKE_CXX_FLAGS="-static ${CXXFLAGS}"
        ;;
        lua )
        ;;
        jack1 )
            git submodule update --init -f
            autoreconf -i || true
            ./configure ${configureArgs[@]} |& log $thing configure
        ;;
        jq )
            git submodule update --init -f
            autoreconf -fi || true
            ./configure ${configureArgs[@]} |& log $thing configure
        ;;
        * )
            if [ ! -f configure ]; then
                autoreconf -i
            fi
            ./configure ${configureArgs[@]} |& log $thing configure
        ;;
    esac
    fi
    markConfigured $thing
    
    clr_blue "Building $thing"
    case $thing in
        lua )
            make $MAKEFLAGS V=1 generic CC=${TARGET_TRIPLE}-gcc AR="${TARGET_TRIPLE}-gcc-ar rcu" RANLIB=${TARGET_TRIPLE}-ranlib  |& log $thing build
        ;;
        mpv )
            if [ ! -f ${SYSROOT}/lib/libc.so ]; then
                mv ${SYSROOT}/lib/libc.so.bak ${SYSROOT}/lib/libc.so
            fi
            mv ${SYSROOT}/lib/libc.so ${SYSROOT}/lib/libc.so.bak
            ./waf build $MAKEFLAGS V=1 |& log $thing build
            mv ${SYSROOT}/lib/libc.so.bak ${SYSROOT}/lib/libc.so
        ;;
        * )
            make $MAKEFLAGS V=1 |& log $thing build
        ;;
    esac
    
    clr_blue "Installing $thing"
    case $thing in
        ffmpeg )
            sudo env PATH=$PATH make install V=1 |& log $thing install
            if [ -f ffmpeg ]; then cp ffmpeg ${OUTPUT_DIR}/ffmpeg; fi
            if [ -f ffprobe ]; then cp ffprobe ${OUTPUT_DIR}/ffprobe; fi
            if [ -f ffplay ]; then cp ffplay ${OUTPUT_DIR}/ffplay; fi

        ;;
        mpv )
            cp build/mpv  ${OUTPUT_DIR}/mpv
        ;;
        jq )
            strip --strip-all jq
            cp jq ${OUTPUT_DIR}/jq
        ;;
        aria2 )
            strip --strip-all src/aria2c
            cp src/aria2c ${OUTPUT_DIR}/aria2c
        ;;
        ffmpegthumbnailer )
            strip --strip-all ffmpegthumbnailer
            cp ffmpegthumbnailer ${OUTPUT_DIR}/ffmpegthumbnailer
        ;;
        libressl )
            strip --strip-all apps/openssl/openssl
            cp apps/openssl/openssl ${OUTPUT_DIR}/openssl
            make install |& log $thing install
        ;;
        lua )
            make install INSTALL_TOP=${SYSROOT} |& log $thing install
        ;;
        * )
            make install |& log $thing install
        ;;
    esac
    
    clr_blue "Copying license for $thing"
    case $thing in
        mpv )
            if [ "$LICENSE" == GPL ]; then
                cp ${ROOT_DIR}/sources/mpv/LICENSE.GPL ${OUTPUT_DIR}/licenses/mpv
            else
                cp ${ROOT_DIR}/sources/mpv/LICENSE.LGPL ${OUTPUT_DIR}/licenses/mpv
            fi
        ;;
        * )
            copyLicense $thing
        ;;
    esac
    
    markInstalled $thing
    
    cd $ROOT_DIR
    trap - HUP INT TERM PIPE EXIT
}


function makeMesonCrossFile() {
    _MESON_TARGET_CPU=${TARGET_ARCH/-musl/}
    case "$XBPS_TARGET_MACHINE" in
        mips|mips-musl|mipshf-musl)
            _MESON_TARGET_ENDIAN=big
            _MESON_CPU_FAMILY=mips
        ;;
        armv*)
            _MESON_CPU_FAMILY=arm
        ;;
        ppc|ppc-musl)
            _MESON_TARGET_ENDIAN=big
            _MESON_CPU_FAMILY=ppc
        ;;
        i686*)
            _MESON_CPU_FAMILY=x86
        ;;
        ppc64le*)
            _MESON_CPU_FAMILY=ppc64
        ;;
        ppc64*)
            _MESON_TARGET_ENDIAN=big
            _MESON_CPU_FAMILY=ppc64
        ;;
        *)
            _MESON_CPU_FAMILY=${_MESON_TARGET_CPU}
        ;;
    esac
    
    
		cat > ${SYSROOT}/meson.cross <<EOF
[binaries]
c = '${TARGET_TRIPLE}-gcc'
cpp = '${TARGET_TRIPLE}-g++'
ar = '${TARGET_TRIPLE}-gcc-ar'
nm = '${TARGET_TRIPLE}-nm'
ld = '${TARGET_TRIPLE}-gcc'
strip = '${TARGET_TRIPLE}-strip'
readelf = '${TARGET_TRIPLE}-readelf'
objcopy = '${TARGET_TRIPLE}-objcopy'
pkgconfig = 'pkg-config'
#exe_wrapper = '${SYSROOT}/${TARGET_TRIPLE}/lib/libc.so' # A command used to run generated executables.
[properties]
c_args = ['$(echo ${CFLAGS} | sed -r "s/\s+/','/g")']
c_link_args = ['$(echo ${LDFLAGS} | sed -r "s/\s+/','/g")']
cpp_args = ['$(echo ${CXXFLAGS} | sed -r "s/\s+/','/g")']
cpp_link_args = ['$(echo ${LDFLAGS} | sed -r "s/\s+/','/g")']
#needs_exe_wrapper = true
[host_machine]
system = 'linux'
cpu_family = '${_MESON_CPU_FAMILY}'
cpu = '${_MESON_TARGET_CPU}'
endian = '${_MESON_TARGET_ENDIAN}'
EOF
}

function licenseFilepathOf() {
    echo `jq -r .licenseFilepath $ROOT_DIR/meta/$1.json`
}

function versionOf() {
    echo `jq -r .version $ROOT_DIR/meta/$1.json`
}

function folderOf() {
    echo `jq -r .folder $ROOT_DIR/meta/$1.json`
}

function filenameOf() {
    echo `jq -r .filename $ROOT_DIR/meta/$1.json`
}

function typeOf() {
    echo `jq -r .type $ROOT_DIR/meta/$1.json`
}

function urlOf() {
    echo `jq -r .url $ROOT_DIR/meta/$1.json`
}

function modifyThing() {
    clr_red "Had to modify $2 on $1."
    tmp=$(mktemp)  
    jq ".$2 = \"$3\"" $ROOT_DIR/meta/$1.json > "$tmp"
    mv "$tmp" $ROOT_DIR/meta/$1.json
}

function copyLicense() {

    LICENSE_FILEPATH=$(licenseFilepathOf $1)
    FOLDER=${SOURCES_DIR}/$(folderOf $1)
    if [ "${LICENSE_FILEPATH}" == "null" ]; then

        if [ -f $FOLDER/LICENSE ]; then
            LICENSE_FILEPATH=LICENSE
        elif [ -f $FOLDER/COPYING ]; then
            LICENSE_FILEPATH=COPYING
        elif [ -f $FOLDER/LICENSE.md ]; then
            LICENSE_FILEPATH=LICENSE.md
        elif [ -f $FOLDER/NOTICE ]; then
            LICENSE_FILEPATH=NOTICE
        fi
        if [ "${LICENSE_FILEPATH}" == "null" ]; then
            clr_red "Cant find license file for $1... Please fix in meta/$1.json"
            return
        else   
            modifyThing $1 "licenseFilepath" "${LICENSE_FILEPATH}"
        fi
    fi
    
    if [ ! -f ${OUTPUT_DIR}/licenses/$1 ]; then
        cp ${FOLDER}/${LICENSE_FILEPATH} ${OUTPUT_DIR}/licenses/$1
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
