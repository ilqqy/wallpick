import QtQuick

FocusScope {
    id: root
    property string text: "Apply wallpaper"
    property bool reducedMotion: false
    property bool active: true
    property real hoverAmount: pointer.containsMouse && enabled ? 1 : 0
    property real pressAmount: pointer.pressed && enabled ? 1 : 0
    signal clicked()

    width: 171
    height: 43
    activeFocusOnTab: enabled
    opacity: enabled ? 1 : 0.56
    scale: pressAmount > 0 ? 0.985 : 1
    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: if (enabled) clicked()

    Behavior on opacity { NumberAnimation { duration: root.reducedMotion ? 0 : 160; easing.type: Easing.OutQuad } }
    Behavior on scale { NumberAnimation { duration: root.reducedMotion ? 0 : 110; easing.type: Easing.OutQuad } }
    Behavior on hoverAmount { NumberAnimation { duration: root.reducedMotion ? 0 : 220; easing.type: Easing.OutCubic } }
    Behavior on pressAmount { NumberAnimation { duration: root.reducedMotion ? 0 : 100; easing.type: Easing.OutQuad } }

    Rectangle {
        x: 3; y: 4
        width: root.width - 6; height: root.height - 1
        radius: height / 2
        color: "#30040a18"
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: "#b5283a5d"
        border.color: root.activeFocus ? "#bddce6f6" : root.hoverAmount > 0 ? "#a1b1c8df" : "#7b8ba8c3"
        border.width: 1
        gradient: Gradient {
            GradientStop { position: 0; color: "#bb585b8d" }
            GradientStop { position: 0.48; color: "#a82b4268" }
            GradientStop { position: 1; color: "#bf1b304d" }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "#5b8277ba" }
            GradientStop { position: 0.48; color: "#0464789f" }
            GradientStop { position: 1; color: "#466496bb" }
        }
        opacity: 0.56 + root.hoverAmount * 0.19
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        gradient: Gradient {
            GradientStop { position: 0; color: "#477d9ab7" }
            GradientStop { position: 0.27; color: "#087d9ab7" }
            GradientStop { position: 0.55; color: "#00121f34" }
            GradientStop { position: 1; color: "#32081427" }
        }
        opacity: 0.55 + root.hoverAmount * 0.24
    }

    Rectangle {
        x: 18; y: 1; width: root.width - 36; height: 1
        radius: 0.5
        color: "#a6dce7f4"
        opacity: 0.65 + root.hoverAmount * 0.25
    }
    Rectangle {
        x: 29; y: root.height - 2; width: root.width - 58; height: 1
        radius: 0.5
        color: "#28415f86"
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: height / 2
        color: "transparent"
        border.width: 1
        border.color: "#286c89b0"
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: "#4709152a"
        opacity: root.pressAmount * 0.65
    }

    Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 1
        text: root.text
        color: "#7007121f"
        font.pixelSize: 15
        font.weight: Font.DemiBold
        renderType: Text.NativeRendering
    }
    Text {
        anchors.centerIn: parent
        text: root.text
        color: root.enabled ? "#f8fafc" : "#e1e8f0"
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
        border.color: "#9bdce8f4"
        visible: root.activeFocus
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        enabled: root.enabled
        onClicked: root.clicked()
    }

    Keys.onReturnPressed: event => { if (enabled) clicked(); event.accepted = true }
    Keys.onEnterPressed: event => { if (enabled) clicked(); event.accepted = true }
    Keys.onSpacePressed: event => { if (enabled) clicked(); event.accepted = true }
}
