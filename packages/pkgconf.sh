version="1.1.0"
depends=("toolchain")
optdepend=()

function dlsrc() {
    aria2c https://distfiles.dereferenced.org/pkgconf/pkgconf-${version}.tar.xz
    tar xf pkgconf-${version}.tar.xz
}


function configure() {
    cd pkgconf-${version}
    CC=gcc CXX=g++ LD=gcc ./configure --prefix=${SYSROOT} --enable-static --disable-shared
    cd ..
}

function build() {
    cd pkgconf-${version}
    make -j5
    cd ..
}

function install() {
    cd pkgconf-${version}
    make install
    ln -sf ${SYSROOT}/bin/pkgconf ${SYSROOT}/bin/${TARGET_TRIPLE}-pkgconf
    ln -sf ${SYSROOT}/bin/pkgconf ${SYSROOT}/bin/${TARGET_TRIPLE}-pkg-config
    ln -sf ${SYSROOT}/bin/pkgconf ${SYSROOT}/bin/pkg-config
    cd ..
}