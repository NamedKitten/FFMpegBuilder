version="3.100"
depends=("toolchain")
optdepend=()

function dlsrc() {
    aria2chttps://downloads.sourceforge.net/project/lame/lame/${version}/lame-${version}.tar.gz
    tar xf lame-${version}.tar.gz
}


function configure() {
    cd lame-${version}
    ./configure --host=${TARGET_TRIPLE} --prefix=${SYSROOT} --disable-shared --enable-static --disable-frontend --disable-decoder --enable-nasm
    cd ..
}

function build() {
    cd lame-${version}
    make -j5
    cd ..
}

function install() {
    cd lame-${version}
    make install
    cd ..
}