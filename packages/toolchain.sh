version=""
depends=()
optdepend=()

function dlsrc() {
    aria2c "http://musl.cc/${TARGET_TRIPLE}-cross.tgz"
}

function install() {
        tar xf "${TARGET_TRIPLE}-cross.tgz" -C ${SYSROOT}/ --strip-components=2  &>/dev/null
        mkdir ${SYSROOT}/installed
}