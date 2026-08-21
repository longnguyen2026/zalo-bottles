#!/usr/bin/env bash
# Zalo Bottles - Setup v1.9.1
# Author: Long Nguyen
# 2-file installer architecture: install.sh -> setup-zalo-bottles.sh
set -Eeuo pipefail

APP_ID="com.usebottles.bottles"
BOTTLE="Zalo"
RUNNER_PREFERRED="wine-11.13-amd64"
BOTTLE_ROOT="$HOME/.var/app/$APP_ID/data/bottles/bottles/$BOTTLE"
LAUNCHER="$HOME/.local/bin/zalo-bottles"
DESKTOP="$HOME/.local/share/applications/Zalo.desktop"
LOG_DIR="$HOME/.local/state/zalo-bottles"
LOG_FILE="$LOG_DIR/install.log"
mkdir -p "$LOG_DIR" "$HOME/.local/bin" "$HOME/.local/share/applications"
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'echo "[ERROR] Setup failed at line $LINENO. Log: $LOG_FILE"' ERR

info(){ echo "[INFO] $*"; }
ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*"; }
die(){ echo "[ERROR] $*" >&2; exit 1; }

[[ "$(uname -m)" == "x86_64" ]] || die "Chỉ hỗ trợ x86_64."
command -v flatpak >/dev/null || die "Flatpak chưa được cài."
command -v curl >/dev/null || die "curl chưa được cài."
flatpak remote-list | awk '{print $1}' | grep -qx flathub || \
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

if ! flatpak info "$APP_ID" >/dev/null 2>&1; then
  info "Installing Bottles..."
  flatpak install -y flathub "$APP_ID"
else
  ok "Bottles already installed."
fi
BOTTLES=(flatpak run --command=bottles-cli "$APP_ID")

# Locate Zalo installer
INSTALLER=""
for f in "$HOME/Downloads/ZaloSetup.exe" "$HOME/Downloads/zalo/ZaloSetup.exe"; do
  [[ -f "$f" ]] && { INSTALLER="$(realpath "$f")"; break; }
done
if [[ -z "$INSTALLER" ]]; then
  INSTALLER="$(find "$HOME/Downloads" -maxdepth 4 -type f \( -iname 'ZaloSetup.exe' -o -iname 'ZaloSetup*.exe' \) -print -quit 2>/dev/null || true)"
fi
[[ -n "$INSTALLER" && -f "$INSTALLER" ]] || die "Không tìm thấy ZaloSetup.exe trong ~/Downloads."
ok "Installer: $INSTALLER"

# Stop only Zalo/Bottles processes
pkill -f 'Zalo-26\.7\.10' 2>/dev/null || true
pkill -f 'ZaloCap' 2>/dev/null || true
pkill -f 'bottles-cli.*Zalo' 2>/dev/null || true
sleep 2

# Clean only Zalo bottle
if [[ -d "$BOTTLE_ROOT" ]]; then
  warn "Existing Zalo Bottle found. It will be deleted: $BOTTLE_ROOT"
  rm -rf --one-file-system "$BOTTLE_ROOT"
  ok "Old Zalo Bottle removed."
fi
rm -f "$LAUNCHER" "$DESKTOP" "$HOME/Desktop/Zalo.desktop" "$HOME/Desktop/zalo.desktop"

# Verify runner
RUNNER_LIST="$(${BOTTLES[@]} list components -f category:runners 2>/dev/null || true)"
# Bottles may print runners with list markers such as "- wine-11.13-amd64".
# Normalize list markers, whitespace, and ANSI formatting before matching.
RUNNER_NAMES="$(printf '%s\n' "$RUNNER_LIST" | sed -E 's/^[[:space:]]*-[[:space:]]*//; s/^[[:space:]]+//; s/[[:space:]]+$//' | sed -E 's/\x1B\[[0-9;]*[[:alpha:]]//g')"
if printf '%s\n' "$RUNNER_NAMES" | grep -Fqx "$RUNNER_PREFERRED"; then
  RUNNER="$RUNNER_PREFERRED"
  ok "Verified runner: $RUNNER"
else
  echo "$RUNNER_LIST"
  die "Không tìm thấy runner $RUNNER_PREFERRED. Cài runner này trong Bottles rồi chạy lại."
fi

# Fresh application bottle
info "Creating fresh Bottle '$BOTTLE'..."
"${BOTTLES[@]}" new --bottle-name "$BOTTLE" --environment application --arch win64 --runner "$RUNNER"
# Windows 10 is the safer target for current Electron/Wine Zalo builds.
"${BOTTLES[@]}" edit -b "$BOTTLE" --win win10 >/dev/null 2>&1 || true
ok "Bottle created."

