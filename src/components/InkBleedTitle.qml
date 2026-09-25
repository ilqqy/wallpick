import QtQuick
import ".."

Item {
    id: root
    property string text: "Wallpick"
    property bool opened: false
    property bool reducedMotion: AppConfig.reducedMotion
    property bool animating: false
    property int entranceCount: 0
    readonly property int staggerMs: 55
    readonly property int glyphDurationMs: 900
    readonly property int totalDurationMs: glyphDurationMs + Math.max(0, text.length - 1) * staggerMs + 50
    implicitWidth: settledTitle.implicitWidth
    implicitHeight: 66
    Accessible.role: Accessible.StaticText
    Accessible.name: text

    function seeded(n) {
        const v = Math.sin(n * 12.9898) * 43758.5453
        return v - Math.floor(v)
    }
    function resetEntrance() {
        endTimer.stop()
        animating = false
    }
    function startEntrance() {
        resetEntrance()
        if (reducedMotion) return
        entranceCount++
        animating = true
        endTimer.restart()
    }

    onOpenedChanged: {
        if (opened) startEntrance()
        else resetEntrance()
    }
    onReducedMotionChanged: if (reducedMotion) resetEntrance()

    Timer {
        id: endTimer
        interval: root.totalDurationMs
        onTriggered: root.animating = false
    }

    Text {
        id: settledTitle
        x: 0; y: 6
        visible: !root.animating
        text: root.text
        color: Theme.foreground
        font.family: "DejaVu Sans"
        font.pixelSize: 39
        font.bold: true
        font.letterSpacing: -1.2
        renderType: Text.NativeRendering
    }

    // Loaded only for the entrance. Each glyph has its own staggered wet-to-dry
    // animation; its shader and texture are destroyed once the title settles.
    Loader {
        active: root.animating
        sourceComponent: Row {
            x: 0; y: 6
            spacing: -1.2
            Repeater {
                model: root.text.length
                delegate: Item {
                    id: glyph
                    property real progress: 0
                    readonly property real wetRadius: (0.34 + root.seeded(index * 1.7 + 3) * 0.12) * 39
                    width: Math.max(1, glyphText.implicitWidth)
                    height: 49

                    Item {
                        id: maskItem
                        x: -18; y: -15
                        width: glyph.width + 36
                        height: glyph.height + 30
                        Text {
                            id: glyphText
                            x: 18; y: 15
                            text: root.text.charAt(index)
                            color: "white"
                            font.family: "DejaVu Sans"
                            font.pixelSize: 39
                            font.bold: true
                            renderType: Text.NativeRendering
                        }
                    }

                    ShaderEffectSource {
                        id: glyphTexture
                        sourceItem: maskItem
                        hideSource: true
                        live: false
                        visible: false
                    }

                    ShaderEffect {
                        x: -18; y: -15
                        width: maskItem.width
                        height: maskItem.height
                        property var source: glyphTexture
                        property real progress: glyph.progress
                        property real blurPixels: glyph.wetRadius * (1 - glyph.progress)
                        property real roughness: 1.6
                        property real pixelWidth: width
                        property real pixelHeight: height
                        property color inkColor: Theme.foreground
                        property color accentColor: Theme.warm
                        fragmentShader: Qt.resolvedUrl("../shaders/inkbleed.frag.qsb")
                    }

                    SequentialAnimation {
                        running: true
                        PauseAnimation { duration: index * root.staggerMs }
                        NumberAnimation {
                            target: glyph
                            property: "progress"
                            from: 0; to: 1
                            duration: root.glyphDurationMs
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.23, 1, 0.32, 1, 1, 1]
                        }
                    }
                }
            }
        }
    }
}
