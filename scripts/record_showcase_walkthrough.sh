#!/usr/bin/env bash
#
# scripts/record_showcase_walkthrough.sh
# Automates scrolling through all 30 TDLib message types in the dev showcase while recording screen.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_MP4="$ROOT/build/recordings/full_showcase.mp4"
OUT_GIF="$ROOT/build/recordings/full_showcase.gif"
SSH_HOST="itgphone"

echo "[+] Preparing walkthrough script on device..."
ssh "$SSH_HOST" "cat << 'EOF' > /tmp/walkthrough.sh
#!/bin/sh
sbunlock --cmd 'row/0'
sleep 3.0
sbunlock --cmd 'row/6'
sleep 4.0
sbunlock --cmd 'row/11'
sleep 3.5
sbunlock --cmd 'row/16'
sleep 3.5
sbunlock --cmd 'row/20'
sleep 3.5
sbunlock --cmd 'row/25'
sleep 3.5
sbunlock --record-stop
EOF
chmod +x /tmp/walkthrough.sh
"

echo "[+] Bringing LegacyTG to foreground and launching showcase..."
ssh "$SSH_HOST" "sbunlock"
sleep 0.5
ssh "$SSH_HOST" "openapp org.legacy.itg"
sleep 1.5
ssh "$SSH_HOST" "sbunlock --cmd 'dev'"
sleep 1.5
ssh "$SSH_HOST" "sbunlock --cmd 'row/0'"
sleep 1.0

echo "[+] Starting capture on device (35s safety window)..."
ssh "$SSH_HOST" "sbunlock --record 35 10"

START_TIME=$(date +%s)

echo "[+] Running automated walkthrough sequence on device..."
ssh "$SSH_HOST" "/tmp/walkthrough.sh"

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))
if [ "$DURATION" -lt 1 ]; then DURATION=18; fi
echo "[+] Walkthrough finished in ${DURATION}s. Fetching frames..."

# Pull frames from device
TMPDIR="$(mktemp -d /tmp/itg_screen_record.XXXXXX)"
cleanup() {
    rm -rf "$TMPDIR"
    ssh "$SSH_HOST" "rm -rf /tmp/cap /tmp/cap_cfg.txt /tmp/walkthrough.sh" 2>/dev/null || true
}
trap cleanup EXIT

ssh "$SSH_HOST" "tar -C /tmp/cap -cf - ." 2>/dev/null | tar -C "$TMPDIR" -xf - 2>/dev/null || true

FRAME_COUNT="$(ls "$TMPDIR"/frame_*.jpg 2>/dev/null | wc -l | tr -d ' ')"
if [ "$FRAME_COUNT" -eq 0 ]; then
    echo "[-] No frames captured! Make sure SpringBoard has AutoUnlock loaded." >&2
    exit 1
fi
echo "[+] Downloaded $FRAME_COUNT frames."

# Calculate real recorded framerate so video matches real time 1:1
ACTUAL_FPS=$(awk "BEGIN { fps = $FRAME_COUNT / $DURATION; if (fps < 1.0) fps = 1.0; printf \"%.2f\", fps }")
echo "[+] Real capture framerate: ${ACTUAL_FPS} fps (duration: ${DURATION}s)"

# Encode to MP4 with ffmpeg
mkdir -p "$(dirname "$OUT_MP4")"
echo "[+] Encoding video with ffmpeg..."
ffmpeg -y -framerate "$ACTUAL_FPS" -i "$TMPDIR/frame_%04d.jpg" -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$OUT_MP4" >/dev/null 2>&1

echo "[✓] Screen recording saved to: $OUT_MP4 ($(du -h "$OUT_MP4" | cut -f1))"

echo "[+] Generating animated GIF: $OUT_GIF..."
ffmpeg -y -i "$OUT_MP4" -vf "fps=${ACTUAL_FPS},scale=320:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" "$OUT_GIF" >/dev/null 2>&1
echo "[✓] GIF saved to: $OUT_GIF ($(du -h "$OUT_GIF" | cut -f1))"

echo "[✓] Complete showcase walkthrough recording successfully generated!"
echo "    MP4: $OUT_MP4"
echo "    GIF: $OUT_GIF"
