import QtQuick
import Quickshell
import Quickshell.Io
import "components"

ShellRoot {
    InkBleedTitle { id: title; opened: false }
    IpcHandler {
        target: "wallpick-title-test"
        function open(): void { title.opened = true }
        function close(): void { title.opened = false }
        function reduced(): void { title.reducedMotion = true }
        function state(): string {
            return JSON.stringify({ opened: title.opened, animating: title.animating,
                entrances: title.entranceCount, reducedMotion: title.reducedMotion })
        }
    }
}
