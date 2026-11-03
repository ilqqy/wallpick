import QtQuick
import Quickshell
import Quickshell.Io
import "services"
import "components"

ShellRoot {
    DriftWallpaperSlider { id: slider; active: false }
    id: shell
    WallpaperService { id: service; onPreviewFailed: key => shell.failedPreviews = shell.failedPreviews.concat([key]) }
    property var failedPreviews: []
    Component.onCompleted: service.refresh()
    function previewResult(id) {
        return { key: "anime:danbooru_" + id, id: id, source: "anime", remote: true, previewFetch: true,
                 preview: "https://cdn.donmai.us/sample/" + id + ".jpg" }
    }
    IpcHandler {
        target: "wallpick-test"
        function refresh(): void { service.refresh() }
        function randomAnime(): void { service.random("randomanime", ["tag;literal", "-chibi"]) }
        function search(): void { service.search("anime", ["tag;literal", "-chibi"]) }
        function searchMore(): void { service.searchMore() }
        function supersede(): void { service.search("anime", ["first"]); service.search("general", ["second"]) }
        function clearSearch(): void { service.clearSearch() }
        function preview(id: string): void { service.fetchPreview(shell.previewResult(id)) }
        function supersedePreview(): void {
            service.fetchPreview(shell.previewResult("slow"))
            service.fetchPreview(shell.previewResult("8"))
        }
        function previewState(): string {
            return JSON.stringify({ cache: service.previewCache, failed: shell.failedPreviews,
                running: !!service.previewRequest, busy: service.busy })
        }
        function searchState(): string {
            return JSON.stringify({ searching: service.searching, error: service.searchError, source: service.resultsSource,
                page: service.resultsPage, more: service.resultsMore, keys: service.results.map(result => result.key),
                busy: service.busy })
        }
        function sliderRegression(): string {
            slider.items = Array.from({length: 10}, (_, i) => ({path: "w-" + i, url: ""}))
            const notch = {angleDelta: Qt.point(0, -15), pixelDelta: Qt.point(0, 0)}
            for (let i = 0; i < 7; i++) slider.wheelBy(notch)
            if (slider.activeIndex !== 0) return "high-resolution wheel stepped early"
            slider.wheelBy(notch)
            if (slider.activeIndex !== 1) return "high-resolution wheel did not step"
            const swipe = {angleDelta: Qt.point(0, -10), pixelDelta: Qt.point(0, -8)}
            for (let i = 0; i < 16; i++) slider.wheelBy(swipe)
            if (slider.activeIndex !== 3) return "touchpad scrolling is not distance based"
            slider.items = Array.from({length: 40}, (_, i) => ({path: "old-" + i, url: ""}))
            slider.goTo(39)
            slider.items = [{path: "new", url: ""}]
            if (slider.activeIndex !== 0 || slider.lastPath !== "new") return "short collection failed"
            slider.items = []
            slider.goTo(1)
            if (slider.activeIndex !== 0 || slider.lastPath !== "") return "empty collection failed"
            const page = Array.from({length: 6}, (_, i) => ({key: "anime:" + i, path: "", url: ""}))
            slider.items = page
            slider.goTo(4)
            slider.progress = 3.5
            slider.items = page.concat([{key: "anime:6", path: "", url: ""}])
            if (slider.activeIndex !== 4 || slider.lastPath !== "anime:4") return "appended page lost the selection"
            if (slider.progress !== 3.5) return "appended page interrupted the drift"
            return "PASS"
        }
        function state(): string {
            return JSON.stringify({ busy: service.busy, scanning: service.scanning,
                error: service.error, uncertain: service.currentUncertain, catalog: service.catalog })
        }
    }
}
