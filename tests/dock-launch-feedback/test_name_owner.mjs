import assert from 'node:assert/strict';
import {layout, nameOwner} from '../../shell/desktop/modules/dock/DockMagnification.mjs';
const states = Array.from({length: 6}, (_, i) => ({
    item: {index: i}, cx: 30 + i * 60, half: 26, artHalf: 22, growable: true,
}));
for (const scale of [1, 1.2, 2, 3]) {
    for (let x = states[0].cx; x <= states.at(-1).cx; x += 0.5) {
        const frame = layout(states, x, 1, scale, 220, 8);
        assert.ok(nameOwner(states, frame, x), `blank at ${x}, scale ${scale}`);
    }
}
const flat = layout(states, 120, 0, 1, 220, 8);
assert.equal(nameOwner(states, flat, -1000), null);
assert.equal(nameOwner(states, flat, 1000), null);
assert.equal(nameOwner(states, flat, NaN), null);
const divider = {item: {}, cx: 180, half: 3, growable: false};
const separated = states.slice(0, 3).concat([divider], states.slice(3));
const blocked = layout(separated, 180, 0, 1, 220, 8);
assert.equal(nameOwner(separated, blocked, 180), null);
// A rigid slot may never become an application's ownership region.
const spacer = {...divider, half: 30, flexible: true};
const spaced = states.slice(0, 3).concat([spacer], states.slice(4));
assert.equal(nameOwner(spaced, layout(spaced, 180, 0, 1, 220, 8), 180), null);
console.log('Continuous bounded name ownership: shared layouts, spacing and rigid barriers passed');
