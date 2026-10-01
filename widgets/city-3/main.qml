import QtQuick
import "../../components"
import "widget"

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

    // World-clock model: City III shows a single city (1x1 only). Angles come
    // from the configured timezone; the second hand sweeps from the shared
    // local-second sweep (whole-minute zone offsets keep it accurate).
    WorldClockQs {
        id: world
        clocks: plugin.settings.clocks
        needsSeconds: true
    }
    readonly property var _e: world.entries.length ? world.entries[0] : null
    readonly property real _secondAngle: world.sweepAngle
    readonly property real _minuteAngle: _e ? _e.minuteAngle : 0
    readonly property real _hourAngle:   _e ? _e.hourAngle : 0

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
        solidMode: colors.isSolid && plugin.settings.opaqueBackground
        solidColor: colors.solidBackground
    }

    // Squircle-following perimeter dial: 60 static ticks, hour positions
    // slightly lighter and longer (inner tips form a perfect circle).
    HourDial {
        id: dial
        anchors.fill: parent
        cornerRadius: glass.radius
        roundness: glass.roundness
        outerInset: 0.05
        tickLength: 0.026
        cornerOuterExtension: 0.012
        tickWidthPx: 2.2
        // Hour markers match the numeral text exactly — same color
        // (colors.foreground) AND same opacity (colors.dialNumeralOpacity).
        tickColor: colors.foreground
        // Minor (non-hour) ticks stay faint; hour markers match the numerals.
        baseOpacity: colors.dialTickOpacity
        hourOpacity: colors.dialNumeralOpacity
        // Hour-tick inner tips form a circle ~15% larger than clock-analog's hour hand
        // (~0.608r), so circleR ≈ 0.699r of the full widget's min-side / 2.
        hourCircleRadiusFrac: 0.699
    }

    // Interior area matching clock-analog's 8% inset — used for numeral
    // and hand placement so margins stay consistent with clock-analog.
    Item {
        id: face
        anchors.fill: parent
        anchors.margins: Math.min(full.width, full.height) * 0.08

        readonly property real r: Math.min(width, height) / 2
        readonly property real cx: width / 2
        readonly property real cy: height / 2

        // Quarter numerals: 12, 3, 6, 9. The 12/6 (vertical) sit deeper
        // inward to clear the longer vertical hour lines.
        Repeater {
            model: [{ num: 12, pos: 0 }, { num: 3, pos: 3 }, { num: 6, pos: 6 }, { num: 9, pos: 9 }]

            delegate: Text {
                textFormat: Text.PlainText
                required property var modelData
                readonly property int num: modelData.num
                readonly property int pos: modelData.pos
                // All four cardinal hour lines reach the same circle, so all
                // numerals sit at one distance for an even gap to each line.
                readonly property real dist: face.r * 0.64
                readonly property real angle: (pos / 12) * 2 * Math.PI
                x: face.cx + Math.sin(angle) * dist - width  / 2
                y: face.cy - Math.cos(angle) * dist - height / 2
                text: num.toString()
                font.family: colors.uiFont
                // 40% larger than clock-analog's r*0.17
                font.pixelSize: Math.max(10, face.r * 0.238)
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
        // Spans the FULL widget (negative margins cancel face's 8% inset) so
        // the lengthened minute hand isn't clipped at the face edge. `r` is
        // rebased to the face radius (R_full * 0.84) so all hand sizes stay
        // identical to the inset-canvas version.
        Canvas {
            id: handsCanvas
            anchors.fill: parent
            anchors.margins: -Math.min(full.width, full.height) * 0.08
            z: 8
            renderStrategy: Canvas.Immediate

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const cx = width / 2
                const cy = height / 2
                const r  = (Math.min(width, height) / 2) * 0.84   // face radius

                ctx.save()
                ctx.translate(cx, cy)

                const handColor = Qt.rgba(
                    colors.foreground.r, colors.foreground.g, colors.foreground.b,
                    colors.dialHandOpacity
                )

                // Minute/hour hand lengths match clock-analog-3 exactly
                // (same 8%-inset face, same tick geometry, same 1.15x bump).
                const tickW   = r * 0.020
                const tickLen = r * 0.09
                const outerR  = r - tickW * 2
                const innerR  = outerR - tickLen
                const minuteLen = ((outerR + innerR) / 2) * 1.15
                const hourLen   = minuteLen * 0.65

                face._drawHand(ctx, full._hourAngle,
                    hourLen, r * 0.15, r * 0.0336, r * 0.065, handColor)

                face._drawHand(ctx, full._minuteAngle,
                    minuteLen, r * 0.15, r * 0.0336, r * 0.065, handColor)

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
        // Spans the FULL widget (negative margins cancel face's 8% inset) so
        // the tip can reach the perimeter without being clipped by `face`.
        // Still a child of `face`, so it paints above HourDial (later sibling)
        // and above the hour/minute hands (z 8).
        Canvas {
            id: secondCanvas
            anchors.fill: parent
            anchors.margins: -Math.min(full.width, full.height) * 0.08
            z: 10
            renderStrategy: Canvas.Immediate

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const cx = width / 2
                const cy = height / 2
                const r  = Math.min(width, height) / 2   // == full widget R
                // Tip touches the OUTER (start) end of the 3 o'clock perimeter
                // tick: HourDial outerInset 0.05 of min-side = 0.10 of R, so
                // the tick's outer end is at r*(1 - 2*0.05) = r*0.90.
                const len   = r * (1 - 2 * 0.05)
                const counterWeight = r * 0.15 * 0.84   // keep tail ~ as before
                const hw = r * 0.007 * 1.3 * 0.84       // 1.3x thicker, matching clock-analog-3

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
                ctx.fillStyle = "#F6A029"
                ctx.fill()
                ctx.restore()
            }

            onWidthChanged:  requestPaint()
            onHeightChanged: requestPaint()
        }
    }

    // City code sits inboard of the "12" numeral, hour-diff inboard of the
    // "6" numeral — i.e. at the numeral band but pulled further toward the
    // center by an extra margin (so they clear the numerals). The dial's
    // quarter numerals sit at 0.64*r; we park these at 0.40*r from center.
    // Font reduced 10% from the prior size.
    //
    // Opacity: one quiet step, not two. The annotation used to compound a
    // second 0.55 on top of the glass 0.55 (0.30) — below the documented
    // floor (MacOSColors.textQuiet) and measured as a ghost: on a light
    // themed glass tile the hour-diff read 1.6:1 against what is behind it,
    // against 8.6:1 for the numerals beside it. City I/II's 1x1 annotation is
    // the same call site (code + offset on the card rather than on a dial
    // plate) and takes the same token, so this is the third copy of one rule.
    // The solid-mode value is unchanged: textQuiet IS the 0.55 it already had.
    readonly property real _faceR:   (Math.min(full.width, full.height) / 2) * 0.84
    readonly property real _annoFont: Math.max(7, _faceR * 0.165)
    readonly property real _annoInset: _faceR * 0.40
    readonly property real _annoOpacity: colors.textQuiet

    Text {
        textFormat: Text.PlainText
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height / 2 - full._annoInset - height / 2
        text: full._e ? full._e.code : ""
        font.family: colors.uiFont
        font.pixelSize: full._annoFont
        font.weight: Font.Medium
        color: colors.foreground
        opacity: full._annoOpacity
    }
    Text {
        textFormat: Text.PlainText
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height / 2 + full._annoInset - height / 2
        text: full._e ? full._e.offsetLabel : ""
        font.family: colors.uiFont
        font.pixelSize: full._annoFont
        font.weight: Font.Medium
        color: colors.foreground
        opacity: full._annoOpacity
    }
}
