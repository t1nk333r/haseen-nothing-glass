import QtQuick
import "../../components"

// Sunrise / sunset, from the reference screenshot's top-left stack: a small-caps SUNRISE
// label with a sun glyph, the sunrise time large beneath it, an arc from
// horizon to horizon with the sun's current position marked, and
// `Sunset: HH:MM` under it.
//
// Plan 012 opened with a stop-and-ask about GPS. What it did not know is that
// the coordinates already exist on this machine, hand-set and exact, in the
// prayers plugin's settings - so `components/GeoLocation.qml` prefers
// GeoClue2 when it can actually produce a fix and otherwise uses those,
// naming the winner in `source`. And the sun times need no network at all:
// the vendored adhan-js engine behind `PrayerTimes` computes them, so this
// tile works offline, unlike the Open-Meteo path the plan assumed.
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

    GeoLocation {
        id: geo
        useGeoclue: plugin.settings.useGeoclue
        fallbackLatitude: plugin.settings.latitude
        fallbackLongitude: plugin.settings.longitude
    }

    PrayerTimes {
        id: sun
        overrideLatitude: geo.latitude
        overrideLongitude: geo.longitude
    }

    // The sun is drawn, not written: a glyph would tie the tile to whichever
    // Nerd Font happens to be installed, and the first attempt
    // (U+F185) rendered as a gear.

    // One scale for the four drawings - see components/GlassScale.qml. This
    // tile used to derive its own label (by a formula the weather tile did
    // not share) and its own margin, so on one 400x400 tile the two tiles
    // disagreed about what a label was by 7 px.
    GlassScale {
        id: scale
        tileWidth: full.width
        tileHeight: full.height
    }

    // The tile counts down to the NEXT horizon crossing, not to a fixed one:
    // while the sun is up that is sunset, and once it is down it is the
    // morning's sunrise. The label and the hero time follow the same choice,
    // and the footer carries the other one so both times stay on screen.
    readonly property bool _day: sun.isDaylight
    readonly property string _heroLabel: _day ? "SUNSET" : "SUNRISE"
    readonly property string _heroText: {
        var t = _day ? sun.sunsetText : sun.sunriseText
        return t !== "" ? t : "--:--"
    }
    readonly property string _otherLabel: _day ? "Sunrise: " : "Sunset: "
    readonly property string _otherText: {
        var t = _day ? sun.sunriseText : sun.sunsetText
        return t !== "" ? t : "--:--"
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
        solidMode: colors.isSolid && plugin.settings.opaqueBackground
        solidColor: colors.solidBackground
    }

    Item {
        id: content
        anchors.fill: parent
        anchors.margins: scale.pad

        // In the wide tile the arc takes the right half instead of a sliver
        // under the time - at 400x192 there was 20 px left for it and only
        // the horizon line drew.
        readonly property real textWidth: scale.isWide ? Math.round(width * 0.46) : width

        // ── Header: SUNRISE + sun ────────────────────────────────────────
        Row {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            spacing: Math.round(scale.label * 0.5)

            Text {
                text: full._heroLabel
                color: colors.foreground
                opacity: 0.6
                font.family: colors.uiFont
                font.pixelSize: scale.label
                font.letterSpacing: scale.label * 0.12
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(scale.label * 0.62)
                height: width
                radius: width / 2
                color: colors.todayAccent
            }
        }

        Text {
            id: heroTime
            anchors.top: header.bottom
            anchors.topMargin: Math.round(scale.label * 0.3)
            anchors.left: parent.left
            width: content.textWidth
            text: full._heroText
            color: colors.foreground
            font.family: colors.uiFont
            font.pixelSize: Math.round(scale.minSide * (scale.isWide ? 0.26 : 0.22))
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 10
        }

        // ── The arc, with the sun where it is now ────────────────────────
        Canvas {
            id: arc
            // Always between the header/time and the footer: anchoring the
            // wide arc to the tile's bottom instead let the dome run through
            // "Sunset: ..." once the span cap made it taller.
            //
            // Both horizontal branches carry an explicit x and width, never an
            // anchor in one and a width in the other. `anchors.left` used to
            // vanish exactly as the wide `width` appeared, and Qt's anchor
            // layout then wrote x/width over the binding: measured after any
            // resize into the wide preset the arc was 380 px (from min) and
            // 368 px (from big) wide where the expression asks for 186, so it
            // covered the whole content box including the hero time. The same
            // widget created at 400x192 draws 186. The Nothing twin states the
            // rule in its own words - an explicit width in both branches.
            readonly property real arcWidth: scale.isWide
                ? Math.round(content.width - content.textWidth - scale.label)
                : content.width

            x: scale.isWide ? parent.width - arcWidth : 0
            width: arcWidth
            anchors.bottom: footer.top
            anchors.bottomMargin: Math.round(scale.label * 0.4)
            anchors.top: scale.isWide ? header.bottom : heroTime.bottom
            anchors.topMargin: Math.round(scale.label * 0.2)

            // Everything the paint needs, precomputed on change rather than
            // per frame (AGENTS.md's Canvas convention).
            readonly property real progress: sun.dayProgress
            readonly property bool daylight: sun.isDaylight
            readonly property color line: colors.foreground
            readonly property color accent: colors.todayAccent

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                if (width <= 0 || height <= 0) return

                var stroke = Math.max(1.5, height * 0.045)
                var inset = stroke
                var baseY = height - stroke
                var peakY = stroke
                var rise0 = baseY - peakY

                // Keep the dome from flattening into a lens on a tall tile:
                // a half-ellipse spanning 312 px over 130 px of height reads
                // as a shallow curve. Cap the span at ~2.4x the rise and
                // centre what is left; wide tiles are unaffected because
                // their arc is already about that ratio.
                var maxSpan = Math.max(rise0 * 2.4, height)
                var span = Math.min(width - inset * 2, maxSpan)
                if (span <= 0) return
                var left = (width - span) / 2
                var right = left + span

                // A half-ellipse from horizon to horizon: y = baseY - sin(t)
                // * rise, x = left + t/pi * span.
                var rise = rise0
                function pointAt(f) {
                    var clamped = Math.max(0, Math.min(1, f))
                    return {
                        x: left + clamped * span,
                        y: baseY - Math.sin(clamped * Math.PI) * rise
                    }
                }

                // Horizon.
                ctx.lineWidth = Math.max(1, stroke * 0.5)
                ctx.strokeStyle = Qt.rgba(arc.line.r, arc.line.g, arc.line.b, 0.20)
                ctx.beginPath()
                ctx.moveTo(left, baseY)
                ctx.lineTo(right, baseY)
                ctx.stroke()

                // Full path, dim.
                ctx.lineWidth = stroke
                ctx.lineCap = "round"
                ctx.strokeStyle = Qt.rgba(arc.line.r, arc.line.g, arc.line.b, 0.25)
                ctx.beginPath()
                for (var i = 0; i <= 48; i++) {
                    var p = pointAt(i / 48)
                    if (i === 0) ctx.moveTo(p.x, p.y); else ctx.lineTo(p.x, p.y)
                }
                ctx.stroke()

                // Travelled portion, accent. Empty before sunrise and after
                // sunset - the marker parks at the end instead of running off
                // the path.
                if (arc.progress > 0 && arc.progress < 1) {
                    ctx.strokeStyle = arc.accent
                    ctx.beginPath()
                    var steps = Math.max(2, Math.round(48 * arc.progress))
                    for (var j = 0; j <= steps; j++) {
                        var q = pointAt((j / steps) * arc.progress)
                        if (j === 0) ctx.moveTo(q.x, q.y); else ctx.lineTo(q.x, q.y)
                    }
                    ctx.stroke()
                }

                // The sun itself.
                var marker = pointAt(arc.progress)
                var dot = stroke * 1.6
                ctx.fillStyle = arc.daylight
                    ? arc.accent
                    : Qt.rgba(arc.line.r, arc.line.g, arc.line.b, 0.45)
                ctx.beginPath()
                ctx.arc(marker.x, marker.y, dot, 0, Math.PI * 2)
                ctx.fill()
            }

            Connections {
                target: sun
                function onDayProgressChanged() { arc.requestPaint() }
                function onIsDaylightChanged() { arc.requestPaint() }
            }
            Connections {
                target: colors
                function onForegroundChanged() { arc.requestPaint() }
                function onTodayAccentChanged() { arc.requestPaint() }
            }
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }

        // ── Footer: sunset, and where the coordinates came from ──────────
        Column {
            id: footer
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: scale.gap

            Text {
                width: parent.width
                elide: Text.ElideRight
                text: full._otherLabel + full._otherText
                color: colors.foreground
                font.family: colors.uiFont
                font.pixelSize: scale.body
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                // One rule, the same one the Nothing twin uses: the small
                // square has no line to spare for provenance UNLESS the fix
                // failed, in which case the tile must not be quietly wrong
                // about its own position. The old rule here keyed off this
                // line's measured width instead, so the two styles disagreed
                // about when a tile was too small to be honest.
                visible: scale.isWide || scale.isBig || !sun.ok
                // Never silently wrong about its own position: the tile says
                // which source won, and the engine's error if it did not
                // resolve at all.
                text: sun.ok
                    ? ((geo.label !== "" ? geo.label + " · " : "") + geo.source)
                    : sun.error
                color: colors.foreground
                opacity: colors.textQuiet
                font.family: colors.uiFont
                font.pixelSize: scale.micro
            }
        }
    }
}
