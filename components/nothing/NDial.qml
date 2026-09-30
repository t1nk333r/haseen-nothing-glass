import QtQuick

// A ring gauge: the geometric readout the style uses instead of a pie or a
// smooth arc. Ticks, not a sweep - the same segmentation idea as
// NProgress, wrapped round.
Canvas {
    id: dial
    required property var theme

    property real value: 0          // 0..1
    property int ticks: 60
    property int majorEvery: 5
    property bool accent: false

    onValueChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onTicksChanged: requestPaint()
    onMajorEveryChanged: requestPaint()
    onAccentChanged: requestPaint()

    // Canvas does not repaint on a bound property change, and `theme` is a
    // stable object whose colours are readonly properties: following the
    // desktop palette mutates it in place rather than replacing it, so each
    // colour the painter strokes with needs its own handler. One on `theme`
    // itself would only fire if the object were swapped.
    Connections {
        target: dial.theme
        function onRedChanged() { dial.requestPaint() }
        function onOnChanged() { dial.requestPaint() }
        function onOnFaintChanged() { dial.requestPaint() }
    }

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var side = Math.min(width, height)
        if (side <= 0) return

        var cx = width / 2
        var cy = height / 2
        var outer = side / 2
        var lit = Math.round(dial.ticks * Math.max(0, Math.min(1, dial.value)))

        for (var i = 0; i < dial.ticks; i++) {
            var major = (i % dial.majorEvery) === 0
            var len = side * (major ? 0.12 : 0.07)
            var a = -Math.PI / 2 + (i / dial.ticks) * Math.PI * 2

            ctx.strokeStyle = i < lit
                ? (dial.accent ? dial.theme.red : dial.theme.on)
                : dial.theme.onFaint
            ctx.lineWidth = Math.max(1, side * (major ? 0.016 : 0.010))
            ctx.beginPath()
            ctx.moveTo(cx + Math.cos(a) * (outer - len), cy + Math.sin(a) * (outer - len))
            ctx.lineTo(cx + Math.cos(a) * outer, cy + Math.sin(a) * outer)
            ctx.stroke()
        }
    }
}
