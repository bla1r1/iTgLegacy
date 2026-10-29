#!/bin/bash
# scripts/record_screen.sh - Record smooth screen video from connected iPhone 4S
# Captures display frames without saving anything to the device photo gallery.
#
# Usage:
#   ./scripts/record_screen.sh [options] [output.mp4]
#
# Options:
#   --duration SECONDS   Duration of the recording in seconds (default: 5)
#   --fps FPS            Frames per second (default: 10)
#   --out PATH           Output MP4 file path
#   --gif                Also generate an animated GIF for quick web preview
#   --open               Open video player on Mac when recording finishes

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH_HOST="itgphone"
SSH_PORT="2222"
SSH_OPTS="-o ConnectTimeout=6 -o BatchMode=yes"

DURATION=5
FPS=10
OUTPUT=""
GEN_GIF=0
DO_OPEN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --duration|-d)
            DURATION="$2"; shift 2 ;;
        --fps|-f)
            FPS="$2"; shift 2 ;;
        --out|-o)
            OUTPUT="$2"; shift 2 ;;
        --gif|-g)
            GEN_GIF=1; shift ;;
        --open)
            DO_OPEN=1; shift ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1 ;;
        *)
            OUTPUT="$1"; shift ;;
    esac
done

if [ -z "$OUTPUT" ]; then
    STAMP="$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$ROOT/build/recordings"
    OUTPUT="$ROOT/build/recordings/record-$STAMP.mp4"
else
    mkdir -p "$(dirname "$OUTPUT")"
fi

echo "=== iPhone Screen Recorder ==="
echo "Target: $SSH_HOST (Port: $SSH_PORT)"
echo "Duration: ${DURATION}s | Framerate: ${FPS} fps"
echo "Output: $OUTPUT"

# Ensure SSH connection
if ! ssh $SSH_OPTS "$SSH_HOST" true 2>/dev/null; then
    echo "[!] SSH not responding, starting iproxy..."
    pkill -f "iproxy $SSH_PORT" 2>/dev/null || true
    iproxy "$SSH_PORT" 22 >/dev/null 2>&1 &
    sleep 2
    ssh $SSH_OPTS "$SSH_HOST" true || { echo "[-] Failed to connect to device over SSH." >&2; exit 1; }
fi

# Ensure device is unlocked and screen is awake
ssh $SSH_OPTS "$SSH_HOST" "sbunlock" >/dev/null 2>&1 || true

# Start recording via AutoUnlock & sbunlock
echo "[+] Starting capture on device..."
ssh $SSH_OPTS "$SSH_HOST" "sbunlock --record $DURATION $FPS"

# Wait for capture duration
echo "[+] Recording ${DURATION}s in progress..."
sleep "$DURATION"
sleep 1

# Pull frames from device
TMPDIR="$(mktemp -d /tmp/itg_screen_record.XXXXXX)"
cleanup() {
    rm -rf "$TMPDIR"
    ssh $SSH_OPTS "$SSH_HOST" "rm -rf /tmp/cap /tmp/cap_cfg.txt" 2>/dev/null || true
}
trap cleanup EXIT

echo "[+] Downloading frames..."
ssh $SSH_OPTS "$SSH_HOST" "tar -C /tmp/cap -cf - ." 2>/dev/null | tar -C "$TMPDIR" -xf - 2>/dev/null || true

FRAME_COUNT="$(ls "$TMPDIR"/frame_*.jpg 2>/dev/null | wc -l | tr -d ' ')"
if [ "$FRAME_COUNT" -eq 0 ]; then
    echo "[-] No frames captured! Make sure SpringBoard has AutoUnlock loaded." >&2
    exit 1
fi
echo "[+] Downloaded $FRAME_COUNT frames."

# Calculate real recorded framerate so video matches real time
ACTUAL_FPS=$(awk "BEGIN { fps = $FRAME_COUNT / $DURATION; if (fps < 1.0) fps = 1.0; printf \"%.2f\", fps }")
echo "[+] Real capture framerate: ${ACTUAL_FPS} fps (duration: ${DURATION}s)"

# Encode to MP4 with ffmpeg
echo "[+] Encoding video with ffmpeg..."
ffmpeg -y -framerate "$ACTUAL_FPS" -i "$TMPDIR/frame_%04d.jpg" -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$OUTPUT" >/dev/null 2>&1

echo "[✓] Screen recording saved to: $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"

if [ "$GEN_GIF" -eq 1 ]; then
    GIF_OUT="${OUTPUT%.mp4}.gif"
    echo "[+] Generating animated GIF: $GIF_OUT..."
    ffmpeg -y -i "$OUTPUT" -vf "fps=${ACTUAL_FPS},scale=320:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" "$GIF_OUT" >/dev/null 2>&1
    echo "[✓] GIF saved to: $GIF_OUT ($(du -h "$GIF_OUT" | cut -f1))"
fi

if [ "$DO_OPEN" -eq 1 ]; then
    open "$OUTPUT"
fi
