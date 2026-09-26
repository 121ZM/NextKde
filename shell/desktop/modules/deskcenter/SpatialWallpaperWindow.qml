import QtQuick
import Quickshell
import Quickshell.Wayland

// Separate wallpaper surface: widget glass asks KWin to blur the window
// behind it, so the wallpaper must not be painted inside DeskCenterWindow.
PanelWindow {
    id: root

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.namespace: "kos-spatial-wallpaper"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { top: true; left: true; right: true; bottom: true }
    implicitWidth: screen?.width ?? 1920
    implicitHeight: screen?.height ?? 1080
    mask: Region {}

    property real pointerX: 0
    property real pointerY: 0
    readonly property bool active: wallpaperLayer.active

    WallpaperImageLayer {
        id: ordinaryWallpaper
        anchors.fill: parent
        targetScreen: root.screen
        source: WallpaperPreviewService.active ? WallpaperPreviewService.image
            : WallpaperService.takeoverEnabled ? WallpaperService.wallpaperUrl : ""
        fitMode: WallpaperService.fitMode
        transition: WallpaperService.transition
        visible: (WallpaperPreviewService.active || WallpaperService.takeoverEnabled) && ordinaryWallpaper.ready
            && !wallpaperLayer.visualReady
    }

    DepthWallpaperLayer {
        id: wallpaperLayer
        anchors.fill: parent
        targetScreen: root.screen
        pointerX: root.pointerX
        pointerY: root.pointerY
    }
}
