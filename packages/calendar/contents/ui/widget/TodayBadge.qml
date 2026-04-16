import QtQuick

// Filled circle with the day-number "punched out" so the backdrop
// (liquid glass → wallpaper) shows through the digit. Rendered as a
// single Canvas using destination-out composition, which produces a
// real alpha cut-out rather than just drawing a different color.
Item {
    id: root

    property int dayNumber: 1
    property real diameter: 40
    property color badgeColor: "#ff3b30"
    property string fontFamily: ""

    implicitWidth: diameter
    implicitHeight: diameter
    width: diameter
    height: diameter

    onDayNumberChanged: canvas.requestPaint()
    onBadgeColorChanged: canvas.requestPaint()
    onFontFamilyChanged: canvas.requestPaint()
    onDiameterChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()

            const w = width
            const h = height
            const cx = w / 2
            const cy = h / 2
            const r = Math.min(w, h) / 2

            // 1. Filled circle.
            ctx.fillStyle = root.badgeColor
            ctx.beginPath()
            ctx.arc(cx, cy, r, 0, Math.PI * 2)
            ctx.closePath()
            ctx.fill()

            // 2. Punch the digit out of the circle. "destination-out"
            //    keeps existing pixels only where the new shape is NOT
            //    drawn, so the digit becomes fully transparent.
            ctx.globalCompositeOperation = "destination-out"
            ctx.fillStyle = "#ffffff" // color doesn't matter, only alpha
            // Glyph height ≈ 56% of the badge diameter so digits fit
            // cleanly inside the circle with margin on all sides.
            const px = Math.round(r * 1.12)
            ctx.font = "400 " + px + "px \"" + root.fontFamily + "\""
            ctx.textAlign = "center"
            ctx.textBaseline = "middle"
            // SF Pro's "middle" baseline sits optically low — lift slightly.
            ctx.fillText(String(root.dayNumber), cx, cy + px * 0.04)

            ctx.globalCompositeOperation = "source-over"
        }
    }
}
