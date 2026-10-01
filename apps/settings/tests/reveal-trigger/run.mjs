import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

// Run the compiled SettingsBridge against an isolated IPC executable. This
// tests serialization and legacy/full snapshots without a live Shell.
assert.ok(process.argv[2], 'usage: run.mjs <kos-settings binary>');
const binary = resolve(process.argv[2]);
const directory = mkdtempSync(join(tmpdir(), 'kos-settings-reveal-trigger-'));
try {
    const checkout = join(directory, 'checkout');
    const shell = join(checkout, 'shell');
    const pages = join(checkout, 'apps/settings');
    const commands = join(directory, 'bin');
    const log = join(directory, 'ipc.jsonl');
    for (const path of [shell, pages, commands, ...['config', 'state', 'runtime', 'cache'].map(name => join(directory, name))])
        mkdirSync(path, { recursive: true, mode: 0o700 });
    writeFileSync(join(shell, 'shell.qml'), 'import QtQuick\nItem {}\n');
    writeFileSync(join(pages, 'main.qml'), `import QtQuick
import QtQuick.Window
Window {
    visible: true
    width: 240
    height: 120
    property int stage: 0
    Connections {
        target: settingsBridge
        function onDockSnapshotChanged(state) {
            const expected = ["fullEdge", "dockSpan", "fullEdge"][stage]
            if (state.revealTriggerMode !== expected) {
                console.log("FAIL snapshot " + stage + ": " + JSON.stringify(state))
                Qt.quit()
                return
            }
            stage++
            if (stage === 1)
                settingsBridge.updateDockRevealTriggerMode("dockSpan")
            else if (stage === 2)
                settingsBridge.updateDockRevealTriggerMode("fullEdge")
            else {
                console.log("SETTINGS_REVEAL_BRIDGE_PASS")
                Qt.quit()
            }
        }
    }
    Component.onCompleted: settingsBridge.dockSnapshot()
    Timer {
        interval: 5000; running: true
        onTriggered: { console.log("FAIL bridge timeout"); Qt.quit() }
    }
}
`);
    const fakeIpc = join(commands, 'quickshell');
    writeFileSync(fakeIpc, `#!${process.execPath}
const { appendFileSync } = require('node:fs');
const args = process.argv.slice(2);
appendFileSync(process.env.KOS_TEST_IPC_LOG, JSON.stringify(args) + '\\n');
const ipc = args.indexOf('ipc');
if (ipc < 0 || args[ipc + 1] !== 'call' || args[ipc + 2] !== 'dock-settings') process.exit(2);
const method = args[ipc + 3];
const snapshot = { baseHeight: 60, visibilityMode: 'smart', windowGrouping: 'grouped' };
if (method === 'updateRevealTriggerMode') {
    if (!['dockSpan', 'fullEdge'].includes(args[ipc + 4]) || args.length !== ipc + 5) process.exit(3);
    snapshot.revealTriggerMode = args[ipc + 4];
} else if (method !== 'snapshot' || args.length !== ipc + 4) process.exit(4);
console.log(JSON.stringify(snapshot));
`);
    chmodSync(fakeIpc, 0o700);
    const result = spawnSync(binary, [], {
        encoding: 'utf8', timeout: 10000, killSignal: 'SIGKILL',
        env: { ...process.env, PATH: `${commands}:${process.env.PATH || ''}`,
            KOS_TEST_IPC_LOG: log, KOS_SHELL_DIR: shell,
            XDG_CONFIG_HOME: join(directory, 'config'), XDG_STATE_HOME: join(directory, 'state'),
            XDG_RUNTIME_DIR: join(directory, 'runtime'), XDG_CACHE_HOME: join(directory, 'cache'),
            QT_QPA_PLATFORM: 'offscreen', QT_QUICK_BACKEND: 'software', QSG_RHI_BACKEND: 'software',
            QT_FORCE_STDERR_LOGGING: '1', WAYLAND_DISPLAY: '', DISPLAY: '' },
    });
    const output = (result.stdout || '') + (result.stderr || '');
    assert.equal(result.error, undefined, String(result.error));
    assert.equal(result.status, 0, output);
    assert.doesNotMatch(output, /FAIL |ReferenceError|TypeError|is not a function/, output);
    assert.match(output, /SETTINGS_REVEAL_BRIDGE_PASS/, output);
    const requests = readFileSync(log, 'utf8').trim().split('\n').map(line => {
        const args = JSON.parse(line);
        return args.slice(args.indexOf('ipc') + 1);
    });
    assert.deepEqual(requests, [
        ['call', 'dock-settings', 'snapshot'],
        ['call', 'dock-settings', 'updateRevealTriggerMode', 'dockSpan'],
        ['call', 'dock-settings', 'updateRevealTriggerMode', 'fullEdge'],
    ]);
    console.log('Settings reveal bridge: legacy default, both IPC arguments and snapshot round trips passed');
} finally {
    rmSync(directory, { recursive: true, force: true });
}
