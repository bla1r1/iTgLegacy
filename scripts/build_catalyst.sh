#!/bin/bash
# build_catalyst.sh - build and run LegacyTG as a Mac Catalyst app.
#
#   ./scripts/build_catalyst.sh           build, sign, launch
#   ./scripts/build_catalyst.sh --no-run  build only
#   ./scripts/build_catalyst.sh --shot    build, launch, screenshot the window
#
# This is a probe, not a shipping target. It answers one question - does the
# app's own UI code stand up on macOS - and it answers yes: all 113 sources
# compile for arm64-apple-ios*-macabi untouched. What it does NOT carry:
#
#   * TDLib. TGClient dlopens libtdjson and reports "unavailable" when it is
#     missing, so the app starts with no network and opens the Dev Showcase.
#   * Calls, voice, WebM and WebP - their libraries (libtgvoip, opus, vpx,
#     libwebp) have no macabi build, so those four files are left out and
#     tools/catalyst/catalyst_stubs.m stands in for the classes.
#   * AddressBook and AssetsLibrary, which Catalyst does not have at all. A
#     real Mac target replaces them with Contacts and PhotoKit.
#
# Everything the stubs cover is listed in tools/catalyst/catalyst_stubs.m,
# and that file IS the to-do list for a shipping Mac build.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${ROOT}/build/catalyst"
APP="${OUT}/LegacyTG.app"
OBJ="${OUT}/obj"
DEPLOY_TARGET="14.0"          # AVCaptureDeviceInput is macCatalyst 14.0+
JOBS="$(sysctl -n hw.ncpu)"

DO_RUN=1
DO_SHOT=0
for arg in "$@"; do
	case "$arg" in
		--no-run) DO_RUN=0 ;;
		--shot)   DO_SHOT=1 ;;
		*) echo "unknown option: $arg"; exit 2 ;;
	esac
done

SDK="$(xcrun --sdk macosx --show-sdk-path)"
[ -d "$SDK" ] || { echo "no macOS SDK - install Xcode"; exit 1; }
[ -d "$SDK/System/iOSSupport/System/Library/Frameworks/UIKit.framework" ] || {
	echo "this SDK has no iOSSupport, so it cannot build Catalyst"; exit 1; }

# The files whose third-party libraries have no macabi build.
SKIP="src/Views/UIImage+WebP.m src/Views/TGWebMDecoder.m src/Audio/TGVoiceDecoder.m src/Audio/TGStreamingVoicePlayer.m src/Audio/TGVoiceRecorder.mm src/Views/TGLottieView.mm src/Calls/TGCall.mm src/Calls/TGCallAudioEngine.mm src/Calls/TGCallIce.m src/Calls/TGCallStun.m src/Calls/TGCallMessages.m src/Calls/TGCallReflector.m"

FLAGS="-target arm64-apple-ios${DEPLOY_TARGET}-macabi
	-isysroot ${SDK}
	-iframework ${SDK}/System/iOSSupport/System/Library/Frameworks
	-isystem ${SDK}/System/iOSSupport/usr/include
	-I${ROOT}/include -I${ROOT}/compat -I${ROOT}/libs -I${ROOT}/src
	-I${ROOT}/src/Core -I${ROOT}/src/Controllers -I${ROOT}/src/Views
	-I${ROOT}/src/UI -I${ROOT}/src/Calls -I${ROOT}/src/Audio
	-I${ROOT}/third_party -I${ROOT}/third_party/libvpx/include
	-I${ROOT}/third_party/nestegg/include -I${ROOT}/third_party/ogg
	-I${ROOT}/third_party/ogg/ogg -I${ROOT}/third_party/opus/include
	-I${ROOT}/third_party/opus/include/opus -I${ROOT}/third_party/opusenc
	-I${ROOT}/third_party/opusfile -I${ROOT}/tdlib/td -I${ROOT}/tdlib/include
	-F${ROOT}/libs -fobjc-arc -O1 -w"
# One line, because the command list below is fed to xargs line by line.
FLAGS=$(echo $FLAGS)

cd "$ROOT"
mkdir -p "$OBJ" "$APP/Contents/MacOS" "$APP/Contents/Resources"

