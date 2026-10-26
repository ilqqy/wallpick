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
        property var results: []
        property string resultsSource: ""
        property var resultsWords: []
        property bool resultsMore: false
        property bool searching: false
        property string searchError: ""
        property string searched: ""
        property string resultAction: ""
        signal actionFinished(string operation, bool success)
        signal searchFinished(bool success)
        function refresh() {}
        function apply(path) { applications++ }
        function random(command, words) { service.command = command; return true }
        function search(source, words) {
            searched = source + ":" + words.join(" ")
            resultsSource = source
            resultsWords = words
            results = [
                {key: source + ":1", id: "1", stem: "konachan_1", source: source, name: "Remote one", url: "", preview: "", full: "https://konachan.net/image/1.png"},
                {key: source + ":2", id: "2", stem: "konachan_2", source: source, name: "Saved two", url: "", preview: "", full: "https://konachan.net/image/2.png"}
            ]
            searchFinished(true)
            return true
        }
        function searchMore() { return false }
        function clearSearch() { results = []; resultsSource = "" }
        function applyResult(result) { resultAction = "apply:" + result.key; return true }
        function favoriteResult(result) { resultAction = "favorite:" + result.key; return true }
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
        function favorite(): void { popup.favorite() }
        function randomSource(key: string): void { popup.randomFromSource(key) }
        function localCollection(): void {
            service.catalog = {sources: {favorites: {exists: true, items: [
                {path: "one", url: "", name: "One", applied: false},
                {path: "two", url: "", name: "Two", applied: false}
            ]}}, current: null}
            popup.chooseSource("favorites")
            popup.selectIndex(0)
        }
        // "Saved two" was downloaded earlier, so it must be treated as local.
        function searchResults(): void {
            service.catalog = {sources: {anime: {exists: true, items: [
                {path: "/saved/konachan_2.png", url: "", name: "konachan_2.png", applied: true}
            ]}}, current: null}
            popup.searchFor("anime", "bleach -chibi")
        }
        function closeResults(): void { popup.closeResults(false) }
        function selectIndex(index: int): void { popup.selectIndex(index) }
        function state(): string {
            const item = popup.selectedItem
            return JSON.stringify({error: popup.previewError, displayed: popup.displayedUrl, ready: popup.previewReady,
                selected: popup.selectedUrl, path: popup.selectedPath, command: service.command,
                applications: service.applications, showing: popup.showingResults, source: popup.sourceKey,
                searched: service.searched, resultAction: service.resultAction, remote: popup.selectedRemote,
                key: item ? item.key || item.path : "", applied: item ? !!item.applied : false})
        }
    }
}