# Prepare common fonts. These are installed by Bottles if available; failure is non-fatal.
info "Preparing fonts..."
"${BOTTLES[@]}" install -b "$BOTTLE" allfonts >/dev/null 2>&1 || true

info "Installing ZaloSetup.exe..."
"${BOTTLES[@]}" run -b "$BOTTLE" -e "$INSTALLER" 2> >(sed -E '/err:ole:/d; /err:winemenubuilder:/d; /process_run_key.*winemenubuilder\.exe/d' >&2)

info "Searching installed Zalo.exe..."
ZALO_ROOT="$BOTTLE_ROOT/drive_c/users/$USER/AppData/Local/Programs/Zalo"
ZALO_EXE="$(find "$ZALO_ROOT" -type f -iname 'Zalo.exe' -not -path '*/plugins/capture/*' -print 2>/dev/null | sort -V | tail -n1 || true)"
[[ -n "$ZALO_EXE" && -f "$ZALO_EXE" ]] || {
  find "$BOTTLE_ROOT/drive_c" -type f -iname 'Zalo.exe' 2>/dev/null || true
  die "Không tìm thấy Zalo.exe sau khi cài."
}
ok "Zalo: $ZALO_EXE"

REL="${ZALO_EXE#"$BOTTLE_ROOT/drive_c/"}"
WIN_ZALO="C:/${REL//\//\/}"

# Launcher: shell -> cmd -> start. Important Electron compatibility flags:
# --no-sandbox avoids Wine/Electron IPC sandbox failures seen as uv_pipe_open.
# libglesv2.dll is disabled for this Bottle to avoid Chromium/Wine GL issues.
# WINEDEBUG=-ole hides known non-fatal OLE/WinRT registration noise.
cat > "$LAUNCHER" <<EOF2
#!/usr/bin/env bash
set -u
APP_ID="$APP_ID"
BOTTLE="$BOTTLE"
WIN_ZALO='$WIN_ZALO'
LOG="$HOME/.local/state/zalo-bottles/launch.log"
mkdir -p "\$(dirname "\$LOG")"

# Do not create duplicate Zalo processes.
if pgrep -af 'Zalo-26\\.7\\.10/Zalo\\.exe' >/dev/null 2>&1; then
    exit 0
fi

# Electron/Wine compatibility configuration.
export WINEDEBUG='-ole'
export WINEDLLOVERRIDES='libglesv2.dll='

# Use Wine shell instead of direct bottles-cli run for the installed app.
# --no-sandbox addresses Electron IPC/sandbox problems under Wine.
flatpak run --command=bottles-cli "\$APP_ID" \\
    shell -b "\$BOTTLE" \\
    -i "cmd.exe /c start \"\" \"\$WIN_ZALO\" --no-sandbox" \\
    >>"\$LOG" 2>&1 &
exit 0
EOF2
chmod 755 "$LAUNCHER"

# Desktop entry
cat > "$DESKTOP" <<EOF2
[Desktop Entry]
Name=Zalo
Comment=Zalo Messenger (Bottles)
Exec=$LAUNCHER
Terminal=false
Type=Application
Categories=Network;Chat;
StartupNotify=true
EOF2
chmod 644 "$DESKTOP"

# Remove stale desktop cache entry if available
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true

cat > "$LOG_DIR/zalo-info.txt" <<EOF2
Zalo Bottles v1.9.1
Bottle: $BOTTLE
Runner: $RUNNER
Zalo: $ZALO_EXE
Launcher: $LAUNCHER
Electron flags: --no-sandbox
Wine DLL override: libglesv2.dll disabled
Wine debug: -ole
EOF2

echo
echo "================================================="
echo "      ZALO BOTTLES INSTALLATION COMPLETE"
echo "================================================="
echo "Bottle : $BOTTLE"
echo "Runner : $RUNNER"
echo "Zalo   : $ZALO_EXE"
echo "Launcher: $LAUNCHER"
echo
echo "[OK] Zalo không được launch trực tiếp bằng bottles-cli run."
echo "[OK] Launcher dùng shell -> cmd.exe -> start."
echo "[OK] Electron: --no-sandbox."
echo "[OK] libglesv2.dll disabled trong launcher để tránh lỗi GL/Chromium."
echo "[OK] OLE diagnostic noise được ẩn khi launch."
echo
echo "Mở Zalo bằng: $LAUNCHER"
echo "Log: $LOG_FILE"
echo "================================================="
