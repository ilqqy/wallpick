import QtQuick
import ".."

FocusScope {
    id: root
    property string text: ""
    property bool selected: false
    property real radius: 10
    signal clicked()
    implicitWidth: label.implicitWidth + 28
    implicitHeight: 43
    activeFocusOnTab: enabled
    opacity: enabled ? 1 : 0.48
    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: if (enabled) clicked()
    Keys.onReturnPressed: event => { if (enabled) clicked(); event.accepted = true }
    Keys.onEnterPressed: event => { if (enabled) clicked(); event.accepted = true }
    Keys.onSpacePressed: event => { if (enabled) clicked(); event.accepted = true }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: pointer.containsMouse || pointer.pressed ? Theme.panelRaised : Theme.panel
        border.color: root.activeFocus ? Theme.foreground : root.selected ? Theme.accent : Theme.border
        border.width: root.activeFocus ? 2 : 1
    }
    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: Theme.foreground
        font.pixelSize: 12
        font.weight: Font.Medium
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { root.forceActiveFocus(); root.clicked() }
    }
}
