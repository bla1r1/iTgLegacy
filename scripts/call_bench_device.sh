#!/bin/bash
# Our client on the device, with its real audio engine, against tgcalls_cli on this Mac
# through a real Telegram reflector. No account: signaling goes over an SSH tunnel.
# Needs a dev build on the device and the same tgcalls_cli as scripts/call_bench.sh.
#   scripts/call_bench_device.sh [version] [seconds]     default: 5.0.0 20
# The device plays the peer's 440 Hz tone out loud and sends SOS at 800 Hz.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="${CALL_BENCH_CLI:-$HOME/.crew/calls/Telegram-iOS/bazel-bin/submodules/TgVoipWebrtc/tgcalls/tools/cli/tgcalls_cli}"
REFLECTOR="${CALL_BENCH_REFLECTOR:-91.108.13.2:598}"
VERSION="${1:-5.0.0}"
SECONDS_LONG="${2:-20}"
PORT=47300
HOST_DEV="${CALL_BENCH_DEVICE:-itgphone}"
LOGS="$ROOT/build/call_bench"
mkdir -p "$LOGS"
KEY=$(openssl rand -hex 256)
TAG=$(openssl rand -hex 16)
python3 - "$KEY" "01${TAG:2}" "$REFLECTOR" "$PORT" "$VERSION" > "$LOGS/callbench.json" <<'PY'
import base64,json,sys
key,tag,reflector,port,version=sys.argv[1:]
host,rport=reflector.split(':')
print(json.dumps({"role":"callee","version":version,"signalPort":int(port),"morse":True,
  "reflectorHost":host,"reflectorPort":int(rport),
  "key":base64.b64encode(bytes.fromhex(key)).decode(),"tag":base64.b64encode(bytes.fromhex(tag)).decode()}))
PY
scp -O -q "$LOGS/callbench.json" "$HOST_DEV:/var/mobile/Library/Caches/callbench.json" || exit 1
"$CLI" --mode bridge --version "$VERSION" --reflector "$REFLECTOR" --duration "$SECONDS_LONG" \
	--role caller --key-hex "$KEY" --tag-hex "00${TAG:2}" --signal-port "$PORT" \
	--rtc-log "$LOGS/device.rtc.log" > "$LOGS/device.theirs.out" 2> "$LOGS/device.theirs.log" &
PEER=$!
sleep 1
ssh -o BatchMode=yes -o ExitOnForwardFailure=yes -N -R "$PORT:127.0.0.1:$PORT" "$HOST_DEV" &
TUNNEL=$!
sleep 2
ssh -o BatchMode=yes "$HOST_DEV" "uiopen itglegacy://callbench"
for _ in $(seq 1 $((SECONDS_LONG + 8))); do kill -0 "$PEER" 2>/dev/null || break; sleep 1; done
ssh -o BatchMode=yes "$HOST_DEV" "uiopen itglegacy://callbench/stop"
kill "$PEER" "$TUNNEL" 2>/dev/null
wait 2>/dev/null
grep -h 'BRIDGE_RESULT' "$LOGS/device.theirs.out" | sed 's/BRIDGE_RESULT/theirs/'
ssh -o BatchMode=yes "$HOST_DEV" "grep -a 'TGCall' /var/mobile/Library/Caches/log.txt" > "$LOGS/device.ours.log"
grep -E 'audio frames in|sent [0-9]+ audio frames|connected over|mic level|engine started|verified media' "$LOGS/device.ours.log" | tail -8 | cut -c1-110
