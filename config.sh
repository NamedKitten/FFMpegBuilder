# Architecture to build for.
TARGET_ARCH=x86_64
TARGET_TRIPLE=${TARGET_ARCH}-linux-musl

# Compilation flags
CFLAGS="-Os -pipe -static"
CXXFLAGS=${CFLAGS}
LDFLAGS=${CFLAGS}

# Either aria2c or curl
TARBALL_DOWNLOADER=aria2c
TARBALL_DOWNLOADER_ARGS="-s4 -x4"


# Audio
CONF_OPUS=true
CONF_AAC=true
CONF_FDK_AAC=false # Is nonfree. Will make binarys non-redistributable.
CONF_FLAC=true
CONF_MP3=true
CONF_OGG=true
CONF_VORBIS=true # Requires OGG

# Video
CONF_PNG=false # Needed for album art sometimes.
CONF_MJPEG=false # Needed for album art sometimes.
CONF_X264=false # Will make resulting binarys GPL licensed.
CONF_VPX=false

# Formats
CONF_MKV=false
CONF_WEBM=false
CONF_MP4=false
CONF_MOV=false

# Libraries
CONF_ZLIB=true # Needed for PNG in FFMpeg, libjpeg and libpng for ffmpegthumbnailer
CONF_LIBJPEG=true
CONF_LIBPNG=true
CONF_ALSA_LIB=true # Needed for mpv audio output with ALSA
CONF_LIBSNDFILE=true
CONF_JACK=true
CONF_XORG=true # Needed for xorg video output with MPV
CONF_SSL=true
CONF_LUA=true # Needed for youtube-dl support on MPV
CONF_LIBASS=true # Needed for subtitles and OSD on MPV
CONF_LIBCACA=true # Terminal output for MPV
CONF_SDL2=true


# Tools
CONF_FFMPEG=true
CONF_FFPROBE=true
CONF_FFMPEGTHUMBNAILER=false
CONF_MPV=true
