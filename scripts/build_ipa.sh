#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${ROOT_DIR}"

echo "[+] Building LegacyTG IPA (iOS 6.0 - 12.0)..."

# Ensure ccache exports are set for maximum speed
if command -v ccache &>/dev/null; then
  echo "[+] ccache detected: $(ccache --version | head -1)"
  export CCACHE_NOHASHDIR=1
  export CCACHE_CPP2=1
fi

# Run root Makefile build
make ipa

echo "[+] Build completed successfully!"
