import QtQuick
import ".."

FocusScope {
    id: root
    property string text: "Apply wallpaper"
    property bool reducedMotion: false
    property real hoverAmount: pointer.containsMouse && enabled ? 1 : 0
    property real pressAmount: pointer.pressed && enabled ? 1 : 0
    signal clicked()

    width: 171
    height: 43
    activeFocusOnTab: enabled
    opacity: enabled ? 1 : 0.54
    scale: pressAmount > 0 ? 0.984 : 1
    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: if (enabled) clicked()

    Behavior on opacity { NumberAnimation { duration: root.reducedMotion ? 0 : 160; easing.type: Easing.OutQuad } }
    Behavior on scale { NumberAnimation { duration: root.reducedMotion ? 0 : 110; easing.type: Easing.OutQuad } }
    Behavior on hoverAmount { NumberAnimation { duration: root.reducedMotion ? 0 : 180; easing.type: Easing.OutCubic } }
    Behavior on pressAmount { NumberAnimation { duration: root.reducedMotion ? 0 : 90; easing.type: Easing.OutQuad } }

    Rectangle {
        x: 3; y: 4
        width: root.width - 6; height: root.height - 1
        radius: height / 2
        color: "#34060e17"
        opacity: 0.65 + root.hoverAmount * 0.25
    }

    Rectangle {
        id: glass
        anchors.fill: parent
        radius: height / 2
        clip: true
        border.width: 1
        border.color: root.activeFocus ? Theme.foreground : root.hoverAmount > 0 ? "#aec2d2dd" : Theme.primaryGlassEdge
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.primaryGlassTop }
            GradientStop { position: 0.52; color: Theme.primaryGlassMiddle }
            GradientStop { position: 1; color: Theme.primaryGlassBottom }
        }

        Rectangle {
            x: 2; y: 1
            width: parent.width - 4; height: 18
            radius: 17
            gradient: Gradient {
                GradientStop { position: 0; color: "#35e0e8ef" }
                GradientStop { position: 1; color: "#00e0e8ef" }
            }
            opacity: 0.65 + root.hoverAmount * 0.3
        }
        Rectangle {
            x: 18; y: 1
            width: parent.width - 36; height: 1
            color: "#80cbd8e3"
            opacity: 0.6 + root.hoverAmount * 0.35
        }
        Rectangle {
            x: 27; y: parent.height - 2
            width: parent.width - 54; height: 1
            color: "#24495e70"
        }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "#370c1824"
            opacity: root.pressAmount
        }
    }

    Text {
        anchors.centerIn: parent
        text: root.text
        color: "#f3f6f9"
        font.pixelSize: 15
        font.weight: Font.DemiBold
        renderType: Text.NativeRendering
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: height / 2
        color: "transparent"
        border.width: 1
        border.color: "#a9dce6ee"
        visible: root.activeFocus
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        enabled: root.enabled
        onClicked: { root.forceActiveFocus(); root.clicked() }
    }

    Keys.onReturnPressed: event => { if (enabled) clicked(); event.accepted = true }
    Keys.onEnterPressed: event => { if (enabled) clicked(); event.accepted = true }
    Keys.onSpacePressed: event => { if (enabled) clicked(); event.accepted = true }
}
