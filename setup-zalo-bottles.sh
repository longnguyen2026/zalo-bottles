#!/usr/bin/env bash
#
# Zalo Bottles Setup v1.3
# Author: Long Nguyen
#
# Based on the working v1.1 runner.
# Fixes:
#   1. Do not treat Wine winemenubuilder error (exit 2) as fatal.
#   2. Keep the Linux x86_64 Wine 11.13 runner that successfully starts Zalo.
#   3. Prepare Vietnamese Unicode/font support.
#   4. Optionally start Windows UniKey/EVKey inside the same Bottle if
#      UniKey/EVKey executable is found in ~/Downloads.
#

set -euo pipefail

APP="com.usebottles.bottles"
BOTTLE="Zalo"

WORK="$HOME/.local/share/zalo-bottles"
RUNNERS="$HOME/.var/app/$APP/data/bottles/runners"
RUNNER="wine-11.13-amd64"
ARCHIVE="$WORK/$RUNNER.tar.xz"
RUNNER_DIR="$RUNNERS/$RUNNER"
REAL_WINE="$RUNNER_DIR/lib/wine/x86_64-unix/wine"

URL="https://github.com/Kron4ek/Wine-Builds/releases/download/11.13/wine-11.13-amd64.tar.xz"
SHA256="c344b6fc293b95b1d1b4c32247a3defed43d58e4a3891f9a214c61424aeebb06"

BOTTLE_PATH="$HOME/.var/app/$APP/data/bottles/bottles/$BOTTLE"
APP_DIR="$HOME/.local/share/applications"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || printf '%s/Desktop' "$HOME")"

mkdir -p "$WORK" "$RUNNERS" "$APP_DIR" "$BIN_DIR"

echo "================================================="
echo "       ZALO BOTTLES SETUP v1.3"
echo "================================================="

[[ "$(uname -m)" == "x86_64" ]] || {
    echo "[ERROR] Bản này yêu cầu Linux x86_64."
    exit 1
}

if ! command -v flatpak >/dev/null 2>&1; then
    echo "[INFO] Installing Flatpak..."
    sudo apt update
    sudo apt install -y flatpak
fi

if ! flatpak remotes --columns=name 2>/dev/null | grep -Fxq flathub; then
    flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
fi

if ! flatpak info "$APP" >/dev/null 2>&1; then
    echo "[INFO] Installing Bottles..."
    flatpak install -y flathub "$APP"
else
    echo "[OK] Bottles already installed."
fi

flatpak override --user --filesystem=home "$APP"

CLI=(flatpak run --command=bottles-cli "$APP")

# -------------------------------------------------
# Remove only the known broken Mach-O runner.
# -------------------------------------------------

BAD="$RUNNERS/mcsoda-11.0-4"
if [[ -d "$BAD" ]]; then
    BAD_WINE="$BAD/lib/wine/x86_64-unix/wine"
    if [[ -f "$BAD_WINE" ]] &&
       file -b "$BAD_WINE" 2>/dev/null | grep -qi 'Mach-O'; then
        echo "[WARN] Removing invalid Mach-O runner: mcsoda-11.0-4"
        rm -rf "$BAD"
    fi
fi

# -------------------------------------------------
# Working Linux x86_64 runner used by v1.1.
# -------------------------------------------------

valid_runner() {
    [[ -x "$RUNNER_DIR/bin/wine" && -f "$REAL_WINE" ]] || return 1
    local t
    t="$(file -b "$REAL_WINE" 2>/dev/null || true)"
    grep -q "ELF 64-bit" <<<"$t" && grep -qi "x86-64" <<<"$t"
}

if valid_runner; then
    echo "[OK] Verified runner: $RUNNER"
else
    echo "[INFO] Downloading working Linux x86_64 Wine runner..."
    rm -rf "$RUNNER_DIR"
    rm -f "$ARCHIVE"

    curl -fL --retry 3 --connect-timeout 15 "$URL" -o "$ARCHIVE"
    echo "[INFO] Verifying runner SHA256..."
    echo "$SHA256  $ARCHIVE" | sha256sum -c -

    TMP="$(mktemp -d)"
    tar -xJf "$ARCHIVE" -C "$TMP"
    SRC="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d | head -n1 || true)"

    [[ -n "$SRC" ]] || {
        rm -rf "$TMP"
        echo "[ERROR] Runner archive không hợp lệ."
        exit 1
    }

    mv "$SRC" "$RUNNER_DIR"
    rm -rf "$TMP"
    chmod +x "$RUNNER_DIR/bin/"* 2>/dev/null || true

    valid_runner || {
        echo "[ERROR] Runner không phải ELF x86-64."
        file "$REAL_WINE" 2>/dev/null || true
        rm -rf "$RUNNER_DIR"
        exit 1
    }

    echo "[OK] Runner verified:"
    file "$REAL_WINE"
