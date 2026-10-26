#!/bin/bash
# scripts/deploy.sh - Fast deployment to connected iOS device over SSH
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DO_FULL=0
DO_SYNC=0
for arg in "$@"; do
    case "$arg" in
        --full) DO_FULL=1 ;;
        --sync) DO_SYNC=1 ;;
    esac
done

echo "[+] Building armv7 binary..."
make ipa-armv7

DEVICE_UDID="$(idevice_id -l 2>/dev/null | head -1)"
if [ -z "$DEVICE_UDID" ]; then
    echo "[-] No connected iOS device detected via USB!"
    exit 1
fi
echo "[+] Device detected: $DEVICE_UDID"

# Ensure iproxy is running on port 2222 -> 22
if ! nc -z localhost 2222 2>/dev/null; then
    echo "[+] Starting iproxy 2222:22 in background..."
    iproxy 2222 22 -u "$DEVICE_UDID" >/dev/null 2>&1 &
    sleep 2
fi

SSH_CMD="sshpass -p alpine ssh -p 2222 -o UserKnownHostsFile=/dev/null -o HostKeyAlgorithms=+ssh-rsa -o StrictHostKeyChecking=no mobile@localhost"
SCP_CMD="sshpass -p alpine scp -O -P 2222 -o UserKnownHostsFile=/dev/null -o HostKeyAlgorithms=+ssh-rsa -o StrictHostKeyChecking=no"

if [ "$DO_FULL" -eq 1 ]; then
    echo "[+] Performing full IPA install via ideviceinstaller..."
    ideviceinstaller -u "$DEVICE_UDID" install "$ROOT/build/ipa/LegacyTG-armv7.ipa"
    echo "[+] Full install complete!"
    exit 0
fi

echo "[+] Locating installed app bundle on device..."
REMOTE_APP_DIR="$($SSH_CMD "find /var/containers/Bundle/Application /var/mobile/Containers/Bundle/Application /var/mobile/Applications /Applications \( -name 'LegacyTG.app' -o -name 'iTgLegacy.app' \) 2>/dev/null | head -1" 2>/dev/null | tr -d '\r')"

if [ -z "$REMOTE_APP_DIR" ]; then
    echo "[!] App not found on device. Performing first-time full install..."
    ideviceinstaller -u "$DEVICE_UDID" install "$ROOT/build/ipa/LegacyTG-armv7.ipa"
    echo "[+] Installed!"
    exit 0
fi

REMOTE_APP_NAME="$(basename "$REMOTE_APP_DIR")"
REMOTE_EXE_NAME="${REMOTE_APP_NAME%.app}"

echo "[+] Target app directory: $REMOTE_APP_DIR (executable: $REMOTE_EXE_NAME)"
if [ "$DO_SYNC" -eq 1 ]; then
    echo "[+] Syncing full app bundle (binary, images, plists)..."
    $SCP_CMD -r "$ROOT/build/armv7/app/LegacyTG.app/"* "mobile@localhost:$REMOTE_APP_DIR/"
    if [ "$REMOTE_EXE_NAME" != "LegacyTG" ]; then
        $SSH_CMD "cp '$REMOTE_APP_DIR/LegacyTG' '$REMOTE_APP_DIR/$REMOTE_EXE_NAME'" 2>/dev/null || true
    fi
else
    echo "[+] Copying fresh executable over SSH..."
    $SCP_CMD "$ROOT/build/armv7/app/LegacyTG.app/LegacyTG" "mobile@localhost:$REMOTE_APP_DIR/$REMOTE_EXE_NAME"
fi

echo "[+] Restarting app process & waking screen..."
$SSH_CMD "killall -9 LegacyTG iTgLegacy 2>/dev/null || true; sbunlock --launch 2>/dev/null || openURL legacytg:// 2>/dev/null || openURL itglegacy:// 2>/dev/null || true" 2>/dev/null || true

echo "[+] Fast deploy complete in seconds! App updated on device."
