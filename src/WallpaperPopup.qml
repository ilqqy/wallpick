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
    readonly property string fetchSourceName: commandLabel(fetchMode) || "Konachan"
    readonly property string busyOperation: service && service.busy ? String(service.operation || "") : ""
    readonly property string busyLabel: busyOperation === "" ? ""
        : busyOperation === "Apply" ? "Applying wallpaper…"
        : busyOperation === "Favorite" ? "Saving to favorites…"
        : commandLabel(busyOperation) ? "Fetching from " + commandLabel(busyOperation) + "…"
        : "Working…"
    readonly property string heroPlaceholder: previewError ? previewError
        : !gallery.selectedItem ? (service.scanning ? "Loading your wallpapers…" : "Choose a collection or fetch a new wallpaper")
        : heroImage.status === Image.Loading && !displayedUrl ? "Loading preview…"
        : ""
    // Logical screen size; the popup shrinks on short or scaled outputs so the
    // action row never ends up off-screen.
    readonly property int screenWidth: screen ? screen.width : 1920
    readonly property int screenHeight: screen ? screen.height : 1080
    property bool opened: false
    signal requestClose()

    visible: opened
    implicitWidth: Math.min(910, screenWidth - margins.right - 18)
    implicitHeight: Math.min(890, screenHeight - margins.top - 12)
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
    function sourceCount(key) { return sourceItems(key).length }
    function commandLabel(command) {
        const info = AppConfig.sourceInfo.find(source => source.command && source.command === command)
        return info ? info.label : ""
    }
    // viaKeyboard decides whether the gallery shows its focus ring after the switch.
    function chooseSource(key, viaKeyboard) {
        if (!AppConfig.sourceInfo.some(info => info.key === key))
            return
        sourceKey = key
        if (key === "anime") fetchMode = "randomanime"
        else if (key === "general") fetchMode = "randomwall"
        else if (key === "gooner") fetchMode = "randomgooner"
        gallery.pointerFocus = !viaKeyboard
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
    function randomFromSource(key, viaKeyboard) {
        const info = AppConfig.sourceInfo.find(source => source.key === key)
        if (!info || service.busy) return
        if (info.command) {
            fetch(info.command)
            return
        }
        if (!sourceItems(key).length) return
        chooseSource(key, viaKeyboard)
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
        // Success feedback is transient; errors stay until the next action.
        function onMessageChanged() {
            if (window.service.message) messageTimer.restart()
        }
    }

    Timer {
        id: messageTimer
        interval: 4000
        onTriggered: if (!window.service.busy) window.service.message = ""
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
            else if (event.key === Qt.Key_R) { window.randomFromSource(window.sourceKey, true); event.accepted = true }
        }

        Item {
            id: content
            // Header, sources and actions keep their size; the preview and the
            // gallery share whatever height the screen leaves.
            readonly property real mediaHeight: height - header.height - sources.height - bottom.height - 43
            anchors.fill: parent
            anchors.margins: 20

            Item {
                id: header
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 63
                InkBleedTitle { id: title; x: 20; y: -2; text: "Wallpick"; opened: window.opened }
                QuietButton {
                    id: closeButton
                    anchors.right: parent.right
                    y: Math.round(title.y + title.capCenterY - height / 2)
                    width: 30; height: 30; radius: 15
                    text: "×"
                    Accessible.name: "Close"
                    onClicked: window.requestClose()
                }
            }

            Rectangle {
                id: hero
                anchors.top: header.bottom
                anchors.topMargin: 10
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: sources.top
                anchors.bottomMargin: 13
                radius: 16
                color: "#a014202c"
                border.color: "#8492a8b9"
                Accessible.role: Accessible.Graphic
                Accessible.name: gallery.selectedItem && !window.previewError ? "Preview of " + gallery.selectedItem.name : window.heroPlaceholder

                RoundedClip {
                    anchors.fill: parent
                    anchors.margins: 4
                    radius: hero.radius - 4

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
                        height: 54
                        gradient: Gradient {
                            GradientStop { position: 0; color: "#00070c13" }
                            GradientStop { position: 1; color: "#55070c13" }
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    width: parent.width - 48
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    visible: text !== ""
                    text: window.heroPlaceholder
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
                    // Without an image there is nothing meaningful to badge.
                    visible: !!service.catalog.current && currentThumb.status !== Image.Error
                    Accessible.role: Accessible.Graphic
                    Accessible.name: service.currentUncertain ? "Last known desktop wallpaper" : "Current desktop wallpaper"

                    RoundedClip {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: 6

                        Image {
                            id: currentThumb
                            anchors.fill: parent
                            source: service.catalog.current ? service.catalog.current.url : ""
                            sourceSize.width: 240
                            sourceSize.height: 140
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                        }
                        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 20; color: Theme.scrim }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 3
                            text: service.currentUncertain ? "LAST KNOWN" : "CURRENT"
                            color: "white"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.4
                        }
                    }
                }
            }

            Row {
                id: sources
                anchors.bottom: gallery.top
                anchors.bottomMargin: 12
                anchors.left: parent.left
                width: parent.width
                height: 111
                spacing: 9
                // Source tooltips open downwards over the gallery's top edge.
                z: 2
                Repeater {
                    model: AppConfig.sourceInfo
                    delegate: FolderSourceCard {
                        width: (sources.width - (AppConfig.sourceInfo.length - 1) * sources.spacing) / AppConfig.sourceInfo.length
                        height: 105
                        title: modelData.label
                        hint: modelData.hint
                        count: window.sourceCount(modelData.key)
                        previews: window.sourceItems(modelData.key)
                        selected: window.sourceKey === modelData.key
                        remote: !!modelData.command
                        randomEnabled: !service.busy && (!!modelData.command || window.sourceCount(modelData.key) > 0)
                        onClicked: window.chooseSource(modelData.key, keyboardActivation)
                        onRandomClicked: window.randomFromSource(modelData.key, keyboardActivation)
                    }
                }
            }

            DriftWallpaperSlider {
                id: gallery
                active: window.opened
                loading: service.scanning
                anchors.bottom: bottom.top
                anchors.bottomMargin: 8
                anchors.left: parent.left
                anchors.right: parent.right
                height: Math.round(Math.max(170, Math.min(220, content.mediaHeight * 0.42)))
                items: window.sourceItems(window.sourceKey)
            }

            Item {
                id: bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 105

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
                    // The whole field, padding included, focuses the input.
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.IBeamCursor
                        onPressed: query.forceActiveFocus()
                    }
                    TextInput {
                        id: query
                        anchors { left: parent.left; right: fetchButton.left; top: parent.top; bottom: parent.bottom; leftMargin: 15; rightMargin: 12 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.foreground
                        selectionColor: Theme.accent
                        selectedTextColor: Theme.selectionText
                        font.pixelSize: 13
                        clip: true
                        activeFocusOnTab: true
                        Accessible.role: Accessible.EditableText
                        Accessible.name: placeholder.text
                        Accessible.description: "Press Enter to fetch a wallpaper"
                        onAccepted: window.fetch(window.fetchMode)
                    }
                    Text {
                        id: placeholder
                        anchors.fill: query
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: window.fetchSourceName + (window.fetchMode === "randomwall" ? " query" : " tags")
                        color: Theme.dim
                        font.pixelSize: 13
                        visible: !query.text && !query.preeditText
                    }
                    QuietButton {
                        id: fetchButton
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 128; height: 35; radius: 8
                        text: window.busyOperation.startsWith("random") ? "Fetching…" : "Fetch " + window.fetchSourceName
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
                    Accessible.name: "Favorite"
                    Accessible.description: "Save the selected wallpaper to favorites"
                    onClicked: window.favorite()
                }
                GlassApplyButton {
                    id: applyButton
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    width: 171
                    height: 43
                    text: window.busyOperation === "Apply" ? "Applying…" : "Apply wallpaper"
                    enabled: !!window.selectedPath && !service.busy && window.previewReady
                    reducedMotion: AppConfig.reducedMotion
                    onClicked: window.apply()
                }
                Item {
                    anchors.left: parent.left
                    anchors.right: favoriteButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: applyButton.verticalCenter
                    height: 31

                    Rectangle {
                        id: activityDot
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6; height: 6; radius: 3
                        color: Theme.accent
                        visible: !!service.busy
                        SequentialAnimation on opacity {
                            running: activityDot.visible && window.opened && !AppConfig.reducedMotion
                            loops: Animation.Infinite
                            NumberAnimation { from: 1; to: 0.25; duration: 650; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 0.25; to: 1; duration: 650; easing.type: Easing.InOutSine }
                        }
                    }
                    Text {
                        anchors.left: activityDot.visible ? activityDot.right : parent.left
                        anchors.leftMargin: activityDot.visible ? 9 : 0
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        color: service.busy ? Theme.muted : service.error ? Theme.danger : service.message ? Theme.success : Theme.muted
                        text: window.busyLabel || service.error || service.message || ""
                        font.pixelSize: 12
                        Accessible.role: service.error ? Accessible.AlertMessage : Accessible.StaticText
                        Accessible.name: text
                    }
                }
            }
        }
    }
}
