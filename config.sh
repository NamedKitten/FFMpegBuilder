# Architecture to build for.
TARGET_ARCH=x86_64
TARGET_TRIPLE=${TARGET_ARCH}-linux-musl

# Compilation flags
CFLAGS="-Ofast -pipe -march=native -DFLOAT_APPROX"
CXXFLAGS=${CFLAGS}
LDFLAGS=${CFLAGS}

# Audio
CONF_OPUS=true
CONF_AAC=true
CONF_FDK_AAC=false # Is nonfree. Will make binarys non-redistributable.
CONF_FLAC=true
CONF_MP3=true
CONF_OGG=true
CONF_VORBIS=true # Requires OGG

# Video
CONF_PNG=true # Needed for album art sometimes.
CONF_MJPEG=true # Needed for album art sometimes.
CONF_X264=true # Will make resulting binarys GPL licensed.
CONF_VPX=true

# Formats
CONF_MKV=true
CONF_WEBM=true
CONF_MP4=true
CONF_MOV=true

# Libraries
CONF_ZLIB=true # Needed for PNG in FFMpeg, libjpeg and libpng for ffmpegthumbnailer
CONF_LIBJPEG=true # Needed for ffmpegthumbnailer
CONF_LIBPNG=true # Needed for ffmpegthumbnailer

# Tools
CONF_FFMPEG=true
CONF_FFPROBE=true
CONF_FFMPEGTHUMBNAILER=true
