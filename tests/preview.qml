import QtQuick
import Quickshell
import Quickshell.Io
import "."

ShellRoot {
    QtObject {
        id: service
        property var catalog: ({sources: {}, current: null})
        property bool busy: false
        property bool scanning: false
        property bool currentUncertain: false
        property string error: ""
        property string message: ""
        property int applications: 0
        property string command: ""
        signal actionFinished(string operation, bool success)
        function refresh() {}
        function apply(path) { applications++ }
        function random(command, words) { service.command = command; return true }
    }
    WallpaperPopup { id: popup; service: service; Component.onCompleted: opened = true }
    IpcHandler {
        target: "wallpick-preview-test"
        function select(url: string): void {
            service.catalog = {sources: {recent: {exists: true, items: [
                {path: url, url: url, name: "Fixture", source: "recent", applied: false}
            ]}}, current: null}
        }
        function apply(): void { popup.apply() }
        function randomSource(key: string): void { popup.randomFromSource(key) }
        function localCollection(): void {
            service.catalog = {sources: {favorites: {exists: true, items: [
                {path: "one", url: "", name: "One", applied: false},
                {path: "two", url: "", name: "Two", applied: false}
            ]}}, current: null}
            popup.chooseSource("favorites")
            popup.selectIndex(0)
        }
        function state(): string {
            return JSON.stringify({error: popup.previewError, displayed: popup.displayedUrl, ready: popup.previewReady,
                selected: popup.selectedUrl, path: popup.selectedPath, command: service.command,
                applications: service.applications})
        }
    }
}
