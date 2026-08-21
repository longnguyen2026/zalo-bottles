#!/usr/bin/env bash
#
# Zalo Bottles Setup
# Version: 1.0
# Author: Long Nguyen
#
# Requires: Bottles Flatpak
#

set -euo pipefail

BOTTLES_APP="com.usebottles.bottles"
BOTTLE_NAME="Zalo"
WORKDIR="$HOME/.local/share/zalo-bottles"
APP_DIR="$HOME/.local/share/applications"
LOCAL_BIN="$HOME/.local/bin"
DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || printf '%s/Desktop' "$HOME")"

mkdir -p "$WORKDIR" "$APP_DIR" "$LOCAL_BIN"

echo "================================================="
echo "        ZALO BOTTLES SETUP"
echo "================================================="

# ---------- Flatpak ----------
if ! command -v flatpak >/dev/null 2>&1; then
    echo "[INFO] Installing Flatpak..."
    sudo apt update
    sudo apt install -y flatpak
fi

# ---------- Flathub ----------
if ! flatpak remotes --columns=name 2>/dev/null | grep -Fxq flathub; then
    echo "[INFO] Adding Flathub..."
    flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
fi

# ---------- Bottles ----------
if ! flatpak info "$BOTTLES_APP" >/dev/null 2>&1; then
    echo "[INFO] Installing Bottles..."
    flatpak install -y flathub "$BOTTLES_APP"
else
    echo "[OK] Bottles already installed."
fi

# ---------- Flatpak filesystem access ----------
# Bottles needs access to the user's home to select/run a local installer.
flatpak override --user --filesystem=home "$BOTTLES_APP"

# ---------- Find installer ----------
echo
echo "[INFO] Searching for ZaloSetup.exe..."

INSTALLER=""

SEARCH_PATHS=(
    "$HOME/Downloads"
    "$HOME/Desktop"
    "$HOME/Documents"
)

for dir in "${SEARCH_PATHS[@]}"; do
    [[ -d "$dir" ]] || continue
    found="$(find "$dir" -maxdepth 3 -type f \
        \( -iname 'ZaloSetup.exe' -o -iname 'zalosetup.exe' \) \
        2>/dev/null | head -n1 || true)"
    if [[ -n "$found" ]]; then
        INSTALLER="$found"
        break
    fi
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

if [[ -z "$INSTALLER" || ! -f "$INSTALLER" ]]; then
    echo "[ERROR] Không tìm thấy ZaloSetup.exe."
    exit 1
fi

echo "[OK] Installer: $INSTALLER"

# ---------- Create bottle ----------
echo
echo "[INFO] Checking Bottle '$BOTTLE_NAME'..."

if ! flatpak run --command=bottles-cli "$BOTTLES_APP" list bottles 2>/dev/null \
    | grep -Fqx "$BOTTLE_NAME"; then

    echo "[INFO] Creating Bottle '$BOTTLE_NAME'..."
    flatpak run --command=bottles-cli "$BOTTLES_APP" new \
        --bottle-name "$BOTTLE_NAME" \
        --environment application \
        --arch win64
else
    echo "[OK] Bottle '$BOTTLE_NAME' already exists."
fi

# ---------- Install Zalo ----------
echo
echo "[INFO] Launching ZaloSetup.exe inside Bottles..."
echo "[INFO] Hoàn tất trình cài Zalo trước khi quay lại Terminal."

# Official Bottles CLI syntax: -b/--bottle + -e/--executable.
flatpak run --command=bottles-cli "$BOTTLES_APP" run \
    --bottle "$BOTTLE_NAME" \
    --executable "$INSTALLER"

# ---------- Find installed executable ----------
BOTTLE_PATH="$HOME/.var/app/$BOTTLES_APP/data/bottles/bottles/$BOTTLE_NAME"

echo
echo "[INFO] Searching installed Zalo.exe..."

ZALO_EXE="$(find "$BOTTLE_PATH/drive_c" -type f -iname 'Zalo.exe' \
    2>/dev/null \
    | grep -v '/plugins/' \
    | grep -v '/capture/' \
    | head -n1 || true)"

if [[ -z "$ZALO_EXE" ]]; then
    echo "[WARN] Không tự tìm thấy Zalo.exe."
    echo "[INFO] Mở Bottles và vào Bottle '$BOTTLE_NAME' > Programs > Refresh."
    exit 0
fi

echo "[OK] Zalo executable:"
echo "$ZALO_EXE"

# ---------- Launcher ----------
LAUNCHER="$LOCAL_BIN/zalo-bottles"

cat > "$LAUNCHER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

APP="com.usebottles.bottles"
BOTTLE="Zalo"
BOTTLE_PATH="$HOME/.var/app/$APP/data/bottles/bottles/$BOTTLE"

EXE="$(find "$BOTTLE_PATH/drive_c" -type f -iname 'Zalo.exe' \
    2>/dev/null \
    | grep -v '/plugins/' \
    | grep -v '/capture/' \
    | head -n1 || true)"

if [[ -z "$EXE" ]]; then
    if command -v zenity >/dev/null 2>&1; then
        zenity --error --title="Zalo Bottles" \
            --text="Không tìm thấy Zalo.exe trong Bottle Zalo." || true
    else
        echo "Không tìm thấy Zalo.exe trong Bottle Zalo."
    fi
    exit 1
fi

exec flatpak run --command=bottles-cli "$APP" run \
    --bottle "$BOTTLE" \
    --executable "$EXE"
EOF

chmod 700 "$LAUNCHER"

# ---------- Desktop entry ----------
DESKTOP_FILE="$APP_DIR/zalo-bottles.desktop"

cat > "$DESKTOP_FILE" <<EOF
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

chmod 644 "$DESKTOP_FILE"

if [[ -d "$DESKTOP_DIR" ]]; then
    cp -f "$DESKTOP_FILE" "$DESKTOP_DIR/Zalo.desktop"
    chmod +x "$DESKTOP_DIR/Zalo.desktop"
fi

command -v update-desktop-database >/dev/null 2>&1 && \
    update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true

echo
echo "================================================="
echo "       ZALO BOTTLES INSTALLATION COMPLETE"
echo "================================================="
echo
echo "Bottle   : $BOTTLE_NAME"
echo "Launcher : $LAUNCHER"
echo
echo "Mở Zalo từ Menu hoặc Desktop."
