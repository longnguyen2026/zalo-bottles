#!/usr/bin/env bash
#
# Zalo Bottles - Bootstrap Installer
# Version: 1.0
# Author: Long Nguyen
#

set -euo pipefail

SETUP_URL="https://raw.githubusercontent.com/longnguyen2026/script-long/main/setup-zalo-bottles.sh"
TMP_DIR="$(mktemp -d)"
SETUP="$TMP_DIR/setup-zalo-bottles.sh"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

echo "================================================="
echo "        ZALO BOTTLES INSTALLER"
echo "================================================="

command -v curl >/dev/null 2>&1 || {
    echo "[ERROR] curl chưa được cài."
    echo "Chạy: sudo apt install curl"
    exit 1
}

echo "[INFO] Downloading setup script..."
curl -fL --retry 3 --connect-timeout 10 "$SETUP_URL" -o "$SETUP"

[[ -s "$SETUP" ]] || { echo "[ERROR] Setup script rỗng."; exit 1; }

chmod 700 "$SETUP"
exec bash "$SETUP"
