import QtQuick
import qs.desktop.modules.deskcenter

// Ordinary wallpaper for every output. Only a switch briefly keeps two
// screen-sized textures; the outgoing image is released when it finishes.
Item {
    id: root

    property url source: ""
    property var targetScreen: null
    property bool previewTarget: false
    property string fitMode: "crop"
    property string transition: "cinematic"
    property real revealProgress: 0
    readonly property bool revealSupported: GraphicsInfo.api !== GraphicsInfo.Software
    readonly property bool useReveal: transition === "cinematic" && revealSupported

    function reportReady(path) {
        if (root.previewTarget) WallpaperPreviewService.imageReady(path, root.targetScreen?.name || "")
        else if (root.targetScreen) WallpaperService.reportImageReady(root.targetScreen.name, path)
    }
    readonly property real pixelRatio: Math.max(1,
        Number(targetScreen?.devicePixelRatio || 1))
    readonly property size decodedSize: Qt.size(
        Math.max(1, Math.ceil(width * pixelRatio * 1.06)),
        Math.max(1, Math.ceil(height * pixelRatio * 1.06)))
    readonly property int imageFillMode: fitMode === "fit"
        ? Image.PreserveAspectFit : fitMode === "stretch"
        ? Image.Stretch : fitMode === "center"
        ? Image.Pad : Image.PreserveAspectCrop
    readonly property bool ready: currentImage.status === Image.Ready
        || nextImage.status === Image.Ready

    function requestSource() {
        const requested = root.source.toString()
        if (!requested) {
            switchAnimation.stop()
            currentImage.source = ""
            nextImage.source = ""
            return
        }
        if (requested === nextImage.source.toString()) {
            if (nextImage.status === Image.Ready) reportReady(requested)
            return
        }
        if (requested === currentImage.source.toString()) {
            if (switchAnimation.running)
                switchAnimation.stop()
            nextImage.source = ""
            currentImage.opacity = 1
            currentImage.scale = 1
            if (currentImage.status === Image.Ready) reportReady(requested)
            return
        }
        if (switchAnimation.running) {
            switchAnimation.stop()
            currentImage.source = nextImage.source
            currentImage.opacity = 1
            currentImage.scale = 1
        }
        nextImage.opacity = 0
        nextImage.scale = 1
        nextImage.source = root.source
    }

    function promote() {
        currentImage.source = nextImage.source
        currentImage.opacity = 1
        currentImage.scale = 1
        nextImage.source = ""
        nextImage.opacity = 0
        nextImage.scale = 1
    }

    onSourceChanged: Qt.callLater(requestSource)
    Component.onCompleted: requestSource()
    Connections {
        target: WallpaperPreviewService
        function onActiveChanged() { Qt.callLater(root.requestSource) }
    }

    Rectangle { anchors.fill: parent; color: "#111111" }

    Image {
        id: currentImage
        anchors.fill: parent
        sourceSize: root.decodedSize
        fillMode: root.imageFillMode
        autoTransform: true
        asynchronous: true
        cache: true
        smooth: true
        onStatusChanged: if (status === Image.Ready) root.reportReady(source.toString())
    }

    Image {
        id: nextImage
        layer.enabled: root.useReveal && switchAnimation.running
        layer.effect: ShaderEffect {
            property real progress: root.revealProgress
            property real direction: WallpaperPreviewService.active ? WallpaperPreviewService.direction : 1
            fragmentShader: Qt.resolvedUrl("../../shaders/wallpaper_reveal.frag.qsb")
        }
        anchors.fill: parent
        opacity: 0
        sourceSize: root.decodedSize
        fillMode: root.imageFillMode
        autoTransform: true
        asynchronous: true
        cache: true
        smooth: true
        onStatusChanged: {
            if (status === Image.Ready
                    && source.toString() === root.source.toString()) {
                root.reportReady(source.toString())
                if (!currentImage.source.toString() || root.transition === "none")
                    root.promote()
                else
                    switchAnimation.start()
            } else if (status === Image.Error) {
                console.warn("[WallpaperImageLayer] image failed: " + source)
                if (root.previewTarget)
                    WallpaperPreviewService.imageFailed(source.toString())
            }
        }
    }

    ParallelAnimation {
        id: switchAnimation
        NumberAnimation {
            target: root
            property: "revealProgress"
            from: 0
            to: 1
            duration: root.useReveal ? 560 : 300
            easing.type: Easing.InOutCubic
        }
        NumberAnimation {
            target: currentImage
            property: "scale"
            from: 1
            to: root.useReveal && root.fitMode === "crop" ? 1.018 : 1
            duration: root.useReveal ? 560 : 300
            easing.type: Easing.InOutCubic
        }
        NumberAnimation {
            target: nextImage
            property: "scale"
            from: root.useReveal && root.fitMode === "crop" ? 1.03 : 1
            to: 1
            duration: root.useReveal ? 560 : 300
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: nextImage
            property: "opacity"
            from: root.useReveal ? 1 : 0
            to: 1
            duration: root.useReveal ? 560 : 300
            easing.type: Easing.InOutCubic
        }
        onFinished: root.promote()
    }
}