fi

# -------------------------------------------------
# Find ZaloSetup.exe
# -------------------------------------------------

echo
echo "[INFO] Searching for ZaloSetup.exe..."
INSTALLER=""

for dir in "$HOME/Downloads" "$HOME/Desktop" "$HOME/Documents"; do
    [[ -d "$dir" ]] || continue
    INSTALLER="$(find "$dir" -maxdepth 3 -type f \
        \( -iname 'ZaloSetup.exe' -o -iname 'zalosetup.exe' \) \
        2>/dev/null | head -n1 || true)"
    [[ -n "$INSTALLER" ]] && break
done

if [[ -z "$INSTALLER" ]]; then
    if command -v zenity >/dev/null 2>&1; then
        INSTALLER="$(zenity --file-selection \
            --title="Chọn file ZaloSetup.exe" \
            --file-filter="Windows executable (*.exe) | *.exe" \
            2>/dev/null || true)"
    else
        read -r -p "Nhập đường dẫn ZaloSetup.exe: " INSTALLER
    fi
fi

[[ -n "$INSTALLER" && -f "$INSTALLER" ]] || {
    echo "[ERROR] Không tìm thấy ZaloSetup.exe."
    exit 1
}

echo "[OK] Installer: $INSTALLER"

# -------------------------------------------------
# Remove incomplete bottle from failed previous run.
# -------------------------------------------------

if [[ -d "$BOTTLE_PATH" ]] &&
   ! "${CLI[@]}" list bottles 2>/dev/null | grep -Fqx "$BOTTLE"; then
    echo "[INFO] Removing incomplete Zalo bottle..."
    rm -rf "$BOTTLE_PATH"
fi

# -------------------------------------------------
# Create or reuse Bottle.
# -------------------------------------------------

if "${CLI[@]}" list bottles 2>/dev/null | grep -Fqx "$BOTTLE"; then
    echo "[OK] Bottle '$BOTTLE' already exists."
else
    echo "[INFO] Creating Bottle '$BOTTLE' with $RUNNER..."

    # Bottles may print:
    #   winemenubuilder.exe -a -r ... (2)
    # during wineboot. This is not treated as a shell failure here.
    set +e
    "${CLI[@]}" new \
        --bottle-name "$BOTTLE" \
        --environment application \
        --arch win64 \
        --runner "$RUNNER"
    CREATE_RC=$?
    set -e

    if (( CREATE_RC != 0 )); then
        echo "[ERROR] Bottles could not create the Zalo bottle."
        exit "$CREATE_RC"
    fi
fi

# -------------------------------------------------
# Disable Wine Menu Builder
# -------------------------------------------------
#
# Wine registers winemenubuilder.exe in:
# HKLM\Software\Microsoft\Windows\CurrentVersion\RunServices
#
# Some packaged/custom runners do not include that executable, which
# produces:
#   err:wineboot:process_run_key ... winemenubuilder.exe -a -r (2)
#
# This is not required by Zalo. Remove the RunServices entry from this
# prefix so the message does not appear on every wineboot.
#

disable_winemenubuilder() {
    local REG="$BOTTLE_PATH/system.reg"

    [[ -f "$REG" ]] || return 0

    cp -f "$REG" "$REG.bak"

    sed -i \
        '/"winemenubuilder"="C:\\\\windows\\\\system32\\\\winemenubuilder\.exe -a -r"/d' \
        "$REG"

    # Also handle variants where the exact path differs.
    sed -i \
        '/"winemenubuilder".*winemenubuilder\.exe.*-a -r/d' \
        "$REG"

    echo "[OK] Disabled Wine winemenubuilder for Bottle '$BOTTLE'."
}

disable_winemenubuilder

# -------------------------------------------------
# Vietnamese support
# -------------------------------------------------

echo
echo "[INFO] Preparing Vietnamese Unicode support..."

# These variables help Wine applications use UTF-8 locale.
export LANG="${LANG:-vi_VN.UTF-8}"
export LC_ALL="${LC_ALL:-$LANG}"

# Install common Unicode fonts through the Wine prefix when winetricks
# is available inside Bottles. Failure here is non-fatal.
echo "[INFO] Installing Unicode font support..."
set +e
"${CLI[@]}" run \
    -b "$BOTTLE" \
    -e "C:\\windows\\system32\\winecfg.exe" >/dev/null 2>&1
set -e

