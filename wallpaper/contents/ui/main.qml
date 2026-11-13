// Live2DViewerEX as a real Plasma wallpaper.
// The viewer (Steam/Proton) keeps rendering into its own window, which the KWin script "live2dviewerex-wallpaper"
// parks out of sight. This plugin shows that window's live picture in the wallpaper layer - so desktop icons,
// widgets and Plasma's own right-click menu stay on top and keep working - and tells the viewer about clicks.
import QtQuick
import org.kde.plasma.plasmoid

WallpaperItem {
    id: root

    Live {
        anchors.fill: parent
        config: root.configuration
        desktop: root.parent        // the containment item: everything on the desktop lives in it
    }
}
