import QtQuick
import "../../components/nothing"

// Analog clock, Nothing style: the "Analog — Markers" face.
//
// The Liquid Glass twin next door (widgets/clock-analog-2) is the plain
// analog dial with a heavier ring: twelve fat pill marks, one per hour,
// instead of a fine 60-tick perimeter, and no numerals - the marks do the
// anchoring. This file draws that same face in this style's language, on the
// same body as the Nothing analog clock (widgets-nothing/clock-analog), which
// is the template for the whole widget: NCard, the dot field on the large
// tile, the header/badge/footer, the wide-tile readout column, and the
// ticking second hand are all that file's, unchanged.
//
// What is NOT that file's is the ring. Where the sibling runs NDial - 60
// hairline ticks whose elapsed minutes are lit - this face carries the glass
// twin's twelve heavy marks. They are still a readout and not decoration:
// the hours the hand has already reached are inked, the rest are `onFaint`,
// so the ring fills through the half-day exactly the way NDial fills through
// the hour. That is the same "ticks, not a sweep" idea the style uses
// everywhere, at the heavier pitch this face is named for.
//
// Everything visual comes from `nothing`, the NTheme WidgetHost injects;
// MacOSColors and LiquidGlass are never touched here, and the glass-only
// configuration keys (cornerRadius, refract*, tint*, blurRadius,
// opaqueBackground, styleMode, appearance) have no meaning in this style, so
// this file reads none of them. `theme` and `backdrop` are likewise never
// read: a Nothing tile draws its own card over the desktop, it does not
// refract what is behind it.
Item {
    id: full
    anchors.fill: parent

    // The three grid presets: 192x192, 400x192, 400x400. Same thresholds as
    // the sibling - the face changes size, not the tile's proportions.
    readonly property bool isWide: full.width >= full.height * 1.6
    readonly property bool isBig: !full.isWide && Math.min(full.width, full.height) >= 300

    // The second hand TICKS: one discrete step a second, with a short
    // overshoot as it lands, the way a quartz movement does. The Liquid Glass
    // twin of this face sweeps continuously - it never reads the sweep
    // setting - but a dot-matrix desktop should move in steps, so this body
    // keeps the Nothing analog clock's behaviour: the sweep setting turns the
    // free-running sweep back on, and the compositor's reduced-motion
    // preference overrides it.
    //
    // The timer re-aligns itself to the wall-clock second on every tick
    // instead of free-running at 1000 ms, so the hand lands ON the second
    // rather than drifting up to a second out of phase with the readout
    // beside it.
    property date now: new Date()
    property int second: new Date().getSeconds()

    // Fail open: if the compositor's style module is missing, `item` is null
    // and the clock animates. See components/MotionWatch.qml.
    Loader { id: motionWatch; source: "../../components/MotionWatch.qml" }

    readonly property bool _reducedMotion: motionWatch.item
        ? motionWatch.item.reduceMotion : false

    // Off by default: this style ticks.
    readonly property bool _sweep: plugin.settings.analogSecondSweep
        && !_reducedMotion

    // The sweep's fractional second, advanced by sweepTimer below when the
    // hand is not ticking.
    property real _sweepSecond: full.second

    Timer {
        id: sweepTimer
        interval: 16
        repeat: true
        running: full._sweep && full.visible
        onTriggered: {
            const d = new Date()
            full._sweepSecond = d.getSeconds() + d.getMilliseconds() / 1000
        }
    }

    Timer {
        id: tick
        interval: 1000 - (Date.now() % 1000)
        repeat: false
        running: true
        onTriggered: {
            var n = new Date()
            full.second = n.getSeconds()
            if (n.getMinutes() !== full.now.getMinutes() || n.getHours() !== full.now.getHours())
                full.now = n
            tick.interval = Math.max(50, 1000 - (Date.now() % 1000))
            tick.restart()
        }
    }

    // The minute hand advances with the seconds rather than jumping on the
    // minute - a minute hand frozen between minutes is the tell of a fake
    // clock face - but it moves in the same one-second steps.
    readonly property real minuteFrac: (full.now.getMinutes() + full.second / 60) / 60
    readonly property real minuteAngle: full.minuteFrac * 360
    readonly property real hourAngle: ((full.now.getHours() % 12) + full.minuteFrac) / 12 * 360
    readonly property real secondAngle: (full._sweep ? full._sweepSecond : full.second) / 60 * 360
    readonly property real dayFrac: (full.now.getHours() + full.now.getMinutes() / 60) / 24
    readonly property string clockText: Qt.formatDateTime(full.now, "HH:mm")
    readonly property string dateText: Qt.formatDateTime(full.now, "ddd d MMM")

    NCard {
        id: card
        theme: nothing
        anchors.fill: parent

        NDotField {
            theme: nothing
            anchors.fill: parent
            anchors.margins: nothing.pad
            intensity: 0.4
            visible: full.isBig
        }

        // ── Header ─────────────────────────────────────────────────────
        NLabel {
            id: header
            theme: nothing
            text: Qt.formatDateTime(full.now, full.isWide || full.isBig ? "dddd" : "ddd")
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: badge.visible ? badge.left : parent.right
            anchors.margins: nothing.pad
            anchors.rightMargin: badge.visible ? nothing.gap : nothing.pad
            elide: Text.ElideRight
        }

        NBadge {
            id: badge
            theme: nothing
            active: true
            label: Qt.formatDateTime(full.now, "AP")
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: nothing.pad
            visible: full.isBig
        }

        // ── The dial ───────────────────────────────────────────────────
        Item {
            id: stage
            anchors.top: header.bottom
            anchors.topMargin: nothing.gap
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: footer.top
            anchors.bottomMargin: nothing.gap
            anchors.leftMargin: nothing.pad
            anchors.rightMargin: nothing.pad

            Item {
                id: face
                // Wide tile: the dial takes the left column and leaves the
                // horizontal room to a readout stack. Square tiles: it is
                // the whole stage.
                readonly property real side: Math.max(nothing.px(40), Math.min(
                    full.isWide ? stage.width * 0.44 : stage.width, stage.height))
                width: face.side
                height: face.side
                anchors.verticalCenter: parent.verticalCenter
                // Position on `x`, never by swapping anchor sets. Swapping
                // between anchors.left and anchors.horizontalCenter as the
                // tile crosses the wide threshold clobbers the `width`
                // binding above (measured: side 134, width 372 after a
                // 160x160 -> 400x192 resize), and that stretched face then
                // drags `readout`'s anchors.left past the tile — column width
                // -14 at x 386, so the time, date and day bar drew nothing at
                // all. A plain x binding leaves width alone.
                x: full.isWide ? 0 : (parent.width - face.side) / 2

                // The hour the hand has reached, 1..12. Mark 0 is 12 o'clock
                // and the ring fills clockwise, so this is "marks passed in
                // this half-day" - the same thing NDial's `value` means, one
                // hour at a time instead of one minute at a time. At exactly
                // 3:00 the hand sits on the 3 mark and that mark is lit, so
                // the ring's leading edge is always the mark under the hand.
                readonly property int litMarks: Math.floor(full.hourAngle / 30) + 1

                // ── Twelve heavy hour marks ────────────────────────────
                // Flat pills, not the sibling's hairline strokes: the whole
                // point of this face is that the ring reads heavier than the
                // hands it surrounds. Each mark is the glass twin's geometry
                // brought over unchanged - flush to the ring's outer gap,
                // reaching inward to where the minute hand stops (0.362 of
                // the dial's side), and wider than the hour hand - but drawn
                // with the style's own ink instead of a Canvas alpha fill, so
                // a palette change repaints it with no requestPaint() to
                // mirror by hand.
                Repeater {
                    model: 12

                    delegate: Item {
                        required property int index
                        anchors.fill: parent
                        // Mark 0 sits at the top and the ring winds clockwise,
                        // so rotating the full-face container by the index is
                        // the whole placement - no per-mark trigonometry.
                        rotation: index * 30

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: face.side * 0.02
                            width: Math.max(3, face.side * 0.036)
                            height: Math.max(4, face.side * 0.118)
                            radius: width / 2
                            color: index < face.litMarks ? nothing.on : nothing.onFaint
                            antialiasing: true
                        }
                    }
                }

                // Hour hand: flat, blunt, the quiet one.
                Rectangle {
                    id: hourHand
                    width: Math.max(2, face.side * 0.030)
                    height: face.side * 0.24
                    radius: hourHand.width / 2
                    color: nothing.on
                    antialiasing: true
                    x: face.width / 2 - hourHand.width / 2
                    y: face.height / 2 - hourHand.height
                    transformOrigin: Item.Bottom
                    rotation: full.hourAngle
                }

                // Minute hand: the one red thing on the face.
                Rectangle {
                    id: minuteHand
                    width: Math.max(2, face.side * 0.022)
                    height: face.side * 0.36
                    radius: minuteHand.width / 2
                    color: nothing.red
                    antialiasing: true
                    x: face.width / 2 - minuteHand.width / 2
                    y: face.height / 2 - minuteHand.height
                    transformOrigin: Item.Bottom
                    rotation: full.minuteAngle
                }

                // Second hand: a hairline with a short counterweight.
                //
                // The overshoot is the tick: OutBack carries the hand a
                // degree or so past the mark and lets it settle back, which
                // is what makes a step read as a mechanical movement instead
                // of a teleport. Wrapping 59 -> 0 is excluded, or the hand
                // would spin the long way round once a minute.
                Rectangle {
                    id: secondHand
                    readonly property real len: face.side * 0.42
                    width: Math.max(1, face.side * 0.008)
                    height: secondHand.len + face.side * 0.08
                    color: nothing.onDim
                    antialiasing: true
                    x: face.width / 2 - secondHand.width / 2
                    y: face.height / 2 - secondHand.len
                    transform: Rotation {
                        id: secondRotation
                        origin.x: secondHand.width / 2
                        origin.y: secondHand.len
                        angle: full.secondAngle

                        Behavior on angle {
                            enabled: !full._sweep && full.second !== 0
                            NumberAnimation {
                                duration: 140
                                easing.type: Easing.OutBack
                                easing.overshoot: 2.4
                            }
                        }
                    }
                }

                // Hub, over the hand roots.
                Rectangle {
                    width: Math.max(4, face.side * 0.055)
                    height: width
                    radius: width / 2
                    color: nothing.on
                    antialiasing: true
                    anchors.centerIn: parent
                }
                Rectangle {
                    // surfaceSolid: the backdrop here is the cap, not the card material.
                    width: Math.max(2, face.side * 0.020)
                    height: width
                    radius: width / 2
                    color: nothing.surfaceSolid
                    antialiasing: true
                    anchors.centerIn: parent
                }
            }

            // ── Wide tile only: the readout column beside the dial ──────
            Column {
                id: readout
                anchors.left: face.right
                anchors.leftMargin: nothing.pad
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: nothing.px(5)
                visible: full.isWide

                NMono {
                    width: parent.width
                    theme: nothing
                    text: full.clockText
                    font.pixelSize: Math.min(nothing.px(40), stage.height * 0.34)
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: nothing.fBody
                    elide: Text.ElideRight
                }
                NLabel {
                    width: parent.width
                    theme: nothing
                    text: full.dateText
                    elide: Text.ElideRight
                }
                NProgress {
                    width: parent.width
                    theme: nothing
                    height: nothing.px(4)
                    segments: 24
                    value: full.dayFrac
                    accent: true
                }
            }
        }

        // ── Footer: only the large tile has the height for one ──────────
        Item {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: nothing.pad
            visible: full.isBig
            height: footer.visible
                ? footLine.implicitHeight + nothing.px(6) + dayBar.height
                : 0

            NMono {
                id: footLine
                theme: nothing
                text: full.clockText + "  " + full.dateText
                color: nothing.onDim
                font.pixelSize: nothing.fLabel
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                elide: Text.ElideRight
            }

            NProgress {
                id: dayBar
                theme: nothing
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: nothing.px(4)
                segments: 24
                value: full.dayFrac
                accent: true
            }
        }
    }
}
