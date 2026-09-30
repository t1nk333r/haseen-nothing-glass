import QtQuick
import "../../components/nothing"

// Analog clock, Nothing style.
//
// Same information as the Liquid Glass analog clock next door - local wall
// time on a dial - drawn as the style draws it: a tick ring instead of a
// decorated watch plate, flat hands, one red one. Everything visual comes
// from `nothing`, the NTheme WidgetHost injects; MacOSColors and LiquidGlass
// are never touched here, and the glass-only configuration keys
// (cornerRadius, refract*, tint*, blurRadius, opaqueBackground) have no
// meaning in this style, so this file reads none of them - exactly like the
// Nothing clock-digital tile.
Item {
    id: full
    anchors.fill: parent

    // The three grid presets: 192x192, 400x192, 400x400.
    readonly property bool isWide: full.width >= full.height * 1.6
    readonly property bool isBig: !full.isWide && Math.min(full.width, full.height) >= 300

    // The second hand TICKS: one discrete step a second, with a short
    // overshoot as it lands, the way a quartz movement does. The Liquid Glass
    // twin ticks the same way by default now - its older continuous sweep is
    // behind the sweep setting, which this style reads too - a dot-matrix
    // desktop should move in steps, and one wake-up a second costs a
    // sixtieth of the sweep.
    //
    // The timer re-aligns itself to the wall-clock second on every tick
    // instead of free-running at 1000 ms, so the hand lands ON the second
    // rather than drifting up to a second out of phase with the digits next
    // to it.
    property date now: new Date()
    property int second: new Date().getSeconds()

    // Fail open: if the compositor's style module is missing, `item` is null
    // and the clock animates. See components/MotionWatch.qml.
    Loader { id: motionWatch; source: "../../components/MotionWatch.qml" }

    readonly property bool _reducedMotion: motionWatch.item
        ? motionWatch.item.reduceMotion : false

    // Off by default: this style ticks. The sweep setting turns the sweep
    // back on, unless the compositor asks for less animation.
    readonly property bool _sweep: plugin.settings.analogSecondSweep
        && !_reducedMotion

    // The sweep's fractional second, advanced by sweepTimer below when the
    // hand is not ticking.
    property real _sweepSecond: full.second

    Timer {
        id: sweepTimer
        interval: 16
        repeat: true
        running: full._sweep
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

                // The ring: 60 marks, the elapsed minutes of this hour lit.
                // Same segmentation idea as NProgress, wrapped round - so
                // the face is a readout, not decoration.
                NDial {
                    theme: nothing
                    anchors.fill: parent
                    ticks: 60
                    majorEvery: 5
                    value: full.minuteFrac
                }

                // 12 / 3 / 6 / 9 only, and only where there is room for
                // them to sit inside the ring without crowding the hands.
                Repeater {
                    model: ["12", "3", "6", "9"]

                    delegate: NLabel {
                        id: numeral
                        required property int index
                        required property var modelData
                        readonly property real dist: face.side * 0.30
                        theme: nothing
                        text: numeral.modelData
                        font.pixelSize: nothing.fLabel
                        visible: full.isBig
                        x: face.width / 2 + Math.sin(numeral.index * Math.PI / 2) * numeral.dist
                           - numeral.width / 2
                        y: face.height / 2 - Math.cos(numeral.index * Math.PI / 2) * numeral.dist
                           - numeral.height / 2
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

                // Second hand: a hairline with a short counterweight, on
                // every tile now that it steps instead of sweeping - the cost
                // is one repaint a second, not sixty.
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
