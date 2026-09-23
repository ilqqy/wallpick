//@ pragma ShellId wallpick
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "."
import "services"

ShellRoot {
    id: root
    property bool opened: false
    property bool openRequested: false
    property int openGeneration: 0
    property int queryGeneration: 0

    function targetScreen() {
        const screens = Quickshell.screens
        if (!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE"))
            return screens.length ? screens[0] : null
        const monitor = Hyprland.focusedMonitor
        for (let i = 0; i < screens.length; ++i) {
            const mapped = Hyprland.monitorFor(screens[i])
            if (monitor && mapped && mapped.name === monitor.name)
                return screens[i]
        }
        return screens.length ? screens[0] : null
    }
    function finishOpen(output) {
        if (!openRequested) return
        let screen = targetScreen()
        try {
            const cursor = JSON.parse(output)
            const monitor = Hyprland.monitors.values.find(m => cursor.x >= m.x && cursor.x < m.x + m.width && cursor.y >= m.y && cursor.y < m.y + m.height)
            if (monitor) {
                const match = Quickshell.screens.find(s => s.name === monitor.name)
                if (match) screen = match
            }
        } catch (error) { /* Use the focused monitor if the cursor query fails. */ }
        popup.screen = screen
        openRequested = false
        opened = true
    }
    function open() {
        if (opened || openRequested) return
        openRequested = true
        openGeneration++
        if (!cursorQuery.running)
            queryCursor()
    }
    function queryCursor() {
        queryGeneration = openGeneration
        if (!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")) {
            finishOpen("")
            return
        }
        cursorFallback.restart()
        cursorQuery.exec([AppConfig.pythonCommand, AppConfig.backendPath, "cursor"])
    }
    // Let an outstanding query finish. Killing and immediately restarting it
    // lets the old exit callback resolve a newer open request on the wrong screen.
    function close() { openRequested = false; opened = false }
    function toggle() { if (opened || openRequested) close(); else open() }

    Timer {
        id: cursorFallback
        interval: 750
        onTriggered: { if (root.openRequested) root.finishOpen("") }
    }

    Process {
        id: cursorQuery
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.queryGeneration === root.openGeneration) root.finishOpen(text)
            }
        }
        onExited: (code, status) => {
            if (!root.openRequested) return
            if (root.queryGeneration !== root.openGeneration) root.queryCursor()
            else if (code !== 0) root.finishOpen("")
        }
    }

    WallpaperService { id: wallpapers }

    WallpaperPopup {
        id: popup
        service: wallpapers
        opened: root.opened
        onRequestClose: root.close()
    }

    IpcHandler {
        target: "wallpick"
        function open(): void { root.open() }
        function close(): void { root.close() }
        function toggle(): void { root.toggle() }
        function status(): string { return root.opened || root.openRequested ? "open" : "closed" }
        function operationStatus(): string { return JSON.stringify({ busy: wallpapers.busy, operation: wallpapers.operation, error: wallpapers.error, message: wallpapers.message }) }
        function refresh(): void { wallpapers.refresh() }
        function selectSource(key: string): void { popup.chooseSource(key) }
        function selectIndex(index: int): void { popup.selectIndex(index) }
        function selectedPath(): string { return popup.selectedPath }
        function applySelected(): void { popup.apply() }
        function favoriteSelected(): void { popup.favorite() }
        function randomAnime(): void { wallpapers.random("randomanime", []) }
        function randomSource(key: string): void { popup.randomFromSource(key) }
        function randomWall(): void { wallpapers.random("randomwall", []) }
        function randomGooner(): void { wallpapers.random("randomgooner", []) }
    }
}