sources() {
	ls src/*/*.m src/*/*.mm src/*.m 2>/dev/null
	# The C core the on-device build links as well: icon SVG paths and the
	# perf sampler TGBench reads.
	echo "src/Core/TGSVGPath.c"
	echo "src/Core/TGSampler.c"
	echo "src/Core/TGUpdateType.c"
	echo "third_party/yyjson/yyjson.c"
	echo "compat/tlv_polyfill.c"
	echo "tools/catalyst/catalyst_stubs.m"
}

echo "[+] compiling for Catalyst (iOS ${DEPLOY_TARGET} macabi, ${JOBS} jobs)"
: > "$OUT/objs.txt"
: > "$OUT/failed.txt"
pids=""
running=0
for f in $(sources); do
	case " $SKIP " in *" $f "*) continue ;; esac
	o="$OBJ/$(echo "$f" | tr '/' '_').o"
	echo "$o" >> "$OUT/objs.txt"
	(
		if [[ "$f" == *.mm ]]; then
			xcrun clang++ $FLAGS -std=c++14 -stdlib=libc++ -c "$f" -o "$o" 2>"$o.log"
		else
			xcrun clang $FLAGS -c "$f" -o "$o" 2>"$o.log"
		fi
		[ $? -eq 0 ] || echo "$f" >> "$OUT/failed.txt"
	) &
	# bash 3.2 ships with macOS and has no `wait -n`, so the oldest job in the
	# queue is the one waited on. Close enough with 113 files of similar size.
	pids="$pids $!"
	running=$((running + 1))
	if [ "$running" -ge "$JOBS" ]; then
		set -- $pids
		wait "$1" 2>/dev/null
		shift
		pids="$*"
		running=$((running - 1))
	fi
done
wait

missing=0
while read -r o; do [ -f "$o" ] || { echo "[!] never built: $o"; missing=1; }; done < "$OUT/objs.txt"
[ "$missing" -eq 0 ] || exit 1
echo "    $(wc -l < "$OUT/objs.txt" | tr -d ' ') objects, no errors"

echo "[+] linking"
xcrun clang++ \
	-target "arm64-apple-ios${DEPLOY_TARGET}-macabi" -isysroot "$SDK" \
	-iframework "${SDK}/System/iOSSupport/System/Library/Frameworks" \
	-stdlib=libc++ $(tr '\n' ' ' < "$OUT/objs.txt") \
	-framework UIKit -framework Foundation -framework QuickLook \
	-framework SystemConfiguration -framework CoreGraphics -framework QuartzCore \
	-framework MediaPlayer -framework AVFoundation -framework AudioToolbox \
	-framework CoreMedia -framework CoreLocation -framework MapKit \
	-framework CoreImage -framework CoreText -framework ImageIO \
	-framework CoreServices -lz \
	-o "$APP/Contents/MacOS/LegacyTG" || exit 1

cp -f "$ROOT/tools/catalyst/Info.plist" "$APP/Contents/Info.plist"
cp -f "$ROOT/resources/fonts/OpenMoji.ttf" "$APP/Contents/Resources/"
codesign -s - --force --deep "$APP" >/dev/null 2>&1
echo "    $APP  ($(du -h "$APP/Contents/MacOS/LegacyTG" | cut -f1))"

[ "$DO_RUN" -eq 1 ] || exit 0

pkill -f "LegacyTG.app/Contents/MacOS/LegacyTG" 2>/dev/null
# The app points stderr at its own log in Caches, so nothing lands here.
"$APP/Contents/MacOS/LegacyTG" >/dev/null 2>&1 &
sleep 6

if pgrep -f "LegacyTG.app/Contents/MacOS/LegacyTG" >/dev/null; then
	echo "[+] running"
else
	echo "[!] it started and died - newest crash report:"
	ls -t ~/Library/Logs/DiagnosticReports/LegacyTG*.ips 2>/dev/null | head -1
	exit 1
fi

if [ "$DO_SHOT" -eq 1 ]; then
	osascript -e 'tell application "System Events" to set frontmost of (first process whose name contains "LegacyTG") to true' >/dev/null 2>&1
	sleep 2
	screencapture -x -o "$OUT/catalyst-showcase.png"
	echo "[+] $OUT/catalyst-showcase.png"
fi
