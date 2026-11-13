import QtQuick
import org.kde.taskmanager as TaskManager
import org.kde.pipewire as PipeWire
import org.kde.plasma.workspace.dbus as DBus

Item {
    id: live

    required property var config    // the wallpaper's configuration (see ../config/main.xml)
    property Item desktop: null     // item that holds the icons and widgets; clicks are observed on top of it

    readonly property bool streaming: stream.nodeId > 0

    function fileUrl(s) {
        if (!s) return "";
        return s.charAt(0) === "/" ? "file://" + s.split("/").map(encodeURIComponent).join("/") : s;
    }

    // l2dex-bridge (D-Bus activated) hands these on to the viewer; see its header for the tokens
    function send(tokens) {
        DBus.SessionBus.asyncCall({ service: "local.l2dex.Bridge", path: "/Bridge", iface: "local.l2dex.Bridge",
                                    member: "Event", arguments: [tokens] }, function () {}, function () {});
    }

    Rectangle {
        anchors.fill: parent
        color: live.config.FallbackColor
    }

    Image {
        anchors.fill: parent
        source: live.fileUrl(live.config.FallbackImage)
        fillMode: live.config.FillMode
        sourceSize: Qt.size(live.width * Screen.devicePixelRatio, live.height * Screen.devicePixelRatio)
        asynchronous: true
        cache: false
    }

    TaskManager.ScreencastingRequest {
        id: cast
        uuid: live.config.WindowUuid
    }

    PipeWire.PipeWireSourceItem {
        id: stream
        anchors.fill: parent
        nodeId: cast.nodeId
        opacity: nodeId > 0 && ready ? 1 : 0      // stays "visible" at 0: a hidden item would pause the stream
        Behavior on opacity { NumberAnimation { duration: 250 } }
    }

    // Invisible layer above the icons. Its handlers only watch (passive grabs): every press still reaches the
    // icons, widgets and Plasma's desktop menu exactly as before. The viewer gets the same down/up it would get
    // from its global mouse hook on Windows; the cursor position comes from the KWin script.
    Item {
        parent: live.desktop
        anchors.fill: parent
        z: 999999
        visible: live.streaming

        PointHandler {
            acceptedButtons: Qt.LeftButton
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            enabled: live.config.ForwardClicks
            onActiveChanged: live.send(active ? "d" : "u")
        }
        PointHandler {
            acceptedButtons: Qt.RightButton
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            enabled: live.config.ForwardRightClicks
            onActiveChanged: live.send(active ? "rd" : "ru")
        }
    }

    // Wheel turns that nothing on the desktop used (no icon view or widget scrolled)
    WheelHandler {
        property real turned: 0
        parent: live.desktop
        target: null
        blocking: false
        acceptedDevices: PointerDevice.Mouse
        enabled: live.streaming && live.config.ForwardWheel
        onWheel: (ev) => {
            turned += ev.angleDelta.y;
            for (; turned >= 120; turned -= 120) live.send("wu");
            for (; turned <= -120; turned += 120) live.send("wd");
        }
    }
}
