import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.lock

// One lock surface per output.
//
// This file is the surface *policy* and nothing else: which layer to sit on,
// whose keyboard to take, when to map and unmap. The composition lives in
// LockSurface, which is a plain Item and therefore loadable without a
// compositor -- see the note there.
//
// The grab is an Overlay layer-shell surface with exclusive keyboard focus.
// That takes pointer and keyboard input away from every other client, and the
// surface is opaque, so the desktop behind it is not visible. It does not stop
// the compositor's global shortcuts; see LockService for what that means.
PanelWindow {
    id: root

    // Injected by LockScreen; see the note there.
    required property var groupService

    WlrLayershell.namespace: "quickshell-lock"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: LockService.locked
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    // Mapped for the whole lock, and kept mapped until the exit animation has
    // finished so the fade is actually visible.
    visible: LockService.locked || LockService.exiting
    focusable: LockService.locked
    anchors { top: true; left: true; right: true; bottom: true }

    // 0 while unlocked, 1 while fully locked. The Behavior below carries both
    // directions, and its completion is what finally unmaps the surface.
    property real revealProgress: LockService.locked ? 1.0 : 0.0
    Behavior on revealProgress {
        NumberAnimation {
            duration: LockService.locked ? 340 : 200
            easing.type: LockService.locked ? Easing.OutCubic : Easing.InCubic
            onRunningChanged: if (!running && !LockService.locked)
                LockService.finishExit()
        }
    }

    LockSurface {
        anchors.fill: parent
        groupService: root.groupService
        revealProgress: root.revealProgress
    }
}
