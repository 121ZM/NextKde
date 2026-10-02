import QtQuick

Rectangle {
    id: action
    property string label: ""
    property bool primary: false
    property bool compact: false
    property bool light: false
    signal triggered()
    implicitWidth: compact ? 42 : labelText.implicitWidth + 28
    implicitHeight: 40
    radius: compact ? 13 : 14
    color: primary ? (light ? "#faffff" : pointer.containsMouse ? "#eefaff" : "#e5f6ff")
        : light ? (pointer.containsMouse ? "#8cffffff" : "#58ffffff")
        : pointer.containsMouse ? "#35ffffff" : "#1cffffff"
    border.color: light ? "#7cffffff" : primary ? "#aaffffff"
        : pointer.containsMouse ? "#58ffffff" : "#26ffffff"
    border.width: light && !primary ? 0 : 1
    scale: pointer.pressed ? 0.96 : 1
    Behavior on color { ColorAnimation { duration: 140 } }
    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
    Text {
        id: labelText
        anchors.centerIn: parent
        text: action.label
        color: action.primary ? "#10212e" : action.light ? "#2b4552" : "white"
        font.pixelSize: action.compact ? 22 : 12
        font.weight: action.primary ? Font.DemiBold : Font.Medium
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: action.triggered()
    }
}
