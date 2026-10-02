import QtQuick
import "ParticlePhysics.mjs" as Physics

Item {
    id: root
    property string themeId: "starfield"
    property real phase: 0
    property bool foreground: false
    property bool economical: false
    property bool storm: false
    property var simulation: null
    property real lastPhase: 0
    property int particleCount: 80
    readonly property int count: Math.max(24, Math.min(economical ? 72 : 160, particleCount))

    function reset() {
        simulation = Physics.create(themeId, count)
        // Populate trails even for a static settings thumbnail.
        for (let i = 0; i < 9; ++i) Physics.advance(simulation, 0.04, storm)
        lastPhase = phase
        particles.requestPaint()
    }
    function advance() {
        if (!simulation || !enabled) return
        if (phase < lastPhase) { reset(); return }
        Physics.advance(simulation, Math.min(0.2, phase - lastPhase), storm)
        lastPhase = phase
        particles.requestPaint()
    }
    onPhaseChanged: advance()
    onThemeIdChanged: reset()
    onCountChanged: reset()
    Component.onCompleted: reset()

    Canvas {
        id: particles
        width: Math.max(1, Math.min(root.width, (root.economical ? 800 : 1280)
            * Math.min(1, root.width / Math.max(1, root.height))))
        height: root.width > 0 ? width * root.height / root.width : 1
        scale: width > 0 ? root.width / width : 1
        transformOrigin: Item.TopLeft
        renderTarget: Canvas.Image
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            if (!root.simulation || width < 1 || height < 1) return
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.globalCompositeOperation = "lighter"
            const unit = height * (root.themeId === "blackhole" ? 0.105 : 0.13)
            function project(pos) {
                if (root.themeId === "weather")
                    return [width / 2 + pos[0] * width / 12, height / 2 + pos[1] * height / 8]
                let x = pos[0], y = -pos[2] * (root.themeId === "blackhole" ? 0.23 : 0.52) + pos[1]
                const roll = root.themeId === "blackhole" ? -0.14 : -0.38
                return [width * 0.53 + (x * Math.cos(roll) - y * Math.sin(roll)) * unit,
                    height * 0.49 + (x * Math.sin(roll) + y * Math.cos(roll)) * unit]
            }
            for (const p of root.simulation.particles) {
                if (root.foreground) continue
                const pos = project([p.x, p.y, p.z])
                if (root.themeId === "blackhole" && !root.foreground
                    && Math.hypot(pos[0] - width * 0.53, pos[1] - height * 0.49) < height * 0.15) continue
                const hot = p.seed > 0.985
                const radius = hot ? 1.8 : (0.45 + p.seed * 0.7)
                const tint = root.themeId === "blackhole" ? (hot ? "255,239,200" : "255,157,67")
                    : root.themeId === "weather" ? "135,197,245"
                    : p.seed > 0.67 ? "130,197,255" : "255,192,124"
                const alpha = root.themeId === "weather" ? (root.storm ? 0.32 : 0.17) : 0.28 + p.seed * 0.52
                ctx.lineWidth = Math.max(0.5, radius * 0.65)
                // One path per particle; avoid a draw call for every trail segment.
                ctx.strokeStyle = "rgba(" + tint + "," + alpha * 0.20 + ")"
                ctx.beginPath()
                for (let i = p.trail.length - 1; i >= 0; --i) {
                    const point = project(p.trail[i])
                    if (i === p.trail.length - 1) ctx.moveTo(point[0], point[1])
                    else ctx.lineTo(point[0], point[1])
                }
                ctx.stroke()
                if (hot) {
                    const glowSize = hot ? 19 : 5
                    const gradient = ctx.createRadialGradient(pos[0], pos[1], 0, pos[0], pos[1], glowSize)
                    gradient.addColorStop(0, "rgba(" + tint + "," + alpha * 0.55 + ")")
                    gradient.addColorStop(0.18, "rgba(" + tint + "," + alpha * 0.18 + ")")
                    gradient.addColorStop(1, "rgba(" + tint + ",0)")
                    ctx.fillStyle = gradient
                    ctx.fillRect(pos[0] - glowSize, pos[1] - glowSize, glowSize * 2, glowSize * 2)
                }
                ctx.fillStyle = "rgba(" + tint + "," + alpha + ")"
                ctx.beginPath(); ctx.arc(pos[0], pos[1], radius, 0, Math.PI * 2); ctx.fill()
                if (hot && root.themeId !== "weather") {
                    ctx.strokeStyle = "rgba(" + tint + ",0.24)"; ctx.lineWidth = 0.5
                    ctx.beginPath(); ctx.moveTo(pos[0] - 11, pos[1]); ctx.lineTo(pos[0] + 11, pos[1]);
                    ctx.moveTo(pos[0], pos[1] - 11); ctx.lineTo(pos[0], pos[1] + 11); ctx.stroke()
                }
            }
        }
    }
}
