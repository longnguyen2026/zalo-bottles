#!/usr/bin/env bash
# Zalo Bottles - Bootstrap Installer v1.9
# Author: Long Nguyen
set -euo pipefail
SETUP_URL="https://raw.githubusercontent.com/longnguyen2026/zalo-bottles/main/setup-zalo-bottles.sh"
TMP_DIR="$(mktemp -d)"
SETUP="$TMP_DIR/setup-zalo-bottles.sh"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "================================================="
echo "        ZALO BOTTLES INSTALLER v1.9"
echo "================================================="
command -v curl >/dev/null 2>&1 || { echo "[ERROR] curl chưa được cài."; exit 1; }
curl -fL --retry 3 --connect-timeout 10 --proto '=https' --tlsv1.2 "$SETUP_URL" -o "$SETUP"
[[ -s "$SETUP" ]] || { echo "[ERROR] Setup script rỗng."; exit 1; }
chmod 700 "$SETUP"
exec bash "$SETUP" "$@"
