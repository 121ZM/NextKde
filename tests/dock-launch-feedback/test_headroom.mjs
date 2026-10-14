import assert from 'node:assert/strict';
import { launchBounce, visualHeadroom } from '../../shell/desktop/modules/dock/DockMagnification.mjs';

// Reconstruct physical surface and artwork bounds, rather than using an
// oversized fixture window. The inputs include the exact no-hover case that
// previously allocated only 4 px for a 0.65 * iconSize launch excursion.
for (const edge of ['bottom', 'left', 'right']) {
    for (const size of [18, 44, 96]) {
        for (const gap of [0, 4]) {
            for (const maxScale of [1, 1.2, 2, 3]) {
                const liftRatio = 0.2 * (maxScale - 1);
                const slot = size + 2 * gap;
                const thickness = slot + 8;
                const headroom = visualHeadroom(size, gap, maxScale, liftRatio, thickness, 0.65);
                const edgeMargin = 6;
                const workspaceMargin = 6;
                const nameBudget = 6 + (edge === "bottom" ? 28 : 220);
                const surfaceThickness = thickness + edgeMargin + workspaceMargin + headroom + nameBudget;
                const glassNear = edge === 'left' ? edgeMargin : workspaceMargin + headroom + nameBudget;
                const slotCenter = glassNear + thickness / 2;
                const inputNear = edge === 'left' ? glassNear : glassNear - headroom;
                const inputFar = edge === 'left' ? glassNear + thickness + headroom : glassNear + thickness;
                assert.ok(edge === 'left'
                    ? surfaceThickness - inputFar >= nameBudget
                    : inputNear >= nameBudget, 'label-only space must remain outside input mask');
                for (const hover of [0, 0.5, 1]) {
                    const scale = 1 + hover * (maxScale - 1);
                    // This is DockIcon's actual center-origin scale compensation
                    // and continuous hover lift, composed with ballistic flight.
                    const hoverTranslation = -size * liftRatio * hover - slot / 2 * (scale - 1);
                    for (let phase = 0; phase <= 1; phase += 0.025) {
                        const launchTranslation = -size * 0.65 * launchBounce(phase);
                        const direction = edge === 'left' ? -1 : 1;
                        const center = slotCenter + direction * (hoverTranslation + launchTranslation);
                        const near = center - slot * scale / 2;
                        const far = center + slot * scale / 2;
                        const context = `${edge} size=${size} gap=${gap} scale=${maxScale} phase=${phase}`;
                        assert.ok(near >= 0 && far <= surfaceThickness, `surface clips: ${context}`);
                        assert.ok(near >= inputNear && far <= inputFar, `hover input clips: ${context}`);
                    }
                }
            }
        }
    }
}
console.log('Real thin surface + input budgets contain combined hover/launch motion on all edges');
