import QtQuick
import qs.desktop.modules.common
import qs.desktop.modules.dock
import qs.desktop.modules.lock
import "../../../Kos/Ui"

// The lock surface's content: backdrop, clock, cards, password capsule.
//
// Split out of LockWindow deliberately. LockWindow is the surface *policy* --
// which layer, whose keyboard, when to unmap -- and it is a PanelWindow, which
// cannot be constructed outside a Wayland session, so nothing inside it can be
// loaded by a test. The composition below is the part that breaks quietly while
// being edited, so it lives on a plain Item that an offscreen fixture can build
// with a synthetic group service and inspect.
//
// Layout follows the iPadOS lock screen: a blurred wallpaper, the clock and
// date at the top, the now-playing widget, the unread notification stack, and
// a single password capsule at the bottom. Nothing here is interactive beyond
// that capsule -- there is no path from this surface back to the desktop.
Item {
    id: surface

    // Injected by LockWindow; see the note there. Null is a supported value and
    // means "no notification source", which is what the fixture uses.
    required property var groupService

    // 0 while unlocked, 1 while fully locked. Owned by the window, because its
    // animation completion is what unmaps the surface.
    property real revealProgress: 0

    // ---- notifications ---------------------------------------------------

    // How many app groups fit without pushing the clock off the top. Sorted
    // newest-first by the group service, so this is the freshest slice.
    readonly property int maxGroups: 3

    // Flattened to the fields the cards read. Re-evaluated whenever the group
    // service rebuilds, which is what the sidecarRevision read is for: the
    // rows are read through ListModel.get(), and that returns a snapshot
    // object whose fields carry no change signals of their own.
    readonly property var visibleGroups: {
        const result = []
        const service = surface.groupService
        if (!service)
            return result
        void service.sidecarRevision
        const model = service.groupsModel
        const total = Math.min(surface.maxGroups, model.count)
        for (let index = 0; index < total; ++index) {
            const row = model.get(index)
            result.push({
                groupKey: row.groupKey,
                appName: row.appName,
                appIcon: row.appIcon,
                summary: row.latestSummary,
                body: row.latestBody,
                count: row.count,
                urgency: row.latestUrgency,
                image: row.latestImage
            })
        }
        return result
    }

    // ---- clock -----------------------------------------------------------

    property date now: new Date()
    readonly property string clockText: Qt.formatTime(surface.now, "HH:mm")
    readonly property string dateText: Qt.formatDate(surface.now, "M月d日 dddd")

    Timer {
        interval: 1000
        repeat: true
        running: surface.visible
        triggeredOnStart: true
        onTriggered: surface.now = new Date()
    }

    // ---- backdrop --------------------------------------------------------

    readonly property url wallpaperSource: WallpaperColorSource.wallpaperUrl
    readonly property bool hasWallpaper: String(wallpaperSource).length > 0

    // Sits under everything, so a session with no resolvable wallpaper still
    // gets an opaque surface rather than a transparent hole onto the desktop.
    Rectangle {
        anchors.fill: parent
        color: AppearanceTokens.colors.layer0
    }

    Image {
        anchors.fill: parent
        visible: surface.hasWallpaper
        source: surface.wallpaperSource
        // A blur that costs one bilinear upscale instead of a full-screen
        // effect pass: ask the loader for a small decode and let the scene
        // graph stretch it back. A lock backdrop is precisely the case where
        // a soft, detail-free wallpaper is wanted, and it keeps the surface
        // cheap on every output at once.
        sourceSize: Qt.size(Math.max(2, Math.round(surface.width / 8)),
            Math.max(2, Math.round(surface.height / 8)))
        fillMode: Image.PreserveAspectCrop
        smooth: true
        // Settles from a slight push-in as the lock lands, so the wall behind
        // the clock feels like it moved rather than appeared.
        scale: 1.06 - 0.06 * surface.revealProgress
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.46) }
            GradientStop { position: 0.38; color: Qt.rgba(0, 0, 0, 0.20) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.58) }
        }
    }

    // ---- content ---------------------------------------------------------

    Item {
        id: content
        anchors.fill: parent
        opacity: surface.revealProgress
        scale: 0.98 + 0.02 * surface.revealProgress

        Column {
            id: clockColumn
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Math.round(surface.height * 0.10)
            spacing: 2

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "󰌾"
                font.pixelSize: 22
                color: Qt.rgba(1, 1, 1, 0.72)
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: surface.clockText
                color: "#ffffff"
                font {
                    pixelSize: Math.round(Math.min(surface.width, surface.height) * 0.13)
                    weight: Font.Light
                }
                style: Text.Outline
                styleColor: Qt.rgba(0, 0, 0, 0.20)
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: surface.dateText
                color: Qt.rgba(1, 1, 1, 0.84)
                font { pixelSize: 15; weight: Font.Medium }
            }
        }

        Column {
            id: cardColumn
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: clockColumn.bottom
            anchors.topMargin: 40
            anchors.bottom: passwordField.top
            anchors.bottomMargin: 24
            width: Math.min(380, surface.width - 72)
            spacing: 10

            // Column skips invisible children, so a session with no player
            // simply does not reserve the space.
            LockMusicCard {
                width: parent.width
                visible: DockMprisService.hasPlayer
            }

            Repeater {
                model: surface.visibleGroups
                delegate: LockNotificationCard {
                    required property var modelData
                    width: cardColumn.width
                    appName: modelData.appName
                    appIcon: modelData.appIcon
                    summary: modelData.summary
                    body: modelData.body
                    count: modelData.count
                    urgency: modelData.urgency
                    image: modelData.image
                }
            }

            Item {
                width: parent.width
                height: 54
                visible: surface.visibleGroups.length === 0
                    && !DockMprisService.hasPlayer

                Text {
                    anchors.centerIn: parent
                    text: "没有新通知"
                    color: Qt.rgba(1, 1, 1, 0.44)
                    font { pixelSize: 13; weight: Font.Medium }
                }
            }
        }

        LockPasswordField {
            id: passwordField
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.round(surface.height * 0.11)
            busy: LockService.authenticating
            failed: LockService.failed
            errorMessage: LockService.errorMessage
            onSubmitted: password => LockService.submitPassword(password)
        }
    }
}
