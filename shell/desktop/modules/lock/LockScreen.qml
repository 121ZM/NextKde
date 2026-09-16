import Quickshell
import Quickshell.Io
import qs.desktop.modules.common
import qs.desktop.modules.lock

// Lock screen controller. One window per output, all driven by LockService.
//
// The pre-existing convention is wrong for this surface: Bar, Dock and
// Overview each bind a single PanelWindow to ScreenLifecycle.activeScreen,
// because they live on one selected output. A lock that only covered the
// active output would leave every other monitor showing the desktop, so this
// is the first consumer of Variants -- one LockWindow per real screen.
Scope {
    id: root

    // The live unread set, injected by DesktopEnvironment from the one
    // NotificationServer the session is allowed to own. Taking it as a
    // property instead of importing the notifications module keeps the
    // dependency pointing the way the rest of the shell points it, and keeps
    // the lock from being able to publish notifications of its own.
    required property var groupService

    // Every output, not just the preferred one. ScreenLifecycle exists to keep
    // output-bound surfaces off Qt's synthetic placeholder screen during a
    // suspend/resume teardown; a lock that only covered the active output would
    // leave the other monitors showing the desktop, and one that built its own
    // screen list would reintroduce exactly the race that singleton settles.
    readonly property var lockScreens: ScreenLifecycle.usableScreens

    // Locking is the only thing IPC may do. Unlocking stays a password
    // conversation with PAM, so there is no endpoint that would let anything
    // holding the session bus talk its way past the lock.
    IpcHandler {
        target: "lock"
        function lock(): void { LockService.lock() }
        function isLocked(): string { return LockService.locked ? "true" : "false" }
    }

    Variants {
        model: root.lockScreens
        delegate: LockWindow {
            required property var modelData
            screen: modelData
            groupService: root.groupService
        }
    }
}
