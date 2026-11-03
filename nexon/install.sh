#!/usr/bin/env bash
# Set up Nexon Launcher under Wine. Run after wine/install-winehq-stable.sh.
#
#   bash nexon/install.sh [path/to/NexonLauncherSetup.exe]
#
# Download NexonLauncherSetup.exe yourself from nexon.com (default location:
# ~/Downloads/NexonLauncherSetup.exe). Steps:
#   1. Create a dedicated 64-bit prefix ~/.wine-nexon (Windows 10 mode)
#   2. Install DXVK 2.3 (Direct3D -> Vulkan) for games
#   3. Make the launcher UI itself (nexon_client.exe) use Wine's built-in Direct3D
#   4. Run the Nexon installer (you click through it and accept Nexon's terms)
#   5. Let the launcher's first-run update finish, then close it
#   6. Patch app.asar (crash fix + no promotion pop-up)
#   7. Install ~/.local/bin/nexon-launcher, a menu entry, and the nxl:// link handler
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SETUP=${1:-$HOME/Downloads/NexonLauncherSetup.exe}
export WINEPREFIX="$HOME/.wine-nexon" WINEARCH=win64 WINEDEBUG=-all
P="$WINEPREFIX/drive_c/Program Files (x86)/Nexon/Nexon Launcher"
step() { printf '\n\033[1;35m==== %s\033[0m\n' "$1"; }

command -v wine >/dev/null || { echo "Wine not installed. Run wine/install-winehq-stable.sh first."; exit 1; }
command -v winetricks >/dev/null || { echo "winetricks missing: sudo apt install winetricks"; exit 1; }
WV=$(wine --version | sed -E 's/^wine-([0-9]+).*/\1/')
if [ "${WV:-0}" -lt 10 ]; then
  echo "WARNING: $(wine --version) detected. Nexon Launcher needs Wine 10+ (WineHQ 11 tested)."
  echo "         Ubuntu's Wine 9.0 crashes the launcher. Run wine/install-winehq-stable.sh."
fi

step "1. Prefix ~/.wine-nexon (Windows 10)"
wineboot -u >/dev/null 2>&1 || true
winetricks -q win10 >/dev/null

step "2. DXVK 2.3"
# 2.3 is the version tested here. (Newer DXVK 3.x needs a newer Vulkan feature
# set than Ubuntu's Wine 9.0 exposed; with WineHQ 11 newer DXVK may also work.)
winetricks -q -f dxvk2030 >/dev/null

step "3. Launcher UI (nexon_client.exe) uses Wine's built-in Direct3D"
K='HKCU\Software\Wine\AppDefaults\nexon_client.exe\DllOverrides'
# The '*' form is required: winetricks writes '*d3d11=native' globally, which
# beats plain 'd3d11' entries.
for d in d3d11 dxgi d3d10core d3d9; do wine reg add "$K" /v "*$d" /d builtin /f >/dev/null; done

step "4. Nexon installer"
if [ -f "$P/bin/nexon_client/nexon_client.exe" ]; then
  echo "Already installed, skipping installer."
else
  [ -f "$SETUP" ] || { echo "Installer not found: $SETUP (download it from nexon.com)"; exit 1; }
  echo "Click through the installer window (keep the default folder)."
  wine "$SETUP" || true
fi

step "5. Wait for the launcher's first-run update, then close it"
# The installer starts nexon_launcher.exe, which updates the UI files and then
# starts nexon_client.exe (that first window may be blank: it lacks the fix yet).
sleep 20
for _ in $(seq 1 180); do
  pgrep -f '^C:.*\\nexon_client\.exe' >/dev/null && break
  [ -f "$P/bin/nexon_client/resources/app.asar" ] && ! pgrep -f '^C:.*nexon_' >/dev/null && break
  sleep 1
done
sleep 5; wineserver -k || true; sleep 1
[ -f "$P/bin/nexon_client/resources/app.asar" ] || { echo "Launcher files missing - did the installer finish?"; exit 1; }

step "6. Patch app.asar"
install -Dm755 "$HERE/patch-app-asar.sh" "$HOME/.local/bin/nexon-launcher-patch"
"$HOME/.local/bin/nexon-launcher-patch"

step "7. Launch script, menu entry, nxl:// handler"
install -Dm755 "$HERE/nexon-launcher" "$HOME/.local/bin/nexon-launcher"
APPS="$HOME/.local/share/applications"; mkdir -p "$APPS"
ICON=$(ls "$HOME"/.local/share/icons/hicolor/*/apps/*logo*.png 2>/dev/null | tail -1 || true)
cat > "$APPS/nexon-launcher-wine.desktop" <<EOF
[Desktop Entry]
Name=Nexon Launcher (Wine)
Comment=Nexon Launcher running under Wine (~/.wine-nexon)
Exec=$HOME/.local/bin/nexon-launcher %u
Type=Application
Icon=${ICON:-wine}
Categories=Game;
MimeType=x-scheme-handler/nxl;
StartupWMClass=nexon_client.exe
EOF
xdg-mime default nexon-launcher-wine.desktop x-scheme-handler/nxl
# Hide Wine's auto-generated entry: it starts nexon_launcher.exe without the fix.
W="$APPS/wine/Programs/Nexon/Nexon Launcher.desktop"
[ -f "$W" ] && { grep -q '^NoDisplay=true' "$W" || echo 'NoDisplay=true' >> "$W"; }
update-desktop-database "$APPS" 2>/dev/null || true

echo
echo "Done. Start \"Nexon Launcher (Wine)\" from the app menu, or run: ~/.local/bin/nexon-launcher"
