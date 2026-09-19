// Shape geometry for the Material form -- one outline, several consumers.
//
// The definitions are ports of the ones AndroidX ships as
// `MaterialShapes` (androidx.compose.material3.MaterialShapes, built on
// androidx.graphics.shapes RoundedPolygon / star / customPolygon). Keeping the
// reference's numbers is the point: a shape library is a set of *proportions*,
// and re-inventing "a flower-ish blob" produces something that reads as an
// accident next to the real thing.
//
// Three deliberate differences from the reference:
//
//   * No bezier path is produced. Every shape comes back as a sampled polygon,
//     because the shell has two consumers with incompatible needs: QML's
//     ShapePath wants points it can fill and stroke, and the compositor blur
//     region is a scanline fill over the same outline (Wayland regions are
//     rectangles, so the outline has to be walked row by row). One geometry,
//     two consumers, no chance of the frosted edge drifting off the painted
//     one.
//   * Corners are sampled from a quadratic bezier through the vertex instead of
//     the reference's cubic. `rounding` keeps its meaning -- 0 is a sharp
//     corner, 0.5 the rounded-variant of a polygon, 1 consumes the whole edge
//     -- but the ramp differs by a couple of percent. The `smoothing` second
//     argument of the reference's CornerRounding is therefore not carried: a
//     quadratic already has one shape of corner and no free parameter.
//   * Shapes are normalised into [-1, 1] on BOTH axes rather than into a unit
//     box the consumer stretches. Consumers scale x by half the width and y by
//     half the height, which is exactly what the reference's toShape() does
//     with its scale(x = size.width, y = size.height) matrix -- a wide card
//     gets an elliptical flower rather than a flower with empty margins.
//
// Deterministic: same name, same samples, same points, every process.

const RADIANS = Math.PI / 180

// Sampled points per rounded corner. Ten is already past what the eye can
// resolve on a 300px card, and the whole point of this module is that the
// compositor's scanline fill reads the same numbers.
export const CORNER_SAMPLES = 10

function vertex(x, y, radius) {
    return { x: x, y: y, radius: radius === undefined ? 0 : radius }
}

function angleDegrees(x, y) {
    return Math.atan2(y, x) / RADIANS
}

function rotateDegrees(point, degrees, center) {
    const a = degrees * RADIANS
    const dx = point.x - center.x
    const dy = point.y - center.y
    return vertex(center.x + dx * Math.cos(a) - dy * Math.sin(a),
        center.y + dx * Math.sin(a) + dy * Math.cos(a), point.radius)
}

function scaleY(points, factor) {
    return points.map(function (p) {
        return vertex(p.x, p.y * factor, p.radius)
    })
}

// Port of the reference's private doRepeat(). With `mirroring` each half-turn
// repeats the point list back to front and reflects the angles about the
// section's axis, which is how the reference gets a symmetric leaf out of one
// hand-written quarter of it. The `i > 0 || it % 2 === 0` guard drops the
// duplicated point where the mirrored copy meets the original.
function repeat(points, reps, mirroring, center) {
    const out = []
    if (mirroring) {
        const angles = points.map(function (p) {
            return angleDegrees(p.x - center.x, p.y - center.y)
        })
        const distances = points.map(function (p) {
            return Math.hypot(p.x - center.x, p.y - center.y)
        })
        const actualReps = reps * 2
        const sectionAngle = 360 / actualReps
        for (let it = 0; it < actualReps; ++it) {
            const mirrored = it % 2 === 1
            for (let index = 0; index < points.length; ++index) {
                const i = mirrored ? points.length - 1 - index : index
                if (i > 0 || !mirrored) {
                    const angle = (sectionAngle * it + (mirrored
                        ? sectionAngle - angles[i] + 2 * angles[0]
                        : angles[i])) * RADIANS
                    out.push(vertex(center.x + Math.cos(angle) * distances[i],
                        center.y + Math.sin(angle) * distances[i],
                        points[i].radius))
                }
            }
        }
        return out
    }
    const count = points.length
    for (let it = 0; it < count * reps; ++it) {
        const source = points[it % count]
        out.push(rotateDegrees(source, Math.floor(it / count) * 360 / reps,
            center))
    }
    return out
}

