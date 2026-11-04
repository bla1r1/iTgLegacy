#!/bin/bash
# FFmpeg for the software video player on Vintage devices, whose decoder stops at
# H.264 Main: H.264, AAC and MP4 only, static, armv7 Thumb-2 with NEON (machofix
# sets the Thumb bit on every pointer into __text, so the asm has to be Thumb).
# Output: build/armv7/ffmpeg/{lib,include}. LGPL: this script is how to relink it.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/build/src/ffmpeg"
OUT="$ROOT/build/armv7/ffmpeg"
SDK="$ROOT/build/sdks/iPhoneOS15.6.sdk"
CLANG="$(xcrun -f clang)"
[ -d "$SRC" ] || git clone --depth 1 --branch n6.1.1 https://github.com/FFmpeg/FFmpeg.git "$SRC"
# .Lpic is a named symbol on Mach-O, where local labels start with L, and ld asserts
# on a non-lazy pointer that has a name.
sed -i '' 's/\.Lpic\\@/Lpic\\@/g' "$SRC/libavutil/arm/asm.S"
OBJ="$ROOT/build/armv7/ffmpeg-obj"
rm -rf "$OBJ" "$OUT"; mkdir -p "$OBJ"; cd "$OBJ"
FL="-arch armv7 -mthumb -mcpu=cortex-a8 -mfpu=neon -miphoneos-version-min=6.0 -isysroot $SDK -O2"
"$SRC/configure" --prefix="$OUT" --enable-cross-compile --target-os=darwin --arch=arm --cpu=cortex-a8 \
	--cc="$CLANG" --as="$CLANG" --sysroot="$SDK" --extra-cflags="$FL" --extra-ldflags="$FL" \
	--enable-thumb --enable-neon --enable-pic --disable-pthreads --disable-programs --disable-doc --disable-debug \
	--disable-avdevice --disable-avfilter --disable-swscale --disable-swresample --disable-network --disable-iconv \
	--disable-zlib --disable-bzlib --disable-lzma --disable-sdl2 --disable-securetransport --disable-videotoolbox \
	--disable-audiotoolbox --disable-coreimage --disable-appkit --disable-avfoundation --disable-everything \
	--enable-decoder=h264,aac --enable-parser=h264,aac --enable-demuxer=mov --enable-protocol=file \
	--enable-static --disable-shared > configure.log
make -j8 > make.log
make install > install.log
ls -la "$OUT/lib"
