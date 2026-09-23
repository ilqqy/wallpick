import QtQuick

FocusScope {
    id: root

    property string text: "Apply wallpaper"
    property bool reducedMotion: false
    property real sheenPhase: 1
    property real elapsed: 0
    property bool active: true
    signal clicked()

    width: 172
    height: 48
    activeFocusOnTab: true
    scale: pointer.pressed && enabled && !reducedMotion ? 0.98 : 1
    opacity: enabled ? 1 : 0.48

    Behavior on scale {
        NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
    }

    NumberAnimation on elapsed {
        from: 0
        to: 3600
        duration: 3600000
        loops: Animation.Infinite
        running: root.active && root.visible && root.enabled && !root.reducedMotion
    }

    NumberAnimation {
        id: sheenSweep
        target: root
        property: "sheenPhase"
        from: 0
        to: 1
        duration: 720
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.23, 1, 0.32, 1, 1, 1]
    }

    // Qt's software scene graph does not draw ShaderEffect. Keep the action legible
    // in headless previews while the GPU path supplies the actual metallic rim.
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: "#151517"
        border.width: 1
        border.color: "#687078"
    }

    ShaderEffect {
        anchors.fill: parent
        property real pixelWidth: width
        property real pixelHeight: height
        property real time: root.reducedMotion ? 0 : root.elapsed
        property real rimWidth: 3
        property real prism: 0.5
        property real hoverAmount: pointer.containsMouse && root.enabled && !root.reducedMotion ? 1 : 0
        property real sheenPhase: root.sheenPhase
        property real pressedAmount: pointer.pressed && root.enabled ? 1 : 0
        fragmentShader: Qt.resolvedUrl("../shaders/liquidmetal.frag.qsb")
    }

    Text {
        anchors.centerIn: parent
        text: root.text
        color: root.enabled ? "#f5f5f5" : "#a3a3a3"
        font.pixelSize: 15
        font.weight: Font.Medium
        font.letterSpacing: -0.15
        renderType: Text.NativeRendering
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: "transparent"
        border.width: root.activeFocus ? 1 : 0
        border.color: "#cdd4dc"
        anchors.margins: root.activeFocus ? -3 : 0
        visible: root.activeFocus
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        enabled: root.enabled
        onEntered: {
            if (!root.reducedMotion) {
                root.sheenPhase = 0
                sheenSweep.restart()
            }
        }
        onClicked: root.clicked()
    }

    Keys.onReturnPressed: (event) => {
        if (root.enabled) root.clicked()
        event.accepted = true
    }
    Keys.onEnterPressed: (event) => {
        if (root.enabled) root.clicked()
        event.accepted = true
    }
    Keys.onSpacePressed: (event) => {
        if (root.enabled) root.clicked()
        event.accepted = true
    }
}
