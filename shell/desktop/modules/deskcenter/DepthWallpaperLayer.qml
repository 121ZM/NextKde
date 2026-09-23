import QtQuick
import qs.desktop.modules.deskcenter
import qs.desktop.modules.common

// GPU-only wallpaper presentation. The worker prepares optional layered
// assets; this item falls back to the depth shader when they are unavailable.
Item {
    id: root

    property var targetScreen: null
    readonly property bool selectedOutput: targetScreen !== null
        && targetScreen !== undefined
        && ScreenLifecycle.activeScreen !== null
        && targetScreen.name === ScreenLifecycle.activeScreen.name
    readonly property bool active: selectedOutput && SpatialWallpaperService.ready
    visible: selectedOutput
    property real pointerX: 0
    property real pointerY: 0
    property real renderedPointerX: pointerX
    property real renderedPointerY: pointerY
    Behavior on renderedPointerX { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on renderedPointerY { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

    // ShaderEffect receives the raw Image texture, not Image's fillMode.
    // Recreate PreserveAspectCrop in texture coordinates for both inputs.
    readonly property real sourceAspect: sourceImage.implicitHeight > 0
        ? sourceImage.implicitWidth / sourceImage.implicitHeight : 1
    readonly property real outputAspect: height > 0 ? width / height : 1
    readonly property real outputScale: targetScreen
        ? Math.max(1, Number(targetScreen.devicePixelRatio || 1)) : 1
    readonly property size textureSize: Qt.size(
        Math.max(1, Math.round(width * outputScale)),
        Math.max(1, Math.round(height * outputScale)))
    readonly property vector2d cropScale: Qt.vector2d(
        Math.min(1, outputAspect / sourceAspect),
        Math.min(1, sourceAspect / outputAspect))
    readonly property bool layeredTexturesReady:
        SpatialWallpaperService.layeredReady
        && backgroundImage.status === Image.Ready
        && matteImage.status === Image.Ready
        && influenceImage.status === Image.Ready

    onActiveChanged: console.log("[DepthWallpaperLayer] active=" + active
        + " output=" + (targetScreen ? targetScreen.name : "none"))

    Image {
        id: sourceImage
        anchors.fill: parent
        visible: false
        source: root.active ? SpatialWallpaperService.wallpaperUrl : ""
        sourceSize: root.textureSize
        fillMode: Image.PreserveAspectCrop
        autoTransform: true
        asynchronous: true
        cache: true
        onStatusChanged: {
            if (status === Image.Error)
                console.warn("[DepthWallpaperLayer] source image failed: " + source)
        }
    }

    Image {
        id: depthImage
        anchors.fill: parent
        visible: false
        source: root.active ? SpatialWallpaperService.depthPath : ""
        sourceSize: root.textureSize
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        onStatusChanged: {
            if (status === Image.Error)
                console.warn("[DepthWallpaperLayer] depth image failed: " + source)
        }
    }

    Image {
        id: backgroundImage
        anchors.fill: parent
        visible: false
        source: root.active && SpatialWallpaperService.layeredReady
            ? SpatialWallpaperService.backgroundPath : ""
        sourceSize: root.textureSize
        asynchronous: true
        cache: true
        onStatusChanged: {
            if (status === Image.Error)
                console.warn("[DepthWallpaperLayer] background failed: " + source)
        }
    }

    Image {
        id: matteImage
        anchors.fill: parent
        visible: false
        source: root.active && SpatialWallpaperService.layeredReady
            ? SpatialWallpaperService.mattePath : ""
        sourceSize: root.textureSize
        asynchronous: true
        cache: true
        onStatusChanged: {
            if (status === Image.Error)
                console.warn("[DepthWallpaperLayer] matte failed: " + source)
        }
    }

    Image {
        id: influenceImage
        anchors.fill: parent
        visible: false
        source: root.active && SpatialWallpaperService.layeredReady
            ? SpatialWallpaperService.influencePath : ""
        sourceSize: root.textureSize
        asynchronous: true
        cache: true
        onStatusChanged: {
            if (status === Image.Error)
                console.warn("[DepthWallpaperLayer] influence failed: " + source)
        }
    }

    ShaderEffect {
        anchors.fill: parent
        visible: root.active && sourceImage.status === Image.Ready
            && depthImage.status === Image.Ready && !root.layeredTexturesReady
        property variant source: sourceImage
        property variant depthMap: depthImage
        property vector2d pointer: Qt.vector2d(root.renderedPointerX,
            root.renderedPointerY)
        property vector2d cropScale: root.cropScale
        fragmentShader: Qt.resolvedUrl("../../shaders/depth_parallax.frag.qsb")
    }

    ShaderEffect {
        anchors.fill: parent
        visible: root.active && sourceImage.status === Image.Ready
            && root.layeredTexturesReady
        property variant source: sourceImage
        property variant background: backgroundImage
        property variant matte: matteImage
        property variant influence: influenceImage
        property vector2d pointer: Qt.vector2d(root.renderedPointerX,
            root.renderedPointerY)
        property vector2d cropScale: root.cropScale
        fragmentShader: Qt.resolvedUrl("../../shaders/layered_wallpaper.frag.qsb")
    }

}
