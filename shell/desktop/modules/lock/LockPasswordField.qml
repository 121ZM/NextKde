import QtQuick

// The password capsule: the only interactive thing on the lock surface.
//
// It owns no state and talks to nothing. The window passes `busy` / `failed` /
// `errorMessage` down from LockService and listens for `submitted`, which keeps
// the verification path in exactly one place instead of letting a text field
// reach for PAM itself.
//
// Shape is a plain stadium (radius = half the height), matching the pills the
// rest of the shell already draws -- the Dock's music popup, the search field.
// Only surfaces that own a large fill carry the continuous-corner mask; on a
// 46px capsule the exponent-3 caps read as wedge-shaped, not rounded.
FocusScope {
    id: field

    property bool busy: false
    property bool failed: false
    property string errorMessage: ""

    /// Emitted on Enter, and only when there is something to verify.
    signal submitted(string password)

    readonly property string password: input.text

    readonly property real plateHeight: 46
    readonly property bool hasText: input.text.length > 0
    // Typing again clears the failure styling before the next attempt, the way
    // every other lock screen behaves. The message itself is only re-armed by
    // the next failed submit, which is why it keys off the empty field too.
    readonly property bool showError: failed && errorMessage.length > 0
        && !hasText

    implicitWidth: 260
    implicitHeight: plateHeight + (showError ? 22 : 0)
    width: implicitWidth
    height: implicitHeight

    Behavior on implicitHeight {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }

    function submit() {
        if (busy || !hasText)
            return
        const value = input.text
        // Clear locally as well as in the service: a rejected attempt must not
        // leave the rejected password sitting on screen for the next one.
        submitted(value)
    }

    function takeFocus() {
        input.forceActiveFocus()
    }

    // Outermost scope holds focus whenever the surface is mapped, which is what
    // makes the capsule type-into-able the moment the lock lands.
    focus: visible
    Component.onCompleted: takeFocus()

    // ---- failure shake ---------------------------------------------------

    // Applied to an inner item, never to the root: the call site positions this
    // component with anchors, and a parent that also writes x/y is undefined.
    property real _shakeOffset: 0

    SequentialAnimation {
        id: shake
        NumberAnimation {
            target: field; property: "_shakeOffset"
            to: -10; duration: 55; easing.type: Easing.Linear
        }
        NumberAnimation {
            target: field; property: "_shakeOffset"
            to: 9; duration: 55; easing.type: Easing.Linear
        }
        NumberAnimation {
            target: field; property: "_shakeOffset"
            to: -6; duration: 55; easing.type: Easing.Linear
        }
        NumberAnimation {
            target: field; property: "_shakeOffset"
            to: 4; duration: 55; easing.type: Easing.Linear
        }
        NumberAnimation {
            target: field; property: "_shakeOffset"
            to: 0; duration: 55; easing.type: Easing.Linear
        }
    }

    onFailedChanged: {
        if (!failed)
            return
        input.text = ""
        shake.restart()
    }

    Item {
        id: shaker
        x: field._shakeOffset
        width: field.width
        height: field.plateHeight

        Rectangle {
            id: plate
            anchors.fill: parent
            radius: height / 2
            color: field.showError
                ? Qt.rgba(1.0, 0.34, 0.32, 0.20)
                : Qt.rgba(1, 1, 1, 0.14)
            border.width: 1
            border.color: field.showError
                ? Qt.rgba(1.0, 0.44, 0.42, 0.78)
                : Qt.rgba(1, 1, 1, 0.24)

            Behavior on color {
                ColorAnimation { duration: 140 }
            }
            Behavior on border.color {
                ColorAnimation { duration: 140 }
            }
        }

        Text {
            id: lockGlyph
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: "󰌾"
            font.pixelSize: 15
            color: Qt.rgba(1, 1, 1, 0.62)
        }

        // Clicking the plate -- including the padding either side of the text
        // -- has to reach the field, or the capsule looks focusable and is not.
        MouseArea {
            anchors.fill: parent
            onClicked: field.takeFocus()
        }

        TextInput {
            id: input
            anchors.left: lockGlyph.right
            anchors.leftMargin: 10
            anchors.right: rightSlot.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter

            enabled: !field.busy
            echoMode: TextInput.Password
            passwordCharacter: "●"
            passwordMaskDelay: 0
            font.pixelSize: 15
            color: "#ffffff"
            selectionColor: Qt.rgba(1, 1, 1, 0.28)
            selectedTextColor: "#ffffff"
            selectByMouse: false
            // Keeps the caret on screen in the window that owns this surface.
            focus: field.focus

            onAccepted: field.submit()

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: !field.hasText
                text: "输入密码"
                font.pixelSize: 15
                color: Qt.rgba(1, 1, 1, field.busy ? 0.30 : 0.48)
            }
        }

        Item {
            id: rightSlot
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 22

            // Same busy arc the control centre uses for its in-flight radio
            // toggles: a Canvas stroke driven by a RotationAnimation.
            Canvas {
                id: busyArc
                anchors.fill: parent
                visible: field.busy
                property color arcColor: Qt.rgba(1, 1, 1, 0.85)
                onArcColorChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    ctx.strokeStyle = arcColor
                    ctx.lineWidth = 2.0
                    ctx.lineCap = "round"
                    const cx = width / 2, cy = height / 2, r = width / 2 - 1.5
                    ctx.beginPath()
                    ctx.arc(cx, cy, r, 0, Math.PI * 1.5)
                    ctx.stroke()
                }
                Component.onCompleted: requestPaint()

                RotationAnimation on rotation {
                    running: field.busy
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 900
                }
            }

            Text {
                anchors.centerIn: parent
                visible: !field.busy && field.hasText
                text: "󰅖"
                font.pixelSize: 14
                color: Qt.rgba(1, 1, 1, 0.52)
            }

            MouseArea {
                anchors.fill: parent
                enabled: !field.busy && field.hasText
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    input.text = ""
                    field.takeFocus()
                }
            }
        }
    }

    Text {
        id: errorText
        anchors.top: shaker.bottom
        anchors.topMargin: 6
        anchors.horizontalCenter: parent.horizontalCenter
        visible: field.showError
        text: field.errorMessage
        font { pixelSize: 12; weight: Font.Medium }
        color: Qt.rgba(1.0, 0.62, 0.60, 0.95)
    }
}
