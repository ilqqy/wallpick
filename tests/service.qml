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
            return "PASS"
        }
        function state(): string {
            return JSON.stringify({ busy: service.busy, scanning: service.scanning,
                error: service.error, uncertain: service.currentUncertain, catalog: service.catalog })
        }
    }
}
