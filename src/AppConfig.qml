pragma Singleton
import QtQuick
import Quickshell

QtObject {
    readonly property string picturesDirectory: Quickshell.env("WALLPICK_PICTURES_DIR") || (Quickshell.env("HOME") + "/Pictures")
    readonly property string cacheDirectory: Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")
    readonly property string walColorsPath: Quickshell.env("WALLPICK_WAL_COLORS") || (cacheDirectory + "/wal/colors.json")
    readonly property string pythonCommand: Quickshell.env("WALLPICK_PYTHON") || "python3"
    readonly property string backendPath: Quickshell.shellDir + "/../scripts/backend.py"
    readonly property string actionsPath: Quickshell.shellDir + "/../scripts/actions.py"
    readonly property bool reducedMotion: Quickshell.env("WALLPICK_REDUCED_MOTION") === "1"
    readonly property var sourceInfo: [
        { key: "recent", label: "Recent", hint: "Latest arrivals", command: "" },
        { key: "favorites", label: "Favorites", hint: "Saved for later", command: "" },
        { key: "anime", label: "Konachan", hint: "Anime · safe", command: "randomanime" },
        { key: "general", label: "Wallhaven", hint: "General · safe", command: "randomwall" },
        { key: "gooner", label: "Gooner", hint: "Questionable", command: "randomgooner" }
    ]
}
