import QtQuick
import "../../components"
import "../../components/nothing"

// One city's clock, Nothing style.
//
// Same data path as the Liquid Glass city-digital tile: WorldClockQs off the
// `clocks` setting, first entry only, seconds off (this face has no second
// hand, so nothing here needs a per-second tick - the TzClock behind the
// model already wakes on the minute and across DST). The drawing is the only
// difference: a dot-matrix readout instead of a condensed typeface, and the
// city's 24 hours as a row of dots instead of a tick ring.
Item {
    id: full
    anchors.fill: parent

    // The three grid presets: 192x192, 400x192, 400x400.
    readonly property bool isWide: full.width >= full.height * 1.6
    readonly property bool isBig: !full.isWide && Math.min(full.width, full.height) >= 300

    WorldClockQs {
        id: world
        clocks: plugin.settings.clocks
        needsSeconds: false
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

    readonly property int hour12: full.entry ? full.entry.hour12
                                             : ((full._localNow.getHours() + 11) % 12) + 1
    readonly property int minute: full.entry ? full.entry.minute : full._localNow.getMinutes()
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

    // The model publishes a 12-hour clock plus AM/PM; the hour-dot row wants
    // the 24-hour position, which is that pair and no new source of truth.
    readonly property int hour24: (full.hour12 % 12) + (full.ampm === "PM" ? 12 : 0)

    readonly property string hourText: String(full.hour12)
    readonly property string minuteText:
        full.minute < 10 ? "0" + full.minute : String(full.minute)

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

            Item {
                id: heroBox
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: dayBlock.visible ? dayBlock.top : parent.bottom
                anchors.bottomMargin: dayBlock.visible ? nothing.gap : 0

                // Sized for "12:45" even when it currently reads "9:03", so
                // the hero keeps its size across ten o'clock. Wide tile: one
                // line, 27 dot columns (5+1+5+1+3+1+5+1+5). Square tiles:
                // hour over minute, 11 columns and 15 rows, which is how the
                // Nothing digital clock next door fills a square.
                readonly property real dotSize: {
                    var cols = full.isWide ? 27 : 11
                    var rows = full.isWide ? 7 : 15
                    var byW = heroBox.width / (cols + (cols - 1) * 0.34)
                    var byH = heroBox.height / (rows + (rows - 1) * 0.34)
                    return Math.max(2, Math.min(byW, byH))
                }
                readonly property real dotGap: Math.max(1, heroBox.dotSize * 0.34)

                Column {
                    anchors.centerIn: parent
                    spacing: heroBox.dotGap
                    visible: !full.isWide

                    // Centred, not left-aligned: a one-glyph hour ("9") over
                    // a two-glyph minute ("03") hangs off to one side
                    // otherwise, and the 12-hour readout the twin publishes
                    // does not pad its hour.
                    NDotMatrix {
                        anchors.horizontalCenter: parent.horizontalCenter
                        theme: nothing
                        text: full.hourText
                        dot: heroBox.dotSize
                        gap: heroBox.dotGap
                        onColor: nothing.on
                    }
                    NDotMatrix {
                        anchors.horizontalCenter: parent.horizontalCenter
                        theme: nothing
                        text: full.minuteText
                        dot: heroBox.dotSize
                        gap: heroBox.dotGap
                        onColor: nothing.red
                    }
                }

                NDotMatrix {
                    anchors.centerIn: parent
                    theme: nothing
                    text: full.hourText + ":" + full.minuteText
                    dot: heroBox.dotSize
                    gap: heroBox.dotGap
                    onColor: nothing.on
                    visible: full.isWide
                }
            }

            // ── The city's 24 hours as dots ─────────────────────────────
            // The row is what the wide tile does with its extra width; the
            // large tile gets the label and rule above it as well.
            Column {
                id: dayBlock
                visible: full.isWide || full.isBig
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: nothing.px(6)

                Item {
                    width: parent.width
                    height: Math.max(hoursLabel.implicitHeight, dayBadge.implicitHeight)
                    visible: full.isBig

                    NLabel {
                        id: hoursLabel
                        theme: nothing
                        text: "Hours"
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    NBadge {
                        id: dayBadge
                        theme: nothing
                        active: full.isDay
                        label: full.isDay ? "Day" : "Night"
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                NDivider {
                    theme: nothing
                    width: parent.width
                    visible: full.isBig
                }

                Item {
                    id: hourDots
                    width: parent.width
                    height: nothing.px(8)

                    readonly property real dotGap: nothing.px(3)
                    readonly property real cell: Math.max(2, Math.min(
                        (hourDots.width - 23 * hourDots.dotGap) / 24, hourDots.height))

                    Row {
                        anchors.centerIn: parent
                        spacing: hourDots.dotGap

                        Repeater {
                            model: 24

                            delegate: Rectangle {
                                id: hourDot
                                required property int index
                                readonly property bool daylight:
                                    hourDot.index >= 6 && hourDot.index < 18
                                width: hourDots.cell
                                height: hourDots.cell
                                radius: hourDots.cell / 2
                                antialiasing: true
                                color: hourDot.index === full.hour24 ? nothing.red
                                     : hourDot.daylight ? nothing.onDim : nothing.onFaint

                                Behavior on color { ColorAnimation { duration: nothing.fast } }
                            }
                        }
                    }
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
