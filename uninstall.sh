#!/bin/bash
# Removes what install.sh added and puts the desktop back on the plain picture wallpaper.
# Afterwards: clear Live2DViewerEX's Steam Launch Options and start the viewer once with L2D_WINE_TRAY=1 in front of
# the old options if you want Wine's own tray icon back. progman_shim.exe in the app folder can then be deleted.
set -euo pipefail
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
PLUGIN=local.live2dviewerex.stream
SCRIPT=live2dviewerex-wallpaper
EFFECT=live2dviewerex-hide
gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell --method org.kde.PlasmaShell.evaluateScript \
  "desktops().forEach(function (d) { if (d.wallpaperPlugin == '$PLUGIN') { d.wallpaperPlugin = 'org.kde.image'; d.reloadConfig(); } });"
kwriteconfig6 --file kwinrc --group Plugins --key "${SCRIPT}Enabled" false
kwriteconfig6 --file kwinrc --group Plugins --key "${EFFECT}Enabled" false
gdbus call --session --dest org.kde.KWin --object-path /Scripting --method org.kde.kwin.Scripting.unloadScript "$SCRIPT" >/dev/null || true
gdbus call --session --dest org.kde.KWin --object-path /Effects --method org.kde.kwin.Effects.unloadEffect "$EFFECT" >/dev/null || true
busctl --user --auto-start=no call local.l2dex.Bridge /Bridge local.l2dex.Bridge Quit >/dev/null 2>&1 || true
rm -rf "$DATA/kwin/scripts/$SCRIPT" "$DATA/kwin/effects/$EFFECT" "$DATA/plasma/wallpapers/$PLUGIN"
rm -f "$DATA/dbus-1/services/local.l2dex.Bridge.service" "$HOME/.local/bin/l2dex-bridge" "$DATA/l2dex/installed" "$CONF/l2dex/app_dir"
busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig
echo "Removed. Now clear the Launch Options of Live2DViewerEX in Steam (Properties -> General)."
