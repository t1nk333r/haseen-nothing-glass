import QtQuick
import "../../components"
import "../../components/nothing"

// One city, one face - the Nothing drawing of widgets/city-3.
//
// Same data path as the Liquid Glass twin: WorldClockQs off the `clocks`
// setting, first entry only, seconds on so the second hand sweeps. What
// changes is the drawing. Glass fills the whole squircle with a
// perimeter tick ring, sets the quarter numerals on it and prints the city
// code / hour offset inboard of the 12 and the 6. Nothing draws the style's
// own dial instead - an NDial ring whose elapsed-minute ticks are the same
// readout the Nothing analog clock next door shows - with flat hands, and
// names the city in the header where every other Nothing card names its
// subject. The twin is 1x1 in practice (the registry draws it as a single
// face), so the dial stays centred at every size rather than growing a
// side panel: there is no wide layout to mirror.
Item {
    id: full
    anchors.fill: parent

    // The three grid presets: 192x192, 400x192, 400x400.
    readonly property bool isWide: full.width >= full.height * 1.6
    readonly property bool isBig: !full.isWide && Math.min(full.width, full.height) >= 300

    WorldClockQs {
        id: world
        clocks: plugin.settings.clocks
        needsSeconds: true
    }

    readonly property var entry: world.entries.length ? world.entries[0] : null

    // The fallback clock. A `new Date()` read inside a binding has no
    // dependencies, so QML evaluates it once and the tile freezes at its load
    // minute - a city is what owns the TzClock that would wake it.
    property date _localNow: new Date()

    Timer {
        running: full.entry === null   // only the fallback needs this
        interval: 1000
        repeat: true
        onTriggered: {
            const now = new Date()
            // A compare a second, a write a minute. A timer aligned to the
            // wall minute at load would drift; this cannot.
            if (now.getMinutes() !== full._localNow.getMinutes())
                full._localNow = now
        }
    }

    readonly property string ampm: full.entry ? full.entry.ampm
                                              : (full._localNow.getHours() < 12 ? "AM" : "PM")
    readonly property string cityCode: full.entry ? full.entry.code : ""
    readonly property string cityLabel: full.entry ? full.entry.label : ""
    readonly property string offsetLabel: full.entry ? full.entry.offsetLabel : ""
    readonly property string dayWord: full.entry ? full.entry.dayWord : "Today"
    // The same 06:00-18:00 rule WorldClockQs uses, so an unconfigured tile
    // does not read Day at 03:00.
    readonly property bool isDay: full.entry ? full.entry.isDay
                                             : full._localNow.getHours() >= 6
                                               && full._localNow.getHours() < 18

    // The smooth second sweep the model publishes for a `needsSeconds` clock
    // (degrees, universal - seconds are the same in every real zone). Used
    // for the hand directly, and, on the fallback path, as the sub-minute
    // part of the other two hands - the model's own second value is only as
    // fresh as its last minute rebuild.
    readonly property real secondAngle: world.sweepAngle
    readonly property real _localSecond: full.secondAngle / 6

    readonly property real minuteFrac: full.entry
        ? full.entry.minuteAngle / 360
        : (full._localNow.getMinutes() + full._localSecond / 60) / 60
    readonly property real minuteAngle: full.entry ? full.entry.minuteAngle
                                                   : full.minuteFrac * 360
    readonly property real hourAngle: full.entry
        ? full.entry.hourAngle
        : ((full._localNow.getHours() % 12) + full.minuteFrac) / 12 * 360

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

        // ── Header: the city, and whether it is daytime there ──────────
        NLabel {
            id: header
            theme: nothing
            loud: true
            text: full.isWide || full.isBig ? full.cityLabel : full.cityCode
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: ampmBadge.visible ? ampmBadge.left : parent.right
            anchors.margins: nothing.pad
            anchors.rightMargin: ampmBadge.visible ? nothing.gap : nothing.pad
            elide: Text.ElideRight
        }

        NBadge {
            id: ampmBadge
            theme: nothing
            active: full.isDay
            label: full.ampm
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: nothing.pad
            visible: full.width >= nothing.px(150)
        }

        // ── Stage ──────────────────────────────────────────────────────
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

            // The dial is a circle in this style, so it takes the smaller
            // side and centres - the tile's extra width is not spent, the
            // same as the glass twin whose face is one unbroken dial.
            Item {
                id: face
                readonly property real side: Math.max(nothing.px(40), Math.min(stage.width, stage.height))
                width: face.side
                height: face.side
                anchors.centerIn: parent

                // The ring: 60 marks, the elapsed minutes of the city's hour
                // lit - the same readout the Nothing analog clock puts round
                // its face. Hour marks are the longer, heavier ones, which is
                // what the glass twin's perimeter promotes too.
                NDial {
                    theme: nothing
                    anchors.fill: parent
                    ticks: 60
                    majorEvery: 5
                    value: full.minuteFrac
                }

                // 12 / 3 / 6 / 9 only, and only where there is room for them
                // to sit inside the ring without crowding the hands.
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

                // Second hand: a hairline with a short counterweight. This
                // face is a city's, so it sweeps from the model's shared
                // sweep rather than taking the analog clock's discrete step -
                // the twin sweeps, and the seconds are the same in every zone
                // whatever the hour offset.
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

        // ── Footer: the offset, and the date the city is on ─────────────
        Item {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: nothing.pad
            height: Math.max(offsetLine.implicitHeight, dayWordLabel.implicitHeight)

            NMono {
                id: offsetLine
                theme: nothing
                text: full.offsetLabel !== "" ? full.offsetLabel : "--"
                color: nothing.onDim
                font.pixelSize: nothing.fLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
            }

            NLabel {
                id: dayWordLabel
                theme: nothing
                text: full.dayWord
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                // On the small square the day word only earns its space when
                // the city is actually on another date.
                visible: full.isWide || full.isBig || full.dayWord !== "Today"
            }
        }
    }
}
