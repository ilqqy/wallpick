import QtQuick
import QtQuick.Effects
import ".."

Item {
    id: root
    property string text: "Wallpapers"
    property bool reducedMotion: AppConfig.reducedMotion
    property int seed: 7
    property color accent: Theme.accent
    property real elapsed: 0
    property bool active: true
    implicitWidth: 286
    implicitHeight: 66

    function seeded(n) {
        const v = Math.sin(n * 12.9898) * 43758.5453
        return v - Math.floor(v)
    }

    Timer {
        interval: 33
        repeat: true
        running: root.active && root.visible && !root.reducedMotion
        onTriggered: root.elapsed += interval / 1000
    }

    Text {
        id: bloomText
        anchors.centerIn: chrome
        text: root.text
        font.family: "DejaVu Sans"
        font.pixelSize: 39
        font.bold: true
        font.letterSpacing: -1.2
        color: root.accent
        visible: false
    }

    MultiEffect {
        anchors.fill: chrome
        source: bloomText
        blurEnabled: true
        blurMax: 32
        blur: 0.75
        opacity: root.reducedMotion ? 0.32 : (0.28 + 0.08 * Math.cos(root.elapsed * 2 * Math.PI / 5.5))
    }

    Canvas {
        id: chrome
        x: 14
        y: 8
        width: root.width - 28
        height: 50
        onPaint: {
            const c = getContext("2d")
            c.clearRect(0, 0, width, height)
            c.font = "bold 39px 'DejaVu Sans'"
            c.textBaseline = "middle"
            const y = height / 2 + 2
            c.shadowColor = "#080c14"
            c.shadowBlur = 2
            c.shadowOffsetY = 3
            c.fillStyle = "#55677b"
            c.fillText(root.text, 0, y)
            c.shadowBlur = 0
            c.shadowOffsetY = 0
            const gradient = c.createLinearGradient(0, 2, 0, height - 5)
            gradient.addColorStop(0, "#ffffff")
            gradient.addColorStop(0.34, "#e5eaf0")
            gradient.addColorStop(0.7, "#abbdd0")
            gradient.addColorStop(1, "#e3eaf2")
            c.fillStyle = gradient
            c.fillText(root.text, 0, y - 2)
        }
        Connections {
            target: root
            function onTextChanged() { chrome.requestPaint() }
        }
    }

    Repeater {
        model: 7
        delegate: Item {
            id: particle
            readonly property real n: index + root.seed * 100
            readonly property real angle: (index / 7 + (root.seeded(n * 2.3) - 0.5) * (1.5 / 7)) * Math.PI * 2 - Math.PI / 2
            readonly property real radius: 1.05 + root.seeded(n * 3.1) * 0.3
            readonly property real size: 14 + root.seeded(n * 1.7) * 17
            readonly property real delay: root.seeded(n * 4.9) * 2.6
            readonly property real duration: 1.8 + root.seeded(n * 5.7) * 1.8
            readonly property real phase: root.reducedMotion ? 0.45 : Math.max(0, (root.elapsed - delay) % duration / duration)
            readonly property real strength: root.reducedMotion ? 0.65 :
                phase < 0.45 ? phase / 0.45 : phase < 0.7 ? 1 - (phase - 0.45) / 0.25 * 0.65 : 0.35 * (1 - (phase - 0.7) / 0.3)
            width: size
            height: size
            x: root.width * (0.5 + Math.cos(angle) * 0.58 * radius) - width / 2
            y: root.height * (0.46 + Math.sin(angle) * 0.5 * radius) - height / 2
            opacity: Math.max(0, strength) * 0.67
            scale: root.reducedMotion ? 0.66 : phase < 0.45 ? 0.2 + phase / 0.45 * 0.8 : phase < 0.7 ? 1 - (phase - 0.45) / 0.25 * 0.3 : 0.7 - (phase - 0.7) / 0.3 * 0.5
            rotation: root.reducedMotion ? 18 : phase < 0.45 ? phase / 0.45 * 30 : 30 + (phase - 0.45) / 0.55 * 15
            Canvas {
                anchors.fill: parent
                onPaint: {
                    const c = getContext("2d")
                    c.clearRect(0, 0, width, height)
                    const unit = width / 24
                    c.scale(unit, unit)
                    c.beginPath()
                    c.moveTo(12, 0)
                    c.bezierCurveTo(12.9, 7.6, 16.4, 11.1, 24, 12)
                    c.bezierCurveTo(16.4, 12.9, 12.9, 16.4, 12, 24)
                    c.bezierCurveTo(11.1, 16.4, 7.6, 12.9, 0, 12)
                    c.bezierCurveTo(7.6, 11.1, 11.1, 7.6, 12, 0)
                    c.fillStyle = index % 3 === 0 ? "#ffffff" : index % 3 === 1 ? "#d9e5f2" : "#b8cbdc"
                    c.shadowColor = "#afc7dd"
                    c.shadowBlur = 8
                    c.fill()
                }
            }
        }
    }
}
