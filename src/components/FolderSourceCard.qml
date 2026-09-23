import QtQuick
import ".."

FocusScope {
    id: root
    property string title: "Favorites"
    property string hint: ""
    property int count: 0
    property var previews: []
    property bool selected: false
    property bool reducedMotion: AppConfig.reducedMotion
    property bool hovered: area.containsMouse
    readonly property bool opened: hovered || activeFocus || selected
    signal clicked()
    activeFocusOnTab: true
    width: 145
    height: 102

    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()
    Keys.onSpacePressed: clicked()

    Rectangle {
        x: 3; y: 24; width: root.width - 6; height: 68
        radius: 12
        color: root.selected ? "#273443" : "#1e2935"
        border.color: root.selected ? Theme.accent : Theme.border
        border.width: 1
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
                color: "#485666"
                border.color: "#b6c4d0"
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
            color: root.selected ? "#34465a" : "#2b3948"
            border.color: root.selected ? "#9fb3c7" : "#4b5b6a"
        }
        Text {
            x: 11; y: 8
            text: root.title
            color: Theme.foreground
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
        Text {
            x: 11; y: 25
            text: root.count + " images"
            color: Theme.muted
            font.pixelSize: 10
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: "transparent"
        border.color: root.activeFocus ? Theme.foreground : "transparent"
        border.width: 1
        z: 8
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        z: 10
        onClicked: { root.forceActiveFocus(); root.clicked() }
    }
}
