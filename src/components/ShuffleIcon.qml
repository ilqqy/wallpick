import QtQuick
import ".."

Canvas {
    id: icon
    property color stroke: Theme.foreground
    width: 17; height: 17
    onStrokeChanged: requestPaint()
    onPaint: {
        const c = getContext("2d")
        c.clearRect(0, 0, width, height)
        c.lineWidth = 1.55
        c.lineCap = "round"
        c.lineJoin = "round"
        c.strokeStyle = stroke
        c.beginPath()
        c.moveTo(2, 4); c.lineTo(4, 4); c.bezierCurveTo(7, 4, 9, 13, 13, 13); c.lineTo(15, 13)
        c.moveTo(12.5, 10.5); c.lineTo(15, 13); c.lineTo(12.5, 15.5)
        c.moveTo(2, 13); c.lineTo(4, 13); c.bezierCurveTo(7, 13, 9, 4, 13, 4); c.lineTo(15, 4)
        c.moveTo(12.5, 1.5); c.lineTo(15, 4); c.lineTo(12.5, 6.5)
        c.stroke()
    }
}
