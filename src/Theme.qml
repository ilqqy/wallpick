pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The palette follows pywal and updates live whenever wal rewrites
// colors.json. Every surface is derived from the wal background, foreground
// and accent; without a palette the original slate theme is used.
Singleton {
    id: root

    property var wal: ({})

    function walColor(section, key, fallback) {
        const group = wal && wal[section]
        const value = group && group[key]
        return typeof value === "string" && /^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(value) ? value : fallback
    }
    function reloadPalette() {
        try {
            const parsed = JSON.parse(colorsFile.text())
            if (parsed && typeof parsed === "object") wal = parsed
        } catch (error) {
            // wal rewrites the file in place; keep the last complete palette.
        }
    }
    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
    }
    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    // The background tinted toward the accent: t = 0 is the background, 1 the tint.
    function tone(t, a) { return alpha(mix(base, tint, t), a === undefined ? 1 : a) }
    function over(top, bottom) {
        return Qt.rgba(top.r * top.a + bottom.r * (1 - top.a), top.g * top.a + bottom.g * (1 - top.a),
                       top.b * top.a + bottom.b * (1 - top.a), 1)
    }
    function luminance(c) {
        const channel = v => v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
        return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
    }
    function contrast(a, b) {
        const x = luminance(a), y = luminance(b)
        return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05)
    }
    // Pushes c away from the surface until text reaches the WCAG ratio; wal's
    // greys are not guaranteed to have enough contrast on their own.
    function readable(c, surface, ratio) {
        const extreme = luminance(surface) > 0.18 ? Qt.rgba(0, 0, 0, 1) : Qt.rgba(1, 1, 1, 1)
        let result = alpha(c, 1)
        for (let t = 0.1; contrast(result, surface) < ratio && t < 1.05; t += 0.1)
            result = mix(c, extreme, Math.min(t, 1))
        return result
    }

    FileView {
        id: colorsFile
        path: AppConfig.walColorsPath
        preload: true
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.reloadPalette()
    }

    Component.onCompleted: reloadPalette()

    readonly property color base: walColor("special", "background", "#0c141e")
    readonly property color foreground: walColor("special", "foreground", "#f0f2f4")
    // Same accent slot as the rest of the desktop's Quickshell widgets.
    readonly property color accent: walColor("colors", "color5", "#a6b6c9")
    // Surfaces use a calmer accent so the wallpapers keep most of the colour.
    readonly property color tint: accent.hslSaturation > 0
        ? Qt.hsla(accent.hslHue, accent.hslSaturation * 0.6, accent.hslLightness, 1) : accent
    readonly property color warm: walColor("colors", "color1", "#d8b38a")

    // Worst case for text: the translucent popup over a white desktop.
    readonly property color brightBackdrop: over(background, Qt.rgba(1, 1, 1, 1))

    readonly property color background: alpha(base, 0.81)
    readonly property color panel: tone(0.13, 0.51)
    readonly property color panelRaised: tone(0.2, 0.68)
    readonly property color panelPressed: tone(0.06, 0.77)
    readonly property color field: tone(0.1, 0.63)
    readonly property color well: tone(0.05, 0.63)
    readonly property color stage: tone(0.05, 0.47)
    readonly property color fade: tone(0.05, 0.54)
    readonly property color cardBase: tone(0.11)
    readonly property color popover: alpha(base, 0.94)
    readonly property color scrim: alpha(base, 0.72)
    readonly property color shade: alpha(mix(base, Qt.rgba(0, 0, 0, 1), 0.4), 0.33)
    readonly property color glow: alpha(tint, 0.12)

    readonly property color border: tone(0.6, 0.35)
    readonly property color edge: tone(0.82, 0.5)
    readonly property color sheen: tone(0.72, 0.24)
    readonly property color sheenStrong: alpha(mix(tint, foreground, 0.35), 0.42)
    readonly property color selectedEdge: alpha(mix(tint, foreground, 0.3), 0.75)
    readonly property color focusEdge: alpha(mix(accent, foreground, 0.5), 0.7)

    readonly property color folder: tone(0.13)
    readonly property color folderSelected: tone(0.24)
    readonly property color folderGlow: tone(0.45)
    readonly property color pocket: tone(0.19)
    readonly property color pocketSelected: tone(0.3)
    readonly property color sheet: tone(0.3)
    readonly property color control: tone(0.16)
    readonly property color controlHover: tone(0.37)
    readonly property color controlPressed: tone(0.46)

    readonly property color muted: readable(mix(foreground, base, 0.3), brightBackdrop, 4.5)
    // Placeholder text: at least 4.5:1 on the search field even over a bright desktop.
    readonly property color dim: readable(mix(foreground, base, 0.42), over(field, brightBackdrop), 4.5)
    readonly property color danger: "#e9a7a6"
    readonly property color success: "#abd4c3"
    readonly property color selectionText: readable(base, accent, 4.5)

    readonly property color primaryGlassTop: tone(0.5, 0.75)
    readonly property color primaryGlassMiddle: tone(0.31, 0.82)
    readonly property color primaryGlassBottom: tone(0.19, 0.87)
    readonly property color primaryGlassEdge: alpha(mix(base, tint, 0.92), 0.53)
    readonly property color primaryGlassEdgeHover: alpha(mix(tint, foreground, 0.4), 0.68)
    readonly property color primaryGlassSheen: alpha(mix(tint, foreground, 0.7), 0.2)
    readonly property color primaryGlassLine: alpha(mix(tint, foreground, 0.55), 0.5)
    readonly property color primaryGlassFloor: tone(0.33, 0.14)
    readonly property color primaryGlassText: readable(foreground, over(primaryGlassMiddle, base), 4.5)

    readonly property int focusWidth: 2
    readonly property int radius: 18
    readonly property int fast: 160
    readonly property int normal: 320
}
