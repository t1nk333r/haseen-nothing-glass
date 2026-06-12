import QtQuick

// City I clock face — the analog dial extracted from clock-analog's main.qml,
// parameterized so it can render at any size and in two ring styles:
//
//   ringStyle "perimeter"     — 60 pill ticks + 12 hour numerals (the 1x1 face,
//                               identical to plain clock-analog).
//   ringStyle "numeralsOnly"  — no perimeter ticks; the 12 hour numerals sit at
//                               the 12 hour positions (the 2x2 / 4x2 grid face).
//
// Colors are passed in (no MacOSColors dependency) so the caller can drive
// per-city day/night theming on the disc independently of the widget chrome:
//   discColor     — the circular face plate behind the hands
//   discVisible   — whether to draw the plate at all
//   markColor     — base color for ticks / numerals / hands (an opaque color)
//   numeralOpacity, tickMajorOpacity, tickMinorOpacity, handOpacity
//
// Time comes in as angles (degrees). The second hand is optional and, when
// shown, reads `secondAngle` directly (driven at 60fps by the caller).

Item {
    id: face

    // --- Geometry ---
    readonly property real r:  Math.min(width, height) / 2
    readonly property real cx: width / 2
    readonly property real cy: height / 2

    // --- Time (degrees) ---
    property real hourAngle: 0
    property real minuteAngle: 0
    property real secondAngle: 0
    property bool showSeconds: true

    // --- Style ---
    property string ringStyle: "perimeter"   // or "numeralsOnly"
    property string fontFamily: ""

    // --- Colors (caller-supplied) ---
    property color discColor: Qt.rgba(1, 1, 1, 0.20)
    property bool  discVisible: true
    property color markColor: "#ffffff"
    property real  numeralOpacity: 0.85
    property real  tickMajorOpacity: 0.75
    property real  tickMinorOpacity: 0.30
    property real  handOpacity: 0.92
    property color secondColor: "#F6A029"

    readonly property bool _perimeter: ringStyle === "perimeter"

    // Circular face plate.
    Rectangle {
        id: faceBackground
        width: Math.min(parent.width, parent.height)
        height: width
        anchors.centerIn: parent
        radius: width / 2
        visible: face.discVisible
        color: face.discColor
    }

    // --- Perimeter ticks (1x1 only) ---
    Canvas {
        id: tickCanvas
        anchors.fill: parent
        visible: face._perimeter
        renderStrategy: Canvas.Immediate

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (!face._perimeter) return
            const cx = width / 2
            const cy = height / 2
            const r  = Math.min(width, height) / 2

            const tickW   = r * 0.020
            const tickLen = r * 0.09
            const hw      = tickW / 2
            const outerR  = r - tickW * 2
            const innerR  = outerR - tickLen

            ctx.save()
            ctx.translate(cx, cy)

            for (let i = 0; i < 60; i++) {
                const isMajor = (i % 5 === 0)
                const alpha   = isMajor ? face.tickMajorOpacity : face.tickMinorOpacity
                ctx.fillStyle = Qt.rgba(face.markColor.r, face.markColor.g, face.markColor.b, alpha)

                const angle = i * 6 * Math.PI / 180
                ctx.save()
                ctx.rotate(angle)

                const x = -hw, y = -outerR, w = tickW, h = tickLen
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

        onVisibleChanged: requestPaint()
        onWidthChanged:  requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: face
            function onMarkColorChanged() { tickCanvas.requestPaint() }
            function onTickMajorOpacityChanged() { tickCanvas.requestPaint() }
            function onTickMinorOpacityChanged() { tickCanvas.requestPaint() }
        }
    }

    // --- Hour numbers ---
    // Perimeter mode: dist 0.72r (original). Numerals-only: pushed near the
    // disc edge (where perimeter ticks would have been) at 0.80r.
    Repeater {
        model: 12
        delegate: Text {
            required property int index
            readonly property int num: index === 0 ? 12 : index
            readonly property real dist: face.r * (face._perimeter ? 0.72 : 0.80)
            readonly property real angle: (num / 12) * 2 * Math.PI
            x: face.cx + Math.sin(angle) * dist - width  / 2
            y: face.cy - Math.cos(angle) * dist - height / 2
            text: num.toString()
            font.family: face.fontFamily
            font.pixelSize: Math.max(8, face.r * 0.17)
            font.weight: Font.Medium
            color: face.markColor
            opacity: face.numeralOpacity
        }
    }

    // Thin stem from pivot, then a wider pill with fully rounded ends.
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

    // --- Hour + minute hands ---
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

    // --- Second hand (optional) ---
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
            // Grid faces (numeralsOnly) get a 2x thicker second hand — at small
            // grid sizes the r*0.007 hairline is nearly invisible. The 1x1
            // perimeter face keeps the original thin hand.
            const hw    = r * 0.007 * (face._perimeter ? 1 : 2)

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

    // --- Center hinge dot ---
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
