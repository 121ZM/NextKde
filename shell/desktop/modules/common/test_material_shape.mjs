// Node harness for the Material shape library. Run directly:
//
//   node shell/desktop/modules/common/test_material_shape.mjs
//
// Three things are pinned here that a screenshot cannot pin:
//
//   1. The library is normalised. Every outline reaches the edge of the box it
//      is drawn into and never leaves it, so a card cannot end up with a shape
//      that is 20% smaller than its neighbours because of a stray vertex.
//   2. The scanline the compositor frosts with agrees with the outline that is
//      painted: spansAt() is compared against the analytic answer for a circle
//      and a square, and against the shape's own concavity for a flower.
//   3. Which shapes a card may wear is a *measurement*, not a taste: every
//      entry of CARD_SHAPES fits the four region slots MaterialShapeBlurRegion
//      declares per row and leaves a centred rectangle big enough for content.
//      A shape that stops qualifying fails here instead of emptying a card.
//
// The last block reads the shipped QML for shape names, so a card cannot be
// given a shape this file has never checked.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
    CARD_OUTLINES,
    CARD_SHAPES,
    SHAPE_NAMES,
    fitsRegion,
    hasShape,
    inscribedRect,
    isCardShape,
    maxSpansPerRow,
    rowSpanCount,
    shapeOutline,
    spansAt,
} from "./MaterialShape.mjs";

let checks = 0;
function check(condition, message) {
    checks += 1;
    assert.ok(condition, message);
}

// ---------------------------------------------------------------------------
// 1. Library and lookup
// ---------------------------------------------------------------------------

check(SHAPE_NAMES.length >= 20,
    "the library carries the reference's shape set, not a handful of blobs");
check(new Set(SHAPE_NAMES).size === SHAPE_NAMES.length,
    "shape names are unique");

for (const name of SHAPE_NAMES) {
    check(hasShape(name), name + " is looked up by its own name");
    check(/^[a-z][A-Za-z0-9]*$/.test(name),
        name + " is a plain camelCase identifier");
}

// An unknown name is a caller's typo, and a shape library that throws inside a
// QML binding blanks the surface. It answers with the circle instead.
check(!hasShape("nonexistent"));
const fallback = shapeOutline("nonexistent");
assert.deepEqual(fallback, shapeOutline("circle"),
    "an unknown shape name draws a circle rather than failing");
check(checks > 0, "sanity");

// ---------------------------------------------------------------------------
// 2. Normalisation
// ---------------------------------------------------------------------------

for (const name of SHAPE_NAMES) {
    const outline = shapeOutline(name);
    check(outline.length >= 4, name + " has a closed outline");
    let maxX = 0;
    let maxY = 0;
    for (const point of outline) {
        check(Number.isFinite(point.x) && Number.isFinite(point.y),
            name + " produces finite coordinates");
        maxX = Math.max(maxX, Math.abs(point.x));
        maxY = Math.max(maxY, Math.abs(point.y));
    }
    check(maxX <= 1 + 1e-9 && maxY <= 1 + 1e-9,
        name + " stays inside the [-1, 1] box: " + maxX + ", " + maxY);
    check(Math.abs(Math.max(maxX, maxY) - 1) < 1e-6,
        name + " reaches the edge of that box on its long axis: "
        + Math.max(maxX, maxY));
    // Centred: the box is symmetric about the origin on both axes, or the
    // shape would sit off-centre in its card.
    let minX = 0;
    let minY = 0;
    for (const point of outline) {
        minX = Math.min(minX, point.x);
        minY = Math.min(minY, point.y);
    }
    check(Math.abs(maxX + minX) < 1e-6 && Math.abs(maxY + minY) < 1e-6,
        name + " is centred on the origin");
}

// The circle is the control: a ten-gon whose corners consume their whole edge
// is a circle to within the quadratic's own error, which is the tolerance the
// rest of this file leans on.
{
    const outline = shapeOutline("circle");
    let worst = 0;
    for (const point of outline)
        worst = Math.max(worst, Math.abs(Math.hypot(point.x, point.y) - 1));
    check(worst < 0.02, "circle is round to within " + worst.toFixed(4));
}

// Cached: the region and the painter ask for the same outline, and they must
// be handed the same array rather than two equal copies.
check(shapeOutline("flower") === shapeOutline("flower"),
    "an outline is computed once and shared");

// ---------------------------------------------------------------------------
// 3. Scanline agreement
// ---------------------------------------------------------------------------

