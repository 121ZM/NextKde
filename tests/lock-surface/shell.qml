import QtQuick
import Quickshell
import qs.desktop.modules.lock

// Smoke host for the lock surface. Loaded offscreen by run.mjs.
//
// No pixel assertion is possible here -- this environment has no GPU context
// and no Wayland session, so nothing is rasterised and the PanelWindow that
// normally carries this Item cannot be constructed at all. What is covered is
// the part of the lock that fails silently while editing:
//
//   - the group flattening in LockSurface, against a source with more groups
//     than fit and with column names taken from NotificationGroupService's own
//     schema (run.mjs checks those two lists against each other);
//   - the clock and date formatting;
//   - the rejected-password path end to end through PAM, including the
//     conversation answer that a retry depends on.
//
// The instant is pinned for the clock check, because the surface's own
// one-second timer would otherwise race the assertions.
Item {
    id: root

    width: 480
    height: 900

    // The sleep watcher has nothing to talk to without a system bus, and a
    // failing dbus-monitor would just retry in a loop for the whole run.
    Binding {
        target: LockService
        property: "monitoring"
        value: false
    }

    // ---- stand-in for NotificationGroupService ---------------------------
    //
    // Same two members LockSurface reads: a ListModel of presentation rows and
    // a revision that changes when the rows are rebuilt. Four groups so the
    // surface's three-group cap is actually exercised, newest at index 0 the
    // way the real service sorts them.
    QtObject {
        id: groups

        property int sidecarRevision: 0
        property ListModel groupsModel: ListModel {
            ListElement {
                groupKey: "alpha"; appName: "Alpha"; appIcon: "alpha.png"
                count: 4; collapsed: false
                latestSummary: "Alpha summary"; latestBody: "Alpha body"
                latestUrgency: 2; latestImage: ""
                hasActions: true; hasInlineReply: false; createdAt: 3
            }
            ListElement {
                groupKey: "beta"; appName: "Beta"; appIcon: "beta.png"
                count: 1; collapsed: false
                latestSummary: "Beta summary"; latestBody: ""
                latestUrgency: 1; latestImage: "shot.png"
                hasActions: false; hasInlineReply: false; createdAt: 2
            }
            ListElement {
                groupKey: "gamma"; appName: "Gamma"; appIcon: ""
                count: 2; collapsed: true
                latestSummary: "Gamma summary"; latestBody: "Gamma body"
                latestUrgency: 0; latestImage: ""
                hasActions: false; hasInlineReply: true; createdAt: 1
            }
            ListElement {
                groupKey: "delta"; appName: "Delta"; appIcon: "delta.png"
                count: 9; collapsed: false
                latestSummary: "Delta summary"; latestBody: "Delta body"
                latestUrgency: 1; latestImage: ""
                hasActions: false; hasInlineReply: false; createdAt: 0
            }
        }
    }

    LockSurface {
        id: surface
        anchors.fill: parent
        // Hidden so the surface's own one-second clock timer never starts --
        // `running` is bound to `visible` -- which keeps `now` on the pinned
        // instant below for the whole run. Nothing here is rasterised anyway.
        visible: false
        groupService: groups
        now: new Date(2026, 8, 15, 13, 5, 0)
    }

    property bool passwordCheckDone: false

    function expect(ok, message) {
        console.log((ok ? "LOCK_SURFACE_OK " : "LOCK_SURFACE_FAIL ") + message)
    }

    // ---- group flattening ------------------------------------------------

    function assertGroups() {
        const rows = surface.visibleGroups
        expect(rows.length === 3, "three groups fit, got " + rows.length)

        const expectedKeys = "appIcon,appName,body,count,groupKey,image,summary,urgency"
        const actualKeys = Object.keys(rows[0]).sort().join(",")
        expect(actualKeys === expectedKeys, "card fields are " + actualKeys)

        const first = rows[0]
        expect(first.groupKey === "alpha" && first.appName === "Alpha",
            "newest group is first")
        expect(first.summary === "Alpha summary" && first.body === "Alpha body",
            "summary and body come from the latest* columns")
        expect(first.count === 4 && first.urgency === 2, "count and urgency")
        expect(first.image === "" && first.appIcon === "alpha.png",
            "an empty image column falls through to the app icon")

        // Delta is the fourth group and is the one that must be dropped.
        const keys = rows.map(row => row.groupKey)
        expect(keys.indexOf("delta") < 0, "the fourth group is dropped")

        expect(surface.clockText === "13:05",
            "clock reads " + surface.clockText)
        // Zero-padded 24-hour, and the day name is the locale's long form --
        // which it is in C is not this test's business.
        expect(surface.dateText.startsWith("9月15日 "),
            "date reads " + surface.dateText)
    }

    // ---- rejected password -----------------------------------------------

    function startPasswordCheck() {
        LockService.lock()
        expect(LockService.locked, "lock() raises the locked flag")
        expect(LockService.submitPassword("") === false,
            "an empty password starts nothing")
        expect(LockService.submitPassword("lock-surface-fixture-probe"),
            "a non-empty password starts a conversation")
        expect(LockService.authenticating, "the field is busy while PAM runs")
    }

    function finishPasswordCheck() {
        if (root.passwordCheckDone)
            return
        root.passwordCheckDone = true

        expect(!LockService.authenticating,
            "the conversation ended instead of hanging")
        expect(LockService.failed, "a wrong password is reported as a failure")
        expect(LockService.errorMessage.length > 0,
            "the failure carries a message: " + LockService.errorMessage)
        expect(LockService.locked, "a failed attempt stays locked")
        console.log("LOCK_SURFACE_PASS")
        Qt.quit()
    }

    // PAM answers on a subprocess, so the rejection is not observable in the
    // frame that asked for it.
    Timer {
        id: passwordPoll
        interval: 60
        repeat: true
        running: false
        onTriggered: {
            if (LockService.authenticating)
                return
            running = false
            root.finishPasswordCheck()
        }
    }

    Timer {
        interval: 90
        repeat: false
        running: true
        onTriggered: {
            root.assertGroups()
            root.startPasswordCheck()
            passwordPoll.start()
        }
    }

    // Entering and leaving PAM is a spawn plus a fork. Anything slower than
    // this is a hang, and the assertions above will say which one it was.
    Timer {
        interval: 8000
        repeat: false
        running: true
        onTriggered: root.finishPasswordCheck()
    }
}
