#!/bin/bash
# shoot_settings.sh - photograph every settings page on the device.
#
#   ./scripts/shoot_settings.sh             build, install, launch, shoot all
#   ./scripts/shoot_settings.sh --no-build  the app is already the right build
#   ./scripts/shoot_settings.sh --theme night   shoot the set in one theme
#
# Pages are opened through itglegacy://settings/<n>, which is TGSettingsPage:
# driving them by row index goes stale the moment a setting is added, and the
# debug menu is behind ten taps on a label that no URL can reach.
#
# Output: build/shots/<theme>/<nn>-<name>.png

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH_HOST=itgphone
SSH_PORT=2222
SSH_OPTS="-o ConnectTimeout=6 -o BatchMode=yes"
BUNDLE_ID="org.legacy.itg"
IPA="$ROOT/build/ipa/LegacyTG-armv7.ipa"

DO_BUILD=1
THEMES="day night"

while [ $# -gt 0 ]; do
	case "$1" in
		--no-build) DO_BUILD=0; shift ;;
		--theme)    THEMES="$2"; shift 2 ;;
		*) echo "unknown option: $1"; exit 2 ;;
	esac
done

say() { printf '\n=== %s\n' "$*"; }

ssh_ready() {
	if ! ssh $SSH_OPTS "$SSH_HOST" true 2>/dev/null; then
		pkill -f "iproxy $SSH_PORT" 2>/dev/null
		iproxy "$SSH_PORT" 22 >/dev/null 2>&1 &
		echo $! > /tmp/.itg_iproxy_pid
		sleep 2
		ssh $SSH_OPTS "$SSH_HOST" true 2>/dev/null || return 1
	fi
	return 0
}
cleanup() {
	[ -f /tmp/.itg_iproxy_pid ] && kill "$(cat /tmp/.itg_iproxy_pid)" 2>/dev/null
	rm -f /tmp/.itg_iproxy_pid
}
trap cleanup EXIT

url() { ssh $SSH_OPTS "$SSH_HOST" "uiopen '$1' >/dev/null 2>&1"; }

# Ask the app to photograph itself and pull the file. The app writes to a fixed
# path, so a stale file from a previous run looks exactly like a fresh one -
# hence the age check.
shot() {
	local out="$1"
	url "itglegacy://screenshot"
	sleep 2
	local remote
	remote="$(ssh $SSH_OPTS "$SSH_HOST" \
		'ls -t /var/mobile/Applications/*/Library/Caches/screen.png 2>/dev/null | head -1')"
	[ -n "$remote" ] || { echo "  no screenshot written"; return 1; }

	local age
	age="$(ssh $SSH_OPTS "$SSH_HOST" \
		"expr \$(date +%s) - \$(date -r '$remote' +%s 2>/dev/null || echo 0)")"
	if [ -z "$age" ] || [ "$age" -gt 30 ]; then
		echo "  stale (${age}s) - the app did not answer"
		return 1
	fi
	scp $SSH_OPTS "$SSH_HOST:$remote" "$out" >/dev/null 2>&1 && echo "  $out"
}

# page number : file name : how far down to scroll before shooting
PAGES=(
	"  : 00-root            : 0"
	"  : 01-root-scrolled   : 260"
	"3 : 02-notifications   : 0"
	"4 : 03-privacy         : 0"
	"4 : 04-privacy-scrolled: 240"
	"2 : 05-data-storage    : 0"
	"1 : 06-appearance      : 0"
	"1 : 07-appearance-themes: 300"
	"7 : 08-power-saving    : 0"
	"5 : 09-language        : 0"
	"6 : 10-blocked-users   : 0"
	"8 : 11-recent-calls    : 0"
	"9 : 12-debug-menu      : 0"
	"9 : 13-debug-scrolled  : 240"
)

if [ "$DO_BUILD" = 1 ]; then
	say "building"
	make -C "$ROOT" ipa-armv7 > /tmp/itg-build.log 2>&1 || {
		grep -iE "error:" /tmp/itg-build.log | head; exit 1; }
	grep "machofix:" /tmp/itg-build.log
	say "installing"
	ideviceinstaller install "$IPA" 2>&1 | tail -2
fi

ssh_ready || { echo "no ssh to the device" >&2; exit 1; }

say "launching"
ssh $SSH_OPTS "$SSH_HOST" "killall LegacyTG 2>/dev/null || killall iTgLegacy 2>/dev/null; true"
sleep 2
url "legacytg://" || url "itglegacy://" || { echo "could not launch" >&2; exit 1; }
sleep 12          # TDLib needs a moment before the account is loaded

for theme in $THEMES; do
	outdir="$ROOT/build/shots/$theme"
	mkdir -p "$outdir"
	say "theme: $theme"
	url "itglegacy://theme/$theme"
	sleep 2

	for entry in "${PAGES[@]}"; do
		page="$(echo "${entry%%:*}" | tr -d ' ')"
		rest="${entry#*:}"
		name="$(echo "${rest%%:*}" | tr -d ' ')"
		offset="$(echo "${rest##*:}" | tr -d ' ')"

		echo "$name"
		url "itglegacy://settings/$page"
		sleep 2
		# Always, including 0: the root page is one long-lived controller and
		# keeps whatever offset the previous pass left it at.
		url "itglegacy://scroll/$offset"
		sleep 1
		shot "$outdir/$name.png"
	done

	# Two screens are reached by a row rather than by a page number: Storage
	# hangs off Data and Storage, Edit Profile off the root.
	echo "14-storage-usage"
	url "itglegacy://settings/2"; sleep 2
	url "itglegacy://tap/0/0";    sleep 6   # the walk over the database is slow
	shot "$outdir/14-storage-usage.png"

	echo "15-edit-profile"
	url "itglegacy://settings/";  sleep 2
	url "itglegacy://tap/3/1";    sleep 3
	shot "$outdir/15-edit-profile.png"

	echo "16-edit-profile-scrolled"
	url "itglegacy://scroll/220"; sleep 1
	shot "$outdir/16-edit-profile-scrolled.png"
done

say "done"
ls -R "$ROOT/build/shots" 2>/dev/null
