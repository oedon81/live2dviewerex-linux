import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls

Kirigami.FormLayout {
    id: root
    twinFormLayouts: parentLayout
    property alias formLayout: root

    property string cfg_WindowUuid              // owned by the KWin script; kept as it is
    property alias cfg_FallbackImage: imageField.text
    property alias cfg_FallbackColor: colorButton.color
    property int cfg_FillMode: Image.PreserveAspectCrop
    property alias cfg_ForwardClicks: clicks.checked
    property alias cfg_ForwardRightClicks: rightClicks.checked
    property alias cfg_ForwardWheel: wheel.checked

    // Plasma also hands over each entry's default; declared so that does not log warnings
    property string cfg_WindowUuidDefault
    property string cfg_FallbackImageDefault
    property color cfg_FallbackColorDefault
    property int cfg_FillModeDefault
    property bool cfg_ForwardClicksDefault
    property bool cfg_ForwardRightClicksDefault
    property bool cfg_ForwardWheelDefault

    QQC2.Label {
        Kirigami.FormData.label: "Viewer:"
        text: root.cfg_WindowUuid ? "running - its wallpaper is shown live" : "not running - the picture below is shown"
    }

    RowLayout {
        Kirigami.FormData.label: "Picture when not running:"
        QQC2.TextField {
            id: imageField
            Layout.minimumWidth: Kirigami.Units.gridUnit * 18
            placeholderText: "none (plain colour)"
        }
        QQC2.Button {
            icon.name: "document-open"
            text: "Choose…"
            onClicked: picker.open()
        }
    }

    QQC2.ComboBox {
        Kirigami.FormData.label: "Positioning:"
        model: [ { text: "Scaled and cropped", mode: Image.PreserveAspectCrop },
                 { text: "Scaled, keep proportions", mode: Image.PreserveAspectFit },
                 { text: "Stretched", mode: Image.Stretch } ]
        textRole: "text"
        valueRole: "mode"
        currentIndex: Math.max(0, indexOfValue(root.cfg_FillMode))
        onActivated: root.cfg_FillMode = currentValue
        Component.onCompleted: currentIndex = Math.max(0, indexOfValue(root.cfg_FillMode))
    }

    KQuickControls.ColorButton {
        id: colorButton
        Kirigami.FormData.label: "Background colour:"
        dialogTitle: "Select Background Colour"
    }

    Item { Kirigami.FormData.isSection: true }

    QQC2.CheckBox {
        id: clicks
        Kirigami.FormData.label: "Pass on to the viewer:"
        text: "Left clicks and drags on the desktop"
    }
    QQC2.CheckBox {
        id: rightClicks
        text: "Right clicks (Plasma's desktop menu opens as well)"
    }
    QQC2.CheckBox {
        id: wheel
        text: "Mouse wheel over the empty desktop"
    }

    FileDialog {
        id: picker
        title: "Choose a Picture"
        nameFilters: ["Pictures (*.png *.jpg *.jpeg *.webp *.avif *.bmp)", "All files (*)"]
        onAccepted: imageField.text = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""))
    }
}
