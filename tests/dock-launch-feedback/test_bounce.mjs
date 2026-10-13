import assert from 'node:assert/strict';
import { trackPointer, launchBounce } from '../../shell/desktop/modules/dock/DockMagnification.mjs';
assert.equal(launchBounce(0), 0);
assert.equal(launchBounce(0.41), 1);
assert.equal(launchBounce(0.82), 0);
assert.equal(launchBounce(1), 0);
for (let phase = 0; phase <= 1; phase += 0.001)
    assert.ok(launchBounce(phase) >= 0 && launchBounce(phase) <= 1);
// High-refresh sweeps have no time-constant lag; slow travel stays subpixel.
for (const hz of [60, 120, 144, 240]) {
    for (const speed of [120, 500, 600, 1200, 4000]) {
        let previous = 0;
        for (let frame = 1; frame < hz; frame++) {
            const raw = speed * frame / hz;
            const output = trackPointer(previous, raw, 1 / hz);
            assert.ok(Math.abs(raw - output) <= 0.6);
            if (speed >= 600) assert.equal(output, raw, `fast ${speed}px/s at ${hz}Hz`);
            assert.equal(trackPointer(raw, raw, 1 / hz), raw, 'stop settles next frame exactly');
            previous = raw;
        }
    }
}
console.log('Launch flight and high-refresh bounded-lag pointer tracking passed');
