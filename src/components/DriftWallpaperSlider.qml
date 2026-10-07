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
    property bool loading: false
    property bool pointerFocus: false
    property real pointerVelocity: 0
    property real moved: 0
    property real startX: 0
    property real base: 0
    property real lastX: 0
    property real lastT: 0
    property real wheelAccumulator: 0
    property real lastWheelT: 0
    property string lastPath: ""
    property real tiltX: 0
    property real tiltY: 0
    property real tiltTargetX: 0
    property real tiltTargetY: 0
    property real tiltVelocityX: 0
    property real tiltVelocityY: 0
    readonly property bool tiltMoving: Math.abs(tiltX - tiltTargetX) + Math.abs(tiltY - tiltTargetY) + Math.abs(tiltVelocityX) + Math.abs(tiltVelocityY) > 0.001
    readonly property bool focusVisible: activeFocus && !pointerFocus
    readonly property int count: items.length
    readonly property int windowSize: 9
    readonly property int firstVisibleIndex: Math.max(0, Math.min(Math.max(0, count - windowSize), Math.floor(progress) - 4))
    readonly property var selectedItem: items.length > 0 ? items[Math.min(activeIndex, items.length - 1)] : null
    // Card geometry follows the stage so the gallery can shrink on short screens.
    readonly property real cardWidth: Math.min(stage.width * 0.56, 330, (stage.height - 29) * 330 / 154)
    readonly property real cardHeight: cardWidth * 154 / 330
    readonly property real unit: cardWidth / 330
    signal selected(var item)

    activeFocusOnTab: true
    implicitHeight: 218
    Accessible.role: Accessible.List
    Accessible.name: "Wallpapers"
    Accessible.description: selectedItem
        ? selectedItem.name + (selectedItem.applied ? ", current wallpaper" : "") + ", " + (activeIndex + 1) + " of " + count
        : loading ? "Loading wallpapers" : "No wallpapers in this collection"

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
    function keyboardGoTo(index) {
        pointerFocus = false
        goTo(index)
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
    // Topmost visible card under a stage point, or -1.
    function cardAt(x, y) {
        let hit = -1
        let hitZ = -Infinity
        for (let i = 0; i < cards.count; ++i) {
            const card = cards.itemAt(i)
            if (!card || !card.visible || !card.wallpaper || card.opacity < 0.05 || card.z <= hitZ) continue
            const p = card.mapFromItem(stageArea, x, y)
            if (p.x >= 0 && p.y >= 0 && p.x <= card.width && p.y <= card.height) {
                hit = card.cardIndex
                hitZ = card.z
            }
        }
        return hit
    }
    // Touchpads deliver many small deltas per gesture; step once per wheel
    // notch (120) or per 64 px of smooth scrolling instead of once per event.
    function wheelBy(wheel) {
        if (count === 0) return false
        const smooth = wheel.pixelDelta.x !== 0 || wheel.pixelDelta.y !== 0
        const delta = smooth ? (Math.abs(wheel.pixelDelta.y) >= Math.abs(wheel.pixelDelta.x) ? wheel.pixelDelta.y : wheel.pixelDelta.x)
                             : (Math.abs(wheel.angleDelta.y) >= Math.abs(wheel.angleDelta.x) ? wheel.angleDelta.y : wheel.angleDelta.x)
        if (delta === 0) return true
        const now = Date.now()
        if (now - lastWheelT > 240 || Math.sign(delta) !== Math.sign(wheelAccumulator)) wheelAccumulator = 0
        lastWheelT = now
        wheelAccumulator += delta
        const threshold = smooth ? 64 : 120
        const steps = Math.trunc(wheelAccumulator / threshold)
        if (steps !== 0) {
            wheelAccumulator -= steps * threshold
            goTo(activeIndex - steps)
        }
        return true
    }

    onItemsChanged: reset()
    onActiveFocusChanged: if (!activeFocus) pointerFocus = false
    Keys.onLeftPressed: keyboardGoTo(activeIndex - 1)
    Keys.onRightPressed: keyboardGoTo(activeIndex + 1)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Home) { keyboardGoTo(0); event.accepted = true }
        else if (event.key === Qt.Key_End) { keyboardGoTo(count - 1); event.accepted = true }
    }

    FrameAnimation {
        running: root.active && root.visible && !root.reducedMotion &&
                 ((!root.dragging && Math.abs(root.progress - root.target) + Math.abs(root.springVelocity) > 0.001) || root.tiltMoving)
        onTriggered: {
            // Synchronised with vsync; long frames are clamped so the spring stays stable.
            const dt = Math.min(frameTime, 1 / 30)
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
        height: Math.max(96, root.height - 37)
        radius: 13
        color: "#7815202c"
        border.color: "#50697f91"

        Rectangle {
            x: 17; y: 1; width: parent.width - 34; height: 1
            color: "#397d96ab"
        }

        Text {
            anchors.centerIn: parent
            text: root.count > 0 ? "" : root.loading ? "Loading wallpapers…" : "No wallpapers in this collection"
            color: Theme.muted
            font.pixelSize: 13
        }

        RoundedClip {
            anchors.fill: parent
            radius: stage.radius

            Item {
                id: scene
                anchors.fill: parent
                transform: [
                    Rotation { origin.x: scene.width / 2; origin.y: scene.height / 2; axis.x: 0; axis.y: 1; axis.z: 0; angle: root.reducedMotion ? 0 : root.tiltX },
                    Rotation { origin.x: scene.width / 2; origin.y: scene.height / 2; axis.x: 1; axis.y: 0; axis.z: 0; angle: root.reducedMotion ? 0 : root.tiltY }
                ]
                Repeater {
                    id: cards
                    model: root.windowSize
                    delegate: Item {
                        id: card
                        // A delegate keeps its wallpaper while it stays inside the
                        // window; only the one that wraps around is rebound.
                        readonly property int cardIndex: root.firstVisibleIndex + ((index - root.firstVisibleIndex) % root.windowSize + root.windowSize) % root.windowSize
                        readonly property var wallpaper: root.items[cardIndex] || null
                        readonly property real d: cardIndex - root.progress
                        readonly property real a: Math.abs(d)
                        readonly property real sat: Math.min(a, 1)
                        readonly property real jx: (root.seeded(cardIndex * 3 + 1) - 0.5) * 64 * root.unit
                        readonly property real jy: (root.seeded(cardIndex * 3 + 2) - 0.5) * 84 * root.unit
                        readonly property real jr: (root.seeded(cardIndex * 3 + 3) - 0.5) * 9
                        readonly property real projection: root.reducedMotion ? 1 : 1100 / (1100 + a * 240)
                        width: root.cardWidth
                        height: root.cardHeight
                        x: stage.width / 2 - width / 2 + (d * 200 * root.unit + jx * sat) * projection
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
                            // Opaque, so a loading or broken card never shows its neighbours through it.
                            color: Theme.cardBase
                            border.color: card.cardIndex === root.activeIndex ? "#bacbdae6" : "#667d90a2"
                            border.width: 1
                            layer.enabled: !root.reducedMotion && card.visible && GraphicsInfo.api !== GraphicsInfo.Software
                            layer.effect: MultiEffect {
                                blurEnabled: true
                                blurMax: 8
                                blur: Math.min(card.a * 2, 5) / 8
                            }

                            RoundedClip {
                                anchors.fill: parent
                                anchors.margins: 2
                                radius: cardVisual.radius - 2

                                Image {
                                    id: thumb
                                    anchors.fill: parent
                                    source: card.visible && card.wallpaper ? card.wallpaper.url : ""
                                    sourceSize.width: 540
                                    sourceSize.height: 310
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectCrop
                                    retainWhileLoading: true
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: thumb.status === Image.Error
                                    text: "Preview unavailable"
                                    color: Theme.muted
                                    font.pixelSize: 12
                                }
                                Rectangle {
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                    height: 26
                                    gradient: Gradient {
                                        GradientStop { position: 0; color: "#40ffffff" }
                                        GradientStop { position: 1; color: "#00ffffff" }
                                    }
                                }
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 8
                                    width: currentLabel.implicitWidth + 14
                                    height: 18
                                    radius: 5
                                    color: Theme.scrim
                                    visible: !!card.wallpaper && card.wallpaper.applied
                                    Text {
                                        id: currentLabel
                                        anchors.centerIn: parent
                                        text: "CURRENT"
                                        color: Theme.foreground
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        font.letterSpacing: 0.4
                                    }
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
                    GradientStop { position: 0; color: "#8a14212e" }
                    GradientStop { position: 1; color: "#0014212e" }
                }
            }
            Rectangle {
                width: 68; height: parent.height
                anchors.right: parent.right
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#0014212e" }
                    GradientStop { position: 1; color: "#8a14212e" }
                }
            }
        }

        MouseArea {
            id: stageArea
            anchors.fill: parent
            z: 200
            hoverEnabled: true
            cursorShape: root.count === 0 ? Qt.ArrowCursor : root.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            onPressed: mouse => {
                if (root.count === 0) { mouse.accepted = false; return }
                root.pointerFocus = true
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
                    const hit = root.cardAt(mouse.x, mouse.y)
                    if (hit >= 0) root.goTo(hit)
                    else if (mouse.x < stage.width * 0.35) root.goTo(root.activeIndex - 1)
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
            onWheel: wheel => { wheel.accepted = root.wheelBy(wheel) }
        }
    }

    Rectangle {
        anchors.fill: stage
        anchors.margins: -3
        radius: stage.radius + 3
        color: "transparent"
        border.color: Theme.foreground
        border.width: Theme.focusWidth
        visible: root.focusVisible
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        spacing: 10
        Repeater {
            model: [-1, 1]
            delegate: Rectangle {
                id: chip
                readonly property bool available: modelData < 0 ? root.activeIndex > 0 : root.activeIndex < root.count - 1
                width: 43; height: 28; radius: 7
                color: chipArea.pressed ? Theme.panelPressed : chipArea.containsMouse ? Theme.panelRaised : Theme.panel
                border.color: Theme.border
                opacity: available ? 1 : 0.4
                Accessible.role: Accessible.Button
                Accessible.name: modelData < 0 ? "Previous wallpaper" : "Next wallpaper"
                Accessible.onPressAction: if (available) root.goTo(root.activeIndex + modelData)
                Text { anchors.centerIn: parent; text: modelData < 0 ? "‹" : "›"; color: Theme.foreground; font.pixelSize: 22 }
                MouseArea {
                    id: chipArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: chip.available
                    cursorShape: chip.available ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.goTo(root.activeIndex + modelData)
                }
            }
        }
    }
}
