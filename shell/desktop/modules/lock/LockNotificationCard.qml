import QtQuick
import Quickshell.Widgets
import qs.desktop.modules.common
import qs.desktop.modules.dock

// One app's unread notifications on the lock surface.
//
// Deliberately not the popup card. The popup owns actions, inline reply and
// per-group collapse state, none of which should be reachable before a
// password is typed; this is a read-only summary -- icon, app, headline, two
// lines of body, and how many are waiting behind it.
Rectangle {
    id: card

    property string appName: ""
    property string appIcon: ""
    property string summary: ""
    property string body: ""
    property int count: 1
    property int urgency: 1
    property string image: ""

    // NotificationUrgency.Critical is 2. A critical notification gets a
    // brighter plate so it still reads as urgent over a dark wallpaper.
    readonly property bool critical: urgency === 2
    readonly property real shapeRadius: AppearanceTokens.shape.large
    readonly property bool continuousCorners:
        AppearanceTokens.shape.cornerExponent > 2.0
    readonly property color edgeColor: Qt.rgba(1, 1, 1,
        critical ? 0.34 : 0.18)

    // The popup resolves app icons through the same identity service, so a
    // notification looks the same in both places.
    readonly property string iconSource:
        AppIdentityService._iconPath(image || appIcon)

    width: 380
    implicitHeight: layout.implicitHeight + 22
    height: implicitHeight

    // Continuous corners: the same opt-in the notification popup and the Dock
    // pill carry. The mask shapes the fill and draws the outline along the
    // same field, so both stop being Rectangle properties while it is on, and
    // at exponent 2 every line here collapses back to a plain Rectangle.
    radius: continuousCorners ? 0 : shapeRadius
    color: Qt.rgba(1, 1, 1, critical ? 0.20 : 0.13)
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
        anchors.margins: 11
        spacing: 11

        Rectangle {
            width: 30
            height: 30
            radius: 9
            color: Qt.rgba(1, 1, 1, 0.14)

            IconImage {
                anchors.centerIn: parent
                width: 19
                height: 19
                source: card.iconSource
            }
        }

        Column {
            width: Math.max(0, layout.width - 41)
            spacing: 2

            Row {
                spacing: 6

                Text {
                    text: card.appName
                    color: Qt.rgba(1, 1, 1, 0.74)
                    font { pixelSize: 11; weight: Font.DemiBold }
                    anchors.verticalCenter: parent.verticalCenter
                }

                Rectangle {
                    visible: card.count > 1
                    anchors.verticalCenter: parent.verticalCenter
                    width: countLabel.implicitWidth + 13
                    height: 16
                    radius: 8
                    color: Qt.rgba(1, 1, 1, 0.20)

                    Text {
                        id: countLabel
                        anchors.centerIn: parent
                        text: card.count + " 条"
                        color: "#ffffff"
                        font { pixelSize: 10; weight: Font.DemiBold }
                    }
                }
            }

            Text {
                width: parent.width
                visible: text.length > 0
                text: card.summary
                color: "#ffffff"
                font { pixelSize: 13; weight: Font.DemiBold }
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                width: parent.width
                visible: text.length > 0
                text: card.body
                color: Qt.rgba(1, 1, 1, 0.70)
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 2
            }
        }
    }
}
