import assert from 'node:assert/strict';
import { releaseLaunchFeedback } from '../../shell/desktop/modules/dock/DockMagnification.mjs';

const started = 1000;
const release = (elapsed, ready) => releaseLaunchFeedback(started, started + elapsed, ready, 500, 15000);

// Even an immediately mapped window leaves enough frames for visible feedback.
for (const elapsed of [0, 1, 16, 100, 499]) {
    assert.equal(release(elapsed, true), false, `ready window cleared feedback at ${elapsed}ms`);
}
assert.equal(release(500, true), true);
assert.equal(release(900, true), true, 'slow readiness does not add another minimum delay');
assert.equal(release(500, false), false, 'minimum is not a windowless launch deadline');
assert.equal(release(14999, false), false);
assert.equal(release(15000, false), true, 'windowless launches remain bounded');
assert.equal(release(-1, true), false, 'a backwards clock must not clear feedback early');
console.log('Fast window readiness preserves visible launch feedback without extending slow readiness or the timeout');
