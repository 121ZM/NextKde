import QtQuick
import QtQuick.Shapes
import "MaterialShape.mjs" as Geometry

// The Material form's shape painter.
//
// Draws one of the outlines in MaterialShape.mjs into whatever box the caller
// gives it. The shape fills the box on both axes -- x is scaled by half the
// width and y by half the height -- so a wide card gets a wide flower rather
// than a round one with empty margins. That is the same mapping the geometry
// module documents on its own output, and the same one MaterialShapeBlurRegion
// uses for the compositor's frost, so the painted edge and the frosted edge are
// the same curve by construction.
//
// CurveRenderer, not the GPU geometry renderer: these outlines are concave
// (petals, spikes, notches) and the CPU curve rasteriser has no triangulation
// to get wrong. There are a handful of them per window, so the cost is not
// worth trading correctness for.
Item {
    id: root

    // Any name in MaterialShape.mjs's library. Unknown names draw a circle.
    property string shape: "circle"
    // How much of the shape survives: 1 is the untouched outline, lower values
    // fill its notches in towards the bounding box (see blendToBox in the
    // geometry module). A card carrying content lowers it until the notches
    // clear the content; a decorative surface leaves it at 1.
    property real strength: 1
    property color fillColor: "transparent"
    property color outlineColor: "transparent"
    property real outlineWidth: 1
    // Inset from the item's own box, so a host can leave a margin without
    // resizing the item. Both consumers of an outline must be given the same
    // insets, or the frost edge lands off the painted one.
    property real horizontalInset: 0
    property real verticalInset: 0

    readonly property real halfWidth: Math.max(0, width / 2 - horizontalInset)
    readonly property real halfHeight: Math.max(0, height / 2 - verticalInset)
    readonly property var outline: Geometry.shapeOutline(shape, strength)

    // The outline in this item's coordinates. A function rather than a bound
    // property: PathPolyline wants a point list, and Qt.point() is only
    // available inside a QML scope.
    function pathPoints() {
        const points = root.outline
        const result = []
        const centerX = root.width / 2
        const centerY = root.height / 2
        for (let i = 0; i < points.length; ++i)
            result.push(Qt.point(centerX + points[i].x * root.halfWidth,
                centerY + points[i].y * root.halfHeight))
        return result
    }

    Shape {
        anchors.fill: parent
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: root.fillColor
            strokeColor: root.outlineColor
            strokeWidth: root.outlineColor.a > 0 ? root.outlineWidth : 0
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root.pathPoints() }
        }
    }
}