// A regular polygon inscribed in the unit circle. The default first vertex is
// at twelve o'clock, which is the orientation the reference's star() and most
// of its custom shapes use; `startAngle` is for the ones the reference rotates
// into place (its rectangle() puts four vertices on the diagonals, not on the
// axes).
function polygon(count, rounding, radius, startAngle) {
    const points = []
    const r = radius === undefined ? 1 : radius
    const offset = startAngle === undefined ? -90 : startAngle
    for (let i = 0; i < count; ++i) {
        const angle = (offset + i * 360 / count) * RADIANS
        points.push(vertex(0.5 + Math.cos(angle) * r, 0.5 + Math.sin(angle) * r,
            rounding))
    }
    return points
}

// RoundedPolygon.star(): alternating outer and inner vertices, outer first.
function star(verticesPerRadius, innerRadius, rounding) {
    const points = []
    for (let i = 0; i < verticesPerRadius * 2; ++i) {
        const radius = i % 2 === 0 ? 1 : innerRadius
        const angle = (-90 + i * 180 / verticesPerRadius) * RADIANS
        points.push(vertex(0.5 + Math.cos(angle) * radius,
            0.5 + Math.sin(angle) * radius, rounding))
    }
    return points
}

const CENTER = { x: 0.5, y: 0.5 }

// The reference's `customPolygon(points, reps, mirroring)`.
function custom(points, reps, mirroring) {
    return repeat(points, reps, mirroring === undefined ? false : mirroring,
        CENTER)
}

// ────────────────────────────────────────────────────────────────────────
// The shape library. Every entry below is `name(reference factory)`; numbers
// are the reference's own, so a shape can be diffed against MaterialShapes.kt
// by eye. Descriptions say where the shape wants to be used, not what it looks
// like -- the shapes are recognisable, the roles are the decision.
// ────────────────────────────────────────────────────────────────────────