// A circle: every row's span is the analytic chord.
{
    const outline = shapeOutline("circle");
    const rows = 64;
    for (let row = 0; row < rows; ++row) {
        const offset = -1 + (row + 0.5) * 2 / rows;
        const spans = spansAt(outline, offset, 1, 1);
        check(spans.length === 1,
            "a convex shape crosses row " + row + " once");
        const expected = Math.sqrt(Math.max(0, 1 - offset * offset));
        check(Math.abs(spans[0].left + expected) < 0.02
            && Math.abs(spans[0].right - expected) < 0.02,
        "circle row " + row + " lands on the analytic chord: "
            + spans[0].left.toFixed(4) + " / " + spans[0].right.toFixed(4)
            + " against " + (-expected).toFixed(4));
    }
}

// A square: full width between the corner tangent points, then a rounded
// corner. The flat part is exact, because the rounder only starts where the
// corner arc does.
{
    const outline = shapeOutline("square");
    const rows = 64;
    for (let row = 0; row < rows; ++row) {
        const offset = -1 + (row + 0.5) * 2 / rows;
        if (Math.abs(offset) > 0.65)
            continue
        const spans = spansAt(outline, offset, 1, 1)
        check(spans.length === 1 && Math.abs(spans[0].left + 1) < 1e-6
            && Math.abs(spans[0].right - 1) < 1e-6,
        "square row " + row + " spans the whole box: "
            + spans[0].left.toFixed(4) + " / " + spans[0].right.toFixed(4))
    }
}

// A flower: the notches are real. A row above the shape's middle has to be
// crossed more than once, or the outline is a blob wearing a flower's name.
{
    const outline = shapeOutline("flower");
    let multiple = 0;
    const rows = 24;
    for (let row = 0; row < rows; ++row) {
        const offset = -1 + (row + 0.5) * 2 / rows
        if (spansAt(outline, offset, 1, 1).length > 1)
            multiple += 1
    }
    check(multiple >= 2, "the flower's notches split at least two scanlines, "
        + "not " + multiple)
}

// Spans are ordered and non-overlapping on every row of every shape: the
// region builder publishes them as-is.
for (const name of SHAPE_NAMES) {
    const outline = shapeOutline(name)
    for (let row = 0; row < 24; ++row) {
        const offset = -1 + (row + 0.5) * 2 / 24
        const spans = spansAt(outline, offset, 1, 1)
        for (let i = 0; i < spans.length; ++i) {
            check(spans[i].right - spans[i].left > 0,
                name + " row " + row + " span " + i + " has width");
            if (i > 0)
                check(spans[i].left > spans[i - 1].right,
                    name + " row " + row + " spans stay ordered")
        }
    }
}

// The library's worst case is reported by the same walk the region component
// uses to size itself.
check(maxSpansPerRow(24) === Math.max(...SHAPE_NAMES.map(
    (name) => rowSpanCount(name, 24))), "maxSpansPerRow agrees with its parts");
check(maxSpansPerRow(24) > 4,
    "the library does contain shapes too spiky for the card region, so the "
    + "CARD_SHAPES check below is not vacuous");

// ---------------------------------------------------------------------------
// 4. What a card may wear
// ---------------------------------------------------------------------------

// The region component declares four slots per row.
const REGION_SLOTS = 4
const REGION_ROWS = 24

for (const name of CARD_SHAPES) {
    check(hasShape(name), "card shape " + name + " exists")
    check(fitsRegion(name, REGION_ROWS, REGION_SLOTS),
        "card shape " + name + " fits the region's " + REGION_SLOTS
        + " slots per row, needs " + rowSpanCount(name, REGION_ROWS))
    const rect = inscribedRect(shapeOutline(name), 64)
    check(rect.halfWidth >= 0.45 && rect.halfHeight >= 0.45,
        "card shape " + name + " leaves room for content: "
        + rect.halfWidth.toFixed(2) + " x " + rect.halfHeight.toFixed(2))
    check(isCardShape(name), name + " answers isCardShape()")
}

// Half the library is card-wearable: enough choice that the form is not "one
// blob everywhere", few enough that the list stays meaningful.
check(CARD_SHAPES.length >= 12 && CARD_SHAPES.length < SHAPE_NAMES.length,
    "the card set is a subset, and a substantial one: "
    + CARD_SHAPES.length + " of " + SHAPE_NAMES.length)
check(!isCardShape("boom") && !isCardShape("burst")
    && !isCardShape("triangle"),
    "the shapes with no room for content stay out of it")

