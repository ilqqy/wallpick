import QtQuick
import ".."

FocusScope {
    id: root
    property string text: ""
    property bool selected: false
    property real radius: 10
    // Optional glyph drawn before the label.
    property Component icon: null
    // Set by mouse clicks so the keyboard focus ring only appears for
    // keyboard navigation, like :focus-visible.
    property bool pointerFocus: false
    readonly property bool focusVisible: activeFocus && !pointerFocus
    readonly property real iconSpace: iconLoader.active ? iconLoader.width + content.spacing : 0
    signal clicked()
    implicitWidth: label.implicitWidth + iconSpace + 28
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
    Row {
        id: content
        anchors.centerIn: parent
        spacing: 7
        Loader {
            id: iconLoader
            anchors.verticalCenter: parent.verticalCenter
            active: root.icon !== null
            visible: active
            sourceComponent: root.icon
        }
        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, root.width - 16 - root.iconSpace)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.text
            color: Theme.foreground
            font.pixelSize: 12
            font.weight: Font.Medium
        }
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
