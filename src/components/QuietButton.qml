import QtQuick
import ".."

FocusScope {
    id: root
    property string text: ""
    property bool selected: false
    property real radius: 10
    // Set by mouse clicks so the keyboard focus ring only appears for
    // keyboard navigation, like :focus-visible.
    property bool pointerFocus: false
    readonly property bool focusVisible: activeFocus && !pointerFocus
    signal clicked()
    implicitWidth: label.implicitWidth + 28
    implicitHeight: 43
    activeFocusOnTab: enabled
    opacity: enabled ? 1 : 0.48
    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: if (enabled) clicked()
    onActiveFocusChanged: if (!activeFocus) pointerFocus = false
    Keys.onReturnPressed: event => { if (enabled) clicked(); event.accepted = true }
    Keys.onEnterPressed: event => { if (enabled) clicked(); event.accepted = true }
    Keys.onSpacePressed: event => { if (enabled) clicked(); event.accepted = true }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: pointer.pressed ? Theme.panelPressed : pointer.containsMouse ? Theme.panelRaised : Theme.panel
        border.color: root.focusVisible ? Theme.foreground : root.selected ? Theme.accent : Theme.border
        border.width: root.focusVisible ? Theme.focusWidth : 1
    }
    Text {
        id: label
        anchors.centerIn: parent
        width: Math.min(implicitWidth, root.width - 16)
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.text
        color: Theme.foreground
        font.pixelSize: 12
        font.weight: Font.Medium
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            root.pointerFocus = true
            root.forceActiveFocus()
            root.clicked()
        }
    }
}
