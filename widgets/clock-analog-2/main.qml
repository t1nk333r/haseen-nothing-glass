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

    property real _secondAngle: 0
    property real _minuteAngle: 0
    property real _hourAngle: 0

    Timer {
        id: frameTimer
        interval: 16
        repeat: true
        // Off while the host is hidden (its screen is switched off): a 60 Hz
        // sweep with nothing drawn is all cost (WidgetHost.qml `visible`).
        running: full.visible
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

        // --- 12 hour lines (pill-shaped, one per hour position) ---
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

                // Preserve same outer gap as original perimeter marks
                const tickW   = r * 0.020
                const tickLen = r * 0.09
                const outerR  = r - tickW * 2
                const innerR  = outerR - tickLen

                // Hour line dimensions
                const lineW   = (r * 0.0336) * 0.9 * 1.15 * 1.35  // 90% of minute hand thickness, +15%, then +35% thicker
                const minuteLen = (outerR + innerR) / 2
                const hourLen   = minuteLen * 0.65
                const lineLen   = hourLen * 0.40 * 0.90 * 1.10  // 40% of hour hand length, 10% shorter, then 10% longer
                const hw        = lineW / 2

                ctx.fillStyle = Qt.rgba(
                    colors.foreground.r,
                    colors.foreground.g,
                    colors.foreground.b,
                    0.75
                )

                ctx.save()
                ctx.translate(cx, cy)

                for (let i = 0; i < 12; i++) {
                    const angle = i * 30 * Math.PI / 180

                    ctx.save()
                    ctx.rotate(angle)

                    // Pill-shaped hour line: rounded rect along the radial axis
                    const x = -hw
                    const y = -outerR
                    const w = lineW
                    const h = lineLen
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
                target: colors
                function onForegroundChanged() { tickCanvas.requestPaint() }
            }

            onWidthChanged:  requestPaint()
            onHeightChanged: requestPaint()
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
