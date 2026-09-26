import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('./WallpaperPreviewService.qml', import.meta.url), 'utf8');
const functions = source.slice(source.indexOf('    function begin('), source.indexOf('    property Timer loadingWatchdog:'));
function fixture() {
    const calls = [], commits = [];
    const state = {
        active: false, pending: false, presented: false, previousDesktop: false,
        image: '', images: [], errorMessage: '', remainingSeconds: 60,
        direction: 1, restoring: false, generation: 0, readyOutputs: [], abortPending: false,
        ScreenLifecycle: { usableScreens: [{ name: "HDMI-1" }] },
        loadingWatchdog: { restart() {}, stop() {} },
        WallpaperService: {
            takeoverPending: false,
            localPath: value => String(value).startsWith('/') ? String(value) : '',
            chooseImage(path) { commits.push(path); return true; },
        },
        AppearanceConfigService: { updateSpatialWallpaperEnabled() {} },
        PlatformClient: { request(op, payload, callback) { calls.push({ op, payload, callback }); } },
    };
    state.service = state;
    vm.createContext(state);
    vm.runInContext(functions, state);
    return { state, calls, commits };
}
{
    const { state, calls, commits } = fixture();
    state.begin('/one.jpg', '["/one.jpg","/two.jpg"]');
    assert.deepEqual(commits, [], 'preview must not persist a wallpaper');
    assert.equal(calls.length, 0, 'do not hide windows before the image is ready');
    state.imageReady('/stale.jpg', 'HDMI-1');
    assert.equal(calls.length, 0, 'late decode must not reveal another image');
    state.imageReady('/one.jpg', 'HDMI-1');
    calls[0].callback({ ok: true, result: { previous: false } });
    state.move(1);
    assert.equal(state.image, '/two.jpg');
    state.finish(false);
    assert.equal(state.active, false);
    assert.deepEqual(commits, [], 'cancel must leave the original wallpaper intact');
    assert.equal(calls[1].payload.showing, false, 'restore the previous window visibility');
    calls[1].callback({ ok: true });
    assert.equal(state.restoring, false);
}
{
    const { state, calls, commits } = fixture();
    state.begin('/one.jpg', '[]');
    state.imageReady('/one.jpg', 'HDMI-1');
    calls[0].callback({ ok: true, result: { previous: true } });
    state.finish(true);
    assert.deepEqual(commits, ['/one.jpg']);
    assert.equal(calls[1].payload.showing, true, 'already showing desktop must stay that way');
}
{
    const { state, calls, commits } = fixture();
    state.begin('/broken.jpg', 'null');
    state.imageFailed('/broken.jpg');
    assert.equal(state.active, false);
    assert.equal(calls.length, 0);
    assert.deepEqual(commits, []);
    assert.ok(state.errorMessage);
}
{
    const { state, calls } = fixture();
    state.begin('/one.jpg', '[]');
    state.imageReady('/one.jpg', 'HDMI-1');
    calls[0].callback({ ok: false, error: { message: 'offline' } });
    assert.equal(state.active, false);
    assert.equal(state.errorMessage, 'offline');
}
{
    const { state, calls } = fixture();
    state.ScreenLifecycle.usableScreens.push({ name: 'DP-1' });
    state.begin('/one.jpg', '[]');
    state.imageReady('/one.jpg', 'HDMI-1');
    assert.equal(calls.length, 0, 'keep windows visible until every output decoded');
    state.imageReady('/one.jpg', 'DP-1');
    assert.equal(calls.length, 1);
    calls[0].callback({ ok: true, result: { previous: false } });
    state.finish(false);
    calls[1].callback({ ok: true });
}
console.log('wallpaper preview rollback contracts: passed');
