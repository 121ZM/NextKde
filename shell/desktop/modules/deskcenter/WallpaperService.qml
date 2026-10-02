pragma Singleton

import QtQuick
import QtCore
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.platform
import "../../../Kos/Ui"

// The original image and presentation preferences belong to Quickshell. The
// Plasma wallpaper is read only for first-run migration and fallback.
QtObject {
    id: service

    property Settings config: Settings {
        location: "file://" + Quickshell.stateDir + "/wallpaper.ini"
        category: "Wallpaper"
        property string image: ""
        property string fitMode: "crop"
        property string transition: "cinematic"
        property string recentJson: "[]"
        property bool takeoverEnabled: false
        property bool slideshowEnabled: false
        property int slideshowIntervalMinutes: 15
        property string slideshowJson: "[]"
    }

    readonly property url wallpaperUrl: config.image || WallpaperColorSource.wallpaperUrl
    readonly property bool takeoverEnabled: config.takeoverEnabled
    readonly property bool takeoverAvailable:
        PlatformClient.supports("wallpaper.plasma.proxy")
        && PlatformClient.supports("wallpaper.plasma.restore")
    readonly property string fitMode: config.fitMode
    readonly property string transition: config.transition
    readonly property bool slideshowEnabled: config.slideshowEnabled
    readonly property int slideshowIntervalMinutes: config.slideshowIntervalMinutes
    readonly property var slideshowImages: {
        try {
            const images = JSON.parse(config.slideshowJson)
            return Array.isArray(images) ? images : []
        } catch (_) {
            return []
        }
    }
    property var readyOutputNames: []
    property bool proxyPending: false
    property bool takeoverPending: false
    property bool restoreRequested: false
    property string appliedProxyKey: ""
    property string errorMessage: ""
    property int proxyRetryCount: 0
    readonly property var recentImages: {
        try {
            const images = JSON.parse(config.recentJson)
            return Array.isArray(images) ? images : []
        } catch (_) {
            return []
        }
    }

    function isLocalImage(value) {
        const path = String(value || "").trim()
        return path.startsWith("/") || path.startsWith("file://")
    }

    function localPath(value) {
        const path = String(value || "").trim()
        if (path.startsWith("/"))
            return path
        if (!path.startsWith("file://"))
            return ""
        try {
            const decoded = decodeURIComponent(path.slice(7))
            return decoded.startsWith("/") ? decoded : ""
        } catch (_) {
            return ""
        }
    }

    function chooseImage(value, userSelected) {
        const path = localPath(value)
        if (!path || takeoverPending)
            return false
        config.image = path
        const recent = recentImages.filter(item => item !== path)
        recent.unshift(path)
        config.recentJson = JSON.stringify(recent.slice(0, 12))
        if (userSelected)
            config.takeoverEnabled = true
        if (userSelected)
            config.slideshowEnabled = false
        config.sync()
        WallpaperColorSource.preferredWallpaperUrl = path
        return true
    }

    function setTakeoverEnabled(enabled) {
        if (takeoverPending)
            return false
        if (!takeoverAvailable) {
            errorMessage = PlatformClient.capabilityProbeComplete
                ? "当前平台服务版本不支持壁纸接管"
                : "平台服务尚未准备好"
            return false
        }
        if (enabled) {
            config.takeoverEnabled = true
            config.sync()
            applyPlasmaBackdropIfReady()
            return true
        }
        const imagePath = localPath(config.image)
        if (!imagePath)
            return false
        takeoverPending = true
        restoreRequested = true
        if (!proxyPending)
            restorePlasmaImage()
        return true
    }

    function restorePlasmaImage() {
        if (!restoreRequested || proxyPending || !takeoverAvailable)
            return
        restoreRequested = false
        const imagePath = localPath(config.image)
        PlatformClient.request("wallpaper.plasma.restore", {
            imagePath: imagePath,
            screenCount: Math.max(1, ScreenLifecycle.usableScreens.length)
        }, function(response) {
            service.takeoverPending = false
            if (response?.ok) {
                config.takeoverEnabled = false
                config.sync()
                service.appliedProxyKey = ""
                service.errorMessage = ""
            } else {
                service.errorMessage = response?.error?.message
                    || "Plasma 壁纸恢复失败"
            }
        })
    }

    function reportImageReady(outputName, imageUrl) {
        if (String(imageUrl) !== wallpaperUrl.toString() || !outputName)
            return
        if (readyOutputNames.indexOf(outputName) < 0)
            readyOutputNames = readyOutputNames.concat([outputName])
        applyPlasmaBackdropIfReady()
    }

    function allOutputsReady() {
        const screens = ScreenLifecycle.usableScreens
        return screens.length > 0 && screens.every(screen =>
            screen && readyOutputNames.indexOf(screen.name) >= 0)
    }

    function applyPlasmaBackdropIfReady() {
        if (!takeoverEnabled || takeoverPending || !allOutputsReady()
                || !WallpaperColorSource.ready || proxyPending
                || !takeoverAvailable)
            return
        const color = WallpaperColorSource.primary.toString()
        const accent = color.length === 9 && color.startsWith("#")
            ? "#" + color.slice(3) : color
        const dark = WallpaperColorSource.darkMode
        const screens = ScreenLifecycle.usableScreens.length
        const key = wallpaperUrl.toString() + ":" + accent + ":" + dark
            + ":" + screens
        if (key === appliedProxyKey)
            return
        proxyPending = true
        PlatformClient.request("wallpaper.plasma.proxy", {
            accent: accent,
            dark: dark,
            screenCount: screens
        }, function(response) {
            service.proxyPending = false
            if (response?.ok) {
                service.appliedProxyKey = key
                service.proxyRetryCount = 0
                service.errorMessage = ""
            } else {
                service.errorMessage = response?.error?.message
                    || "Plasma 纯色占位图设置失败"
                if (service.proxyRetryCount++ < 3)
                    retryProxy.restart()
            }
            if (service.restoreRequested)
                service.restorePlasmaImage()
            else if (response?.ok && service.takeoverEnabled)
                service.applyPlasmaBackdropIfReady()
        })
    }

    property Timer retryProxy: Timer {
        interval: 5000
        repeat: false
        onTriggered: service.applyPlasmaBackdropIfReady()
    }

    function setFitMode(value) {
        const mode = String(value)
        if (["crop", "fit", "stretch", "center"].indexOf(mode) < 0)
            return false
        config.fitMode = mode
        config.sync()
        return true
    }

    function setTransition(value) {
        const style = String(value)
        if (["cinematic", "fade", "none"].indexOf(style) < 0)
            return false
        config.transition = style
        config.sync()
        return true
    }

    function setSlideshow(enabled, minutes, rawImages) {
        const allowed = [5, 15, 60, 1440]
        const cadence = Number(minutes)
        if (allowed.indexOf(cadence) < 0)
            return false
        let images
        try {
            images = JSON.parse(String(rawImages))
        } catch (_) {
            return false
        }
        if (!Array.isArray(images))
            return false
        const playlist = images.map(localPath).filter(path => path)
            .filter((path, index, items) => items.indexOf(path) === index)
            .slice(0, 120)
        if (!enabled) {
            if (playlist.length > 1)
                config.slideshowJson = JSON.stringify(playlist)
            config.slideshowIntervalMinutes = cadence
            config.slideshowEnabled = false
            config.sync()
            return true
        }
        if (playlist.length < 2)
            return false
        config.slideshowJson = JSON.stringify(playlist)
        config.slideshowIntervalMinutes = cadence
        config.slideshowEnabled = true
        config.takeoverEnabled = true
        config.sync()
        if (playlist.indexOf(localPath(wallpaperUrl)) < 0)
            chooseImage(playlist[0], false)
        return true
    }

    function advanceSlideshow() {
        const images = slideshowImages
        if (images.length < 2 || takeoverPending)
            return
        const current = localPath(wallpaperUrl)
        let index = images.indexOf(current)
        index = (index + 1) % images.length
        chooseImage(images[index], false)
    }

    property Timer slideshowTimer: Timer {
        interval: Math.max(1, service.slideshowIntervalMinutes) * 60000
        repeat: true
        running: service.slideshowEnabled && service.takeoverEnabled
            && !WallpaperPreviewService.active
            && service.slideshowImages.length > 1
        onTriggered: service.advanceSlideshow()
    }

    function migratePlasmaWallpaper() {
        if (config.image || !isLocalImage(WallpaperColorSource.wallpaperUrl))
            return
        chooseImage(WallpaperColorSource.wallpaperUrl)
    }

    property Connections plasmaMigration: Connections {
        target: WallpaperColorSource
        function onWallpaperUrlChanged() { service.migratePlasmaWallpaper() }
        function onPaletteChanged() { service.applyPlasmaBackdropIfReady() }
        function onDarkModeChanged() { service.applyPlasmaBackdropIfReady() }
    }

    property Connections screenChanges: Connections {
        target: ScreenLifecycle
        function onUsableScreensChanged() { service.applyPlasmaBackdropIfReady() }
    }

    property Connections platformCapabilities: Connections {
        target: PlatformClient
        function onCapabilitiesChanged() {
            if (service.takeoverAvailable)
                service.applyPlasmaBackdropIfReady()
        }
    }

    onWallpaperUrlChanged: {
        readyOutputNames = []
        appliedProxyKey = ""
    }

    Component.onCompleted: {
        if (config.image)
            WallpaperColorSource.preferredWallpaperUrl = config.image
        else
            migratePlasmaWallpaper()
    }
}
