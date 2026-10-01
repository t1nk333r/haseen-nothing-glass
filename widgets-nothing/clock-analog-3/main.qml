import QtQuick
import "../../components/nothing"

// Analog clock, bare dial, Nothing style.
//
// The Nothing drawing of `clock-analog-3` for the catalogue's `Dial, bare`
// ("Four numerals only"): the Nothing analog clock next door with everything
// that is not a numeral taken off the face. No tick ring, no dot field, no
// header, no badge, no footer, no readout - 12 / 3 / 6 / 9 and the hands, on
// the bare card, and the numerals at EVERY tile size rather than on the large
// one only. That is the whole drawing, and it is the same cut the Liquid Glass
// twin (widgets/clock-analog-3) makes to the base glass analog clock.
//
// Everything visual comes from `nothing`, the NTheme WidgetHost injects.
// MacOSColors, LiquidGlass and qs.Ui are never touched here, and the glass-only
// configuration keys (cornerRadius, refract*, tint*, blurRadius,
// opaqueBackground) have no meaning in this style, so this file reads none of
// them. The `plugin.settings` keys it does read are the twin's - there is one
// settings schema for both drawings.
Item {
    id: full
    anchors.fill: parent

    // ── Time ─────────────────────────────────────────────────────────
    // The second hand TICKS: one discrete step a second, with a short
    // overshoot as it lands, the way a quartz movement does. That is the
    // motion the Nothing analog clock has always drawn and the one this style
    // wants - a dot-matrix desktop should move in steps, and one wake-up a
    // second costs a sixtieth of the sweep. The sweep setting turns the
    // sweep back on, unless the compositor asks for less animation.
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

    // The timer re-aligns itself to the wall-clock second on every tick
    // instead of free-running at 1000 ms, so the hand lands ON the second
    // rather than drifting up to a second out of phase with it.
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

    NCard {
        id: card
        theme: nothing
        anchors.fill: parent

        // The bare dial: a square of the tile's SHORT side, centred, so all
        // three grid presets are covered by one rule - 192x192 and 400x192
        // get the same 164 px face (the wide tile just has the card's air
        // either side of it; a dial with only four numerals on it has no
        // second column to put there), 400x400 gets the whole stage.
        Item {
            id: stage
            anchors.fill: parent
            anchors.margins: nothing.pad

            Item {
                id: face
                readonly property real side: Math.max(nothing.px(40),
                    Math.min(stage.width, stage.height))
                width: face.side
                height: face.side
                anchors.centerIn: parent

                // 12 / 3 / 6 / 9 - the whole face, at every size. Same placement
                // as the Nothing analog clock's numerals, so the two dials line
                // up; a numeral size that follows the face instead of the type
                // scale, because on this dial they are the content, not the
                // metadata the small type is meant for.
                Repeater {
                    model: ["12", "3", "6", "9"]

                    delegate: NLabel {
                        id: numeral
                        required property int index
                        required property var modelData
                        readonly property real dist: face.side * 0.30
                        theme: nothing
                        text: numeral.modelData
                        font.pixelSize: Math.max(nothing.fLabel,
                            Math.round(face.side * 0.115))
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

                // Second hand: a hairline with a short counterweight. The
                // overshoot is the tick: OutBack carries the hand a degree or so
                // past the mark and lets it settle back, which is what makes a
                // step read as a mechanical movement instead of a teleport.
                // Wrapping 59 -> 0 is excluded, or the hand would spin the long
                // way round once a minute.
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
        }
    }
}
