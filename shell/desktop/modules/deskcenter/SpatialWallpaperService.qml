pragma Singleton
import QtQuick
import qs.desktop.modules.common
import qs.desktop.modules.platform
import "../../../Kos/Ui"

// Opt-in orchestration for the desktop wallpaper pipeline. The generator and
// model live in the platform's child process; this service only tracks which
// wallpaper is current and publishes a ready depth-map path to the renderer.
QtObject {
    id: root

    property string imagePath: ""
    property string depthPath: ""
    property string requestedPath: ""
    property bool requestInFlight: false
    property int retryCount: 0
    property string errorMessage: ""
    readonly property bool enabled: AppearanceConfigService.spatialWallpaperEnabled
    readonly property url wallpaperUrl: WallpaperColorSource.wallpaperUrl
    readonly property bool ready: enabled && depthPath.length > 0
        && imagePath === currentImagePath()

    function currentImagePath() {
        const value = wallpaperUrl.toString()
        if (value.startsWith("/"))
            return value
        if (!value.startsWith("file://"))
            return ""
        try {
            return decodeURIComponent(value.replace(/^file:\/\//, ""))
        } catch (error) {
            console.warn("[SpatialWallpaper] invalid wallpaper URL: " + error)
            return ""
        }
    }

    function refreshWallpaper() {
        const nextPath = currentImagePath()
        if (nextPath !== imagePath) {
            imagePath = nextPath
            depthPath = ""
            errorMessage = ""
            retryCount = 0
            retryTimer.stop()
        }
        if (enabled && nextPath)
            requestDelay.restart()
    }

    function requestDepthIfNeeded() {
        if (!enabled || !imagePath || requestInFlight || depthPath)
            return
        requestedPath = imagePath
        requestInFlight = true
        console.log("[SpatialWallpaper] requesting depth for " + requestedPath)
        DepthManager.generate(requestedPath)
    }

    // Wallpaper services can publish several URLs during startup. Let the
    // final URL settle before occupying the worker's bounded request queue.
    property Timer requestDelay: Timer {
        interval: 350
        repeat: false
        onTriggered: root.requestDepthIfNeeded()
    }

    property Timer retryTimer: Timer {
        repeat: false
        onTriggered: root.requestDepthIfNeeded()
    }

    property Connections wallpaperChanges: Connections {
        target: WallpaperColorSource
        function onWallpaperUrlChanged() { root.refreshWallpaper() }
    }

    property Connections settingChanges: Connections {
        target: AppearanceConfigService
        function onSpatialWallpaperEnabledChanged() {
            if (root.enabled)
                root.refreshWallpaper()
            else {
                root.requestDelay.stop()
                root.retryTimer.stop()
                root.depthPath = ""
                root.errorMessage = ""
            }
        }
    }

    property Connections generationReplies: Connections {
        target: DepthManager
        function onFinished(sourcePath, resultPath) {
            if (!root.requestInFlight || sourcePath !== root.requestedPath)
                return
            root.requestInFlight = false
            if (root.enabled && sourcePath === root.imagePath && resultPath) {
                root.retryCount = 0
                root.errorMessage = ""
                root.depthPath = resultPath
                console.log("[SpatialWallpaper] depth ready for " + sourcePath)
            } else if (root.enabled)
                root.requestDelay.restart()
        }
        function onFailed(sourcePath, code, message, retryable) {
            if (!root.requestInFlight || sourcePath !== root.requestedPath)
                return
            root.requestInFlight = false
            console.warn("[SpatialWallpaper] " + code + ": " + message
                + " retryable=" + retryable)
            if (root.enabled && sourcePath === root.imagePath) {
                root.errorMessage = message
                if (retryable && code !== "depth-generation-failed") {
                    root.retryCount++
                    root.retryTimer.interval = Math.min(30000,
                        2000 * Math.pow(2, Math.min(root.retryCount - 1, 4)))
                    root.retryTimer.restart()
                }
            } else if (root.enabled)
                root.requestDelay.restart()
        }
    }

    Component.onCompleted: refreshWallpaper()
}
