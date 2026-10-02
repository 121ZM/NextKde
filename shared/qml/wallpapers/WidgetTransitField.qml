import QtQuick

// One deterministic Kepler orbit shared by the two shell surfaces. Sprite
// positions update on the shared clock; no Canvas, blur or simulation copies.
Item {
    id: root
    property string themeId: "starfield"
    property real phase: 0
    property bool foreground: false
    property bool economical: false
    property var widgetRects: []
    readonly property var bounds: {
        if (!widgetRects.length) return null
        let left = width, top = height, right = 0, bottom = 0
        for (const r of widgetRects) {
            left = Math.min(left, r.x); top = Math.min(top, r.y)
            right = Math.max(right, r.x + r.width); bottom = Math.max(bottom, r.y + r.height)
        }
        return {x: (left + right) / 2, y: (top + bottom) / 2,
            a: Math.max(120, (right - left) * 0.65), b: Math.max(90, (bottom - top) * 0.52)}
    }
    function orbit(time) {
        if (!bounds) return {x: 0, y: 0, near: false}
        // E - e sin(E) = mean anomaly: exact two-body elliptic motion.
        const eccentricity = 0.36
        const mean = ((time * 0.68) % (Math.PI * 2) + Math.PI * 2) % (Math.PI * 2)
        let e = mean
        for (let i = 0; i < 5; ++i) e -= (e - eccentricity * Math.sin(e) - mean) / (1 - eccentricity * Math.cos(e))
        return {x: bounds.x + bounds.a * (Math.cos(e) - eccentricity * 0.3),
            y: bounds.y + bounds.b * Math.sin(e), near: Math.sin(e) >= 0}
    }
    Repeater {
        model: root.visible && root.bounds ? (root.economical ? 24 : 40) : 0
        Image {
            required property int index
            readonly property var point: root.orbit(root.phase - index * 0.042)
            visible: point.near === root.foreground
            x: point.x - width / 2
            y: point.y - height / 2
            width: index === 0 ? 52 : 30
            height: width
            opacity: Math.pow(1 - index / (root.economical ? 24 : 40), 1.6)
            source: "assets/transit-glow.svg"
            sourceSize: Qt.size(64, 64)
            smooth: true
        }
    }
}
