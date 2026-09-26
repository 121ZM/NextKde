pragma Singleton
import QtQuick
import qs.desktop.modules.platform
import qs.desktop.modules.common
import "../../../Kos/Ui"

// Transient desktop audition. The persisted wallpaper, slideshow, palette and
// Plasma proxy are untouched until Keep is chosen. Timeout also covers a closed
// Settings window; no application process owns the rollback.
QtObject {
    id: service
    property bool active: false
    property bool pending: false
    property bool presented: false
    property bool previousDesktop: false
    property string image: ""
    property var images: []
    property string errorMessage: ""
    property int remainingSeconds: 60
    property int direction: 1
    property bool restoring: false
    property int generation: 0
    property var readyOutputs: []
    property bool abortPending: false
    readonly property bool available:
        PlatformClient.supports("wallpaper.preview.desktop")

    function begin(path, rawImages) {
        if (!available) {
            errorMessage = PlatformClient.capabilityProbeComplete
                ? "当前平台服务版本不支持桌面壁纸预览"
                : "平台服务尚未准备好"
            return false
        }
        if (pending || restoring || WallpaperService.takeoverPending)
            return false
        const local = WallpaperService.localPath(path)
        if (!local) return false
        let candidates = []
        try { candidates = JSON.parse(rawImages) } catch (_) {}
        if (!Array.isArray(candidates)) candidates = []
        images = candidates.map(value => WallpaperService.localPath(value))
            .filter((value, index, all) => value && all.indexOf(value) === index).slice(0, 120)
        if (images.indexOf(local) < 0) images = [local].concat(images)
        errorMessage = ""
        readyOutputs = []
        abortPending = false
        image = local
        active = true
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
        if (presented || pending) return
        pending = true
        const ticket = ++generation
        PlatformClient.request("wallpaper.preview.desktop", { showing: true }, function(reply) {
            pending = false
            if (ticket !== generation) return
            if (!reply?.ok) {
                errorMessage = reply?.error?.message || "无法进入桌面预览"
                active = false
                image = ""
                return
            }
            previousDesktop = !!reply.result.previous
            presented = true
            remainingSeconds = 60
            if (abortPending) finish(false)
        })
    }

    function move(delta) {
        if (!active || images.length < 2 || pending) return
        direction = delta < 0 ? -1 : 1
        const index = images.indexOf(image)
        image = images[(index + delta + images.length) % images.length]
        readyOutputs = []
        remainingSeconds = 60
        loadingWatchdog.restart()
    }

    function finish(keep) {
        if (!active || pending) return
        if (keep && !WallpaperService.chooseImage(image, true)) return
        if (keep && image.indexOf("/wallpaper-colors/") >= 0)
            AppearanceConfigService.updateSpatialWallpaperEnabled(false)
        active = false
        image = ""
        loadingWatchdog.stop()
        if (!presented) return
        presented = false
        restoring = true
        PlatformClient.request("wallpaper.preview.desktop", { showing: previousDesktop }, function(reply) {
            restoring = false
            if (!reply?.ok)
                errorMessage = reply?.error?.message || "返回桌面窗口失败"
        })
    }

    function imageFailed(path) {
        if (!active || WallpaperService.localPath(path) !== image) return
        errorMessage = "这张图片无法显示，已恢复原壁纸。"
        if (pending) abortPending = true
        else finish(false)
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
}
