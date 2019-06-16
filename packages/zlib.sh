version="develop"
depends=("toolchain")
optdepend=()

function dlsrc() {
    git clone -b $version --depth=1 https://github.com/zlib-ng/zlib-ng zlib
}

function configure() {
    cd zlib
    ./configure --prefix=${SYSROOT}  --zlib-compat --static
    cd ..
}

function build() {
    cd zlib
    make -j5
    cd ..
}

function install() {
    cd zlib
    make install
    cd ..
}