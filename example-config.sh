# Architecture to build for.
TARGET_ARCH=x86_64
TARGET_TRIPLE=${TARGET_ARCH}-linux-musl

# Compilation flags
CFLAGS="-O2"
CXXFLAGS=${CFLAGS}
LDFLAGS="${CFLAGS}"

MAKEFLAGS="-j$(nproc)"

# Either aria2c or curl
TARBALL_DOWNLOADER=aria2c
TARBALL_DOWNLOADER_ARGS="-s4 -x4"


# Audio
CONF_ALSA_LIB=true # for alsa output 
CONF_OPUS=true
CONF_FDK_AAC=false # Is nonfree. Will make binarys non-redistributable.
CONF_MP3=true
CONF_OGG=true
CONF_VORBIS=true # Requires OGG

# Video
CONF_PNG=true # Needed for album art sometimes.
CONF_X264=true # Will make resulting binarys GPL licensed.
CONF_VPX=true

# Libraries
CONF_ZLIB=true # Needed for PNG in FFMpeg, libjpeg and libpng for ffmpegthumbnailer
CONF_LIBJPEG=true
CONF_LIBPNG=true
CONF_LIBSNDFILE=true
CONF_SSL=true
CONF_LUA=true # Needed for youtube-dl support on MPV
CONF_LIBASS=true # Needed for subtitles and OSD on MPV
CONF_LIBCACA=true # Terminal output for MPV


# Tools
CONF_FFMPEG=true
CONF_FFMPEGTHUMBNAILER=true
CONF_MPV=true
# CONF_MPV requirements: CONF_FFMPEG=true CONF_ZLIB=true
CONF_JQ=true
CONF_ARIA2=true