const DEFINITIONS = {
    // circle(10) with a full-length corner: the plainest shape there is.
    circle: function () { return polygon(10, 1) },
    // square(): rectangle(1, 1, cornerRound30) -- vertices on the diagonals, so
    // the flats face the axes.
    square: function () { return polygon(4, 0.30, Math.SQRT1_2, -45) },
    // slanted(): a 2-vertex shape repeated twice -- a leaning capsule.
    slanted: function () {
        return custom([vertex(0.926, 0.970, 0.189), vertex(-0.021, 0.967, 0.187)],
            2)
    },
    // pill(): three points repeated to both ends.
    pill: function () {
        return custom([vertex(0.961, 0.039, 0.426), vertex(1.001, 0.428, 0),
            vertex(1.000, 0.609, 1.000)], 2, true)
    },
    // triangle(): an upward triangle with a fifth of each edge consumed.
    triangle: function () { return polygon(3, 0.20) },
    // diamond(): its points come from the reference's own hand-tuned four.
    diamond: function () {
        return custom([vertex(0.500, 1.096, 0.151), vertex(0.040, 0.500, 0.159)],
            2)
    },
    // pentagon()
    pentagon: function () {
        return custom([vertex(0.500, -0.009, 0.172), vertex(1.030, 0.365, 0.164),
            vertex(0.828, 0.970, 0.169)], 1, true)
    },
    // gem(): the cut-stone outline.
    gem: function () {
        return custom([vertex(0.499, 1.023, 0.241), vertex(-0.005, 0.792, 0.208),
            vertex(0.073, 0.258, 0.228), vertex(0.433, 0.000, 0.491)], 1, true)
    },
    // clamShell(): a half-oval with a flat top, used for dialogs.
    clamShell: function () {
        return custom([vertex(0.171, 0.841, 0.159), vertex(-0.020, 0.500, 0.140),
            vertex(0.170, 0.159, 0.159)], 2)
    },
    // ghostish(): a rounded body with two feet -- the reference's odd one out.
    ghostish: function () {
        return custom([vertex(0.500, 0.000, 1.000), vertex(1.000, 0.000, 1.000),
            vertex(1.000, 1.140, 0.254), vertex(0.575, 0.906, 0.253)], 1, true)
    },
    // sunny(): star(8, 0.8, cornerRound15) -- eight soft rays, Android's own
    // "sunny" tile.
    sunny: function () { return star(8, 0.8, 0.15) },
    // verySunny(): eight longer, narrower rays.
    verySunny: function () {
        return custom([vertex(0.500, 1.080, 0.085), vertex(0.358, 0.843, 0.085)],
            8)
    },
    // cookie4(): a rounded square whose sides dip slightly inwards.
    cookie4: function () {
        return custom([vertex(1.237, 1.236, 0.258), vertex(0.500, 0.918, 0.233)],
            4)
    },
    // cookie6()
    cookie6: function () {
        return custom([vertex(0.723, 0.884, 0.394), vertex(0.500, 1.099, 0.398)],
            6)
    },
    // cookie7(): star(7, .75, cornerRound50)
    cookie7: function () { return star(7, 0.75, 0.5) },
    // cookie9(): star(9, .8, cornerRound50) -- Android's softest tile, almost a
    // circle but with nine readable flats.
    cookie9: function () { return star(9, 0.8, 0.5) },
    // cookie12(): star(12, .8, cornerRound50) -- the pill's round cousin.
    cookie12: function () { return star(12, 0.8, 0.5) },
    // clover4(): four rounded leaves, the reference's Instagram-ish blob.
    clover4: function () {
        return custom([vertex(0.500, 0.074, 0), vertex(0.725, -0.099, 0.476)],
            4, true)
    },
    // clover8()
    clover8: function () {
        return custom([vertex(0.500, 0.036, 0), vertex(0.758, -0.101, 0.209)],
            8)
    },
    // flower(): eight petals with a notch between each pair.
    flower: function () {
        return custom([vertex(0.370, 0.187, 0), vertex(0.416, 0.049, 0.381),
            vertex(0.479, 0.001, 0.095)], 8, true)
    },
    // burst(): twelve sharp spikes.
    burst: function () {
        return custom([vertex(0.500, -0.006, 0.006), vertex(0.592, 0.158, 0.006)],
            12)
    },
    // softBurst(): ten short, blunt spikes.
    softBurst: function () {
        return custom([vertex(0.193, 0.277, 0.053), vertex(0.176, 0.055, 0.053)],
            10)
    },
    // boom(): fifteen very sharp spikes.
    boom: function () {
        return custom([vertex(0.457, 0.296, 0.007), vertex(0.500, -0.051, 0.007)],
            15)
    },
    // softBoom(): sixteen overlapping fins, the reference's scalloped disc.
    softBoom: function () {
        return custom([vertex(0.733, 0.454, 0), vertex(0.839, 0.437, 0.532),
            vertex(0.949, 0.449, 0.439), vertex(0.998, 0.478, 0.174)], 16, true)
    },
    // puffy(): an irregular rounded blob -- deliberately not symmetric-looking.
    puffy: function () {
        return scaleY(custom([vertex(0.500, 0.053, 0), vertex(0.545, -0.040, 0.405),
            vertex(0.670, -0.035, 0.426), vertex(0.717, 0.066, 0.574),
            vertex(0.722, 0.128, 0), vertex(0.777, 0.002, 0.360),
            vertex(0.914, 0.149, 0.660), vertex(0.926, 0.289, 0.660),
            vertex(0.881, 0.346, 0), vertex(0.940, 0.344, 0.126),
            vertex(1.003, 0.437, 0.255)], 2, true), 0.742)
    },
    // puffyDiamond(): four puffy points on the diagonals.
    puffyDiamond: function () {
        return custom([vertex(0.870, 0.130, 0.146), vertex(0.818, 0.357, 0),
            vertex(1.000, 0.332, 0.853)], 4, true)
    },
    // pixelCircle(): a circle stepped in eight-pixel increments.
    pixelCircle: function () {
        return custom([vertex(0.500, 0.000, 0), vertex(0.704, 0.000, 0),
            vertex(0.704, 0.065, 0), vertex(0.843, 0.065, 0),
            vertex(0.843, 0.148, 0), vertex(0.926, 0.148, 0),
            vertex(0.926, 0.296, 0), vertex(1.000, 0.296, 0)], 2, true)
    }
}

