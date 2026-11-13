#!/bin/bash
# Installs (or updates) Live2DViewerEX-as-a-Plasma-wallpaper for the current user. No root needed. Safe to re-run.
#   ./install.sh              install everything and switch the desktop to the "Live2DViewerEX (live)" wallpaper
#   ./install.sh --no-switch  install, but leave the current wallpaper type alone
# If Live2DViewerEX is not found automatically:  L2DEX_DIR=/path/to/steamapps/common/Live2DViewerEX ./install.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
PLUGIN=local.live2dviewerex.stream
SCRIPT=live2dviewerex-wallpaper
EFFECT=live2dviewerex-hide
LAUNCH_OPTIONS="bash -c 'exec \"\${@/launcher.exe/progman_shim.exe}\"' -- %command%"
BACKUP="$DATA/l2dex/backup-$(date +%Y%m%d-%H%M%S)"
FIRST=1; [ -e "$DATA/l2dex/installed" ] && FIRST=0      # only what was there before the first install is backed up
SWITCH=1; [ "${1:-}" = "--no-switch" ] && SWITCH=0

say() { printf '\n== %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
keep() { [ "$FIRST" = 1 ] && [ -e "$1" ] || return 0; mkdir -p "$BACKUP"; cp -a "$1" "$BACKUP/"; }
plasma() { gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell --method org.kde.PlasmaShell.evaluateScript "$1"; }

# --- checks ---------------------------------------------------------------------------------------------------------
[ "${XDG_CURRENT_DESKTOP:-}" = KDE ] || echo "Warning: this is made for KDE Plasma 6; XDG_CURRENT_DESKTOP is '${XDG_CURRENT_DESKTOP:-}'."
for c in gdbus busctl kwriteconfig6 python3; do
    command -v "$c" >/dev/null || die "'$c' is missing (KDE Plasma 6, systemd and python3 are needed)."
done
/usr/bin/python3 -I -c 'import gi; gi.require_version("Gio", "2.0"); from gi.repository import Gio' 2>/dev/null ||
    die "PyGObject is missing. Install it:  Fedora: sudo dnf install python3-gobject   Arch: sudo pacman -S python-gobject   Debian/Ubuntu: sudo apt install python3-gi"

# --- find Live2DViewerEX in any Steam library (native or Flatpak Steam) ---------------------------------------------
find_app() {
    [ -n "${L2DEX_DIR:-}" ] && { echo "$L2DEX_DIR"; return; }
    local roots=("${STEAM_DIR:-}" "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.steam/root"
                 "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam" "$HOME/.var/app/com.valvesoftware.Steam/data/Steam")
    local r lib
    for r in "${roots[@]}"; do
        [ -n "$r" ] && [ -d "$r" ] || continue
        for lib in "$r" $( [ -f "$r/steamapps/libraryfolders.vdf" ] &&
                            sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$r/steamapps/libraryfolders.vdf" | tr ' ' '\001'); do
            lib="$(printf '%s' "$lib" | tr '\001' ' ')"
            [ -d "$lib/steamapps/common/Live2DViewerEX/bin" ] && { echo "$lib/steamapps/common/Live2DViewerEX"; return; }
        done
    done
}
APP="$(find_app)"
[ -n "$APP" ] && [ -d "$APP/bin" ] ||
    die "Live2DViewerEX was not found. Install it in Steam first, or run:  L2DEX_DIR=/path/to/steamapps/common/Live2DViewerEX ./install.sh"
echo "Live2DViewerEX: $APP"
mkdir -p "$CONF/l2dex"; printf '%s\n' "$APP" > "$CONF/l2dex/app_dir"

# --- install --------------------------------------------------------------------------------------------------------
say "Input bridge (D-Bus activated: local.l2dex.Bridge)"
install -Dm755 "$HERE/bridge/l2dex-bridge" "$HOME/.local/bin/l2dex-bridge"
mkdir -p "$DATA/dbus-1/services"
printf '[D-BUS Service]\nName=local.l2dex.Bridge\nExec=/usr/bin/python3 -I %s\n' "$HOME/.local/bin/l2dex-bridge" > "$DATA/dbus-1/services/local.l2dex.Bridge.service"
busctl --user --auto-start=no call local.l2dex.Bridge /Bridge local.l2dex.Bridge Quit >/dev/null 2>&1 || true   # a running old copy; the next cursor move starts the new one
busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig >/dev/null

say "Plasma wallpaper plugin ($PLUGIN)"
keep "$DATA/plasma/wallpapers/$PLUGIN"
rm -rf "$DATA/plasma/wallpapers/$PLUGIN"; mkdir -p "$DATA/plasma/wallpapers"
cp -a "$HERE/wallpaper" "$DATA/plasma/wallpapers/$PLUGIN"

say "KWin effect ($EFFECT)"
rm -rf "$DATA/kwin/effects/$EFFECT"; mkdir -p "$DATA/kwin/effects"
cp -a "$HERE/effect" "$DATA/kwin/effects/$EFFECT"
kwriteconfig6 --file kwinrc --group Plugins --key "${EFFECT}Enabled" true
gdbus call --session --dest org.kde.KWin --object-path /Effects --method org.kde.kwin.Effects.unloadEffect "$EFFECT" >/dev/null || true
echo "loaded: $(gdbus call --session --dest org.kde.KWin --object-path /Effects --method org.kde.kwin.Effects.loadEffect "$EFFECT")"

say "KWin script ($SCRIPT)"
keep "$DATA/kwin/scripts/$SCRIPT"
rm -rf "$DATA/kwin/scripts/$SCRIPT"; mkdir -p "$DATA/kwin/scripts"
cp -a "$HERE/kwin" "$DATA/kwin/scripts/$SCRIPT"
kwriteconfig6 --file kwinrc --group Plugins --key "${SCRIPT}Enabled" true
gdbus call --session --dest org.kde.KWin --object-path /Scripting --method org.kde.kwin.Scripting.unloadScript "$SCRIPT" >/dev/null || true
gdbus call --session --dest org.kde.KWin --object-path /KWin --method org.kde.KWin.reconfigure >/dev/null
sleep 1
echo "loaded: $(gdbus call --session --dest org.kde.KWin --object-path /Scripting --method org.kde.kwin.Scripting.isScriptLoaded "$SCRIPT")"

say "Launch shim (Steam starts progman_shim.exe instead of launcher.exe)"
SHIM_PENDING=0
if ! cmp -s "$HERE/shim/progman_shim.exe" "$APP/progman_shim.exe"; then
    if pgrep -f 'lwtray\.exe' >/dev/null; then
        SHIM_PENDING=1
        echo "Live2DViewerEX is running: progman_shim.exe NOT replaced. Quit it (tray icon -> Exit) and run ./install.sh again."
    else
        keep "$APP/progman_shim.exe"
        install -m755 "$HERE/shim/progman_shim.exe" "$APP/progman_shim.exe"
        echo "installed"
    fi
else
    echo "already current"
fi

if [ "$SWITCH" = 1 ]; then
    say "Desktop wallpaper type -> Live2DViewerEX (live) (your current picture is kept for when the viewer is closed)"
    plasma "desktops().forEach(function (d) {
        if (d.wallpaperPlugin != 'org.kde.image') return;
        d.currentConfigGroup = ['Wallpaper', 'org.kde.image', 'General'];
        var img = String(d.readConfig('Image') || ''), fill = parseInt(d.readConfig('FillMode'));
        d.wallpaperPlugin = '$PLUGIN';
        d.currentConfigGroup = ['Wallpaper', '$PLUGIN', 'General'];
        if (/\\.(png|jpe?g|webp|avif|bmp)\$/i.test(img)) d.writeConfig('FallbackImage', img);
        if (fill >= 0 && fill <= 2) d.writeConfig('FillMode', fill);
        d.writeConfig('WindowUuid', '');
        d.reloadConfig();
    });" >/dev/null
fi

mkdir -p "$DATA/l2dex"; touch "$DATA/l2dex/installed"
[ -d "$BACKUP" ] && echo "Previous files were copied to $BACKUP"

COPIED=""
if command -v wl-copy >/dev/null && printf '%s' "$LAUNCH_OPTIONS" | wl-copy 2>/dev/null; then COPIED=" (already copied to your clipboard)"
elif command -v xclip >/dev/null && printf '%s' "$LAUNCH_OPTIONS" | xclip -selection clipboard 2>/dev/null; then COPIED=" (already copied to your clipboard)"; fi

cat <<EOF

================================================================================================================
 Installed.$( [ "$SHIM_PENDING" = 1 ] && echo "  (Shim still pending - quit the viewer and run ./install.sh again.)")

 Last step, only once: in Steam, right-click Live2DViewerEX -> Properties -> General -> Launch Options, paste$COPIED:

   $LAUNCH_OPTIONS

 Then start Live2DViewerEX from Steam. In its Control Panel pick Launch Mode "Wallpaper" (or "Desktop").
================================================================================================================
EOF
