import QtQuick
import qs.desktop.modules.common
import qs.desktop.modules.dock

// Now-playing card on the lock surface.
//
// Read-only apart from transport: the lock screen is not a place to pick a
// player or scrub a track, so this shows the one player the Dock already
// selected (DockMprisService owns that choice, including the "paused is still
// active" fallback) and offers prev / play-pause / next.
//
// The plate is a plain translucent Rectangle rather than LiquidGlassPanel, and
// the notification card beside it is built the same way, for two reasons. The
// backdrop is already a heavily downscaled wallpaper, so there is no sharp
// detail left for a second blur pass to remove; and a compositor-backed glass
// surface under the tonal theme paints an opaque layer, which on a lock screen
// would cover the wallpaper the card is supposed to be floating over.
// SquircleMask still supplies the continuous corners, so the two cards and
// every other surface in the shell share one outline.
Rectangle {
    id: card

    readonly property var player: DockMprisService.activePlayer

    // DockMprisService mutates metadata on the player object without always
    // emitting a notify for the artwork URL, so consumers bind this revision
    // to re-read it after a track change. Same contract as the Dock widget.
    readonly property url artworkSource: {
        void DockMprisService.metadataRevision
        const art = player?.trackArtUrl
        return art && String(art).length > 0
            ? art : Qt.resolvedUrl("../../assets/defaultCover.png")
    }

    readonly property string title: {
        void DockMprisService.metadataRevision
        return player?.trackTitle ?? ""
    }
    readonly property string artist: {
        void DockMprisService.metadataRevision
        return player?.trackArtist ?? ""
    }
    readonly property bool playing: player?.isPlaying ?? false

    readonly property real shapeRadius: AppearanceTokens.shape.large
    readonly property bool continuousCorners:
        AppearanceTokens.shape.cornerExponent > 2.0
    readonly property color edgeColor: Qt.rgba(1, 1, 1, 0.18)

    width: 380
    implicitHeight: layout.implicitHeight + 20
    height: implicitHeight

    radius: continuousCorners ? 0 : shapeRadius
    color: Qt.rgba(1, 1, 1, 0.15)
    border.width: continuousCorners ? 0 : 1
    border.color: edgeColor

    layer.enabled: continuousCorners
    layer.effect: SquircleMask {
        cornerRadius: card.shapeRadius
        cornerExponent: AppearanceTokens.shape.cornerExponent
        maskWidth: card.width
        maskHeight: card.height
        borderWidth: 1
        borderColor: card.edgeColor
    }

    Row {
        id: layout
        anchors.fill: parent
        anchors.margins: 10
        spacing: 11

        // Artwork keeps its own circular rounding: the plate's corner field is
        // scaled for a 66px-tall card and would read as a wedge on a 46px tile.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 46
            height: 46
            radius: 11
            color: Qt.rgba(1, 1, 1, 0.10)
            clip: true

            Image {
                anchors.fill: parent
                source: card.artworkSource
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 92
                sourceSize.height: 92
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, layout.width - 46 - 11 - controls.width - 11)
            spacing: 2

            Text {
                width: parent.width
                text: card.title.length > 0 ? card.title : "未知曲目"
                color: "#ffffff"
                font { pixelSize: 13; weight: Font.DemiBold }
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                width: parent.width
                visible: card.artist.length > 0
                text: card.artist
                color: Qt.rgba(1, 1, 1, 0.66)
                font.pixelSize: 11
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        Row {
            id: controls
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            component TransportButton: Item {
                id: button

                property string symbol: ""
                property bool primary: false
                property bool enabled: true

                width: primary ? 34 : 28
                height: primary ? 34 : 28

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: button.primary
                        ? Qt.rgba(1, 1, 1, button.enabled ? 0.22 : 0.08)
                        : "transparent"
                }

                Text {
                    anchors.centerIn: parent
                    // The play triangle is visually left-heavy inside its box.
                    anchors.horizontalCenterOffset: button.symbol === "▶" ? 1 : 0
                    text: button.symbol
                    color: Qt.rgba(1, 1, 1, button.enabled ? 0.96 : 0.34)
                    font {
                        pixelSize: button.primary ? 15 : 13
                        weight: Font.DemiBold
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: button.enabled
                    cursorShape: button.enabled
                        ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: button.triggered()
                }

                signal triggered()
            }

            TransportButton {
                symbol: "⏮"
                enabled: card.player?.canGoPrevious ?? false
                onTriggered: DockMprisService.previous()
            }

            TransportButton {
                primary: true
                symbol: card.playing ? "⏸" : "▶"
                enabled: card.player?.canTogglePlaying ?? false
                onTriggered: DockMprisService.togglePlayPause()
            }

            TransportButton {
                symbol: "⏭"
                enabled: card.player?.canGoNext ?? false
                onTriggered: DockMprisService.next()
            }
        }
    }
}