// Scale- and centre-normalise: the shape's bounding box becomes [-1, 1] on its
// long axis and stays centred on the short one. Consumers then multiply x by
// half the target width and y by half the target height.
function normalize(points) {
    let minX = Infinity
    let maxX = -Infinity
    let minY = Infinity
    let maxY = -Infinity
    for (let i = 0; i < points.length; ++i) {
        const p = points[i]
        if (p.x < minX) minX = p.x
        if (p.x > maxX) maxX = p.x
        if (p.y < minY) minY = p.y
        if (p.y > maxY) maxY = p.y
    }
    const width = maxX - minX
    const height = maxY - minY
    if (!(width > 0) || !(height > 0))
        return []
    const scale = 2 / Math.max(width, height)
    const centerX = (minX + maxX) / 2
    const centerY = (minY + maxY) / 2
    return points.map(function (p) {
        return { x: (p.x - centerX) * scale, y: (p.y - centerY) * scale }
    })
}

// Turn a vertex list (every vertex carrying its own corner rounding) into the
// outline a fill or a scanline can use: straight edges stay single segments,
// each rounded corner becomes CORNER_SAMPLES points along the quadratic through
// the vertex. The corner's tangent length is `rounding * half the shorter
// adjacent edge`, so rounding 1 leaves no straight edge at all -- adjacent
// corners meet in the middle, which is how the reference turns a square into a
// circle.
function roundCorners(points) {
    const out = []
    const count = points.length
    for (let i = 0; i < count; ++i) {
        const previous = points[(i - 1 + count) % count]
        const current = points[i]
        const next = points[(i + 1) % count]
        const inLength = Math.hypot(current.x - previous.x, current.y - previous.y)
        const outLength = Math.hypot(next.x - current.x, next.y - current.y)
        const rounding = Math.max(0, Math.min(1, current.radius || 0))
        const cut = Math.min(inLength, outLength) * 0.5 * rounding
        if (!(cut > 1e-9) || !(inLength > 0) || !(outLength > 0)) {
            out.push({ x: current.x, y: current.y })
            continue
        }
        const startX = current.x + (previous.x - current.x) * (cut / inLength)
        const startY = current.y + (previous.y - current.y) * (cut / inLength)
        const endX = current.x + (next.x - current.x) * (cut / outLength)
        const endY = current.y + (next.y - current.y) * (cut / outLength)
        for (let s = 0; s <= CORNER_SAMPLES; ++s) {
            const t = s / CORNER_SAMPLES
            const w = 1 - t
            out.push({
                x: w * w * startX + 2 * w * t * current.x + t * t * endX,
                y: w * w * startY + 2 * w * t * current.y + t * t * endY
            })
        }
    }
    return out
}

const cache = new Map()

// Every shape the Material form can draw, in the reference's own names.
export const SHAPE_NAMES = Object.keys(DEFINITIONS)

export function hasShape(name) {
    return Object.prototype.hasOwnProperty.call(DEFINITIONS, name)
}

// The outline, normalised into [-1, 1], as a closed point list (the last point
// is not repeated). Unknown names fall back to a circle rather than throwing:
// this runs inside QML property bindings, where a throw blanks the surface.
// `strength` defaults to the untouched shape; see blendToBox below.
export function shapeOutline(name, strength) {
    const blend = strength === undefined ? 1
        : Math.max(0, Math.min(1, strength))
    const key = name + "@" + blend
    const cached = cache.get(key)
    if (cached)
        return cached
    const definition = hasShape(name) ? DEFINITIONS[name] : DEFINITIONS.circle
    const outline = blendToBox(normalize(roundCorners(definition())), blend)
    cache.set(key, outline)
    return outline
}

