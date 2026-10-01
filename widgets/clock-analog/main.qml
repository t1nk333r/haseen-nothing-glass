import QtQuick
import "../../components"

Item {
    id: full
    anchors.fill: parent

    MacOSColors {
        id: colors
        styleMode: plugin.settings.styleMode
        appearance: plugin.settings.appearance
        systemBackground: theme.systemBackground
        themePalette: theme.palette
    }

    // The tick ink has to invert with whatever end of the palette the plate
    // took, and `colors.dialPlate` picks that end by `colors.isLight` — which
    // follows the THEME's own polarity in styleMode 2/3 and the appearance
    // setting in 0/1. `colors.dialMark` is that same pick, so the ink reads it
    // rather than spelling the branch out. Keying it off
    // `plugin.settings.appearance` instead left modes 2/3 on the night mark
    // whatever the theme said, so a themed light desktop drew white ticks on
    // the white `dialPlateDay` disc: measured 1.00:1 and 132 px of ink in the
    // tick annulus, against ~3 600 px and 4.0–7.1:1 in every other mode.
    readonly property color _dialColor: colors.dialMark

    property real _secondAngle: 0
    property real _minuteAngle: 0
    property real _hourAngle: 0

    // Fail open: if the compositor's style module is missing, `item` is null
    // and the clock animates. See components/MotionWatch.qml.
    Loader { id: motionWatch; source: "../../components/MotionWatch.qml" }

    readonly property bool _reducedMotion: motionWatch.item
        ? motionWatch.item.reduceMotion : false

    // Tick by default: one repaint a second instead of ~62, and the motion
    // the Nothing twin next door has always drawn. The sweep setting turns
    // the free-running sweep back on; the compositor's reduced-motion
    // preference overrides it.
    readonly property bool _tick: !plugin.settings.analogSecondSweep
        || _reducedMotion

    Timer {
        id: frameTimer
        interval: 16
        repeat: true
        running: !full._tick && full.visible
        onTriggered: {
            const now = Date.now()
            const d = new Date(now)
            const sec = d.getSeconds() + d.getMilliseconds() / 1000
            const min = d.getMinutes() + sec / 60
            const hr  = (d.getHours() % 12) + min / 60
            full._secondAngle = sec / 60 * 360
            full._minuteAngle = min / 60 * 360
            full._hourAngle   = hr / 12 * 360
        }
        Component.onCompleted: triggered()
    }

    // The tick, copied from the Nothing twin: a one-shot timer that re-aligns
    // itself to the wall second on every fire, so the hand lands ON the
    // second instead of drifting up to a second out of phase. The minute and
    // hour hands step with it, one repaint a second.
    Timer {
        id: secondTick
        interval: Math.max(50, 1000 - (Date.now() % 1000))
        repeat: false
        running: full._tick
        onTriggered: {
            const n = new Date()
            const sec = n.getSeconds() + n.getMilliseconds() / 1000
            const min = n.getMinutes() + sec / 60
            const hr  = (n.getHours() % 12) + min / 60
            full._stepSecond(n.getSeconds())
            full._minuteAngle = min / 60 * 360
            full._hourAngle   = hr / 12 * 360
            secondTick.interval = Math.max(50, 1000 - (Date.now() % 1000))
            secondTick.restart()
        }
    }

    property bool _primed: false

    // The step lands with the twin's 140 ms OutBack overshoot (below). The
    // first value and second 0 are ASSIGNED, not animated: every angle is 0 at
    // load, and 354 -> 0 animated goes the long way round.
    function _stepSecond(sec) {
        const to = sec / 60 * 360
        if (sec === 0 || !full._primed) {
            full._secondAngle = to
            full._primed = true
            return
        }
        secondStep.stop()
        secondStep.from = full._secondAngle
        secondStep.to = to
        secondStep.restart()
    }

    NumberAnimation {
        id: secondStep
        target: full; property: "_secondAngle"; duration: 140
        easing.type: Easing.OutBack; easing.overshoot: 2.4
    }

    LiquidGlass {
        id: glass
        anchors.fill: parent
        wallpaperItem: backdrop.item
        radius: plugin.settings.cornerRadius
        roundness: plugin.settings.roundness
        refractThickness: plugin.settings.refractThickness
        refractIOR: plugin.settings.refractIOR
        refractScale: plugin.settings.refractScale
        tint: colors.glassTint
        tintAlpha: plugin.settings.tintAlpha
        chromaStrength: plugin.settings.chromaStrength
        specStrength: plugin.settings.specStrength
        blurRadius: plugin.settings.blurRadiusPx
        realtimeRefraction: plugin.settings.realtimeRefraction
        fallbackOpacity: colors.glassFallbackOpacity
        // Solid style keeps the glass material as the background squircle
        // by default; only "Fully opaque background" reverts to a flat fill.
        solidMode: colors.isSolid && plugin.settings.opaqueBackground
        // Opaque card is always the dark fill, even in light mode.
        solidColor: colors.solidBackground
    }

    // Clock face area inset from the glass squircle edge
    Item {
        id: face
        anchors.fill: parent
        anchors.margins: Math.min(full.width, full.height) * 0.08

        readonly property real r: Math.min(width, height) / 2
        readonly property real cx: width / 2
        readonly property real cy: height / 2

        Rectangle {
            id: faceBackground
            width: Math.min(parent.width, parent.height)
            height: width
            anchors.centerIn: parent
            radius: width / 2
            // Solid style: the clock plate is always a solid opaque circle
            // (white in light, #343436 in dark) — it does NOT go translucent
            // when the background squircle is set to the glass material.
            // Glass style keeps the original translucent disc.
            color: colors.dialPlate
        }

        // --- Tick marks (pill-shaped, uniform width) ---
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
                const hw      = tickW / 2
                const outerR  = r - tickW * 2   // gap from circle = 2x tick width
                const innerR  = outerR - tickLen

                ctx.save()
                ctx.translate(cx, cy)

                for (let i = 0; i < 60; i++) {
                    const isMajor = (i % 5 === 0)
                    const alpha   = isMajor ? 0.75 : 0.30
                    // Dial ticks track real light/dark (black on light,
                    // white on dark) in every style, glass included.
                    ctx.fillStyle = Qt.rgba(
                        full._dialColor.r,
                        full._dialColor.g,
                        full._dialColor.b,
                        alpha
                    )

                    const angle = i * 6 * Math.PI / 180

                    ctx.save()
                    ctx.rotate(angle)

                    // Pill-shaped tick: rounded rect along the radial axis
                    const x = -hw
                    const y = -outerR
                    const w = tickW
                    const h = tickLen
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
                target: full
                function on_DialColorChanged() { tickCanvas.requestPaint() }
            }

            onWidthChanged:  requestPaint()
            onHeightChanged: requestPaint()
        }

        // --- Hour numbers ---
        Repeater {
            model: 12

            delegate: Text {
                id: numLabel
                textFormat: Text.PlainText
                required property int index
                readonly property int num: index === 0 ? 12 : index
                readonly property real dist: face.r * 0.72
                readonly property real angle: (num / 12) * 2 * Math.PI
                x: face.cx + Math.sin(angle) * dist - width  / 2
                y: face.cy - Math.cos(angle) * dist - height / 2
                text: num.toString()
                font.family: colors.uiFont
                font.pixelSize: Math.max(8, face.r * 0.17)
                font.weight: Font.Medium
                color: colors.foreground
                opacity: colors.dialNumeralOpacity
            }
        }

        // Thin stem from pivot, then a wider pill with fully rounded ends.
        function _drawHand(ctx, angleDeg, totalLen, stemEnd, stemW, pillW, color) {
            ctx.save()
            ctx.rotate(angleDeg * Math.PI / 180)
            ctx.fillStyle = color

            const sw2 = stemW / 2

            // Stem: rect from center, hidden behind pivot circle at base
            ctx.beginPath()
            ctx.rect(-sw2, -stemEnd, stemW, stemEnd)
            ctx.fill()

            // Pill: fully rounded capsule from -stemEnd to -totalLen
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

        // --- All hands drawn in a single canvas to avoid per-canvas rotation mess ---
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

                const handColor = Qt.rgba(
                    colors.foreground.r, colors.foreground.g, colors.foreground.b,
                    colors.dialHandOpacity
                )

                const tickW   = r * 0.020
                const tickLen = r * 0.09
                const outerR  = r - tickW * 2
                const innerR  = outerR - tickLen

                const minuteLen = (outerR + innerR) / 2  // midpoint of perimeter
                const hourLen   = minuteLen * 0.65

                // Hour hand
                face._drawHand(ctx, full._hourAngle,
                    hourLen,
                    r * 0.15,   // stemEnd
                    r * 0.0336, // stemW
                    r * 0.065,  // pillW
                    handColor
                )

                // Minute hand
                face._drawHand(ctx, full._minuteAngle,
                    minuteLen,
                    r * 0.15,   // stemEnd
                    r * 0.0336, // stemW
                    r * 0.065,  // pillW
                    handColor
                )

                // Pivot circle covering stem bases
                ctx.beginPath()
                ctx.arc(0, 0, r * 0.050, 0, 2 * Math.PI)
                ctx.fillStyle = handColor
                ctx.fill()

                ctx.restore()
            }

            Connections {
                target: full
                function on_HourAngleChanged()   { handsCanvas.requestPaint() }
                function on_MinuteAngleChanged() { handsCanvas.requestPaint() }
            }
            Connections {
                target: colors
                function onForegroundChanged() { handsCanvas.requestPaint() }
            }
            onWidthChanged:  requestPaint()
            onHeightChanged: requestPaint()
        }

        // --- Second hand ---
        Canvas {
            id: secondCanvas
            anchors.fill: parent
            z: 10
            renderStrategy: Canvas.Immediate

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const cx           = width / 2
                const cy           = height / 2
                const r            = Math.min(width, height) / 2
                const tickW   = r * 0.020
                const len     = r - tickW * 2  // reaches outward point of perimeter
                const counterWeight = r * 0.15  // tail past pivot
                const hw           = r * 0.007 * 1.3  // 1.3x thicker second hand

                ctx.save()
                ctx.translate(cx, cy)
                ctx.rotate(full._secondAngle * Math.PI / 180)

                ctx.fillStyle = "#F6A029"
                ctx.beginPath()
                ctx.rect(-hw, -len, hw * 2, len + counterWeight)
                ctx.fill()

                ctx.restore()
            }

            Connections {
                target: full
                function on_SecondAngleChanged() { secondCanvas.requestPaint() }
            }
            onWidthChanged:  requestPaint()
            onHeightChanged: requestPaint()
        }

        // --- Center hinge dot (topmost) ---
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
                ctx.fillStyle = "#F6A029"
                ctx.fill()

                ctx.restore()
            }

            onWidthChanged:  requestPaint()
            onHeightChanged: requestPaint()
        }
    }
}
