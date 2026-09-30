import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../components/nothing"

// Cities, dials — Nothing style.
//
// Same instance, same store row, same `plugin.settings.clocks` as the Liquid
// Glass city-1 tile next door; only the drawing differs. One WorldClockQs
// feeds up to four faces, exactly as the glass twin does, and the three
// layout presets keep the glass twin's thresholds rather than inventing new
// ones:
//
//   1x1 (count <= 1) : one face; city in the card header, offset in the footer.
//   2x2 (count 2-4)  : up to four faces, city code under each dial.
//   4x2 (count 2-4)  : the same faces in a row, NAME + day word + offset below.
//
// What the glass twin draws as a decorated watch plate, this drawing says in
// Nothing's own vocabulary: a segmented ring readout (NDial) instead of 60
// pill ticks and a filled disc, flat hands instead of a stroked hand shape,
// the card's own type tokens instead of a condensed face. The one thing kept
// from the glass twin is the per-city day/night signal — there it recolors the
// plate, here it lights a surface3 disc in daylight and leaves the card flat at
// night, which is the same flip drawn with surfaces instead of colors.
//
// Nothing here reads MacOSColors or LiquidGlass, and the glass-only keys
// (cornerRadius, refract*, tint*, blurRadius, opaqueBackground) have no
// meaning in this style, so this file reads none of them — same as the
// Nothing clock-analog and city-digital tiles.
Item {
    id: full
    anchors.fill: parent

    WorldClockQs {
        id: world
        clocks: plugin.settings.clocks
        // The faces carry a second hand, so the model has to wake on the
        // second — each city's own TzClock emits it. The glass twin passes
        // true for the same reason.
        needsSeconds: true
        active: full.visible
    }

    // --- Layout state: the glass twin's rule, unchanged. ---
    readonly property int _count: Math.max(1, Math.min(world.count, 4))
    readonly property bool _single: _count <= 1
    readonly property bool _wide: !_single && width >= height * 2
    readonly property int _cols: _single ? 1 : (_wide ? _count : 2)

    // A wide tile or a big square has room for a city's full name; the small
    // square gets the three-letter code instead (the Nothing city-digital
    // tile's rule, which the single face's header follows).
    readonly property bool _roomy: full.width >= full.height * 1.6
        || Math.min(full.width, full.height) >= nothing.px(300)

    // --- The second hand ---
    // This style ticks: one discrete step a second, landing with the short
    // overshoot a quartz movement has. `analogSecondSweep` — the setting the
    // glass twin ignores, because it always sweeps — turns the sweep back on
    // for the single face; the compositor's reduce-motion preference wins
    // over the setting. The grid faces always step: four 60fps canvases in
    // one tile is exactly the cost this style exists to avoid.
    Loader { id: motionWatch; source: "../../components/MotionWatch.qml" }

    readonly property bool _reducedMotion: motionWatch.item
        ? motionWatch.item.reduceMotion : false
    readonly property bool _sweep: plugin.settings.analogSecondSweep
        && !full._reducedMotion && full._single

    // Seconds are identical in every zone, so one local sweep is exact for
    // all four cities — the same reasoning WorldClockQs uses for its own
    // sweepAngle. Used only while `_sweep` is on; the ticking faces read
    // their city's own secondAngle off the model.
    property real _sweepSecond: 0
    Timer {
        interval: 16
        repeat: true
        running: full._sweep && full.visible
        onTriggered: {
            const d = new Date()
            full._sweepSecond = d.getSeconds() + d.getMilliseconds() / 1000
        }
    }

    NCard {
        id: card
        theme: nothing
        anchors.fill: parent

        // Atmospheric, and only on the single face at its full 400px square:
        // behind a 2x2 grid of dials the field would read as noise.
        NDotField {
            theme: nothing
            anchors.fill: parent
            anchors.margins: nothing.pad
            intensity: 0.5
            visible: full._single
                && Math.min(full.width, full.height) >= nothing.px(300)
        }

        // ==================== SINGLE (1x1) ====================
        Item {
            id: singleView
            anchors.fill: parent
            visible: full._single

            readonly property var e: world.entries.length ? world.entries[0] : null

            NLabel {
                id: singleHeader
                theme: nothing
                loud: true
                text: singleView.e
                    ? (full._roomy ? singleView.e.label : singleView.e.code) : ""
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: singleBadge.visible ? singleBadge.left : parent.right
                anchors.margins: nothing.pad
                anchors.rightMargin: singleBadge.visible ? nothing.gap : nothing.pad
                elide: Text.ElideRight
            }

            NBadge {
                id: singleBadge
                theme: nothing
                active: singleView.e ? singleView.e.isDay : false
                label: singleView.e ? singleView.e.ampm : ""
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: nothing.pad
                visible: singleView.e !== null && full.width >= nothing.px(150)
            }

            // Footer: the hour difference, and the date the city is on when
            // that is not the local one. The glass twin writes both inside
            // the dial; this style keeps meta text at the card edges.
            Item {
                id: singleFooter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: nothing.pad
                height: Math.max(offsetLine.implicitHeight, dayWordLabel.implicitHeight)

                NMono {
                    id: offsetLine
                    theme: nothing
                    text: singleView.e && singleView.e.offsetLabel !== ""
                        ? singleView.e.offsetLabel : "--"
                    color: nothing.onDim
                    font.pixelSize: nothing.fLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                }

                NLabel {
                    id: dayWordLabel
                    theme: nothing
                    text: singleView.e ? singleView.e.dayWord : ""
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: singleView.e !== null && singleView.e.dayWord !== "Today"
                }
            }

            CityDial {
                id: singleDial
                anchors.top: singleHeader.bottom
                anchors.topMargin: nothing.gap
                anchors.bottom: singleFooter.top
                anchors.bottomMargin: nothing.gap
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: nothing.pad
                anchors.rightMargin: nothing.pad

                theme: nothing
                hourAngle: singleView.e ? singleView.e.hourAngle : 0
                minuteAngle: singleView.e ? singleView.e.minuteAngle : 0
                secondAngle: full._sweep
                    ? full._sweepSecond * 6
                    : (singleView.e ? singleView.e.secondAngle : 0)
                ticked: !full._sweep
                showSecond: true
                // No day/night plate here: the glass 1x1 face keeps a neutral
                // plate too, and the badge beside the city already says
                // whether it is daytime there.
                plate: false
                showNumerals: singleDial.side >= nothing.px(150)
            }
        }

        // ==================== GRID (2x2) / ROW (4x2) ====================
        GridLayout {
            id: grid
            anchors.fill: parent
            anchors.margins: nothing.pad
            visible: !full._single
            columns: full._cols
            rowSpacing: nothing.gap
            columnSpacing: nothing.gap

            Repeater {
                // Bind to a stable COUNT, not the entries array: `world.entries`
                // is reassigned wholesale every second and an array model would
                // tear down and rebuild every delegate — the Canvas ring would
                // vanish and reappear. With an int model the delegates persist
                // and only the `e` binding below re-evaluates.
                model: full._single ? 0 : full._count

                delegate: Item {
                    id: cell
                    required property int index
                    readonly property var e: world.entries[index] || ({})
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    readonly property bool wide: full._wide
                    // Space the label block under the dial may occupy. The
                    // wide cell stacks NAME / day word / offset; the 2x2 cell
                    // carries one code line.
                    readonly property real labelH: Math.round(
                        cell.wide ? height * 0.34 : nothing.px(15))
                    readonly property real faceSize: Math.max(0,
                        Math.min(width, height - cell.labelH))

                    // Dial and label measured together and centred as one
                    // block, so a 4x2 face does not sit high with dead space
                    // under its text.
                    Item {
                        id: group
                        width: cell.width
                        height: cell.faceSize
                            + (cell.faceSize > 0
                                ? Math.round(cell.faceSize * 0.04) + cellInfo.implicitHeight
                                : 0)
                        anchors.centerIn: parent

                        CityDial {
                            id: cellDial
                            width: cell.faceSize
                            height: cell.faceSize
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top

                            theme: nothing
                            hourAngle: cell.e.hourAngle || 0
                            minuteAngle: cell.e.minuteAngle || 0
                            secondAngle: cell.e.secondAngle || 0
                            ticked: true
                            showSecond: true
                            // The glass twin's per-city day/night plate, in
                            // this style's terms: a lit disc by day, nothing
                            // by night.
                            plate: true
                            day: cell.e.isDay === undefined ? true : cell.e.isDay
                            showNumerals: cellDial.width >= nothing.px(150)
                        }

                        Column {
                            id: cellInfo
                            anchors.top: cellDial.bottom
                            anchors.topMargin: Math.round(cell.faceSize * 0.04)
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: nothing.px(2)

                            // Wide: the city's NAME (or the user's own label).
                            // 2x2: the three-letter code, quiet under the dial.
                            NLabel {
                                width: parent.width
                                theme: nothing
                                loud: cell.wide
                                font.pixelSize: cell.wide ? nothing.fLabel : nothing.fMicro
                                text: cell.wide
                                    ? (cell.e.label || cell.e.code || "")
                                    : (cell.e.code || "")
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                            NLabel {
                                width: parent.width
                                visible: cell.wide
                                theme: nothing
                                font.pixelSize: nothing.fMicro
                                text: cell.e.dayWord || ""
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                            NMono {
                                width: parent.width
                                visible: cell.wide
                                theme: nothing
                                color: nothing.onDim
                                font.pixelSize: nothing.fMicro
                                text: cell.e.offsetLabel || ""
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }

    // ── The dial ────────────────────────────────────────────────────────
    // One face, used at three sizes: the segmented ring is the readout (the
    // elapsed minutes of that city's hour, the same thing the Nothing analog
    // clock's ring shows), the flat hands are the time, and the hairline
    // second hand is the only thing that moves per second. Nothing here is
    // decorative: drop the ring and the tile still tells the time, drop the
    // hands and it stops being a clock.
    component CityDial: Item {
        id: dial
        required property var theme

        property real hourAngle: 0
        property real minuteAngle: 0
        property real secondAngle: 0
        property bool showSecond: true
        // True while the second hand steps; the hand then lands with a short
        // overshoot instead of teleporting.
        property bool ticked: true
        property bool showNumerals: false
        // The plate behind the ring. Off on the single face (the glass twin
        // leaves that one neutral too); on in the grid, where it is the
        // day/night signal. The glass twin flips a light plate to a dark one;
        // here a surface3 disc appears in daylight and the card stays flat at
        // night. An earlier cut used surface2 for the night plate, and the
        // level step between the two dark Nothing surfaces (surface2 ->
        // surface3) measured near-invisible on screen — a distinction nobody
        // can read is decoration, not information.
        property bool plate: false
        property bool day: true

        readonly property real side: Math.min(width, height)
        readonly property real cx: width / 2
        readonly property real cy: height / 2

        Rectangle {
            width: dial.side
            height: dial.side
            x: dial.cx - width / 2
            y: dial.cy - height / 2
            radius: width / 2
            visible: dial.plate && dial.day
            color: dial.theme.surface3
            antialiasing: true
        }

        NDial {
            width: dial.side
            height: dial.side
            x: dial.cx - width / 2
            y: dial.cy - height / 2
            theme: dial.theme
            ticks: 60
            majorEvery: 5
            value: dial.minuteAngle / 360
        }

        // 12 / 3 / 6 / 9 only, and only where the face is big enough for
        // them to sit inside the ring without crowding the hands.
        Repeater {
            model: dial.showNumerals ? ["12", "3", "6", "9"] : []

            delegate: NLabel {
                id: numeral
                required property int index
                required property var modelData
                readonly property real dist: dial.side * 0.30
                theme: dial.theme
                text: numeral.modelData
                font.pixelSize: dial.theme.fLabel
                x: dial.cx + Math.sin(numeral.index * Math.PI / 2) * numeral.dist
                   - numeral.width / 2
                y: dial.cy - Math.cos(numeral.index * Math.PI / 2) * numeral.dist
                   - numeral.height / 2
            }
        }

        // Hour hand: flat, blunt, the quiet one.
        Rectangle {
            id: hourHand
            width: Math.max(2, dial.side * 0.030)
            height: dial.side * 0.24
            radius: hourHand.width / 2
            color: dial.theme.on
            antialiasing: true
            x: dial.cx - hourHand.width / 2
            y: dial.cy - hourHand.height
            transformOrigin: Item.Bottom
            rotation: dial.hourAngle
        }

        // Minute hand: the one red thing on the face.
        Rectangle {
            id: minuteHand
            width: Math.max(2, dial.side * 0.022)
            height: dial.side * 0.36
            radius: minuteHand.width / 2
            color: dial.theme.red
            antialiasing: true
            x: dial.cx - minuteHand.width / 2
            y: dial.cy - minuteHand.height
            transformOrigin: Item.Bottom
            rotation: dial.minuteAngle
        }

        // Second hand: a hairline with a short counterweight. The overshoot is
        // the tick — OutBack carries it a degree or so past the mark and lets
        // it settle back. Wrapping 59 -> 0 is excluded, or the hand would spin
        // the long way round once a minute.
        Rectangle {
            id: secondHand
            readonly property real len: dial.side * 0.42
            width: Math.max(1, dial.side * 0.008)
            height: secondHand.len + dial.side * 0.08
            color: dial.theme.onDim
            antialiasing: true
            visible: dial.showSecond
            x: dial.cx - secondHand.width / 2
            y: dial.cy - secondHand.len
            transform: Rotation {
                origin.x: secondHand.width / 2
                origin.y: secondHand.len
                angle: dial.secondAngle

                Behavior on angle {
                    enabled: dial.ticked && dial.secondAngle > 0
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
            width: Math.max(4, dial.side * 0.055)
            height: width
            radius: width / 2
            color: dial.theme.on
            antialiasing: true
            x: dial.cx - width / 2
            y: dial.cy - height / 2
        }
        Rectangle {
            // surfaceSolid: the backdrop here is the cap, not the card material.
            width: Math.max(2, dial.side * 0.020)
            height: width
            radius: width / 2
            color: dial.theme.surfaceSolid
            antialiasing: true
            x: dial.cx - width / 2
            y: dial.cy - height / 2
        }
    }
}
