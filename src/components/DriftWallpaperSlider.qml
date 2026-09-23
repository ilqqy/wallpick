import QtQuick
import QtQuick.Effects
import ".."

FocusScope {
    id: root
    property var items: []
    property int activeIndex: 0
    property real progress: 0
    property real target: 0
    property real springVelocity: 0
    property bool dragging: false
    property bool reducedMotion: AppConfig.reducedMotion
    property bool active: true
    property real pointerVelocity: 0
    property real moved: 0
    property real startX: 0
    property real base: 0
    property real lastX: 0
    property real lastT: 0
    property string lastPath: ""
    property real tiltX: 0
    property real tiltY: 0
    property real tiltTargetX: 0
    property real tiltTargetY: 0
    property real tiltVelocityX: 0
    property real tiltVelocityY: 0
    readonly property bool tiltMoving: Math.abs(tiltX - tiltTargetX) + Math.abs(tiltY - tiltTargetY) + Math.abs(tiltVelocityX) + Math.abs(tiltVelocityY) > 0.001
    readonly property int count: items.length
    readonly property int firstVisibleIndex: Math.max(0, Math.min(Math.max(0, count - 9), Math.floor(progress) - 4))
    readonly property var selectedItem: items.length > 0 ? items[Math.min(activeIndex, items.length - 1)] : null
    signal selected(var item)

    activeFocusOnTab: true
    implicitHeight: 218

    function seeded(n) { const v = Math.sin(n * 12.9898) * 43758.5453; return v - Math.floor(v) }
    function clamp(v, min, max) { return Math.min(max, Math.max(min, v)) }
    function goTo(index) {
        if (items.length === 0) return
        const next = clamp(index, 0, items.length - 1)
        activeIndex = next
        target = next
        lastPath = items[next].path
        if (reducedMotion) progress = next
        selected(items[next])
    }
    function reset() {
        let next = 0
        if (lastPath) {
            // Derived bindings can still contain the previous collection's
            // length while onItemsChanged is being delivered.
            for (let i = 0; i < items.length; i++) {
                if (items[i].path === lastPath) { next = i; break }
            }
        }
        activeIndex = next
        target = next
        progress = next
        springVelocity = 0
        const item = items[next] || null
        lastPath = item ? item.path : ""
        selected(item)
    }

    onItemsChanged: reset()
    Keys.onLeftPressed: goTo(activeIndex - 1)
    Keys.onRightPressed: goTo(activeIndex + 1)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Home) { goTo(0); event.accepted = true }
        else if (event.key === Qt.Key_End) { goTo(count - 1); event.accepted = true }
    }

    Timer {
        interval: 16
        repeat: true
        running: root.active && root.visible && !root.reducedMotion &&
                 ((!root.dragging && Math.abs(root.progress - root.target) + Math.abs(root.springVelocity) > 0.001) || root.tiltMoving)
        onTriggered: {
            const dt = interval / 1000
            if (!root.dragging) {
                root.springVelocity += ((root.target - root.progress) * 150 - root.springVelocity * 24) * dt
                root.progress += root.springVelocity * dt
                if (Math.abs(root.progress - root.target) < 0.001 && Math.abs(root.springVelocity) < 0.01) {
                    root.progress = root.target
                    root.springVelocity = 0
                }
            }
            root.tiltVelocityX += ((root.tiltTargetX - root.tiltX) * 110 - root.tiltVelocityX * 16) * dt
            root.tiltVelocityY += ((root.tiltTargetY - root.tiltY) * 110 - root.tiltVelocityY * 16) * dt
            root.tiltX += root.tiltVelocityX * dt
            root.tiltY += root.tiltVelocityY * dt
        }
    }

    Rectangle {
        id: stage
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 183
        radius: 13
        color: "#0c1119"
        border.color: Theme.border
        clip: true

        Text {
            anchors.centerIn: parent
            text: root.count === 0 ? "No wallpapers in this collection" : ""
            color: Theme.muted
            font.pixelSize: 13
        }

        Item {
            id: scene
            anchors.fill: parent
            transform: [
                Rotation { origin.x: scene.width / 2; origin.y: scene.height / 2; axis.x: 0; axis.y: 1; axis.z: 0; angle: root.reducedMotion ? 0 : root.tiltX },
                Rotation { origin.x: scene.width / 2; origin.y: scene.height / 2; axis.x: 1; axis.y: 0; axis.z: 0; angle: root.reducedMotion ? 0 : root.tiltY }
            ]
          Repeater {
            model: 9
            delegate: Item {
                id: card
                readonly property int cardIndex: root.firstVisibleIndex + index
                readonly property var wallpaper: root.items[cardIndex] || null
                readonly property real d: cardIndex - root.progress
                readonly property real a: Math.abs(d)
                readonly property real sat: Math.min(a, 1)
                readonly property real jx: (root.seeded(cardIndex * 3 + 1) - 0.5) * 64
                readonly property real jy: (root.seeded(cardIndex * 3 + 2) - 0.5) * 84
                readonly property real jr: (root.seeded(cardIndex * 3 + 3) - 0.5) * 9
                readonly property real projection: root.reducedMotion ? 1 : 1100 / (1100 + a * 240)
                width: Math.min(stage.width * 0.56, 330)
                height: 154
                x: stage.width / 2 - width / 2 + (d * 200 + jx * sat) * projection
                y: stage.height / 2 - height / 2 + jy * sat * projection
                scale: root.reducedMotion ? (cardIndex === root.activeIndex ? 1 : 0.88) : (1 - Math.min(a * 0.08, 0.32)) * projection
                rotation: root.reducedMotion ? 0 : jr * sat
                opacity: root.reducedMotion ? (a < 2 ? 1 : 0) : a < 1 ? 1 - a * 0.25 : a < 2 ? 0.75 - (a - 1) * 0.35 : Math.max(0, 0.4 - (a - 2) * 0.4)
                z: 100 - Math.round(a * 10)
                visible: !!wallpaper && a < 3.2
                transform: Rotation {
                    origin.x: card.width / 2
                    origin.y: card.height / 2
                    axis.x: 0; axis.y: 1; axis.z: 0
                    angle: root.reducedMotion ? 0 : Math.max(-3.2, Math.min(3.2, card.d)) * -16
                }

                Rectangle {
                    id: cardVisual
                    anchors.fill: parent
                    radius: 9
                    color: Theme.panelRaised
                    border.color: card.cardIndex === root.activeIndex ? "#c7d6e3" : "#607080"
                    border.width: card.cardIndex === root.activeIndex ? 2 : 1
                    layer.enabled: !root.reducedMotion && card.visible
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blurMax: 8
                        blur: Math.min(card.a * 2, 5) / 8
                    }
                    clip: true
                    Image {
                        anchors.fill: parent
                        anchors.margins: 2
                        source: card.visible && card.wallpaper ? card.wallpaper.url : ""
                        sourceSize.width: 540
                        sourceSize.height: 310
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                        retainWhileLoading: true
                    }
                    Rectangle {
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        height: 26
                        gradient: Gradient {
                            GradientStop { position: 0; color: "#40ffffff" }
                            GradientStop { position: 1; color: "#00ffffff" }
                        }
                    }
                }
            }
          }
        }

        Rectangle {
            width: 68; height: parent.height
            anchors.left: parent.left
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#0c1119" }
                GradientStop { position: 1; color: "#000c1119" }
            }
            z: 150
        }
        Rectangle {
            width: 68; height: parent.height
            anchors.right: parent.right
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#000c1119" }
                GradientStop { position: 1; color: "#0c1119" }
            }
            z: 150
        }

        MouseArea {
            anchors.fill: parent
            z: 200
            hoverEnabled: true
            cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            onPressed: mouse => {
                if (root.count === 0) { mouse.accepted = false; return }
                root.forceActiveFocus()
                root.dragging = true
                root.tiltTargetX = 0
                root.tiltTargetY = 0
                root.startX = mouse.x
                root.base = root.progress
                root.lastX = mouse.x
                root.lastT = Date.now()
                root.pointerVelocity = 0
                root.moved = 0
            }
            onPositionChanged: mouse => {
                if (!root.dragging) {
                    root.tiltTargetX = (mouse.x / width * 2 - 1) * 4
                    root.tiltTargetY = -(mouse.y / height * 2 - 1) * 3
                    return
                }
                const dx = mouse.x - root.startX
                root.moved = Math.max(root.moved, Math.abs(dx))
                const now = Date.now(), dt = now - root.lastT
                if (dt > 0) root.pointerVelocity = (mouse.x - root.lastX) / dt
                root.lastX = mouse.x
                root.lastT = now
                const step = stage.width * 0.45
                let raw = root.base - dx / step
                if (raw < 0) raw *= 0.35
                else if (raw > root.count - 1) raw = root.count - 1 + (raw - root.count + 1) * 0.35
                root.progress = raw
                root.springVelocity = 0
            }
            onReleased: mouse => {
                if (!root.dragging) return
                root.dragging = false
                if (Date.now() - root.lastT > 100) root.pointerVelocity = 0
                if (root.moved < 6) {
                    if (mouse.x < stage.width * 0.35) root.goTo(root.activeIndex - 1)
                    else if (mouse.x > stage.width * 0.65) root.goTo(root.activeIndex + 1)
                    else root.goTo(root.activeIndex)
                    return
                }
                const next = Math.abs(root.pointerVelocity) > 0.35 && root.moved > 12
                           ? (root.pointerVelocity < 0 ? Math.ceil(root.progress) : Math.floor(root.progress))
                           : Math.round(root.progress)
                root.goTo(next)
            }
            onCanceled: { root.dragging = false; root.goTo(Math.round(root.progress)) }
            onExited: { root.tiltTargetX = 0; root.tiltTargetY = 0 }
            onWheel: wheel => {
                if (root.count === 0) return
                const delta = wheel.angleDelta.y || wheel.angleDelta.x || wheel.pixelDelta.y || wheel.pixelDelta.x
                if (delta !== 0) root.goTo(root.activeIndex + (delta < 0 ? 1 : -1))
                wheel.accepted = true
            }
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        spacing: 10
        Repeater {
            model: [-1, 1]
            delegate: Rectangle {
                width: 43; height: 28; radius: 7
                color: chipArea.containsMouse ? Theme.panelRaised : Theme.panel
                border.color: Theme.border
                opacity: root.count === 0 || (modelData < 0 && root.activeIndex === 0) || (modelData > 0 && root.activeIndex === root.count - 1) ? 0.4 : 1
                Text { anchors.centerIn: parent; text: modelData < 0 ? "‹" : "›"; color: Theme.foreground; font.pixelSize: 22 }
                MouseArea {
                    id: chipArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.goTo(root.activeIndex + modelData)
                }
            }
        }
    }
}
