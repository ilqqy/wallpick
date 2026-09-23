import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "components"
import "."

PanelWindow {
    id: window
    property var service
    property string sourceKey: "recent"
    property string selectedPath: gallery.selectedItem ? gallery.selectedItem.path : ""
    property string selectedUrl: gallery.selectedItem ? gallery.selectedItem.url : ""
    property string displayUrl: ""
    property string displayedUrl: ""
    property string previewError: ""
    readonly property bool previewReady: heroImage.status === Image.Ready && displayUrl === selectedUrl && !!selectedUrl
    property string fetchMode: "randomanime"
    property bool opened: false
    property string transientMessage: ""
    signal requestClose()

    visible: opened
    implicitWidth: 910
    implicitHeight: 890
    color: "transparent"
    anchors.top: true
    anchors.right: true
    margins.top: 30
    margins.right: 18
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function sourceItems(key) {
        const data = service && service.catalog && service.catalog.sources ? service.catalog.sources[key] : null
        return data ? data.items : []
    }
    function sourceExists(key) {
        const data = service && service.catalog && service.catalog.sources ? service.catalog.sources[key] : null
        return data ? data.exists : false
    }
    function sourceCount(key) { return sourceItems(key).length }
    function chooseSource(key) {
        if (!AppConfig.sourceInfo.some(info => info.key === key))
            return
        sourceKey = key
        if (key === "anime") fetchMode = "randomanime"
        else if (key === "general") fetchMode = "randomwall"
        else if (key === "gooner") fetchMode = "randomgooner"
        gallery.forceActiveFocus()
    }
    function selectIndex(index) { gallery.goTo(index) }
    function words() {
        return query.text.trim() ? query.text.trim().split(/\s+/) : []
    }
    function fetch(command) {
        if (!service.busy) {
            fetchMode = command
            service.random(command, words())
        }
    }
    function randomFromSource(key) {
        const info = AppConfig.sourceInfo.find(source => source.key === key)
        if (!info || service.busy) return
        if (info.command) {
            fetch(info.command)
            return
        }
        if (!sourceItems(key).length) return
        chooseSource(key)
        Qt.callLater(() => {
            const count = gallery.items.length
            if (!count) return
            // Prefer a different image when the collection has a choice.
            let next = Math.floor(Math.random() * Math.max(1, count - 1))
            if (count > 1 && next >= gallery.activeIndex) next++
            gallery.goTo(next)
            service.error = ""
            service.message = "Random selection · press Apply to use it"
        })
    }
    function apply() {
        if (selectedPath && !service.busy && previewReady)
            service.apply(selectedPath)
    }
    function favorite() {
        if (service.busy) return
        if (selectedPath && !previewReady) return
        if (selectedPath && (!gallery.selectedItem.applied || service.currentUncertain))
            service.favoriteSelected(selectedPath)
        else if (service.catalog.current && !service.currentUncertain)
            service.favoriteCurrent()
    }
    function transitionTo(url) {
        if (displayUrl === url) return
        previewError = ""
        fadeOld.stop()
        if (displayedUrl && displayedUrl !== url && !AppConfig.reducedMotion) {
            oldImage.source = displayedUrl
            oldImage.opacity = 1
        }
        displayUrl = url
        if (!url) { oldImage.opacity = 0; displayedUrl = "" }
    }

    Connections {
        target: window.service
        function onActionFinished(operation, success) {
            if (!success) return
            const key = operation === "randomanime" ? "anime" : operation === "randomwall" ? "general" : operation === "randomgooner" ? "gooner" : ""
            if (key) {
                window.sourceKey = key
                gallery.lastPath = ""
                window.fetchMode = operation
            }
        }
    }

    onOpenedChanged: {
        if (opened) {
            service.refresh()
            Qt.callLater(() => keyScope.forceActiveFocus())
        }
    }
    onSelectedUrlChanged: Qt.callLater(() => transitionTo(selectedUrl))

    HyprlandFocusGrab {
        windows: [window]
        active: window.opened && !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
        onCleared: window.requestClose()
    }

    Rectangle {
        anchors.fill: parent
        radius: 24
        color: Theme.background
        border.color: "#516071"
        border.width: 1
    }

    AsciiWave {
        active: window.opened
        x: 1; y: 1
        width: parent.width - 2
        height: 146
        opacity: service.busy ? 0.9 : 0.55
        clip: true
        Behavior on opacity { NumberAnimation { duration: 260 } }
    }

    FocusScope {
        id: keyScope
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: window.requestClose()
        Keys.onLeftPressed: event => { if (!query.activeFocus) gallery.goTo(gallery.activeIndex - 1); else event.accepted = false }
        Keys.onRightPressed: event => { if (!query.activeFocus) gallery.goTo(gallery.activeIndex + 1); else event.accepted = false }
        Keys.onReturnPressed: event => { if (!query.activeFocus) window.apply(); else event.accepted = false }
        Keys.onEnterPressed: event => { if (!query.activeFocus) window.apply(); else event.accepted = false }
        Keys.onPressed: event => {
            if (query.activeFocus) return
            if (event.key === Qt.Key_F) { window.favorite(); event.accepted = true }
            else if (event.key === Qt.Key_R) { window.randomFromSource(window.sourceKey); event.accepted = true }
        }

        Item {
            id: content
            anchors.fill: parent
            anchors.margins: 20

            Item {
                id: header
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 63
                SparkleTitle { x: 6; y: -2; text: "Wallpapers"; active: window.opened }
                Column {
                    anchors.right: closeButton.left
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Text {
                        text: window.sourceCount(window.sourceKey) + " wallpapers · " + (window.sourceKey === "recent" ? "Recent" : AppConfig.sourceInfo.find(info => info.key === window.sourceKey).label)
                        color: Theme.foreground
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    Text {
                        text: service.scanning ? "Updating collection…" : service.busy ? "Working…" : "Select, then apply"
                        color: Theme.muted
                        font.pixelSize: 11
                    }
                }
                QuietButton {
                    id: closeButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30; height: 30; radius: 15
                    text: "×"
                    onClicked: window.requestClose()
                }
            }

            Rectangle {
                id: hero
                anchors.top: header.bottom
                anchors.topMargin: 10
                anchors.left: parent.left
                anchors.right: parent.right
                height: 293
                radius: 15
                color: Theme.panel
                border.color: Theme.border
                clip: true

                Image {
                    id: heroImage
                    anchors.fill: parent
                    source: window.displayUrl
                    sourceSize.width: 1200
                    sourceSize.height: 700
                    asynchronous: true
                    retainWhileLoading: true
                    fillMode: Image.PreserveAspectCrop
                    visible: status !== Image.Error && !!window.displayUrl
                    onStatusChanged: {
                        if (status === Image.Ready) {
                            window.displayedUrl = source.toString()
                            if (oldImage.opacity > 0) fadeOld.restart()
                        } else if (status === Image.Error) {
                            oldImage.opacity = 0
                            window.previewError = "This image could not be loaded"
                        }
                    }
                }
                Image {
                    id: oldImage
                    anchors.fill: parent
                    sourceSize.width: 1200
                    sourceSize.height: 700
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    opacity: 0
                    visible: opacity > 0 && status === Image.Ready
                    NumberAnimation on opacity { id: fadeOld; from: 1; to: 0; duration: 260; easing.type: Easing.OutCubic; running: false }
                }
                Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    height: 76
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#00070c13" }
                        GradientStop { position: 1; color: "#df070c13" }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: !gallery.selectedItem || !!window.previewError
                    text: window.previewError || (service.scanning ? "Loading your wallpapers…" : "Choose a collection or fetch a new wallpaper")
                    color: Theme.muted
                    font.pixelSize: 15
                }
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 19
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 17
                    spacing: 10
                    visible: !!gallery.selectedItem
                    Rectangle {
                        width: 6; height: 6; radius: 3
                        anchors.verticalCenter: parent.verticalCenter
                        color: gallery.selectedItem && gallery.selectedItem.applied ? "#a7dbc4" : Theme.accent
                    }
                    Text {
                        text: gallery.selectedItem ? gallery.selectedItem.name : ""
                        width: Math.min(600, hero.width - 130)
                        elide: Text.ElideMiddle
                        color: Theme.foreground
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: gallery.selectedItem && gallery.selectedItem.applied ? "CURRENT" : "SELECTED"
                        color: Theme.muted
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.top: parent.top
                    anchors.topMargin: 15
                    width: 128; height: 72; radius: 7
                    color: "#c90b1119"
                    border.color: "#a0aebd"
                    visible: !!service.catalog.current || service.currentUncertain
                    Image {
                        anchors.fill: parent
                        anchors.margins: 2
                        source: service.catalog.current ? service.catalog.current.url : ""
                        sourceSize.width: 240
                        sourceSize.height: 140
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                    }
                    Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 20; color: "#b70b1119" }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 3; text: service.currentUncertain ? (service.catalog.current ? "LAST KNOWN" : "CURRENT UNKNOWN") : "CURRENT DESKTOP"; color: "white"; font.pixelSize: 9; font.weight: Font.DemiBold }
                }
            }

            Row {
                id: sources
                anchors.top: hero.bottom
                anchors.topMargin: 13
                anchors.left: parent.left
                width: parent.width
                height: 133
                spacing: 9
                Repeater {
                    model: AppConfig.sourceInfo
                    delegate: Column {
                        visible: true
                        width: (window.width - 40 - 4 * sources.spacing) / 5
                        spacing: 2
                        FolderSourceCard {
                            width: parent.width
                            height: 101
                            title: modelData.label
                            hint: modelData.hint
                            count: window.sourceCount(modelData.key)
                            previews: window.sourceItems(modelData.key)
                            selected: window.sourceKey === modelData.key
                            onClicked: window.chooseSource(modelData.key)
                        }
                        QuietButton {
                            width: parent.width - 6
                            x: 3
                            height: 28
                            radius: 7
                            text: "⤨  Random"
                            Accessible.name: "Random " + modelData.label
                            enabled: !service.busy && (!!modelData.command || window.sourceCount(modelData.key) > 0)
                            onClicked: window.randomFromSource(modelData.key)
                        }
                    }
                }
            }

            DriftWallpaperSlider {
                id: gallery
                active: window.opened
                anchors.top: sources.bottom
                anchors.topMargin: 12
                anchors.left: parent.left
                anchors.right: parent.right
                height: 216
                items: window.sourceItems(window.sourceKey)
            }

            Item {
                id: bottom
                anchors.top: gallery.bottom
                anchors.topMargin: 8
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom

                Rectangle {
                    id: searchBox
                    anchors.left: parent.left
                    anchors.top: parent.top
                    width: parent.width * 0.51
                    height: 43
                    radius: 10
                    color: Theme.panel
                    border.color: query.activeFocus ? Theme.accent : Theme.border
                    TextInput {
                        id: query
                        anchors.fill: parent
                        anchors.leftMargin: 15
                        anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.foreground
                        selectionColor: Theme.accent
                        font.pixelSize: 13
                        clip: true
                        activeFocusOnTab: true
                        onAccepted: window.fetch(window.fetchMode)
                    }
                    Text {
                        anchors.fill: query
                        verticalAlignment: Text.AlignVCenter
                        text: window.fetchMode === "randomwall" ? "Search general · dark forest" : "Tags · rezero emilia -chibi"
                        color: Theme.dim
                        font.pixelSize: 13
                        visible: query.text.length === 0 && !query.activeFocus
                    }
                }

                Row {
                    id: fetchActions
                    anchors.left: searchBox.right
                    anchors.leftMargin: 9
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 43
                    spacing: 6
                    Repeater {
                        model: [
                            { text: "Random Anime", command: "randomanime" },
                            { text: "Random General", command: "randomwall" },
                            { text: "Random Gooner", command: "randomgooner" }
                        ]
                        delegate: QuietButton {
                            width: (fetchActions.width - 2 * fetchActions.spacing) / 3
                            height: 43
                            text: modelData.text
                            selected: window.fetchMode === modelData.command
                            enabled: !service.busy
                            onClicked: window.fetch(modelData.command)
                        }
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.top: searchBox.bottom
                    anchors.topMargin: 7
                    text: "Random fetches set the desktop immediately"
                    color: Theme.dim
                    font.pixelSize: 10
                }

                QuietButton {
                    id: favoriteButton
                    anchors.right: applyButton.left
                    anchors.rightMargin: 9
                    anchors.bottom: parent.bottom
                    width: 127
                    height: 43
                    radius: 12
                    text: "♡  Favorite"
                    enabled: !service.busy && (window.selectedPath ? window.previewReady : (!!service.catalog.current && !service.currentUncertain))
                    onClicked: window.favorite()
                }
                LiquidMetalButton {
                    id: applyButton
                    active: window.opened
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    width: 171
                    height: 43
                    text: service.busy && service.operation === "Apply" ? "Applying…" : "Apply wallpaper"
                    enabled: !!window.selectedPath && !service.busy && window.previewReady
                    reducedMotion: AppConfig.reducedMotion
                    onClicked: window.apply()
                }
                Text {
                    anchors.left: parent.left
                    anchors.right: favoriteButton.left
                    anchors.rightMargin: 12
                    anchors.bottom: parent.bottom
                    height: 31
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    color: service.error || window.previewError ? "#e9a7a6" : service.message ? "#abd4c3" : Theme.muted
                    text: service.error || window.previewError || service.message || (gallery.selectedItem ? (gallery.activeIndex + 1) + " / " + gallery.count : "No selection")
                    font.pixelSize: 12
                }
            }
        }
    }
}