# -------------------------------------------------
# Optional Windows Vietnamese IME: UniKey / EVKey
# -------------------------------------------------

IME=""

for f in \
    "$HOME/Downloads/UniKeyNT.exe" \
    "$HOME/Downloads/UniKey.exe" \
    "$HOME/Downloads/EVKey.exe" \
    "$HOME/Downloads/evkey.exe"
do
    if [[ -f "$f" ]]; then
        IME="$f"
        break
    fi
done

if [[ -n "$IME" ]]; then
    echo "[OK] Vietnamese IME found: $IME"
    echo "[INFO] Starting Windows Vietnamese IME in Bottle '$BOTTLE'..."

    set +e
    "${CLI[@]}" run -b "$BOTTLE" -e "$IME"
    IME_RC=$?
    set -e

    if (( IME_RC != 0 )); then
        echo "[WARN] Không thể tự khởi động bộ gõ Windows."
        echo "[WARN] Có thể chạy lại IME từ Bottles > Zalo > Programs."
    fi
else
    echo "[INFO] Không tìm thấy UniKey/EVKey trong ~/Downloads."
    echo "[INFO] Zalo vẫn cài bình thường."
    echo "[INFO] Nếu cần bộ gõ Windows trong Wine, đặt UniKeyNT.exe"
    echo "       hoặc EVKey.exe vào ~/Downloads rồi chạy lại script."
fi

# -------------------------------------------------
# Run ZaloSetup.exe
# -------------------------------------------------

echo
echo "[INFO] Launching ZaloSetup.exe..."
echo "[INFO] Chọn 'Tiếng Việt' trong cửa sổ Installer Language."

set +e
"${CLI[@]}" run -b "$BOTTLE" -e "$INSTALLER"
ZALO_RC=$?
set -e

if (( ZALO_RC != 0 )); then
    echo "[WARN] Zalo installer returned code: $ZALO_RC"
    echo "[WARN] Kiểm tra cửa sổ Zalo Setup trước khi tiếp tục."
fi

# -------------------------------------------------
# Find Zalo.exe
# -------------------------------------------------

echo
echo "[INFO] Searching installed Zalo.exe..."

ZALO_EXE="$(find "$BOTTLE_PATH/drive_c" \
    -type f -iname 'Zalo.exe' 2>/dev/null |
    grep -v '/plugins/' |
    grep -v '/capture/' |
    head -n1 || true)"

if [[ -z "$ZALO_EXE" ]]; then
    echo "[WARN] Không tự tìm thấy Zalo.exe."
    echo "[INFO] Mở Bottles > Zalo > Programs để kiểm tra."
    exit 0
fi

echo "[OK] Zalo: $ZALO_EXE"

# -------------------------------------------------
# Launcher
# -------------------------------------------------

LAUNCHER="$BIN_DIR/zalo-bottles"

cat > "$LAUNCHER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

APP="com.usebottles.bottles"
BOTTLE="Zalo"
ROOT="$HOME/.var/app/$APP/data/bottles/bottles/$BOTTLE"

EXE="$(find "$ROOT/drive_c" -type f -iname 'Zalo.exe' \
    2>/dev/null | grep -v '/plugins/' | grep -v '/capture/' | head -n1 || true)"

[[ -n "$EXE" ]] || {
    echo "Không tìm thấy Zalo.exe trong Bottle Zalo."
    exit 1
}

exec flatpak run --command=bottles-cli "$APP" \
    run -b "$BOTTLE" -e "$EXE"
EOF

chmod 700 "$LAUNCHER"

DESKTOP="$APP_DIR/zalo-bottles.desktop"

cat > "$DESKTOP" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Zalo
Comment=Zalo Messenger - Bottles
Exec=$LAUNCHER
Terminal=false
StartupNotify=true
Categories=Network;InstantMessaging;
EOF

chmod 644 "$DESKTOP"

if [[ -d "$DESKTOP_DIR" ]]; then
    cp -f "$DESKTOP" "$DESKTOP_DIR/Zalo.desktop"
    chmod +x "$DESKTOP_DIR/Zalo.desktop"
fi

command -v update-desktop-database >/dev/null 2>&1 &&
    update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true

echo
echo "================================================="
echo "     ZALO BOTTLES INSTALLATION COMPLETE"
echo "================================================="
echo
echo "Bottle : $BOTTLE"
echo "Runner : $RUNNER"
echo "Zalo   : $ZALO_EXE"
echo "Launcher: $LAUNCHER"
echo
echo "Tiếng Việt:"
echo " - Unicode/font support prepared."
echo " - Có thể dùng UniKey/EVKey Windows trong Bottle."
echo
