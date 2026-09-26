import QtQuick
import QtQuick.Shapes

// Opaque corner wedges cover the pixels outside a rounded tile. This avoids
// an offscreen texture for every thumbnail and works with software rendering.
Item {
    id: corners
    property real cornerRadius: 12
    property color fillColor: "#1c1c1e"

    Repeater {
        model: 4
        delegate: Shape {
            required property int index
            width: corners.cornerRadius
            height: corners.cornerRadius
            x: index % 2 ? corners.width - width : 0
            y: index >= 2 ? corners.height - height : 0
            rotation: [0, 90, 270, 180][index]
            transformOrigin: Item.Center
            ShapePath {
                strokeWidth: 0
                fillColor: corners.fillColor
                startX: 0
                startY: 0
                PathLine { x: corners.cornerRadius; y: 0 }
                PathArc {
                    x: 0
                    y: corners.cornerRadius
                    radiusX: corners.cornerRadius
                    radiusY: corners.cornerRadius
                    direction: PathArc.Counterclockwise
                }
                PathLine { x: 0; y: 0 }
            }
        }
    }
}
