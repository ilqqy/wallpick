pragma Singleton
import QtQuick

QtObject {
    readonly property color background: "#cf0c141e"
    readonly property color panel: "#83202d3b"
    readonly property color panelRaised: "#ad2b3c4d"
    readonly property color panelPressed: "#c4172330"
    readonly property color cardBase: "#1d2a37"
    readonly property color scrim: "#b70b1119"
    readonly property color border: "#586e8296"
    readonly property color foreground: "#f0f2f4"
    readonly property color muted: "#a3aeb9"
    // Keeps placeholder text at 4.5:1 or better on the search field, even
    // when a bright desktop shows through the translucent popup.
    readonly property color dim: "#93a0ac"
    readonly property color accent: "#a6b6c9"
    readonly property color warm: "#d8b38a"
    readonly property color danger: "#e9a7a6"
    readonly property color success: "#abd4c3"
    readonly property color selectionText: "#0c141e"
    readonly property color primaryGlassTop: "#c05a7082"
    readonly property color primaryGlassMiddle: "#d13c5164"
    readonly property color primaryGlassBottom: "#df293c4f"
    readonly property color primaryGlassEdge: "#879eb1c1"
    readonly property int focusWidth: 2
    readonly property int radius: 18
    readonly property int fast: 160
    readonly property int normal: 320
}
