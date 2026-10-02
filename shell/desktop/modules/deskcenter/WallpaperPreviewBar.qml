import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.common

// Full-screen desktop wallpaper preview with a floating glass control shelf.
PanelWindow {
    id: stage
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.namespace: "kos-wallpaper-preview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: stage.screen === ScreenLifecycle.activeScreen
        && stage.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    focusable: stage.screen === ScreenLifecycle.activeScreen && stage.visible
    anchors { top: true; left: true; right: true; bottom: true }
    implicitWidth: screen?.width ?? 1920
    implicitHeight: screen?.height ?? 1080

    property real pointerX: 0
    property real pointerY: 0
    property bool depthEnabled: true
    readonly property bool primaryOutput: screen === ScreenLifecycle.activeScreen
    readonly property bool compact: width < 1100 || height < 760
    readonly property real trayHeight: compact ? 70 : 74

    Rectangle { anchors.fill: parent; color: "#101a24" }
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: mouse => {
            stage.pointerX = Math.max(-1, Math.min(1, mouse.x / Math.max(1, width) * 2 - 1))
            stage.pointerY = Math.max(-1, Math.min(1, mouse.y / Math.max(1, height) * 2 - 1))
        }
        onExited: { stage.pointerX = 0; stage.pointerY = 0 }
    }

    Item {
        id: composition
        anchors.fill: parent

        Rectangle {
            id: canvas
            anchors.fill: parent
            radius: 0
            color: "transparent"
            border.width: 0
            clip: true
            WallpaperImageLayer {
                anchors.fill: parent
                previewTarget: true
                targetScreen: stage.screen
                source: WallpaperPreviewService.active ? WallpaperPreviewService.image : ""
                fitMode: WallpaperService.fitMode
                transition: WallpaperService.transition
                scale: 1.04
                transform: Translate {
                    x: stage.depthEnabled ? -stage.pointerX * 12 : 0
                    y: stage.depthEnabled ? -stage.pointerY * 8 : 0
                    Behavior on x { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
                }
            }
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0; color: "#2e020914" }
                    GradientStop { position: 0.5; color: "#00000000" }
                    GradientStop { position: 1; color: "#5a020914" }
                }
            }
            Row {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: stage.compact ? 24 : 36
                spacing: 13
                Repeater {
                    model: 4
                    delegate: Rectangle {
                        width: stage.compact ? 30 : 37
                        height: width
                        radius: 11
                        color: "#70dcebf4"
                        border.color: "#9effffff"
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width * 0.4
                            height: width
                            radius: index % 2 ? width / 2 : 4
                            color: "#00ffffff"
                            border.width: 1
                            border.color: "#e7ffffff"
                        }
                    }
                }
            }
            Text {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: stage.compact ? 25 : 37
                text: Qt.formatTime(new Date(), "hh:mm")
                color: "#ffffff"
                font.pixelSize: stage.compact ? 14 : 16
                font.weight: Font.Medium
                style: Text.Outline
                styleColor: "#60000000"
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: stage.trayHeight + 52
                width: dockIcons.implicitWidth + 20
                height: stage.compact ? 43 : 49
                radius: 17
                color: "#4cdceaf2"
                border.color: "#68ffffff"
                Row {
                    id: dockIcons
                    anchors.centerIn: parent
                    spacing: 8
                    Repeater {
                        model: 5
                        delegate: Rectangle {
                            width: stage.compact ? 28 : 33
                            height: width
                            radius: 10
                            color: index % 2 ? "#d9f0f7" : "#b9e1ef"
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width * 0.38
                                height: width
                                radius: index % 2 ? width / 2 : 3
                                color: "#7698a8"
                            }
                        }
                    }
                }
            }
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 2
                color: "#68ffffff"
            }
        }

        Rectangle {
            id: tray
            visible: stage.primaryOutput && WallpaperPreviewService.presented
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 22
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width - 32, 548)
            height: stage.trayHeight
            radius: stage.compact ? 21 : 25
            color: "#26d9eef8"
            border.width: 1
            border.color: "#78ffffff"
            clip: true
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#5c091826"
                shadowBlur: 0.68
                shadowVerticalOffset: 14
            }
            Rectangle {
                id: trayImageMask
                anchors.fill: parent
                radius: tray.radius
                visible: false
                layer.enabled: true
            }
            Image {
                anchors.fill: parent
                source: WallpaperPreviewService.active ? WallpaperPreviewService.image : ""
                sourceSize: Qt.size(Math.ceil(width * 0.35), Math.ceil(height * 0.35))
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                opacity: 0.27
                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: 1
                    blurMax: 48
                    maskEnabled: true
                    maskSource: trayImageMask
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: tray.radius
                gradient: Gradient {
                    GradientStop { position: 0; color: "#42ffffff" }
                    GradientStop { position: 0.48; color: "#0cffffff" }
                    GradientStop { position: 1; color: "#20e3f5fa" }
                }
            }
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: tray.radius * 1.6
                anchors.rightMargin: tray.radius * 1.6
                height: 1
                color: "#baffffff"
                opacity: 0.78
            }
            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - 28
                height: 40
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 7
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "景深"
                        color: "#35515e"
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                    Item {
                        implicitWidth: 36
                        Layout.fillHeight: true
                        Accessible.role: Accessible.CheckBox
                        Accessible.name: "景深"
                        Accessible.checked: stage.depthEnabled
                        Accessible.onPressAction: stage.depthEnabled = !stage.depthEnabled
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34
                            height: 20
                            radius: 10
                            color: stage.depthEnabled ? "#59a9cc" : "#7897a5"
                            Behavior on color { ColorAnimation { duration: 160 } }
                            Rectangle {
                                x: stage.depthEnabled ? 16 : 2
                                anchors.verticalCenter: parent.verticalCenter
                                width: 16
                                height: 16
                                radius: 8
                                color: "#f8ffffff"
                                Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: stage.depthEnabled = !stage.depthEnabled
                        }
                    }
                    Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: "#55768c98" }
                    WallpaperPreviewAction {
                        label: "‹"
                        compact: true
                        light: true
                        enabled: WallpaperPreviewService.images.length > 1
                        onTriggered: WallpaperPreviewService.move(-1)
                    }
                    WallpaperPreviewAction {
                        label: "›"
                        compact: true
                        light: true
                        enabled: WallpaperPreviewService.images.length > 1
                        onTriggered: WallpaperPreviewService.move(1)
                    }
                    Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: "#55768c98" }
                    WallpaperPreviewAction {
                        label: "退出预览"
                        light: true
                        onTriggered: WallpaperPreviewService.finish(false)
                    }
                    WallpaperPreviewAction {
                        label: "应用壁纸"
                        primary: true
                        light: true
                        onTriggered: WallpaperPreviewService.finish(true)
                    }
                    Item { Layout.fillWidth: true }
                }
            }
        }
    }

    Text {
        anchors.centerIn: composition
        visible: !WallpaperPreviewService.presented
        text: "正在准备壁纸预览…"
        color: "#ffffff"
        font.pixelSize: 16
        style: Text.Outline
        styleColor: "#99000000"
    }
    contentItem.focus: stage.primaryOutput && stage.visible
    contentItem.Keys.onEscapePressed: WallpaperPreviewService.finish(false)
    contentItem.Keys.onReturnPressed: WallpaperPreviewService.finish(true)
    contentItem.Keys.onLeftPressed: WallpaperPreviewService.move(-1)
    contentItem.Keys.onRightPressed: WallpaperPreviewService.move(1)
}
