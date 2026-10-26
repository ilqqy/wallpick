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

    // Search lists remote wallpapers; nothing is downloaded until one is
    // applied or favorited. It runs beside actions and never sets busy.
    property var results: []
    property string resultsSource: ""
    property var resultsWords: []
    property int resultsPage: 0
    property bool resultsMore: false
    property bool searching: false
    property string searchError: ""
    property var searchRequest: null
    property var pendingSearch: null
    property string searchOutput: ""

    signal actionFinished(string operation, bool success)
    signal searchFinished(bool success)

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

    function search(source, words) {
        if (!["anime", "general", "gooner"].includes(source))
            return false
        results = []
        resultsSource = source
        resultsWords = words
        resultsPage = 0
        resultsMore = false
        searchError = ""
        startSearch({ source: source, words: words, page: 1 })
        return true
    }

    function searchMore() {
        if (searching || !resultsMore || !resultsSource)
            return false
        startSearch({ source: resultsSource, words: resultsWords, page: resultsPage + 1 })
        return true
    }

    function clearSearch() {
        pendingSearch = null
        searchRequest = null
        searching = false
        if (searchProcess.running) searchProcess.running = false
        results = []
        resultsSource = ""
        resultsWords = []
        resultsPage = 0
        resultsMore = false
        searchError = ""
    }

    function startSearch(request) {
        searching = true
        // A newer search replaces one in flight; its output is discarded.
        if (searchProcess.running) {
            pendingSearch = request
            searchProcess.running = false
            return
        }
        pendingSearch = null
        searchRequest = request
        searchOutput = ""
        const argv = ["timeout", "--signal=TERM", "--kill-after=5s", "90s",
                      AppConfig.pythonCommand, AppConfig.actionsPath, "search", "--",
                      request.source, String(request.page)]
        for (const word of request.words)
            argv.push(word)
        searchProcess.exec(argv)
    }

    function applyResult(result) {
        if (!result || !result.remote)
            return false
        return run("apply-result", [result.source, result.id, result.full], "ApplyResult", "")
    }

    function favoriteResult(result) {
        if (!result || !result.remote)
            return false
        return run("favorite-result", [result.source, result.id, result.full], "FavoriteResult", "")
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
        id: searchProcess
        stdout: StdioCollector { onStreamFinished: service.searchOutput = text }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    console.warn("wallpick search:", text.trim())
            }
        }
        onExited: (exitCode, exitStatus) => {
            const request = service.searchRequest
            service.searchRequest = null
            if (service.pendingSearch) {
                Qt.callLater(() => { if (service.pendingSearch) service.startSearch(service.pendingSearch) })
                return
            }
            // Cleared while running: the output belongs to nobody.
            if (!request)
                return
            service.searching = false
            let parsed = null
            if (exitCode === 0) {
                try { parsed = JSON.parse(service.searchOutput) } catch (exception) { parsed = null }
            }
            if (!parsed || !Array.isArray(parsed.results)) {
                service.searchError = exitCode === 124 ? "The search timed out. Please try again."
                                    : "Search failed. Check the network or try other tags."
                service.searchFinished(false)
                return
            }
            // Pages can overlap when the source changes between requests.
            const seen = new Set(request.page === 1 ? [] : service.results.map(result => result.key))
            const added = parsed.results.filter(result => !seen.has(result.key) && seen.add(result.key))
            service.results = request.page === 1 ? added : service.results.concat(added)
            service.resultsPage = request.page
            service.resultsMore = !!parsed.more && added.length > 0
            service.searchError = ""
            service.searchFinished(true)
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
                service.message = completedOperation === "Apply" || completedOperation === "ApplyResult" ? "Wallpaper applied" :
                                  completedOperation === "Favorite" || completedOperation === "FavoriteResult" ? "Added to favorites" :
                                  "Random wallpaper fetched and applied"
                service.error = ""
            } else {
                service.error = exitCode === 124 ? "The request timed out. Please try again." :
                                completedOperation === "Apply" ? "Could not apply this wallpaper." :
                                completedOperation === "Favorite" ? "Could not save this favorite." :
                                completedOperation === "ApplyResult" ? "Could not download this wallpaper." :
                                completedOperation === "FavoriteResult" ? "Could not download this favorite." :
                                "Could not fetch a wallpaper. Try other tags or try again."
                console.warn("wallpick", completedOperation, "failed:", service.actionError, service.actionOutput)
            }
            service.refresh()
            service.actionFinished(completedOperation, exitCode === 0)
        }
    }
}
