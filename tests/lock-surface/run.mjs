import assert from "node:assert/strict";
import { copyFileSync, mkdtempSync, readFileSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

// Loads the lock surface under a real Quickshell, offscreen.
//
// The lock's window cannot be tested here -- LockWindow is a PanelWindow and
// Quickshell refuses to build one without a Wayland session ("No PanelWindow
// backend loaded"), which is exactly why the composition lives on a plain Item
// in LockSurface.qml. That Item, its cards and its password field are what this
// fixture builds, with a synthetic group source standing in for the
// notification centre.
const repository = fileURLToPath(new URL("../..", import.meta.url));
const shell = join(repository, "shell");

// ---- the cross-file contract the fixture cannot see ------------------------
//
// LockSurface reads its rows through ListModel.get() and copies them field by
// field. That copy is the only place the lock depends on
// NotificationGroupService's schema, and a rename on either side is invisible
// to QML: the property just reads undefined and the card goes blank. Compare
// the two source files instead.
const groupService = readFileSync(join(shell, "desktop", "modules",
    "notifications", "NotificationGroupService.qml"), "utf8");
const schemaMatch = groupService.match(/const keys = \[([\s\S]*?)\]/);
assert.ok(schemaMatch,
    "NotificationGroupService still declares one array of model columns");
const schema = new Set(
    [...schemaMatch[1].matchAll(/"([A-Za-z_][A-Za-z0-9_]*)"/g)].map(m => m[1]));
assert.ok(schema.size >= 8, `model schema parsed, got ${schema.size} columns`);

const surfaceSource = readFileSync(join(shell, "desktop", "modules", "lock",
    "LockSurface.qml"), "utf8");
const read = new Set(
    [...surfaceSource.matchAll(/\brow\.([A-Za-z_][A-Za-z0-9_]*)/g)].map(m => m[1]));
assert.ok(read.size >= 8, `LockSurface reads ${read.size} columns`);

for (const column of read) {
    assert.ok(schema.has(column),
        `LockSurface reads "${column}", which NotificationGroupService `
        + "no longer publishes");
}
console.log(`Lock rows: ${read.size} columns read, all present in the schema`);

// ---- the live fixture ------------------------------------------------------

const directory = mkdtempSync(join(tmpdir(), "kos-lock-surface-"));
try {
    copyFileSync(new URL("shell.qml", import.meta.url),
        join(directory, "shell.qml"));
    // Quickshell resolves "qs.desktop.modules.*" against the config directory,
    // and every module that touches the palette reaches the shared library
    // through its own relative "../../../Kos/Ui" path. Both names have to exist
    // in the scratch directory for the tree to resolve exactly as it does in a
    // live session; without the second one the failure is a bare "module
    // ../../../Kos/Ui is not installed" six frames down the type chain.
    symlinkSync(join(shell, "desktop"), join(directory, "desktop"), "dir");
    symlinkSync(join(shell, "Kos"), join(directory, "Kos"), "dir");

    const result = spawnSync(process.argv[2] || "quickshell",
        ["-p", directory], {
            encoding: "utf8",
            timeout: 25000,
            env: {
                ...process.env,
                QT_QPA_PLATFORM: "offscreen",
                QT_QUICK_BACKEND: "software",
            },
        });

    const output = (result.stdout || "") + (result.stderr || "");
    assert.equal(result.error, undefined, String(result.error));
    assert.equal(result.status, 0, output);
    assert.match(output, /LOCK_SURFACE_PASS/);
    assert.doesNotMatch(output, /LOCK_SURFACE_FAIL/, output);
    // QML resolves types and property names at load time, so this catches the
    // cards drifting away from their own registration in modules/lock/qmldir,
    // from SquircleMask, or from the fields the flattening hands them.
    assert.doesNotMatch(output,
        /is not a type|is not a function|Cannot assign|Unable to assign|ReferenceError|TypeError/,
        output);
    console.log("LockSurface offscreen: group flattening, clock and the "
        + "rejected-password path all hold");
} finally {
    // The scratch tree is nothing but symlinks, and some sandboxes route rm
    // through a trash directory the process cannot write. Cleanup failing says
    // nothing about the lock surface, so it must not be able to fail the test.
    try {
        rmSync(directory, { recursive: true, force: true });
    } catch {
        console.error(`left ${directory} for the system temp reaper`);
    }
}
