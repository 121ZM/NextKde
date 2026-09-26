import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.common

// The controls alone sit above the desktop. The preview image remains in the
// existing wallpaper surface, with one extra bounded texture during a switch.
PanelWindow {
    id: bar
    screen: ScreenLifecycle.activeScreen
    visible: WallpaperPreviewService.active && WallpaperPreviewService.presented
    color: "transparent"
    anchors.bottom: true
    margins.bottom: 76
    implicitWidth: Math.min(560, (screen?.width || 800) - 32)
    implicitHeight: 82
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.namespace: "kos-wallpaper-preview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
        id: glass
        anchors.fill: parent
        anchors.margins: 4
        radius: 23
        color: "#d721252b"
        border.color: "#88ffffff"
        border.width: 1
        gradient: Gradient {
            GradientStop { position: 0; color: "#df40464d" }
            GradientStop { position: 0.5; color: "#e924292f" }
            GradientStop { position: 1; color: "#ef14191f" }
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            height: 1
            color: "#aaffffff"
            opacity: 0.7
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 8
            WallpaperPreviewAction {
                label: "‹"
                compact: true
                enabled: WallpaperPreviewService.images.length > 1
                opacity: enabled ? 1 : 0.4
                onTriggered: WallpaperPreviewService.move(-1)
            }
            WallpaperPreviewAction {
                label: "›"
                compact: true
                enabled: WallpaperPreviewService.images.length > 1
                opacity: enabled ? 1 : 0.4
                onTriggered: WallpaperPreviewService.move(1)
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                spacing: 3
                Text {
                    text: "桌面预览"
                    color: "white"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text {
                    text: WallpaperPreviewService.remainingSeconds + " 秒后恢复 · ← → 切换"
                    color: "#b9ffffff"
                    font.pixelSize: 11
                }
            }
            WallpaperPreviewAction {
                label: "取消"
                onTriggered: WallpaperPreviewService.finish(false)
            }
            WallpaperPreviewAction {
                label: "使用这张"
                primary: true
                onTriggered: WallpaperPreviewService.finish(true)
            }
        }
        Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.leftMargin: glass.radius
            anchors.bottomMargin: 1
            width: Math.max(0, (glass.width - glass.radius * 2)
                * WallpaperPreviewService.remainingSeconds / 60)
            height: 2
            radius: 1
            color: "#9edfff"
            opacity: 0.7
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }
    }
    contentItem.focus: true
    contentItem.Keys.onEscapePressed: WallpaperPreviewService.finish(false)
    contentItem.Keys.onReturnPressed: WallpaperPreviewService.finish(true)
    contentItem.Keys.onLeftPressed: WallpaperPreviewService.move(-1)
    contentItem.Keys.onRightPressed: WallpaperPreviewService.move(1)
}
