#!/usr/bin/env bash
#
# Zalo Bottles Setup v1.1
# Author: Long Nguyen
#
# Fixes the invalid mcsoda-11.0-4 runner by installing and verifying
# a Linux x86_64 Wine runner before creating the Zalo bottle.
#
set -euo pipefail

APP="com.usebottles.bottles"
BOTTLE="Zalo"
WORK="$HOME/.local/share/zalo-bottles"
RUNNERS="$HOME/.var/app/$APP/data/bottles/runners"
RUNNER="wine-11.13-amd64"
ARCHIVE="$WORK/$RUNNER.tar.xz"
URL="https://github.com/Kron4ek/Wine-Builds/releases/download/11.13/wine-11.13-amd64.tar.xz"
SHA256="c344b6fc293b95b1d1b4c32247a3defed43d58e4a3891f9a214c61424aeebb06"
BOTTLE_PATH="$HOME/.var/app/$APP/data/bottles/bottles/$BOTTLE"
APP_DIR="$HOME/.local/share/applications"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || printf '%s/Desktop' "$HOME")"

mkdir -p "$WORK" "$RUNNERS" "$APP_DIR" "$BIN_DIR"

echo "================================================="
echo "       ZALO BOTTLES SETUP v1.1"
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

flatpak remotes --columns=name 2>/dev/null | grep -Fxq flathub || \
    flatpak remote-add --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo

if ! flatpak info "$APP" >/dev/null 2>&1; then
    echo "[INFO] Installing Bottles..."
    flatpak install -y flathub "$APP"
else
    echo "[OK] Bottles already installed."
fi

flatpak override --user --filesystem=home "$APP"
CLI=(flatpak run --command=bottles-cli "$APP")

# Remove the known broken runner.
BAD="$RUNNERS/mcsoda-11.0-4"
if [[ -f "$BAD/lib/wine/x86_64-unix/wine" ]] &&
   file -b "$BAD/lib/wine/x86_64-unix/wine" | grep -qi 'Mach-O'; then
    echo "[WARN] Removing invalid Mach-O runner mcsoda-11.0-4..."
    rm -rf "$BAD"
fi

RUNNER_DIR="$RUNNERS/$RUNNER"
REAL_WINE="$RUNNER_DIR/lib/wine/x86_64-unix/wine"

valid_runner() {
    [[ -x "$RUNNER_DIR/bin/wine" && -f "$REAL_WINE" ]] || return 1
    local t
    t="$(file -b "$REAL_WINE" 2>/dev/null || true)"
    grep -q 'ELF 64-bit' <<<"$t" && grep -qi 'x86-64' <<<"$t"
}

if valid_runner; then
    echo "[OK] Verified runner: $RUNNER"
else
    echo "[INFO] Downloading verified Linux x86_64 Wine 11.13..."
    rm -rf "$RUNNER_DIR"
    rm -f "$ARCHIVE"

    curl -fL --retry 3 --connect-timeout 15 "$URL" -o "$ARCHIVE"
    echo "$SHA256  $ARCHIVE" | sha256sum -c -

    TMP="$(mktemp -d)"
    tar -xJf "$ARCHIVE" -C "$TMP"
    SRC="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d | head -n1)"

    [[ -n "$SRC" ]] || { rm -rf "$TMP"; echo "[ERROR] Runner archive invalid."; exit 1; }
    mv "$SRC" "$RUNNER_DIR"
    rm -rf "$TMP"

    chmod +x "$RUNNER_DIR/bin/"* 2>/dev/null || true

    valid_runner || {
        echo "[ERROR] Runner is not a valid Linux x86_64 ELF."
        file "$REAL_WINE" 2>/dev/null || true
        rm -rf "$RUNNER_DIR"
        exit 1
    }

    echo "[OK] Runner verified:"
    file "$REAL_WINE"
fi

# Find ZaloSetup.exe.
echo
echo "[INFO] Searching for ZaloSetup.exe..."
INSTALLER=""
for d in "$HOME/Downloads" "$HOME/Desktop" "$HOME/Documents"; do
    [[ -d "$d" ]] || continue
    INSTALLER="$(find "$d" -maxdepth 3 -type f \
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

# If the previous failed creation left an unregistered/incomplete bottle,
# remove only that incomplete directory.
if [[ -d "$BOTTLE_PATH" ]] && ! "${CLI[@]}" list bottles 2>/dev/null | grep -Fqx "$BOTTLE"; then
    echo "[INFO] Removing incomplete Zalo bottle..."
    rm -rf "$BOTTLE_PATH"
fi

if "${CLI[@]}" list bottles 2>/dev/null | grep -Fqx "$BOTTLE"; then
    echo "[INFO] Bottle '$BOTTLE' exists; selecting verified runner..."
    "${CLI[@]}" edit -b "$BOTTLE" --runner "$RUNNER"
else
    echo "[INFO] Creating Bottle '$BOTTLE' with $RUNNER..."
    "${CLI[@]}" new \
        --bottle-name "$BOTTLE" \
        --environment application \
        --arch win64 \
        --runner "$RUNNER"
fi

echo
echo "[INFO] Launching ZaloSetup.exe..."
"${CLI[@]}" run -b "$BOTTLE" -e "$INSTALLER"

echo
echo "[INFO] Searching installed Zalo.exe..."
ZALO_EXE="$(find "$BOTTLE_PATH/drive_c" -type f -iname 'Zalo.exe' \
    2>/dev/null | grep -v '/plugins/' | grep -v '/capture/' | head -n1 || true)"

if [[ -z "$ZALO_EXE" ]]; then
    echo "[WARN] Không tự tìm thấy Zalo.exe."
    echo "[INFO] Kiểm tra Bottle '$BOTTLE' trong Bottles > Programs."
    exit 0
fi

echo "[OK] Zalo: $ZALO_EXE"

LAUNCHER="$BIN_DIR/zalo-bottles"
cat > "$LAUNCHER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
APP="com.usebottles.bottles"
BOTTLE="Zalo"
ROOT="$HOME/.var/app/$APP/data/bottles/bottles/$BOTTLE"
EXE="$(find "$ROOT/drive_c" -type f -iname 'Zalo.exe' 2>/dev/null |
    grep -v '/plugins/' | grep -v '/capture/' | head -n1 || true)"
[[ -n "$EXE" ]] || exit 1
exec flatpak run --command=bottles-cli "$APP" run -b "$BOTTLE" -e "$EXE"
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
echo "Bottle : $BOTTLE"
echo "Runner : $RUNNER"
echo "Launcher: $LAUNCHER"
