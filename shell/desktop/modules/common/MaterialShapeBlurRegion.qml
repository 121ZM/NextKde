import Quickshell
import QtQuick
import "MaterialShape.mjs" as Geometry

// The compositor blur region for one Material outline.
//
// Wayland regions are rectangles, and the shapes here are concave -- petals,
// notches, spikes -- so no set of axis-aligned ellipses reproduces them and
// `Region.regions` is a readonly list that JS cannot push into. The outline is
// therefore walked row by row (a scanline fill) and each row publishes the span
// or spans it covers. The geometry comes from MaterialShape.mjs, the same
// outline MaterialShape paints, so the frosted edge lands on the drawn one
// instead of near it -- and the two cannot drift, because there is one outline
// rather than two descriptions of it.
//
// Coordinates are surface coordinates, exactly like RoundedBlurRegion: `item`
// must be the positioned wrapper whose x/y are the card's surface position. A
// panel nested inside another item reports 0 there, which puts the frost at the
// window origin.
//
// The rows below are declared statically, in the only shape QML allows: 24
// scanlines x 4 spans. Four is what the shapes a *card* is allowed to wear
// need, and fitsRegion() in the geometry module is the check (the library also
// has spikier members -- boom, softBoom -- which is why the constant is not
// simply "2"). Empty slots collapse to zero-size regions, so a shape that
// crosses a row once costs one rectangle and three no-ops.
Region {
    id: root

    required property Item item
    // Any name from the MaterialShape library.
    property string shape: "circle"
    // Must match the painter's strength, or the frost lands off the paint.
    property real strength: 1
    // Set false to publish nothing while keeping the component alive.
    property bool active: true
    // Must match the painter's insets, or the frost lands off the paint.
    property real horizontalInset: 0
    property real verticalInset: 0
    // Scanlines. More rows means a finer stair on the lobes; the frost behind
    // the edge is blurred anyway, so this is about the silhouette, not about
    // anti-aliasing.
    property int sliceCount: 24
    // Must stay in step with the number of declared slots below.
    readonly property int spansPerRow: 4

    readonly property var outline: Geometry.shapeOutline(shape, strength)
    readonly property real halfWidth: Math.max(0, item.width / 2 - horizontalInset)
    readonly property real halfHeight: Math.max(0, item.height / 2 - verticalInset)

    // sliceCount * spansPerRow entries, null where the row has fewer spans than
    // slots. Rebuilt only when the card's geometry or outline changes.
    readonly property var bands: {
        const outline = root.outline
        const rows = Math.max(1, root.sliceCount)
        const halfWidth = root.halfWidth
        const halfHeight = root.halfHeight
        const result = []
        if (!root.active || halfWidth <= 0 || halfHeight <= 0)
            return result
        const centerX = root.item.x + root.item.width / 2
        const centerY = root.item.y + root.item.height / 2
        const rowHeight = halfHeight * 2 / rows
        for (let row = 0; row < rows; ++row) {
            const offset = -halfHeight + (row + 0.5) * rowHeight
            const spans = Geometry.spansAt(outline, offset, halfWidth, halfHeight)
            for (let slot = 0; slot < root.spansPerRow; ++slot) {
                const span = spans[slot]
                result.push(span ? {
                    x: centerX + span.left,
                    y: centerY + offset - rowHeight / 2,
                    width: span.right - span.left,
                    height: rowHeight
                } : null)
            }
        }
        return result
    }

    // One field of one slot, rounded to the integers a region wants. Missing
    // slots answer 0, which is what collapses them: a zero-size rectangle
    // contributes nothing to the union.
    function slot(index, field) {
        const entry = root.bands[index]
        return entry ? Math.round(entry[field]) : 0
    }

    Region { x: root.slot(0, "x"); y: root.slot(0, "y"); width: root.slot(0, "width"); height: root.slot(0, "height") }
    Region { x: root.slot(1, "x"); y: root.slot(1, "y"); width: root.slot(1, "width"); height: root.slot(1, "height") }
    Region { x: root.slot(2, "x"); y: root.slot(2, "y"); width: root.slot(2, "width"); height: root.slot(2, "height") }
    Region { x: root.slot(3, "x"); y: root.slot(3, "y"); width: root.slot(3, "width"); height: root.slot(3, "height") }
    Region { x: root.slot(4, "x"); y: root.slot(4, "y"); width: root.slot(4, "width"); height: root.slot(4, "height") }
    Region { x: root.slot(5, "x"); y: root.slot(5, "y"); width: root.slot(5, "width"); height: root.slot(5, "height") }
    Region { x: root.slot(6, "x"); y: root.slot(6, "y"); width: root.slot(6, "width"); height: root.slot(6, "height") }
    Region { x: root.slot(7, "x"); y: root.slot(7, "y"); width: root.slot(7, "width"); height: root.slot(7, "height") }
    Region { x: root.slot(8, "x"); y: root.slot(8, "y"); width: root.slot(8, "width"); height: root.slot(8, "height") }
    Region { x: root.slot(9, "x"); y: root.slot(9, "y"); width: root.slot(9, "width"); height: root.slot(9, "height") }
    Region { x: root.slot(10, "x"); y: root.slot(10, "y"); width: root.slot(10, "width"); height: root.slot(10, "height") }
    Region { x: root.slot(11, "x"); y: root.slot(11, "y"); width: root.slot(11, "width"); height: root.slot(11, "height") }
    Region { x: root.slot(12, "x"); y: root.slot(12, "y"); width: root.slot(12, "width"); height: root.slot(12, "height") }
    Region { x: root.slot(13, "x"); y: root.slot(13, "y"); width: root.slot(13, "width"); height: root.slot(13, "height") }
    Region { x: root.slot(14, "x"); y: root.slot(14, "y"); width: root.slot(14, "width"); height: root.slot(14, "height") }
    Region { x: root.slot(15, "x"); y: root.slot(15, "y"); width: root.slot(15, "width"); height: root.slot(15, "height") }
    Region { x: root.slot(16, "x"); y: root.slot(16, "y"); width: root.slot(16, "width"); height: root.slot(16, "height") }
    Region { x: root.slot(17, "x"); y: root.slot(17, "y"); width: root.slot(17, "width"); height: root.slot(17, "height") }
    Region { x: root.slot(18, "x"); y: root.slot(18, "y"); width: root.slot(18, "width"); height: root.slot(18, "height") }
    Region { x: root.slot(19, "x"); y: root.slot(19, "y"); width: root.slot(19, "width"); height: root.slot(19, "height") }
    Region { x: root.slot(20, "x"); y: root.slot(20, "y"); width: root.slot(20, "width"); height: root.slot(20, "height") }
    Region { x: root.slot(21, "x"); y: root.slot(21, "y"); width: root.slot(21, "width"); height: root.slot(21, "height") }
    Region { x: root.slot(22, "x"); y: root.slot(22, "y"); width: root.slot(22, "width"); height: root.slot(22, "height") }
    Region { x: root.slot(23, "x"); y: root.slot(23, "y"); width: root.slot(23, "width"); height: root.slot(23, "height") }
    Region { x: root.slot(24, "x"); y: root.slot(24, "y"); width: root.slot(24, "width"); height: root.slot(24, "height") }
    Region { x: root.slot(25, "x"); y: root.slot(25, "y"); width: root.slot(25, "width"); height: root.slot(25, "height") }
    Region { x: root.slot(26, "x"); y: root.slot(26, "y"); width: root.slot(26, "width"); height: root.slot(26, "height") }
    Region { x: root.slot(27, "x"); y: root.slot(27, "y"); width: root.slot(27, "width"); height: root.slot(27, "height") }
    Region { x: root.slot(28, "x"); y: root.slot(28, "y"); width: root.slot(28, "width"); height: root.slot(28, "height") }
    Region { x: root.slot(29, "x"); y: root.slot(29, "y"); width: root.slot(29, "width"); height: root.slot(29, "height") }
    Region { x: root.slot(30, "x"); y: root.slot(30, "y"); width: root.slot(30, "width"); height: root.slot(30, "height") }
    Region { x: root.slot(31, "x"); y: root.slot(31, "y"); width: root.slot(31, "width"); height: root.slot(31, "height") }
    Region { x: root.slot(32, "x"); y: root.slot(32, "y"); width: root.slot(32, "width"); height: root.slot(32, "height") }
    Region { x: root.slot(33, "x"); y: root.slot(33, "y"); width: root.slot(33, "width"); height: root.slot(33, "height") }
    Region { x: root.slot(34, "x"); y: root.slot(34, "y"); width: root.slot(34, "width"); height: root.slot(34, "height") }
    Region { x: root.slot(35, "x"); y: root.slot(35, "y"); width: root.slot(35, "width"); height: root.slot(35, "height") }
    Region { x: root.slot(36, "x"); y: root.slot(36, "y"); width: root.slot(36, "width"); height: root.slot(36, "height") }
    Region { x: root.slot(37, "x"); y: root.slot(37, "y"); width: root.slot(37, "width"); height: root.slot(37, "height") }
    Region { x: root.slot(38, "x"); y: root.slot(38, "y"); width: root.slot(38, "width"); height: root.slot(38, "height") }
    Region { x: root.slot(39, "x"); y: root.slot(39, "y"); width: root.slot(39, "width"); height: root.slot(39, "height") }
    Region { x: root.slot(40, "x"); y: root.slot(40, "y"); width: root.slot(40, "width"); height: root.slot(40, "height") }
    Region { x: root.slot(41, "x"); y: root.slot(41, "y"); width: root.slot(41, "width"); height: root.slot(41, "height") }
    Region { x: root.slot(42, "x"); y: root.slot(42, "y"); width: root.slot(42, "width"); height: root.slot(42, "height") }
    Region { x: root.slot(43, "x"); y: root.slot(43, "y"); width: root.slot(43, "width"); height: root.slot(43, "height") }
    Region { x: root.slot(44, "x"); y: root.slot(44, "y"); width: root.slot(44, "width"); height: root.slot(44, "height") }
    Region { x: root.slot(45, "x"); y: root.slot(45, "y"); width: root.slot(45, "width"); height: root.slot(45, "height") }
    Region { x: root.slot(46, "x"); y: root.slot(46, "y"); width: root.slot(46, "width"); height: root.slot(46, "height") }
    Region { x: root.slot(47, "x"); y: root.slot(47, "y"); width: root.slot(47, "width"); height: root.slot(47, "height") }
    Region { x: root.slot(48, "x"); y: root.slot(48, "y"); width: root.slot(48, "width"); height: root.slot(48, "height") }
    Region { x: root.slot(49, "x"); y: root.slot(49, "y"); width: root.slot(49, "width"); height: root.slot(49, "height") }
    Region { x: root.slot(50, "x"); y: root.slot(50, "y"); width: root.slot(50, "width"); height: root.slot(50, "height") }
    Region { x: root.slot(51, "x"); y: root.slot(51, "y"); width: root.slot(51, "width"); height: root.slot(51, "height") }
    Region { x: root.slot(52, "x"); y: root.slot(52, "y"); width: root.slot(52, "width"); height: root.slot(52, "height") }
    Region { x: root.slot(53, "x"); y: root.slot(53, "y"); width: root.slot(53, "width"); height: root.slot(53, "height") }
    Region { x: root.slot(54, "x"); y: root.slot(54, "y"); width: root.slot(54, "width"); height: root.slot(54, "height") }
    Region { x: root.slot(55, "x"); y: root.slot(55, "y"); width: root.slot(55, "width"); height: root.slot(55, "height") }
    Region { x: root.slot(56, "x"); y: root.slot(56, "y"); width: root.slot(56, "width"); height: root.slot(56, "height") }
    Region { x: root.slot(57, "x"); y: root.slot(57, "y"); width: root.slot(57, "width"); height: root.slot(57, "height") }
    Region { x: root.slot(58, "x"); y: root.slot(58, "y"); width: root.slot(58, "width"); height: root.slot(58, "height") }
    Region { x: root.slot(59, "x"); y: root.slot(59, "y"); width: root.slot(59, "width"); height: root.slot(59, "height") }
    Region { x: root.slot(60, "x"); y: root.slot(60, "y"); width: root.slot(60, "width"); height: root.slot(60, "height") }
    Region { x: root.slot(61, "x"); y: root.slot(61, "y"); width: root.slot(61, "width"); height: root.slot(61, "height") }
    Region { x: root.slot(62, "x"); y: root.slot(62, "y"); width: root.slot(62, "width"); height: root.slot(62, "height") }
    Region { x: root.slot(63, "x"); y: root.slot(63, "y"); width: root.slot(63, "width"); height: root.slot(63, "height") }
    Region { x: root.slot(64, "x"); y: root.slot(64, "y"); width: root.slot(64, "width"); height: root.slot(64, "height") }
    Region { x: root.slot(65, "x"); y: root.slot(65, "y"); width: root.slot(65, "width"); height: root.slot(65, "height") }
    Region { x: root.slot(66, "x"); y: root.slot(66, "y"); width: root.slot(66, "width"); height: root.slot(66, "height") }
    Region { x: root.slot(67, "x"); y: root.slot(67, "y"); width: root.slot(67, "width"); height: root.slot(67, "height") }
    Region { x: root.slot(68, "x"); y: root.slot(68, "y"); width: root.slot(68, "width"); height: root.slot(68, "height") }
    Region { x: root.slot(69, "x"); y: root.slot(69, "y"); width: root.slot(69, "width"); height: root.slot(69, "height") }
    Region { x: root.slot(70, "x"); y: root.slot(70, "y"); width: root.slot(70, "width"); height: root.slot(70, "height") }
    Region { x: root.slot(71, "x"); y: root.slot(71, "y"); width: root.slot(71, "width"); height: root.slot(71, "height") }
    Region { x: root.slot(72, "x"); y: root.slot(72, "y"); width: root.slot(72, "width"); height: root.slot(72, "height") }
    Region { x: root.slot(73, "x"); y: root.slot(73, "y"); width: root.slot(73, "width"); height: root.slot(73, "height") }
    Region { x: root.slot(74, "x"); y: root.slot(74, "y"); width: root.slot(74, "width"); height: root.slot(74, "height") }
    Region { x: root.slot(75, "x"); y: root.slot(75, "y"); width: root.slot(75, "width"); height: root.slot(75, "height") }
    Region { x: root.slot(76, "x"); y: root.slot(76, "y"); width: root.slot(76, "width"); height: root.slot(76, "height") }
    Region { x: root.slot(77, "x"); y: root.slot(77, "y"); width: root.slot(77, "width"); height: root.slot(77, "height") }
    Region { x: root.slot(78, "x"); y: root.slot(78, "y"); width: root.slot(78, "width"); height: root.slot(78, "height") }
    Region { x: root.slot(79, "x"); y: root.slot(79, "y"); width: root.slot(79, "width"); height: root.slot(79, "height") }
    Region { x: root.slot(80, "x"); y: root.slot(80, "y"); width: root.slot(80, "width"); height: root.slot(80, "height") }
    Region { x: root.slot(81, "x"); y: root.slot(81, "y"); width: root.slot(81, "width"); height: root.slot(81, "height") }
    Region { x: root.slot(82, "x"); y: root.slot(82, "y"); width: root.slot(82, "width"); height: root.slot(82, "height") }
    Region { x: root.slot(83, "x"); y: root.slot(83, "y"); width: root.slot(83, "width"); height: root.slot(83, "height") }
    Region { x: root.slot(84, "x"); y: root.slot(84, "y"); width: root.slot(84, "width"); height: root.slot(84, "height") }
    Region { x: root.slot(85, "x"); y: root.slot(85, "y"); width: root.slot(85, "width"); height: root.slot(85, "height") }
    Region { x: root.slot(86, "x"); y: root.slot(86, "y"); width: root.slot(86, "width"); height: root.slot(86, "height") }
    Region { x: root.slot(87, "x"); y: root.slot(87, "y"); width: root.slot(87, "width"); height: root.slot(87, "height") }
    Region { x: root.slot(88, "x"); y: root.slot(88, "y"); width: root.slot(88, "width"); height: root.slot(88, "height") }
    Region { x: root.slot(89, "x"); y: root.slot(89, "y"); width: root.slot(89, "width"); height: root.slot(89, "height") }
    Region { x: root.slot(90, "x"); y: root.slot(90, "y"); width: root.slot(90, "width"); height: root.slot(90, "height") }
    Region { x: root.slot(91, "x"); y: root.slot(91, "y"); width: root.slot(91, "width"); height: root.slot(91, "height") }
    Region { x: root.slot(92, "x"); y: root.slot(92, "y"); width: root.slot(92, "width"); height: root.slot(92, "height") }
    Region { x: root.slot(93, "x"); y: root.slot(93, "y"); width: root.slot(93, "width"); height: root.slot(93, "height") }
    Region { x: root.slot(94, "x"); y: root.slot(94, "y"); width: root.slot(94, "width"); height: root.slot(94, "height") }
    Region { x: root.slot(95, "x"); y: root.slot(95, "y"); width: root.slot(95, "width"); height: root.slot(95, "height") }
}
