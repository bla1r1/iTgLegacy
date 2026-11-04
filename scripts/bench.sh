#!/bin/bash
# bench.sh - scroll and open chats on the device with nobody holding it, and
# say where the main thread spent the time.
#
#   ./scripts/bench.sh                launch cold, run the suite, report
#   ./scripts/bench.sh --no-launch    run against the app as it is now
#   ./scripts/bench.sh --prof         also sample stacks (adds ~5% load)
#
# Exits 1 when a run is over budget, so it doubles as the regression test for
# what a host test cannot see (CoreAnimation, backboardd). Budgets are the
# iPod touch 4 plus headroom: chat scroll was 33% dropped frames with a
# 277 ms worst before the layer work, 9-10% / ~50 ms after. For scale, the
# plain grouped Settings table drops 13-22% on the same phone: backboardd
# needs ~3 s of every 8 to recomposite a moving 640x960 screen.
#
# Needs the app installed (devrun.sh) and the itgphone ssh block.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/bench/$(date +%Y%m%d-%H%M%S)"
SSH="ssh -o ConnectTimeout=6 -o BatchMode=yes itgphone"
BIN="$ROOT/build/armv7/app-dev/LegacyTG.app/LegacyTG"
LAUNCH=1
PROF=""
while [ $# -gt 0 ]; do
	case "$1" in
		--no-launch) LAUNCH=0; shift ;;
		--prof) PROF="/prof"; shift ;;
		*) echo "unknown option: $1"; exit 2 ;;
	esac
done
mkdir -p "$OUT"

$SSH true 2>/dev/null || { iproxy 2222 22 >/dev/null 2>&1 & sleep 2; }
open_url() { $SSH "uiopen 'itglegacy://$1'"; }

idevicesyslog 2>/dev/null | grep --line-buffered -E "LegacyTG|\[perf\]|\[bench\]" > "$OUT/syslog.log" &
LOGPID=$!
trap 'kill $LOGPID 2>/dev/null' EXIT

if [ "$LAUNCH" = 1 ]; then
	$SSH "killall LegacyTG 2>/dev/null; rm -f /var/mobile/Applications/*/Library/Caches/bench-*.txt \
		/private/var/mobile/Library/Caches/bench-*.txt; true"
	sleep 2
	open_url ""
	# TDLib opens its database and fetches the chat list before anything is
	# worth timing; 20 s covers the 3GS-class devices.
	sleep 20
fi

# Each step waits its run out plus a margin; a URL sent mid-run is refused.
open_url "tab/0";                     sleep 2
open_url "bench/scroll/8$PROF";       sleep 11
open_url "scroll/0";                  sleep 1
for row in 0 1 2; do
	open_url "bench/open/$row$PROF";  sleep 7
done
open_url "chatindex/0";               sleep 4
# Twice: the first pass pays one-time costs (a sticker build is 100-500 ms on
# a background queue, the first emoji measure ~70 ms) that the second does not.
open_url "bench/scroll/8$PROF";       sleep 11
open_url "bench/scroll/8$PROF";       sleep 11
open_url "tab/0";                     sleep 1

kill $LOGPID 2>/dev/null
echo "=== results"
# idevicesyslog replays the device's buffer first; only this run counts.
awk -v launch="$LAUNCH" 'launch == 1 && /Starting application/ { n = 0; delete keep }
	/\[bench\]|\[perf\]/ { keep[n++] = $0 } END { for (i = 0; i < n; i++) print keep[i] }' "$OUT/syslog.log" \
	| grep -av "\] dump " | sed 's/.*LegacyTG[^:]*: //' | tee "$OUT/summary.txt"

if [ -n "$PROF" ]; then
	for remote in $($SSH "ls /var/mobile/Applications/*/Library/Caches/bench-*.txt \
			/private/var/mobile/Library/Caches/bench-*.txt 2>/dev/null"); do
		local_f="$OUT/$(basename "$remote")"
		scp -q -o BatchMode=yes "itgphone:$remote" "$local_f"
		echo
		echo "=== $(basename "$remote" .txt)"
		python3 "$ROOT/scripts/bench_report.py" "$local_f" "$BIN" | tee "${local_f%.txt}.report"
	done
fi
echo
echo "saved in $OUT"

# what, max dropped %, max worst frame ms, which run (head or tail)
check() {
	grep -a "\[bench\] $1 first" "$OUT/summary.txt" | ${4:-tail} -1 | awk -v what="$1" -v pct="$2" -v worst="$3" '
		{ match($0, /\(([0-9]+)%\)/); d = substr($0, RSTART + 1, RLENGTH - 3) + 0
		  match($0, /worst=[0-9]+/); w = substr($0, RSTART + 6, RLENGTH - 6) + 0
		  if (d > pct || w > worst) { printf "OVER BUDGET %s: %d%% dropped (max %d), worst %d ms (max %d)\n", what, d, pct, w, worst; bad = 1 } }
		END { exit bad }'
}
status=0
# No check on the chat list: on the showcase account it is shorter than the
# screen, so its "scroll" never moves and always reads 60 fps.
check scroll-TGChatViewController 20 250 head || status=1
check scroll-TGChatViewController 15 100 tail || status=1
check open-1 10 80 || status=1
[ "$status" = 0 ] && echo "within budget"
exit $status
