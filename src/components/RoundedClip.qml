import QtQuick
import QtQuick.Effects

// Item.clip is rectangular, so square images and overlays poke past rounded
// frames. This masks its children to a rounded rectangle instead. The
// software renderer has no shader effects and falls back to a plain clip.
Item {
    id: root
    property real radius: 0
    default property alias content: container.data
    readonly property bool masked: GraphicsInfo.api !== GraphicsInfo.Software

    Item {
        id: container
        anchors.fill: parent
        clip: !root.masked
        layer.enabled: root.masked
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }
    }

    Item {
        id: mask
        anchors.fill: parent
        visible: false
        layer.enabled: root.masked
        Rectangle {
            anchors.fill: parent
            radius: root.radius
        }
    }
}