// `shapeOutline(name, strength)` blends an outline towards its bounding box:
// every point moves outward along its own ray until, at strength 0, the outline
// IS the box. A point already on the box does not move at all, so blending never
// grows the shape -- it fills its notches in, from the deepest one inward.
//
// That is the knob a content-carrying card needs. This shell's widgets lay
// themselves out in pixels (fixed paddings, fixed type sizes, fixed row
// heights), so handing one a smaller box does not make it fit -- it makes it
// overflow its own card. The outline's depth is what can give instead: the
// silhouette survives, the notch stops short of the content, and 1 is the
// untouched shape.
function blendToBox(points, strength) {
    if (strength >= 1)
        return points.map(function (p) { return { x: p.x, y: p.y } })
    const blend = Math.max(0, strength)
    return points.map(function (p) {
        const extent = Math.max(Math.abs(p.x), Math.abs(p.y))
        if (!(extent > 0))
            return { x: p.x, y: p.y }
        const factor = 1 + (1 / extent - 1) * (1 - blend)
        return { x: p.x * factor, y: p.y * factor }
    })
}

// Horizontal crossing pairs of `outline` on the scanline at `offset`, for the
// compositor region builders: Wayland regions are rectangles, so an outline is
// published as one span per row. `halfWidth` / `halfHeight` are the same
// scaling factors the painter uses, so the two agree by construction.
export function spansAt(outline, offset, halfWidth, halfHeight) {
    const crossings = []
    for (let i = 0; i < outline.length; ++i) {
        const a = outline[i]
        const b = outline[(i + 1) % outline.length]
        const ay = a.y * halfHeight
        const by = b.y * halfHeight
        if ((ay <= offset) !== (by <= offset)) {
            const t = (offset - ay) / (by - ay)
            crossings.push((a.x + t * (b.x - a.x)) * halfWidth)
        }
    }
    crossings.sort(function (left, right) { return left - right })
    const spans = []
    for (let i = 0; i + 1 < crossings.length; i += 2)
        spans.push({ left: crossings[i], right: crossings[i + 1] })
    return spans
}

// The shapes a *card* may wear: expressive enough to be worth having, and
// roomy enough to hold content in the middle. Two constraints, both measured
// rather than felt -- fitsRegion() for the compositor's slot budget, and
// inscribedRect() for the content:
//
//   * a card publishes its frost through MaterialShapeBlurRegion, whose rows
//     carry four spans each;
//   * a card draws text and dials in the middle, so the outline has to leave a
//     usable centred rectangle: at least 45% of the box on both axes.
//
// The spikier library members (burst, boom, softBoom) and the pointiest of the
// plain ones (triangle, diamond -- 28% and 40% of the width) satisfy neither,
// and staying out of this list is what keeps them from being handed to a widget
// by accident. test_material_shape.mjs asserts both numbers for every entry.
export const CARD_SHAPES = [
    "circle", "square", "pill", "pentagon", "gem", "clamShell", "sunny",
    "verySunny", "cookie4", "cookie6", "cookie7", "cookie9", "cookie12",
    "clover4", "clover8", "flower", "puffy", "puffyDiamond", "softBurst",
    "pixelCircle", "ghostish", "slanted"
]

// Which widget wears which outline, and how much of it.
//
// Material is the only form that answers this table (the others keep their
// rounded rectangles), and it is here rather than in the tokens so that it can
// be *measured*: test_material_shape.mjs walks every entry, blends the shape to
// its strength, and checks what the card's content actually gets. A shape and a
// depth that leave too little room fail the suite instead of emptying a widget.
//
// `strength` is the honest trade of this design. A widget's content is laid out
// in pixels and cannot be shrunk, so what gives way is the outline: 1.0 keeps
// the full silhouette, and lower values fill its notches in until they clear the
// content. `default` answers for any widget the shell grows later.
export const CARD_OUTLINES = {
    clock: { shape: "flower", strength: 1.0 },
    weather: { shape: "cookie12", strength: 0.35 },
    calendar: { shape: "cookie9", strength: 0.50 },
    todo: { shape: "cookie6", strength: 0.55 },
    system: { shape: "cookie12", strength: 0.60 },
    activity: { shape: "puffy", strength: 0.45 },
    music: { shape: "cookie7", strength: 0.55 },
    default: { shape: "cookie12", strength: 0.60 }
}

