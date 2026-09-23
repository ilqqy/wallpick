import QtQuick
import ".."

Canvas {
    id: wave
    property int cell: 13
    property real speed: 0.75
    property real spread: 0.15
    property string chars: " .:-=+*xsoX0#8@"
    property color accent: Theme.accent
    property bool reducedMotion: AppConfig.reducedMotion
    property real time: 0
    property bool active: true
    renderTarget: Canvas.Image

    function fract(v) { return v - Math.floor(v) }
    function hash(x, y) { return fract(Math.sin(x * 127.1 + y * 311.7) * 43758.5453) }
    function noise(x, y) {
        const xi = Math.floor(x), yi = Math.floor(y)
        const xf = x - xi, yf = y - yi
        const u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf)
        const tl = hash(xi, yi), tr = hash(xi + 1, yi)
        const bl = hash(xi, yi + 1), br = hash(xi + 1, yi + 1)
        return tl * (1-u) * (1-v) + tr * u * (1-v) + bl * (1-u) * v + br * u * v
    }

    Timer {
        interval: 40
        repeat: true
        running: wave.active && wave.visible && !wave.reducedMotion
        onTriggered: { wave.time += interval / 1000 * wave.speed; wave.requestPaint() }
    }

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const c = getContext("2d")
        c.clearRect(0, 0, width, height)
        c.font = cell + "px monospace"
        c.textBaseline = "top"
        c.globalCompositeOperation = "lighter"
        const cols = Math.ceil(width / cell) + 1
        const rows = Math.ceil(height / cell) + 1
        const rampMax = chars.length - 1
        for (let gx = 0; gx < cols; gx++) {
            const px = gx * cell
            const nx = px / width - 0.5
            const edge = Math.min(1, Math.abs(nx) / 0.5)
            const localSpread = spread * (0.5 + 1.9 * edge * edge)
            const s2 = 2 * localSpread * localSpread
            const core = Math.exp(-(nx * nx) / (2 * 0.26 * 0.26))
            for (let gy = 0; gy < rows; gy++) {
                const py = gy * cell, ny = py / height - 0.5
                const band = Math.exp(-(ny * ny) / s2)
                if (band < 0.04) continue
                let n = noise(gx * 0.16 - time * 0.9, gy * 0.34 + time * 0.16)
                n = 0.6 * n + 0.4 * noise(gx * 0.4 + time * 0.25, gy * 0.5)
                const level = Math.min(1, band * (0.55 + 0.6 * n))
                if (level < 0.08) continue
                const white = band * core, k = white * white
                const r = Math.round(accent.r * 255 + (245 - accent.r * 255) * k)
                const g = Math.round(accent.g * 255 + (243 - accent.g * 255) * k)
                const b = Math.round(accent.b * 255 + (255 - accent.b * 255) * k)
                c.globalAlpha = level * 0.27
                c.fillStyle = "rgb(" + r + "," + g + "," + b + ")"
                const g2 = noise(gx * 0.9 + 19.3 - time * 0.9, gy * 0.9 + 4.1)
                const ci = Math.min(rampMax, Math.max(0, Math.round((0.5 * level + 0.55 * g2) * rampMax)))
                const ch = chars[ci]
                if (ch !== " ") c.fillText(ch, px, py)
            }
        }
        c.globalAlpha = 1
        c.globalCompositeOperation = "source-over"
    }
}
