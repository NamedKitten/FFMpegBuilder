# Architecture to build for.
TARGET_ARCH=aarch64
TARGET_TRIPLE=${TARGET_ARCH}-linux-musl

# Compilation flags
CFLAGS="-O3 -pipe"
CXXFLAGS=${CFLAGS}
LDFLAGS=${CFLAGS}

MAKEFLAGS="-j2"

# Either aria2c or curl
TARBALL_DOWNLOADER=aria2c
TARBALL_DOWNLOADER_ARGS="-s4 -x4"


# Audio
CONF_OPUS=false
CONF_FDK_AAC=false # Is nonfree. Will make binarys non-redistributable.
CONF_MP3=false
CONF_OGG=false
CONF_VORBIS=false # Requires OGG

# Video
CONF_PNG=false # Needed for album art sometimes.
CONF_X264=false # Will make resulting binarys GPL licensed.
CONF_VPX=false

# Libraries
CONF_ZLIB=true # Needed for PNG in FFMpeg, libjpeg and libpng for ffmpegthumbnailer
CONF_LIBJPEG=false
CONF_LIBPNG=false
CONF_ALSA_LIB=false # Needed for mpv audio output with ALSA
CONF_LIBSNDFILE=false
CONF_JACK=false
CONF_SSL=false
CONF_LUA=false # Needed for youtube-dl support on MPV
CONF_LIBASS=false # Needed for subtitles and OSD on MPV
CONF_LIBCACA=false # Terminal output for MPV


# Tools
CONF_FFMPEG=true 
CONF_FFMPEGTHUMBNAILER=false
CONF_MPV=true
# CONF_MPV requirements: CONF_FFMPEG=true CONF_ZLIB=true