// The outline one widget wears. Unknown ids get the default entry rather than
// nothing, so a new card still looks like a Material card.
export function cardOutline(id) {
    return Object.prototype.hasOwnProperty.call(CARD_OUTLINES, id)
        ? CARD_OUTLINES[id] : CARD_OUTLINES.default
}

export function isCardShape(name) {
    return CARD_SHAPES.indexOf(name) >= 0
}

// The largest rectangle centred on the shape's centre that fits inside it, as
// half-extents (1 is the edge of the shape's box). This is the space a card's
// content can be laid out in without spilling past the outline -- the same
// thing a designer would measure with a ruler before putting a label on a
// shaped container.
//
// Accepts a shape name or an outline; names are cached because QML asks for the
// same one every time a card is resized. The returned object is shared, so
// callers read it rather than keeping it.
const inscribedCache = new Map()

export function inscribedRect(shapeOrOutline, rowCount) {
    const rows = rowCount === undefined ? 64 : rowCount
    let outline = shapeOrOutline
    if (typeof shapeOrOutline === "string") {
        const key = shapeOrOutline + "@" + rows
        const cached = inscribedCache.get(key)
        if (cached)
            return cached
        outline = shapeOutline(shapeOrOutline)
    }
    const rect = measureInscribedRect(outline, rows)
    if (typeof shapeOrOutline === "string")
        inscribedCache.set(shapeOrOutline + "@" + rows, rect)
    return rect
}

function measureInscribedRect(outline, rows) {
    const step = 2 / rows
    // Per row: the half-width available symmetrically about the centre.
    const half = []
    for (let row = 0; row < rows; ++row) {
        const offset = -1 + (row + 0.5) * step
        const spans = spansAt(outline, offset, 1, 1)
        let width = 0
        for (const span of spans) {
            if (span.left <= 0 && span.right >= 0)
                width = Math.max(width, Math.min(-span.left, span.right))
        }
        half.push(width)
    }
    const middle = Math.round(rows / 2 - 0.5)
    let narrowest = half[middle] || 0
    let best = { halfWidth: narrowest, halfHeight: step / 2 }
    let area = (narrowest * 2) * step
    for (let steps = 1; steps < rows / 2; ++steps) {
        const below = half[middle - steps]
        const above = half[middle + steps]
        narrowest = Math.min(narrowest, below === undefined ? 0 : below,
            above === undefined ? 0 : above)
        const height = (steps * 2 + 1) * step
        const candidate = (narrowest * 2) * height
        if (candidate > area) {
            area = candidate
            best = { halfWidth: narrowest, halfHeight: height / 2 }
        }
    }
    return best
}


// How many spans one scanline of `name` can produce at this row count.
export function rowSpanCount(name, sliceCount) {
    const rows = sliceCount === undefined ? 24 : sliceCount
    const outline = shapeOutline(name)
    let worst = 1
    for (let row = 0; row < rows; ++row) {
        const offset = -1 + (row + 0.5) * 2 / rows
        const spans = spansAt(outline, offset, 1, 1)
        if (spans.length > worst)
            worst = spans.length
    }
    return worst
}

// Whether a shape can be published through a region component that declares
// `spansPerRow` slots per scanline. A shape that crosses a row more often than
// that would silently lose its outermost spans -- the frost would stop short of
// the painted outline on exactly the rows where the shape is most distinctive.
export function fitsRegion(name, sliceCount, spansPerRow) {
    return rowSpanCount(name, sliceCount) <= spansPerRow
}

// The worst case across the whole library, i.e. the slot count a region
// component would need to publish any shape in it.
export function maxSpansPerRow(sliceCount) {
    const rows = sliceCount === undefined ? 24 : sliceCount
    let worst = 1
    for (const name of SHAPE_NAMES) {
        const count = rowSpanCount(name, rows)
        if (count > worst)
            worst = count
    }
    return worst
}
