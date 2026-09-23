import QtQuick
import Quickshell
import Quickshell.Io
import "services"
import "components"

ShellRoot {
    DriftWallpaperSlider { id: slider; active: false }
    WallpaperService { id: service }
    Component.onCompleted: service.refresh()
    IpcHandler {
        target: "wallpick-test"
        function refresh(): void { service.refresh() }
        function randomAnime(): void { service.random("randomanime", ["tag;literal", "-chibi"]) }
        function sliderRegression(): string {
            slider.items = Array.from({length: 40}, (_, i) => ({path: "old-" + i, url: ""}))
            slider.goTo(39)
            slider.items = [{path: "new", url: ""}]
            if (slider.activeIndex !== 0 || slider.lastPath !== "new") return "short collection failed"
            slider.items = []
            slider.goTo(1)
            if (slider.activeIndex !== 0 || slider.lastPath !== "") return "empty collection failed"
            return "PASS"
        }
        function state(): string {
            return JSON.stringify({ busy: service.busy, scanning: service.scanning,
                error: service.error, uncertain: service.currentUncertain, catalog: service.catalog })
        }
    }
}