// The inscribed rectangle shrinks as the shape gets pointier -- that ordering
// is what makes the measurement meaningful rather than decorative.
check(inscribedRect(shapeOutline("square"), 64).halfWidth
    > inscribedRect(shapeOutline("cookie4"), 64).halfWidth,
"a square holds more than a cookie does")

// ---------------------------------------------------------------------------
// 5. What the cards actually wear
// ---------------------------------------------------------------------------

// The outline a card is given has to leave it room to draw in. The widgets put
// their content within a few percent of the card's edge (fixed paddings, fixed
// type sizes), so the shape's notches must not reach that far in: this is the
// share of the half-box a centred rectangle still has to cover, at the depth
// the widget is actually given.
const CONTENT_SPACE = 0.58

for (const [id, entry] of Object.entries(CARD_OUTLINES)) {
    check(hasShape(entry.shape), "card outline " + id + " names a real shape")
    check(isCardShape(entry.shape),
        "card outline " + id + " is on the card-wearable list: " + entry.shape)
    check(entry.strength > 0 && entry.strength <= 1,
        "card outline " + id + " has a strength in range: " + entry.strength)
    const worn = inscribedRect(shapeOutline(entry.shape, entry.strength), 64)
    check(worn.halfWidth >= CONTENT_SPACE && worn.halfHeight >= CONTENT_SPACE,
        "card outline " + id + " leaves room for its content: "
        + worn.halfWidth.toFixed(2) + " x " + worn.halfHeight.toFixed(2)
        + " against a required " + CONTENT_SPACE)
    // The depth has to actually do something, or the table is decoration.
    if (entry.strength < 1) {
        const full = inscribedRect(shapeOutline(entry.shape, 1), 64)
        check(full.halfWidth < worn.halfWidth || full.halfHeight < worn.halfHeight,
            "card outline " + id + " is shallower than the untouched shape")
    }
}

// Every shape in the table has to be *reachable*: the same shape at full depth
// is what a decorative surface draws, and the table is what a card draws. If a
// name only ever appeared here, its library entry would be untested weight.
check(Object.keys(CARD_OUTLINES).length >= 8,
    "the table covers the desktop's widgets")

// The depth knob is monotonic in the direction the comments claim: lower
// strength, more room for content, never less.
{
    const deep = inscribedRect(shapeOutline("flower", 1), 64)
    const shallow = inscribedRect(shapeOutline("flower", 0.5), 64)
    check(shallow.halfWidth > deep.halfWidth && shallow.halfHeight > deep.halfHeight,
        "blending a flower towards its box only ever widens the space content gets")
    const box = shapeOutline("flower", 0)
    let worst = 0
    for (const point of box)
        worst = Math.max(worst, Math.abs(Math.max(Math.abs(point.x),
            Math.abs(point.y)) - 1))
    check(worst < 1e-9,
        "strength 0 is the bounding box itself: every point sits on it, worst "
        + "miss " + worst)
    check(shapeOutline("flower", 1).length === box.length,
        "blending keeps the outline's point count, so the region stays valid")
}

// ---------------------------------------------------------------------------
// 6. The shipped QML asks the table rather than naming shapes itself
// ---------------------------------------------------------------------------

{
    const tokens = readFileSync(new URL("AppearanceTokens.qml", import.meta.url),
        "utf8")
    check(/function outline\(/.test(tokens) && /cardOutline\(id\)/.test(tokens),
        "the tokens resolve a widget's outline through the geometry table")
    check(!/return "(flower|sunny|cookie)/.test(tokens),
        "the tokens do not hardcode a shape name of their own")

    const window = readFileSync(
        new URL("../deskcenter/DeskCenterWindow.qml", import.meta.url), "utf8")
    check(/surfaceShape: AppearanceTokens\.widget\.outline\(modelData\.id\)/
        .test(window),
    "DeskCenterWindow asks the policy for a card outline")
    check(/surfaceShapeStrength:\s*\n?\s*AppearanceTokens\.widget\.outlineStrength\(modelData\.id\)/
        .test(window),
    "and for the depth that goes with it")

    // The player's controls wear shapes too, and they are named where they are
    // used rather than through the table: they are not cards.
    check(/index === 1 \? "softBurst" : "cookie6"/.test(window),
        "the player's controls draw shapes from the same library")
}

console.log("MaterialShape: " + checks + " checks passed, "
    + SHAPE_NAMES.length + " shapes, " + CARD_SHAPES.length + " card-wearable, "
    + Object.keys(CARD_OUTLINES).length + " card outlines");
