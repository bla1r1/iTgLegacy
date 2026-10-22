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
SCP_CMD="sshpass -p alpine scp -P 2222 -o UserKnownHostsFile=/dev/null -o HostKeyAlgorithms=+ssh-rsa -o StrictHostKeyChecking=no"

if [ "$DO_FULL" -eq 1 ]; then
    echo "[+] Performing full IPA install via ideviceinstaller..."
    ideviceinstaller -u "$DEVICE_UDID" install "$ROOT/build/ipa/iTgLegacy-armv7.ipa"
    echo "[+] Full install complete!"
    exit 0
fi

echo "[+] Locating installed iTgLegacy.app on device..."
REMOTE_APP_DIR="$($SSH_CMD "find /var/mobile/Applications -name 'iTgLegacy.app' 2>/dev/null | head -1" 2>/dev/null | tr -d '\r')"

if [ -z "$REMOTE_APP_DIR" ]; then
    echo "[!] App not found on device. Performing first-time full install..."
    ideviceinstaller -u "$DEVICE_UDID" install "$ROOT/build/ipa/iTgLegacy-armv7.ipa"
    echo "[+] Installed!"
    exit 0
fi

echo "[+] Target app directory: $REMOTE_APP_DIR"
if [ "$DO_SYNC" -eq 1 ]; then
    echo "[+] Syncing full iTgLegacy.app bundle (binary, images, plists)..."
    $SCP_CMD -r "$ROOT/build/armv7/app/iTgLegacy.app/"* "mobile@localhost:$REMOTE_APP_DIR/"
    echo "[+] Refreshing LaunchServices icon cache (without SpringBoard respring)..."
    $SSH_CMD "su -c uicache mobile 2>/dev/null || uicache 2>/dev/null || true"
else
    echo "[+] Copying fresh iTgLegacy executable over SSH..."
    $SCP_CMD "$ROOT/build/armv7/app/iTgLegacy.app/iTgLegacy" "mobile@localhost:$REMOTE_APP_DIR/iTgLegacy"
fi

echo "[+] Restarting iTgLegacy process..."
$SSH_CMD "killall -9 iTgLegacy 2>/dev/null || true; /usr/bin/uiopen itglegacy:// 2>/dev/null || openURL itglegacy:// 2>/dev/null || true" 2>/dev/null || true

echo "[+] Fast deploy complete in seconds! App updated on device."
