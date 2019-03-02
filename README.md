# FFMPEG Builder
Hi!

This is my script I use to build fully static FFMpeg binaries.

It statically links to the musl libc which is a great libc for static linking because it is so small.

You can configure it in config.sh to enable codecs or change the architecture to build for.

You need a x86_64 compatable computer to use this script as it uses the toolchains from https://musl.cc which only run on that architecture.

If you want to build for another OS or look at https://musl.cc/ and see the supported toolchains and pick a ARCH and TARGET_TRIPLE for the config file that fits the system you want to compile for.

If you want a codec or format that ffmpeg supports to be added to this script then just contact me or submit a issue! :3

- Kitteh

Contact information avalable on https://namedkitten.pw

