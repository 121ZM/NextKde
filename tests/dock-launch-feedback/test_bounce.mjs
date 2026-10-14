import assert from 'node:assert/strict';
import { launchBounce } from '../../shell/desktop/modules/dock/DockMagnification.mjs';
assert.equal(launchBounce(0), 0);
assert.equal(launchBounce(0.41), 1);
assert.equal(launchBounce(0.82), 0);
assert.equal(launchBounce(1), 0);
for (let phase = 0; phase <= 1; phase += 0.001)
    assert.ok(launchBounce(phase) >= 0 && launchBounce(phase) <= 1);
console.log('Launch flight stays bounded and returns to ground');
