#!/bin/sh
# A build without DEV=1 must carry no dev mode. The automation URLs would let any
# web page send messages and answer calls, so this reads the linked binary rather
# than trusting the #ifs.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
make -C "$ROOT" DEV=0 ipa-armv7 > /dev/null
APP="$ROOT/build/armv7/app/LegacyTG.app"
FOUND=0
for word in TGDevShowcase TGBench TGDevModeViewController TGTestHarnessViewController \
		TGMessageToolsViewController delete_selected itg_cmd handleOpenURL: \
		"Dev Showcase" "Dev Settings" "Read a String" "Look Up a Card" \
		"Web Proxy Carrier" "Message Tools" TGGhostMode; do
	# handleOpenURL: the selector stays; its log line and routes must not.
	[ "$word" = "handleOpenURL:" ] && word="handleOpenURL: %@"
	if strings -a "$APP/LegacyTG" | grep -qF "$word"; then
		echo "FOUND in release: $word"
		FOUND=1
	fi
done
if plutil -p "$APP/Info.plist" | grep -qE 'legacytg|itglegacy'; then
	echo "FOUND in release: automation URL scheme"
	FOUND=1
fi
[ "$FOUND" = 0 ] && echo "release clean"
exit "$FOUND"
