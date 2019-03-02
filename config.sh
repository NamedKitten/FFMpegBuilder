# Architecture to build for.
TARGET_ARCH=x86_64
TARGET_TRIPLE=${TARGET_ARCH}-linux-musl

# Compilation flags
CFLAGS="-Os -pipe"
CXXFLAGS=${CFLAGS}
LDFLAGS=${CFLAGS}

# Audio
CONF_OPUS=true
CONF_AAC=true
CONF_FLAC=true
CONF_MP3=true

# Video
CONF_PNG=true # Needed for album art sometimes.
CONF_MJPEG=true # Needed for album art sometimes.


