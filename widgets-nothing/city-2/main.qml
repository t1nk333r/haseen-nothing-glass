import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../components/nothing"

// City II, Nothing style: the world clock on the "Analog — Markers" face.
//
// The Liquid Glass twin (widgets/city-2/main.qml) is a world clock built on
// clock-analog-2's minimal-marks dial — twelve hour lines, no numerals — with
// the same layout shell at every size: 1x1 single dial, 2x2 grid, 4x2 row,
// each grid disc flipping light(day)/dark(night) by that city's local time.
// This file keeps that shell and that content (city, offset, day word, the
// day/night plate) and draws it in this style's language.
//
// The face is the one widgets-nothing/clock-analog-2 already established for
// this dial: twelve heavy pills, the hours the hand has reached inked and the
// rest `onFaint`, flat hands with the minute one in the accent, a hairline
// ticking second hand and the sibling's hub. It is a readout, not decoration
// — the ring fills through the half-day exactly as NDial fills through the
// hour. The single tile and every grid cell share the one `CityDial` inline
// component, so the two views cannot drift apart.
//
// Everything visual comes from `nothing`, the NTheme WidgetHost injects;
// MacOSColors, LiquidGlass and qs.Ui are never touched here, and the
// glass-only configuration keys (cornerRadius, refract*, tint*, blurRadius,
// opaqueBackground, styleMode, appearance) have no meaning in this style, so
// this file reads none of them. `theme` and `backdrop` are likewise never
// read: a Nothing tile draws its own card over the desktop, it does not
// refract what is behind it.
Item {
    id: full
    anchors.fill: parent

    // The three grid presets: 192x192, 400x192, 400x400. Same thresholds as
    // the sibling Nothing clocks — the face changes size, not the tile's
    // proportions.
    readonly property bool isWide: full.width >= full.height * 1.6
    readonly property bool isBig: !full.isWide && Math.min(full.width, full.height) >= 300

    // Same data path as the Liquid Glass twin: WorldClockQs off the `clocks`
    // setting, seconds on because every face carries a second hand. One
    // model, one set of TzClocks, no second timer.
    WorldClockQs {
        id: world
        clocks: plugin.settings.clocks
        needsSeconds: true
        active: full.visible
    }

    // The twin's shell rule, unchanged: up to four cities, one of them (or
    // none) is a single dial, the row appears only where the tile is twice as
    // wide as tall.
    readonly property int _count: Math.max(1, Math.min(world.count, 4))
    readonly property bool _single: _count <= 1
    readonly property bool _wide: !_single && width >= height * 2
    readonly property int _cols: _single ? 1 : (_wide ? _count : 2)

    readonly property var _entry: world.entries.length ? world.entries[0] : null

    // Fail open: if the compositor's style module is missing, `item` is null
    // and the clock animates. See components/MotionWatch.qml.
    Loader { id: motionWatch; source: "../../components/MotionWatch.qml" }

    readonly property bool _reducedMotion: motionWatch.item
        ? motionWatch.item.reduceMotion : false

    // Off by default: this style ticks. The single dial follows the Nothing
    // analog clocks — the sweep setting turns the free-running sweep back on,
    // reduced motion overrides it — while the grid faces always step once a
    // second off each city's own `secondAngle`, exactly as the glass twin's
    // grid faces do (four simultaneous 60fps faces is what made that drawing
    // blink). The Liquid Glass single tile sweeps unconditionally because it
    // never reads this setting; here the style's own behaviour wins.
    readonly property bool _sweep: plugin.settings.analogSecondSweep
        && !_reducedMotion

    // ── The face: the dial, marks ──────────────────────────────────────
    // Shared by the single tile and every grid cell. Geometry and inks are
    // widgets-nothing/clock-analog-2's face verbatim; what is parameterized
    // is what differs per use: the angles, the plate, and whether the second
    // hand sweeps or ticks.
    component CityDial: Item {
        id: dial

        required property var theme

        property real hourAngle: 0
        property real minuteAngle: 0
        property real secondAngle: 0
        // The wall second, so the tick animation can skip the 59 -> 0 wrap
        // (a hand that swings all the way round once a minute).
        property int second: 0
        property bool sweep: false

        // The plate behind the ring. Off on the single face (the glass twin
        // keeps it neutral there, and the badge beside the city already says
        // whether it is daytime there), on per city in the grid — and there it
        // is the day/night signal: the glass twin flips a light plate to a
        // dark one, this style lights a surface3 disc in daylight and leaves
        // the card flat at night. A level step between the two dark Nothing
        // surfaces (surface2 -> surface3) measured near-invisible on screen,
        // which makes the flip decoration rather than information.
        property bool plate: false
        property bool day: true

        readonly property real side: Math.min(width, height)

        // Mark 0 is 12 o'clock and the ring winds clockwise, so this is
        // "marks passed in this half-day" — the same thing NDial's `value`
        // means, one hour at a time instead of one minute at a time. At
        // exactly 3:00 the hand sits on the 3 mark and that mark is lit.
        readonly property int litMarks: Math.floor(dial.hourAngle / 30) + 1

        // The day/night plate the glass twin's grid discs carry.
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            visible: dial.plate && dial.day
            color: dial.theme.surface3
            antialiasing: true
        }

        // Twelve heavy hour marks. A Repeater of rotated rectangles, not a
        // Canvas: the ink is a bound property, so a palette change repaints
        // with no requestPaint() to mirror by hand.
        Repeater {
            model: 12

            delegate: Item {
                required property int index
                anchors.fill: parent
                // Mark 0 sits at the top and the ring winds clockwise, so
                // rotating the full-face container by the index is the whole
                // placement — no per-mark trigonometry.
                rotation: index * 30

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: dial.side * 0.02
                    width: Math.max(3, dial.side * 0.036)
                    height: Math.max(4, dial.side * 0.118)
                    radius: width / 2
                    color: index < dial.litMarks ? dial.theme.on : dial.theme.onFaint
                    antialiasing: true
                }
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
            x: dial.width / 2 - hourHand.width / 2
            y: dial.height / 2 - hourHand.height
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
            x: dial.width / 2 - minuteHand.width / 2
            y: dial.height / 2 - minuteHand.height
            transformOrigin: Item.Bottom
            rotation: dial.minuteAngle
        }

        // Second hand: a hairline with a short counterweight.
        //
        // The overshoot is the tick: OutBack carries the hand a degree or so
        // past the mark and lets it settle back, which is what makes a step
        // read as a mechanical movement instead of a teleport. Wrapping
        // 59 -> 0 is excluded, or the hand would spin the long way round once
        // a minute.
        Rectangle {
            id: secondHand
            readonly property real len: dial.side * 0.42
            width: Math.max(1, dial.side * 0.008)
            height: secondHand.len + dial.side * 0.08
            color: dial.theme.onDim
            antialiasing: true
            x: dial.width / 2 - secondHand.width / 2
            y: dial.height / 2 - secondHand.len
            transform: Rotation {
                origin.x: secondHand.width / 2
                origin.y: secondHand.len
                angle: dial.secondAngle

                Behavior on angle {
                    enabled: !dial.sweep && dial.second !== 0
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
            anchors.centerIn: parent
        }
        Rectangle {
            // surfaceSolid: the backdrop here is the cap, not the card material.
            width: Math.max(2, dial.side * 0.020)
            height: width
            radius: width / 2
            color: dial.theme.surfaceSolid
            antialiasing: true
            anchors.centerIn: parent
        }
    }

    // ==================== SINGLE (1x1) ====================
    NCard {
        id: singleCard
        theme: nothing
        anchors.fill: parent
        visible: full._single

        // Atmospheric, and only on the single face at its full 400px square:
        // behind a 2x2 grid of dials the field would read as noise.
        NDotField {
            theme: nothing
            anchors.fill: parent
            anchors.margins: nothing.pad
            intensity: 0.4
            visible: full._single && full.isBig
        }

        // ── Header: the city ───────────────────────────────────────────
        // The full name where there is room for it, the code where there is
        // not - the Nothing city widgets' rule.
        NLabel {
            id: header
            theme: nothing
            loud: true
            text: full._entry
                ? (full.isWide || full.isBig ? full._entry.label : full._entry.code)
                : ""
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
            active: full._entry ? full._entry.isDay : false
            label: full._entry ? full._entry.ampm : ""
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: nothing.pad
            visible: full._entry !== null && full.width >= nothing.px(150)
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

            CityDial {
                theme: nothing
                anchors.centerIn: parent
                // The twin's 8% inset is not needed here: the card's header
                // and footer already reserve the tile's edges, so the dial is
                // simply the largest square the stage holds.
                readonly property real fit: Math.max(nothing.px(40),
                                                     Math.min(stage.width, stage.height))
                width: fit
                height: fit

                hourAngle: full._entry ? full._entry.hourAngle : 0
                minuteAngle: full._entry ? full._entry.minuteAngle : 0
                // Sweep off the model's shared local sweep for smoothness,
                // exactly like the glass twin; off = the city's own stepped
                // angle, which WorldClockQs republishes every second.
                secondAngle: full._sweep
                    ? world.sweepAngle
                    : (full._entry ? full._entry.secondAngle : 0)
                second: full._entry ? full._entry.second : 0
                sweep: full._sweep
                // No day/night plate here: the glass 1x1 face keeps a neutral
                // plate too, and the badge beside the city already says
                // whether it is daytime there.
                plate: false
            }
        }

        // ── Footer: the hour offset, and the city's date ───────────────
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
                text: full._entry && full._entry.offsetLabel !== ""
                    ? full._entry.offsetLabel : "--"
                color: nothing.onDim
                font.pixelSize: nothing.fLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
            }

            NLabel {
                id: dayWordLabel
                theme: nothing
                text: full._entry ? full._entry.dayWord : ""
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                // The glass twin writes the day word inside the dial; here it
                // is only worth the corner when the city is on another date.
                visible: full._entry !== null && full._entry.dayWord !== "Today"
            }
        }
    }

    // ==================== GRID (2x2) / ROW (4x2) ====================
    // No card header, no footer and no dot field here: the glass grid has
    // none of them, the faces and their labels fill the tile, and a 2x2 grid
    // of dials over a dot field reads as noise.
    NCard {
        id: gridCard
        theme: nothing
        anchors.fill: parent
        visible: !full._single

        GridLayout {
            id: grid
            anchors.fill: parent
            anchors.margins: nothing.pad
            columns: full._cols
            rowSpacing: nothing.gap
            columnSpacing: nothing.gap

            Repeater {
                // Bind to a stable COUNT, not the entries array: `world.entries`
                // is reassigned wholesale every second, which would tear down
                // and recreate every delegate. With an int model the delegates
                // persist and only the live `modelData` binding re-evaluates.
                model: full._single ? 0 : full._count

                delegate: Item {
                    id: cell
                    required property int index
                    readonly property var modelData: world.entries[index] || ({})
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    readonly property bool wide: full._wide
                    readonly property bool isDay: cell.modelData.isDay === true
                    readonly property real infoH: wide ? Math.round(height * 0.34) : 0
                    // Mirrors the twin: a small inset between face and cell
                    // edge in the 2x2 grid, a proportional one in the row so
                    // adjacent faces don't crowd each other.
                    readonly property real _faceInset: wide ? Math.round(width * 0.08)
                                                            : nothing.px(4)
                    readonly property real faceSize: Math.max(0, Math.min(width - _faceInset,
                                                                          height - infoH))

                    // Group the face and (row) label block, and center the
                    // group: on the real content height, so the visible block
                    // is centered instead of leaving dead space below it.
                    Item {
                        id: group
                        width: cell.faceSize
                        height: cell.faceSize + (cell.wide
                            ? labelBlock.implicitHeight + nothing.px(4) : 0)
                        anchors.centerIn: parent

                        CityDial {
                            id: gridFace
                            theme: nothing
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            width: cell.faceSize
                            height: cell.faceSize

                            hourAngle: cell.modelData.hourAngle || 0
                            minuteAngle: cell.modelData.minuteAngle || 0
                            secondAngle: cell.modelData.secondAngle || 0
                            second: cell.modelData.second || 0
                            sweep: false

                            // The glass twin's per-city day/night plate, in
                            // this style's terms: a lit disc by day, nothing
                            // by night.
                            plate: true
                            day: cell.isDay
                        }

                        // City code inside the face, toward the top — the
                        // glass grid's placement, dimmed the same way.
                        NMono {
                            anchors.horizontalCenter: gridFace.horizontalCenter
                            y: gridFace.y + cell.faceSize * 0.30 - height / 2
                            theme: nothing
                            text: cell.modelData.code || ""
                            color: nothing.on
                            opacity: 0.55
                            font.pixelSize: Math.max(nothing.px(7), cell.faceSize * 0.13)
                        }

                        // Row only: name, then the day word and the hour
                        // offset — the glass CityLabel "full" block.
                        Column {
                            id: labelBlock
                            visible: cell.wide
                            anchors.top: gridFace.bottom
                            anchors.topMargin: nothing.px(4)
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: nothing.px(2)

                            NLabel {
                                theme: nothing
                                width: parent.width
                                text: cell.modelData.label || ""
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                            NMono {
                                theme: nothing
                                width: parent.width
                                text: cell.modelData.dayWord || ""
                                color: nothing.onDim
                                font.pixelSize: nothing.fMicro
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                            NMono {
                                theme: nothing
                                width: parent.width
                                text: cell.modelData.offsetLabel || ""
                                color: nothing.onDim
                                font.pixelSize: nothing.fMicro
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }
}
