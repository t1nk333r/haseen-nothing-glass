import QtQuick

Item {
    id: spinner

    property bool running: true
    property color color: "#ffffff"
    property int tickCount: 12
    property real minAlpha: 0.15

    property int _phase: 0

    onRunningChanged: canvas.requestPaint()
    onColorChanged: canvas.requestPaint()
    onTickCountChanged: canvas.requestPaint()

    Timer {
        id: phaseTimer
        interval: Math.max(40, Math.round(1000 / spinner.tickCount))
        running: spinner.running && spinner.visible
        repeat: true
        onTriggered: {
            spinner._phase = (spinner._phase + 1) % spinner.tickCount
            canvas.requestPaint()
        }
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            if (!spinner.running) return

            var w = width
            var h = height
            var cx = w / 2
            var cy = h / 2
            var radius = Math.min(w, h) / 2
            var inner = radius * 0.45
            var outer = radius * 0.95
            var thickness = Math.max(1.5, radius * 0.16)
            var n = spinner.tickCount

            var baseColor = spinner.color
            var r = Math.round(baseColor.r * 255)
            var g = Math.round(baseColor.g * 255)
            var b = Math.round(baseColor.b * 255)

            ctx.lineCap = "round"
            ctx.lineWidth = thickness

            for (var i = 0; i < n; i++) {
                var lag = (n + spinner._phase - i) % n
                var alpha = Math.max(spinner.minAlpha, 1.0 - lag / n)
                var angle = (i / n) * Math.PI * 2 - Math.PI / 2
                var ca = Math.cos(angle)
                var sa = Math.sin(angle)
                ctx.strokeStyle = "rgba(" + r + "," + g + "," + b + "," + alpha + ")"
                ctx.beginPath()
                ctx.moveTo(cx + ca * inner, cy + sa * inner)
                ctx.lineTo(cx + ca * outer, cy + sa * outer)
                ctx.stroke()
            }
        }
    }
}
