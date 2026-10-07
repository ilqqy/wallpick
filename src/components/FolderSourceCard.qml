import QtQuick
import ".."

FocusScope {
    id: root
    property string title: "Favorites"
    property string hint: ""
    property int count: 0
    property var previews: []
    property bool selected: false
    // Remote sources download and apply immediately; local ones only select.
    property bool remote: false
    property bool randomEnabled: true
    property bool reducedMotion: AppConfig.reducedMotion
    property bool hovered: area.containsMouse || shufflePointer.containsMouse
    // Whether the latest activation came from the keyboard, so the receiver
    // of the follow-up focus knows whether to show its focus ring.
    property bool keyboardActivation: false
    property bool pointerFocus: false
    property bool tipReady: false
    readonly property bool focusVisible: activeFocus && !shuffle.activeFocus && !pointerFocus
    readonly property bool opened: hovered || activeFocus || selected
    readonly property string randomDescription: remote ? "Download and apply a new " + title + " wallpaper"
                                                       : "Pick a random wallpaper from " + title
    signal clicked()
    signal randomClicked()
    activeFocusOnTab: true
    width: 145
    height: 102
    // Lifts the hovered card so its tooltip is not covered by later siblings.
    z: hovered || activeFocus ? 2 : 0
    transform: [
        Translate {
            y: root.selected ? -6 : 0
            Behavior on y { NumberAnimation { duration: root.reducedMotion ? 0 : 300; easing.type: Easing.OutCubic } }
        },
        Translate {
            y: area.pressed ? 1.5 : 0
            Behavior on y { NumberAnimation { duration: root.reducedMotion ? 0 : 90; easing.type: Easing.OutQuad } }
        }
    ]
    Accessible.role: Accessible.Button
    Accessible.name: title
    Accessible.description: count === 1 ? "1 wallpaper" : count + " wallpapers"
    Accessible.checkable: true
    Accessible.checked: selected
    Accessible.onPressAction: activate(true)

    function activate(viaKeyboard) {
        keyboardActivation = viaKeyboard
        clicked()
    }
    function activateRandom(viaKeyboard) {
        if (!randomEnabled) return
        keyboardActivation = viaKeyboard
        randomClicked()
    }

    onActiveFocusChanged: if (!activeFocus) pointerFocus = false
    Keys.onReturnPressed: activate(true)
    Keys.onEnterPressed: activate(true)
    Keys.onSpacePressed: activate(true)

    Rectangle {
        x: 3; y: 24; width: root.width - 6; height: 68
        radius: 12
        color: root.selected ? "#31475b" : "#223243"
        border.color: root.selected ? "#9bacc1d3" : Theme.border
        border.width: 1
        Behavior on color { ColorAnimation { duration: root.reducedMotion ? 0 : 260; easing.type: Easing.OutCubic } }
    }

    Rectangle {
        x: 4; y: 25; width: root.width - 8; height: 33
        radius: 11
        color: "#526f89"
        opacity: root.selected ? 0.18 : 0
        Behavior on opacity { NumberAnimation { duration: root.reducedMotion ? 0 : 300; easing.type: Easing.OutCubic } }
    }

    Rectangle {
        x: 13; y: 25; width: root.width - 26; height: 1
        color: root.selected ? "#6f9bb1c4" : "#367f94a9"
    }

    Repeater {
        model: 3
        delegate: Item {
            id: sheet
            readonly property real d: index - 1
            x: root.width / 2 - width / 2 + (root.opened && !root.reducedMotion ? d * 17 : 0)
            y: root.opened ? (root.reducedMotion ? 14 : 5 - Math.abs(d) * 5) : 33
            width: 48
            height: 57
            rotation: root.opened && !root.reducedMotion ? d * 9 : 0
            transformOrigin: Item.Bottom
            z: index + 1

            Behavior on x {
                SequentialAnimation {
                    PauseAnimation { duration: root.opened ? 40 + index * 50 : (2 - index) * 45 }
                    NumberAnimation { duration: root.reducedMotion ? 0 : 440; easing.type: Easing.OutBack; easing.overshoot: 1.18 }
                }
            }
            Behavior on y {
                SequentialAnimation {
                    PauseAnimation { duration: root.opened ? 40 + index * 50 : (2 - index) * 45 }
                    NumberAnimation { duration: root.reducedMotion ? 0 : 440; easing.type: Easing.OutBack; easing.overshoot: 1.18 }
                }
            }
            Behavior on rotation { NumberAnimation { duration: root.reducedMotion ? 0 : 500; easing.type: Easing.OutBack; easing.overshoot: 1.18 } }

            Rectangle {
                anchors.fill: parent
                radius: 5
                color: "#3a4d60"
                border.color: "#90a5b7c7"
                border.width: 1
                clip: true
                Image {
                    anchors.fill: parent
                    anchors.margins: 2
                    source: root.previews.length > index ? root.previews[index].url : ""
                    sourceSize.width: 100
                    sourceSize.height: 120
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }
            }
        }
    }

    Item {
        id: pocket
        x: 3; y: 47; width: root.width - 6; height: 46
        z: 5
        transform: Rotation {
            origin.x: pocket.width / 2
            origin.y: pocket.height
            axis.x: 1; axis.y: 0; axis.z: 0
            angle: root.opened && !root.reducedMotion ? -20 : 0
            Behavior on angle { NumberAnimation { duration: root.reducedMotion ? 0 : 500; easing.type: Easing.OutBack; easing.overshoot: 1.18 } }
        }
        Rectangle {
            anchors.fill: parent
            radius: 11
            color: root.selected ? "#3d5368" : "#2b3d50"
            border.color: root.selected ? "#a2bdcbd9" : "#607f91a1"
            Behavior on color { ColorAnimation { duration: root.reducedMotion ? 0 : 260; easing.type: Easing.OutCubic } }
        }
        Rectangle {
            x: 12; y: 1; width: parent.width - 24; height: 1
            color: root.selected ? "#67c1d3df" : "#378fa3b5"
        }
        Text {
            x: 11
            // Stops short of the shuffle control instead of running under it.
            width: shuffle.x - pocket.x - x - 6
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: root.title
            color: Theme.foreground
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
    }

    Rectangle {
        x: 0; y: 21
        width: root.width; height: 75
        radius: 15
        color: "transparent"
        border.color: Theme.foreground
        border.width: Theme.focusWidth
        visible: root.focusVisible
        z: 8
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        z: 10
        onClicked: {
            root.pointerFocus = true
            root.forceActiveFocus()
            root.activate(false)
        }
    }

    FocusScope {
        id: shuffle
        property bool pointerFocus: false
        readonly property bool focusVisible: activeFocus && !pointerFocus
        x: root.width - 39; y: 57
        width: 28; height: 28
        z: 11
        enabled: root.randomEnabled
        opacity: enabled ? 1 : 0.4
        activeFocusOnTab: enabled
        Accessible.role: Accessible.Button
        Accessible.name: "Random " + root.title
        Accessible.description: root.randomDescription
        Accessible.onPressAction: root.activateRandom(true)
        onActiveFocusChanged: if (!activeFocus) pointerFocus = false
        Keys.onReturnPressed: event => { root.activateRandom(true); event.accepted = true }
        Keys.onEnterPressed: event => { root.activateRandom(true); event.accepted = true }
        Keys.onSpacePressed: event => { root.activateRandom(true); event.accepted = true }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: shufflePointer.pressed ? "#576b7c" : shufflePointer.containsMouse || shuffle.focusVisible ? "#485e70" : "#273d4e"
            border.color: shuffle.focusVisible ? Theme.foreground : "#738ba0b2"
            border.width: shuffle.focusVisible ? Theme.focusWidth : 1
        }
        Canvas {
            anchors.centerIn: parent
            width: 17; height: 17
            onPaint: {
                const c = getContext("2d")
                c.clearRect(0, 0, width, height)
                c.lineWidth = 1.55
                c.lineCap = "round"
                c.lineJoin = "round"
                c.strokeStyle = "#e4edf4"
                c.beginPath()
                c.moveTo(2, 4); c.lineTo(4, 4); c.bezierCurveTo(7, 4, 9, 13, 13, 13); c.lineTo(15, 13)
                c.moveTo(12.5, 10.5); c.lineTo(15, 13); c.lineTo(12.5, 15.5)
                c.moveTo(2, 13); c.lineTo(4, 13); c.bezierCurveTo(7, 13, 9, 4, 13, 4); c.lineTo(15, 4)
                c.moveTo(12.5, 1.5); c.lineTo(15, 4); c.lineTo(12.5, 6.5)
                c.stroke()
            }
        }
        MouseArea {
            id: shufflePointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: shuffle.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            enabled: shuffle.enabled
            onContainsMouseChanged: if (!containsMouse) root.tipReady = false
            onClicked: {
                // If the action disables this control, focus falls back to the
                // card; keep that fallback free of a keyboard focus ring too.
                root.pointerFocus = true
                shuffle.pointerFocus = true
                shuffle.forceActiveFocus()
                root.activateRandom(false)
            }
        }
    }

    Timer {
        interval: 450
        running: shufflePointer.containsMouse && !root.tipReady
        onTriggered: root.tipReady = true
    }

    // The same icon fetches-and-applies on remote sources but only selects on
    // local ones, so the consequence is spelled out before the click.
    Rectangle {
        id: tip
        readonly property real boundsWidth: root.parent ? root.parent.width : root.width
        readonly property bool shown: shuffle.enabled && ((root.tipReady && shufflePointer.containsMouse) || shuffle.focusVisible)
        width: Math.min(tipText.implicitWidth + 20, boundsWidth)
        height: 26
        x: Math.max(-root.x, Math.min(boundsWidth - root.x - width, shuffle.x + shuffle.width / 2 - width / 2))
        y: 98
        z: 20
        radius: 7
        color: "#f00b121a"
        border.color: Theme.border
        opacity: shown ? 1 : 0
        visible: opacity > 0
        Accessible.ignored: true
        Behavior on opacity { NumberAnimation { duration: root.reducedMotion ? 0 : Theme.fast; easing.type: Easing.OutCubic } }

        Text {
            id: tipText
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - 20)
            elide: Text.ElideRight
            text: root.randomDescription
            color: Theme.foreground
            font.pixelSize: 11
        }
    }
}
