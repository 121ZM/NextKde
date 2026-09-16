pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

// Session lock state, and the only place a password is ever verified.
//
// State lives here rather than in a window because "locked" is a session-wide
// fact: every output draws its own surface, all of them are showing one lock,
// and a second attempt must not start while the first is still in flight.
//
// Scope, stated honestly: this is a *visual* lock. The surfaces are Overlay
// layer-shell windows holding an exclusive keyboard grab, which hides the
// desktop and takes input away from every other client -- but the compositor's
// own global shortcuts keep working, so it is not a security boundary. KWin
// does not implement ext-session-lock-v1, so a third-party client cannot get
// the guarantee a real locker gets; making this one real means adding the
// protocol to KWin (see the vendorised glass effect for how that looks).
QtObject {
    id: service

    // ---- configuration ---------------------------------------------------

    // PamContext reads a directory of its own instead of /etc/pam.d (through
    // pam_start_confdir), which is what lets the shell ship its PAM service
    // file with no root step. Quickshell.shellDir is the directory holding
    // shell.qml -- the repository root in a development tree, the installed
    // config directory otherwise -- and `pam/` travels with the module either
    // way, so the same expression resolves in both layouts.
    readonly property string pamDirectory:
        Quickshell.shellDir + "/desktop/modules/lock/pam"
    readonly property string pamService: "kos-lock"

    readonly property string userName: Quickshell.env("USER") || ""

    // ---- state -----------------------------------------------------------

    property bool locked: false

    // Set between a successful unlock and the surfaces finishing their exit
    // animation. The windows stay mapped while it holds: unmapping at the
    // instant the fade starts would cut the fade off entirely.
    property bool exiting: false

    property bool authenticating: false
    property bool failed: false
    property string errorMessage: ""
    property int failedAttempts: 0

    // ---- lock / unlock ---------------------------------------------------

    function lock() {
        if (locked)
            return
        // A conversation left open from a previous lock would answer the next
        // attempt with a stale password.
        _pam.abort()
        _pendingPassword = ""
        authenticating = false
        failed = false
        errorMessage = ""
        exiting = false
        locked = true
    }

    // Only a completed PAM conversation reaches this. There is deliberately no
    // IPC call or shortcut that unlocks directly -- the whole point of the
    // surface is that a password has to arrive first.
    function _beginExit() {
        if (!locked)
            return
        locked = false
        exiting = true
        _exitFallback.restart()
    }

    // Called by each surface when its exit animation reports finished, and by
    // the fallback timer if it never does. Idempotent.
    function finishExit() {
        _exitFallback.stop()
        exiting = false
    }

    // ---- authentication --------------------------------------------------

    property string _pendingPassword: ""

    property PamContext _pam: PamContext {
        id: pam

        config: service.pamService
        configDirectory: service.pamDirectory
        user: service.userName

        // pam_unix asks for the password through the conversation rather than
        // taking it as an argument, so this is where the typed value goes.
        // Answering on every request matters for the retry path: a rejected
        // attempt asks again, and a reply that only happened once would hang
        // the second prompt instead of failing.
        onPamMessage: {
            if (pam.responseRequired)
                pam.respond(service._pendingPassword)
        }

        onCompleted: result => service._finishAuthentication(result)
        onError: error => service._failAuthentication(PamError.toString(error))
    }

    // Returns false when nothing was started: no password, not locked, or a
    // conversation already running.
    function submitPassword(password) {
        if (authenticating || !locked)
            return false
        const value = String(password || "")
        if (value.length === 0)
            return false

        authenticating = true
        failed = false
        errorMessage = ""
        _pendingPassword = value

        if (!_pam.start()) {
            _pendingPassword = ""
            authenticating = false
            failed = true
            errorMessage = "认证服务忙，请重试"
            return false
        }
        return true
    }

    function _finishAuthentication(result) {
        _pendingPassword = ""
        authenticating = false

        if (result === PamResult.Success) {
            failed = false
            failedAttempts = 0
            _beginExit()
            return
        }

        failedAttempts += 1
        failed = true
        errorMessage = result === PamResult.MaxTries
            ? "尝试次数过多，请稍候" : "密码错误"
    }

    function _failAuthentication(message) {
        _pendingPassword = ""
        authenticating = false
        failedAttempts += 1
        failed = true
        errorMessage = message && message.length > 0 ? message : "认证失败"
    }

    // ---- logind: lock before the machine sleeps --------------------------

    // Suspending is not ours and does not change: `session.suspend` still goes
    // to `systemctl suspend` through kos-platform. What changes once KDE's own
    // locker is switched off is who locks the session on the way down, which
    // used to be ksmserver reacting to logind and starting
    // kscreenlocker_greet. We watch the same signal it does, so sleep and lid
    // close still end on a locked screen -- ours this time.
    //
    // Waking does *not* unlock: PrepareForSleep arrives with `boolean false`
    // on resume and is ignored, because the session was locked before it slept
    // and nothing has happened since.
    //
    // The other signal ksmserver answers, logind's org.freedesktop.login1
    // .Session.Lock, is deliberately *not* watched. It is not gated by any
    // kscreenlockerrc key, so reacting to it would stack our surface on top of
    // the Plasma greeter that same signal always raises -- two locks, one of
    // them wearing KDE's skin. Locking happens through lock() directly instead
    // (the control centre's lock button); anything else calling `loginctl
    // lock-session` still gets a locked session, just Plasma's.
    property bool monitoring: true

    property Process _logindMonitor: Process {
        command: ["dbus-monitor", "--system",
            "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'"]
        running: service.monitoring

        stdout: SplitParser {
            onRead: line => service._handleLogindLine(line)
        }

        // dbus-monitor exits when the bus drops (or on a stray signal). The
        // lock button keeps working either way, but the sleep hook would not,
        // so put the watcher back.
        onExited: service._restartMonitor()
    }

    property Timer _monitorRestart: Timer {
        interval: 2000
        repeat: false
        onTriggered: {
            if (!service.monitoring)
                return
            // Assigning `running` replaces the binding above; from here on the
            // watchdog owns it, and it only ever starts the process.
            service._logindMonitor.running = false
            service._logindMonitor.running = true
        }
    }

    function _restartMonitor() {
        if (monitoring)
            _monitorRestart.restart()
    }

    // dbus-monitor prints a signal header and then its payload on the next
    // (indented) line, so a header arms the read and the payload acts on it.
    property bool _sleepPending: false

    function _handleLogindLine(line) {
        const trimmed = String(line || "").trim()
        if (trimmed.length === 0)
            return

        if (trimmed.startsWith("signal")) {
            _sleepPending = trimmed.indexOf("member=PrepareForSleep") >= 0
            return
        }

        if (!_sleepPending)
            return
        _sleepPending = false

        // `true` is "about to sleep". The `false` that arrives on resume is
        // ignored on purpose: nothing has changed while the machine was down.
        if (trimmed.indexOf("true") >= 0)
            lock()
    }

    // ---- animation fallback ---------------------------------------------

    // The surfaces clear `exiting` themselves when their fade reports
    // finished. If a surface was never mapped -- no output, or unlocked in the
    // same frame it was locked -- no animation runs, and without this the
    // windows would stay mapped forever waiting for one.
    property Timer _exitFallback: Timer {
        interval: 600
        repeat: false
        onTriggered: service.finishExit()
    }
}
