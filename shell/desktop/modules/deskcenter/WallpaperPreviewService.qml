pragma Singleton
import QtQuick
import qs.desktop.modules.common
import "../../../Kos/Ui"

// The preview is a separate full-output scene on every screen. Nothing in the
// real desktop changes until Apply; dropping the overlay restores the desktop.
QtObject {
    id: service
    property bool active: false
    property bool pending: false
    property bool presented: false
    property string image: ""
    property var images: []
    property string errorMessage: ""
    property int remainingSeconds: 60
    property int direction: 1
    property bool slideshowPlaying: false
    property var readyOutputs: []
    readonly property bool available: ScreenLifecycle.usableScreens.length > 0

    function begin(path, rawImages) {
        if (!available) {
            errorMessage = "当前没有可用的显示器"
            return false
        }
        if (pending || WallpaperService.takeoverPending)
            return false
        const local = WallpaperService.localPath(path)
        if (!local) return false
        let candidates = []
        try {
            candidates = JSON.parse(rawImages)
            // The Quickshell CLI may preserve the JSON string literal used
            // to prevent its argument parser from expanding the array.
            if (typeof candidates === "string") candidates = JSON.parse(candidates)
        } catch (_) {}
        if (!Array.isArray(candidates)) candidates = []
        images = candidates.map(value => WallpaperService.localPath(value))
            .filter((value, index, all) => value && all.indexOf(value) === index).slice(0, 120)
        if (images.indexOf(local) < 0) images = [local].concat(images)
        errorMessage = ""
        readyOutputs = []
        image = local
        active = true
        slideshowPlaying = false
        remainingSeconds = 60
        loadingWatchdog.restart()
        return true
    }

    function imageReady(path, outputName) {
        if (!active || WallpaperService.localPath(path) !== image) return
        if (outputName && readyOutputs.indexOf(outputName) < 0)
            readyOutputs = readyOutputs.concat([outputName])
        const screens = ScreenLifecycle.usableScreens
        if (!screens.length || !screens.every(screen => readyOutputs.indexOf(screen.name) >= 0))
            return
        loadingWatchdog.stop()
        if (!presented) {
            presented = true
            remainingSeconds = 60
        }
    }

    function select(index) {
        if (!active || images.length < 2 || pending) return
        const target = (index + images.length) % images.length
        const current = images.indexOf(image)
        if (target === current) return
        direction = target < current ? -1 : 1
        image = images[target]
        readyOutputs = []
        loadingWatchdog.restart()
    }

    function move(delta) {
        const index = images.indexOf(image)
        if (index < 0) return
        select(index + delta)
    }

    function finish(keep) {
        if (!active || pending) return
        if (keep && !WallpaperService.chooseImage(image, true)) return
        if (keep && image.indexOf("/wallpaper-colors/") >= 0)
            AppearanceConfigService.updateSpatialWallpaperEnabled(false)
        active = false
        slideshowPlaying = false
        image = ""
        loadingWatchdog.stop()
        presented = false
    }

    function imageFailed(path) {
        if (!active || WallpaperService.localPath(path) !== image) return
        errorMessage = "这张图片无法显示，已恢复原壁纸。"
        finish(false)
    }

    property Timer loadingWatchdog: Timer {
        interval: 12000
        onTriggered: service.imageFailed(service.image)
    }
    property Timer expiry: Timer {
        interval: 1000
        repeat: true
        running: service.active && service.presented && !service.pending
        onTriggered: {
            service.remainingSeconds--
            if (service.remainingSeconds <= 0) service.finish(false)
        }
    }
    property Timer slideshow: Timer {
        interval: 5200
        repeat: true
        running: service.active && service.presented && service.slideshowPlaying
            && service.images.length > 1 && !service.loadingWatchdog.running
        onTriggered: service.move(1)
    }
}
