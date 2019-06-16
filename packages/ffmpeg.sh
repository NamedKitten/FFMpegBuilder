version="4.1"
depends=("toolchain")
optdepend=("zlib")

function dlsrc() {
    aria2c http://ffmpeg.org/releases/ffmpeg-${version}.tar.bz2
    tar xf ffmpeg-${version}.tar.bz2
}


function configure() {
    cd ffmpeg-${version}
    ./configure --prefix=${SYSROOT} --target-os=linux --arch=${TARGET_ARCH} --enable-cross-compile --cross-prefix=${TARGET_TRIPLE}- --prefix=${SYSROOT} --libdir=${SYSROOT}/lib --enable-static --disable-shared --pkg-config=pkgconf --disable-htmlpages --disable-manpages --disable-doc
    cd ..
}

function build() {
    cd ffmpeg-${version}
    make -j5
    cd ..
}

function install() {
    cd ffmpeg-${version}
    make install
    cd ..
}