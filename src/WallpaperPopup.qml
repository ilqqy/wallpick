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
    readonly property string fetchSourceName: fetchMode === "randomwall" ? "Wallhaven" : fetchMode === "randomgooner" ? "Gooner" : "Konachan"
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
    WlrLayershell.namespace: "wallpick"
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
            service.message = ""
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
        id: glassShell
        anchors.fill: parent
        radius: 21
        color: Theme.background
        border.color: "#748a9caf"
        border.width: 1
    }

    Rectangle {
        anchors { left: glassShell.left; right: glassShell.right; top: glassShell.top; margins: 2 }
        height: 130
        radius: 20
        gradient: Gradient {
            GradientStop { position: 0; color: "#1f9cb7ce" }
            GradientStop { position: 1; color: "#009cb7ce" }
        }
    }

    Rectangle {
        x: 28; y: 1; width: window.width - 56; height: 1
        color: "#537f9aaf"
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
                InkBleedTitle { x: 20; y: -2; text: "Wallpick"; opened: window.opened }
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
                height: 308
                radius: 16
                color: "#a014202c"
                border.color: "#8492a8b9"
                clip: true

                Image {
                    id: heroImage
                    anchors.fill: parent
                    anchors.margins: 4
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
                    anchors.margins: 4
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
                    height: 54
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#00070c13" }
                        GradientStop { position: 1; color: "#55070c13" }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: !gallery.selectedItem || !!window.previewError
                    text: window.previewError || (service.scanning ? "Loading your wallpapers…" : "Choose a collection or fetch a new wallpaper")
                    color: Theme.muted
                    font.pixelSize: 15
                }
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.top: parent.top
                    anchors.topMargin: 15
                    width: 124; height: 70; radius: 8
                    color: "#ad172331"
                    border.color: "#859aaabc"
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
                    Text { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 3; text: service.currentUncertain ? "LAST KNOWN" : "CURRENT"; color: "white"; font.pixelSize: 9; font.weight: Font.DemiBold }
                }
            }

            Row {
                id: sources
                anchors.top: hero.bottom
                anchors.topMargin: 13
                anchors.left: parent.left
                width: parent.width
                height: 111
                spacing: 9
                Repeater {
                    model: AppConfig.sourceInfo
                    delegate: FolderSourceCard {
                        width: (window.width - 40 - 4 * sources.spacing) / 5
                        height: 105
                        title: modelData.label
                        hint: modelData.hint
                        count: window.sourceCount(modelData.key)
                        previews: window.sourceItems(modelData.key)
                        selected: window.sourceKey === modelData.key
                        randomEnabled: !service.busy && (!!modelData.command || window.sourceCount(modelData.key) > 0)
                        onClicked: window.chooseSource(modelData.key)
                        onRandomClicked: window.randomFromSource(modelData.key)
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
                height: 220
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
                    width: parent.width
                    height: 43
                    radius: 11
                    color: "#a11d2a38"
                    border.color: query.activeFocus ? "#b4bccbd8" : Theme.border
                    border.width: 1
                    Rectangle {
                        x: 14; y: 1; width: parent.width - 28; height: 1
                        color: "#397f94a9"
                    }
                    TextInput {
                        id: query
                        anchors { left: parent.left; right: fetchButton.left; top: parent.top; bottom: parent.bottom; leftMargin: 15; rightMargin: 12 }
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
                        text: window.fetchSourceName + (window.fetchMode === "randomwall" ? " query" : " tags")
                        color: Theme.dim
                        font.pixelSize: 13
                        visible: query.text.length === 0 && !query.activeFocus
                    }
                    QuietButton {
                        id: fetchButton
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 128; height: 35; radius: 8
                        text: "Fetch " + window.fetchSourceName
                        enabled: !service.busy
                        Accessible.name: "Fetch using " + window.fetchSourceName
                        onClicked: window.fetch(window.fetchMode)
                    }
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
                GlassApplyButton {
                    id: applyButton
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
                    text: service.error || window.previewError || service.message || ""
                    font.pixelSize: 12
                }
            }
        }
    }
}
