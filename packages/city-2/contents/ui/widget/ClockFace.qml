import QtQuick

// City II clock face — the minimal-marks analog dial from clock-analog-2,
// parameterized for any size and per-city day/night theming.
//
// City II has no perimeter ring and no numerals: just 12 pill-shaped hour
// lines at the edge plus the hands. The same drawing is used at every size
// (the grid faces are simply scaled down), so there is no ringStyle switch —
// only the disc/mark colors change between the 1x1 (widget-themed) and grid
// (per-city day/night) uses.
//
// Colors are passed in (no MacOSColors dependency):
//   discColor / discVisible — the circular face plate
//   markColor               — base color for hour lines + hands (opaque)
//   markOpacity, handOpacity
//   secondColor             — second hand + hinge
//   showSeconds             — draw the sweeping second hand

Item {
    id: face

    readonly property real r:  Math.min(width, height) / 2
    readonly property real cx: width / 2
    readonly property real cy: height / 2

    property real hourAngle: 0
    property real minuteAngle: 0
    property real secondAngle: 0
    property bool showSeconds: true
    // Grid (2x2 / 4x2) faces set this so the second hand is drawn 2x thicker —
    // the hairline is nearly invisible at small grid sizes. 1x1 leaves it false.
    property bool thickSecond: false

    property color discColor: Qt.rgba(1, 1, 1, 0.20)
    property bool  discVisible: true
    property color markColor: "#ffffff"
    property real  markOpacity: 0.75
    property real  handOpacity: 0.92
    property color secondColor: "#F6A029"

    Rectangle {
        id: faceBackground
        width: Math.min(parent.width, parent.height)
        height: width
        anchors.centerIn: parent
        radius: width / 2
        visible: face.discVisible
        color: face.discColor
    }

    // --- 12 hour lines (pill-shaped) ---
    Canvas {
        id: tickCanvas
        anchors.fill: parent
        renderStrategy: Canvas.Immediate

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const cx = width / 2
            const cy = height / 2
            const r  = Math.min(width, height) / 2

            const tickW   = r * 0.020
            const tickLen = r * 0.09
            const outerR  = r - tickW * 2
            const innerR  = outerR - tickLen

            const lineW   = (r * 0.0336) * 0.9 * 1.15 * 1.35
            const minuteLen = (outerR + innerR) / 2
            const hourLen   = minuteLen * 0.65
            const lineLen   = hourLen * 0.40 * 0.90 * 1.10
            const hw        = lineW / 2

            ctx.fillStyle = Qt.rgba(face.markColor.r, face.markColor.g, face.markColor.b, face.markOpacity)
            ctx.save()
            ctx.translate(cx, cy)

            for (let i = 0; i < 12; i++) {
                const angle = i * 30 * Math.PI / 180
                ctx.save()
                ctx.rotate(angle)
                const x = -hw, y = -outerR, w = lineW, h = lineLen
                ctx.beginPath()
                ctx.moveTo(x + hw, y)
                ctx.arcTo(x + w, y,     x + w, y + h, hw)
                ctx.arcTo(x + w, y + h, x,     y + h, hw)
                ctx.arcTo(x,     y + h, x,     y,     hw)
                ctx.arcTo(x,     y,     x + w, y,     hw)
                ctx.closePath()
                ctx.fill()
                ctx.restore()
            }
            ctx.restore()
        }

        Connections {
            target: face
            function onMarkColorChanged()   { tickCanvas.requestPaint() }
            function onMarkOpacityChanged() { tickCanvas.requestPaint() }
        }
        onWidthChanged:  requestPaint()
        onHeightChanged: requestPaint()
    }

    function _drawHand(ctx, angleDeg, totalLen, stemEnd, stemW, pillW, color) {
        ctx.save()
        ctx.rotate(angleDeg * Math.PI / 180)
        ctx.fillStyle = color
        const sw2 = stemW / 2
        ctx.beginPath()
        ctx.rect(-sw2, -stemEnd, stemW, stemEnd)
        ctx.fill()
        const pw2 = pillW / 2
        const pr  = pw2
        const pillTop    = -totalLen + pr
        const pillBottom = -stemEnd  - pr
        ctx.beginPath()
        ctx.moveTo(pw2, pillBottom)
        ctx.lineTo(pw2, pillTop)
        ctx.arc(0, pillTop, pr, 0, Math.PI, true)
        ctx.lineTo(-pw2, pillBottom)
        ctx.arc(0, pillBottom, pr, Math.PI, 0, true)
        ctx.closePath()
        ctx.fill()
        ctx.restore()
    }

    Canvas {
        id: handsCanvas
        anchors.fill: parent
        z: 8
        renderStrategy: Canvas.Immediate

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const cx = width / 2
            const cy = height / 2
            const r  = Math.min(width, height) / 2
            ctx.save()
            ctx.translate(cx, cy)

            const handColor = Qt.rgba(face.markColor.r, face.markColor.g, face.markColor.b, face.handOpacity)
            const tickW   = r * 0.020
            const tickLen = r * 0.09
            const outerR  = r - tickW * 2
            const innerR  = outerR - tickLen
            const minuteLen = (outerR + innerR) / 2
            const hourLen   = minuteLen * 0.65

            face._drawHand(ctx, face.hourAngle,   hourLen,   r * 0.15, r * 0.0336, r * 0.065, handColor)
            face._drawHand(ctx, face.minuteAngle, minuteLen, r * 0.15, r * 0.0336, r * 0.065, handColor)

            ctx.beginPath()
            ctx.arc(0, 0, r * 0.050, 0, 2 * Math.PI)
            ctx.fillStyle = handColor
            ctx.fill()
            ctx.restore()
        }

        Connections {
            target: face
            function onHourAngleChanged()   { handsCanvas.requestPaint() }
            function onMinuteAngleChanged() { handsCanvas.requestPaint() }
            function onMarkColorChanged()   { handsCanvas.requestPaint() }
            function onHandOpacityChanged() { handsCanvas.requestPaint() }
        }
        onWidthChanged:  requestPaint()
        onHeightChanged: requestPaint()
    }

    Canvas {
        id: secondCanvas
        anchors.fill: parent
        z: 10
        visible: face.showSeconds
        renderStrategy: Canvas.Immediate

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (!face.showSeconds) return
            const cx = width / 2
            const cy = height / 2
            const r  = Math.min(width, height) / 2
            const tickW = r * 0.020
            const len   = r - tickW * 2
            const counterWeight = r * 0.15
            const hw    = r * 0.007 * (face.thickSecond ? 2 : 1)
            ctx.save()
            ctx.translate(cx, cy)
            ctx.rotate(face.secondAngle * Math.PI / 180)
            ctx.fillStyle = face.secondColor
            ctx.beginPath()
            ctx.rect(-hw, -len, hw * 2, len + counterWeight)
            ctx.fill()
            ctx.restore()
        }

        Connections {
            target: face
            function onSecondAngleChanged() { if (face.showSeconds) secondCanvas.requestPaint() }
            function onShowSecondsChanged() { secondCanvas.requestPaint() }
        }
        onWidthChanged:  requestPaint()
        onHeightChanged: requestPaint()
    }

    Canvas {
        id: hingeCanvas
        anchors.fill: parent
        z: 20
        renderStrategy: Canvas.Immediate

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const cx = width / 2
            const cy = height / 2
            const r  = Math.min(width, height) / 2
            ctx.save()
            ctx.translate(cx, cy)
            ctx.beginPath()
            ctx.arc(0, 0, r * 0.035, 0, 2 * Math.PI)
            ctx.fillStyle = face.showSeconds ? face.secondColor
                : Qt.rgba(face.markColor.r, face.markColor.g, face.markColor.b, face.handOpacity)
            ctx.fill()
            ctx.restore()
        }

        Connections {
            target: face
            function onShowSecondsChanged() { hingeCanvas.requestPaint() }
            function onMarkColorChanged()   { hingeCanvas.requestPaint() }
        }
        onWidthChanged:  requestPaint()
        onHeightChanged: requestPaint()
    }
}
