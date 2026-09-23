import QtQuick
import Quickshell.Io
import ".."

Item {
    id: service
    visible: false

    property var catalog: ({ sources: {}, current: null, appliedPath: "" })
    property bool scanning: false
    property bool busy: false
    property string operation: ""
    property string message: ""
    property string error: ""
    property string actionOutput: ""
    property string actionError: ""
    property string selectedForAction: ""
    property bool currentUncertain: false
    property var lastKnownImage: null
    property bool hasSeenCurrent: false
    property bool refreshPending: false

    signal actionFinished(string operation, bool success)

    function refresh() {
        if (scanProcess.running) {
            refreshPending = true
            return
        }
        refreshPending = false
        scanning = true
        scanProcess.exec([AppConfig.pythonCommand, AppConfig.backendPath, "scan"])
    }

    function run(command, args, label, selectedPath) {
        if (busy)
            return false
        busy = true
        error = ""
        message = ""
        operation = label
        selectedForAction = selectedPath || ""
        actionOutput = ""
        actionError = ""
        const argv = ["timeout", "--signal=TERM", "--kill-after=5s", "180s",
                      AppConfig.pythonCommand, AppConfig.actionsPath, command, "--"]
        for (let i = 0; i < args.length; ++i)
            argv.push(args[i])
        actionProcess.exec(argv)
        return true
    }

    function apply(path) {
        if (!path)
            return false
        return run("apply", [path], "Apply", path)
    }

    function random(command, words) {
        if (["randomanime", "randomwall", "randomgooner"].indexOf(command) < 0)
            return false
        return run(command, words, command, "")
    }

    function favoriteCurrent() {
        return run("favorite-current", [], "Favorite", "")
    }

    function favoriteSelected(path) {
        if (!path || busy)
            return false
        busy = true
        error = ""
        message = ""
        operation = "Favorite"
        selectedForAction = path
        actionOutput = ""
        actionError = ""
        actionProcess.exec([AppConfig.pythonCommand, AppConfig.backendPath, "favorite-selected", path])
        return true
    }

    Process {
        id: scanProcess
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text)
                    if (parsed.current) {
                        service.hasSeenCurrent = true
                        service.currentUncertain = false
                        let known = null
                        if (parsed.appliedPath) {
                            for (const key of ["favorites", "anime", "general", "gooner"]) {
                                const match = parsed.sources[key].items.find(item => item.path === parsed.appliedPath)
                                if (match) { known = match; break }
                            }
                        }
                        service.lastKnownImage = known
                    } else if (service.currentUncertain && service.lastKnownImage) {
                        parsed.current = Object.assign({}, service.lastKnownImage, { stale: true })
                    }
                    service.catalog = parsed
                    if (service.error.startsWith("Could not scan")) service.error = ""
                } catch (exception) {
                    service.error = "Could not read wallpaper folders"
                    console.warn("wallpick scan:", exception, text)
                }
                service.scanning = false
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    console.warn("wallpick scan:", text.trim())
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                service.scanning = false
                service.error = "Could not scan wallpaper folders"
            }
            if (service.refreshPending) Qt.callLater(service.refresh)
        }
    }

    Process {
        id: actionProcess
        stdout: StdioCollector { onStreamFinished: service.actionOutput = text }
        stderr: StdioCollector { onStreamFinished: service.actionError = text }
        onExited: (exitCode, exitStatus) => {
            const completedOperation = service.operation
            service.busy = false
            if (exitCode !== 0 && completedOperation.startsWith("random") && service.hasSeenCurrent)
                service.currentUncertain = true
            if (exitCode === 0) {
                service.message = completedOperation === "Apply" ? "Wallpaper applied" :
                                  completedOperation === "Favorite" ? "Added to favorites" :
                                  "Wallpaper fetched and applied"
                service.error = ""
            } else {
                service.error = exitCode === 124 ? "The request timed out. Please try again." :
                                completedOperation === "Apply" ? "Could not apply this wallpaper." :
                                completedOperation === "Favorite" ? "Could not save this favorite." :
                                "Could not fetch a wallpaper. Try other tags or try again."
                console.warn("wallpick", completedOperation, "failed:", service.actionError, service.actionOutput)
            }
            service.refresh()
            service.actionFinished(completedOperation, exitCode === 0)
        }
    }
}
