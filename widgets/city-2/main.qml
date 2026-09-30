import QtQuick
import QtQuick.Layouts
import "../../components"
import "widget"

// City II — world clock built on clock-analog-2's minimal-marks dial.
// Same layout shell as City I (1x1 / 2x2 / 4x2); the face has 12 hour lines
// and no numerals. Grid discs flip light(day)/dark(night) per city; the outer
// squircle is solid-dark by default and turns glass when "Fully opaque
// background" is off.

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

    WorldClockQs {
        id: world
        clocks: plugin.settings.clocks
        // Seconds sweep in every mode (single + grid faces show a second hand).
        needsSeconds: true
        active: full.visible
    }

    readonly property int _count: Math.max(1, Math.min(world.count, 4))
    readonly property bool _single: _count <= 1
    readonly property bool _wide: !_single && width >= height * 2
    readonly property int _cols: _single ? 1 : (_wide ? _count : 2)

    function _discColor(isDay) { return isDay ? colors.dialPlateDay : colors.dialPlateNight }
    function _markColor(isDay) { return isDay ? colors.dialMarkDay : colors.dialMarkNight }

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

    // ==================== SINGLE (1x1) ====================
    Item {
        id: singleView
        anchors.fill: parent
        visible: full._single

        readonly property var e: world.entries.length ? world.entries[0] : null
        readonly property real _r: Math.min(width, height) * 0.42

        ClockFace {
            anchors.fill: parent
            anchors.margins: Math.min(full.width, full.height) * 0.08
            showSeconds: true
            hourAngle:   singleView.e ? singleView.e.hourAngle : 0
            minuteAngle: singleView.e ? singleView.e.minuteAngle : 0
            secondAngle: singleView.visible ? world.sweepAngle : 0
            discVisible: true
            discColor: colors.dialPlate
            markColor: colors.foreground
            markOpacity: 0.75
            handOpacity: colors.dialHandOpacity
        }

        // Code above the hinge, offset (number only, e.g. "+12") below it —
        // centered as a group, same color/opacity as the dial marks.
        readonly property real _annoFont: Math.max(8, singleView._r * 0.16)
        readonly property real _annoInset: singleView._r * 0.40
        // One quiet step, not two: the annotation used to compound a second
        // 0.55 on top of the glass 0.55 (0.30), below the documented floor
        // (MacOSColors.textQuiet) and unreadable on a dark card. City
        // Digital's lowered opacity IS this 0.55, which `annotationOpacity`
        // applies in glass and drops in solid.
        readonly property real _annoOpacity: colors.annotationOpacity

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height / 2 - singleView._annoInset - height / 2
            text: singleView.e ? singleView.e.code : ""
            font.family: colors.uiFont
            font.pixelSize: singleView._annoFont
            font.weight: Font.Medium
            color: colors.foreground
            opacity: singleView._annoOpacity
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height / 2 + singleView._annoInset - height / 2
            text: singleView.e ? singleView.e.offsetLabel.replace("HRS", "") : ""
            font.family: colors.uiFont
            font.pixelSize: singleView._annoFont
            font.weight: Font.Medium
            color: colors.foreground
            opacity: singleView._annoOpacity
        }
    }

    // ==================== GRID (2x2) / ROW (4x2) ====================
    GridLayout {
        id: grid
        anchors.fill: parent
        anchors.margins: Math.round(Math.min(full.width, full.height) * 0.06)
        visible: !full._single
        columns: full._cols
        // Tighter gap between clocks than the outer padding.
        rowSpacing: Math.round(anchors.margins * 0.4)
        columnSpacing: Math.round(anchors.margins * 0.4)

        Repeater {
            // Bind to a stable COUNT, not the entries array. `world.entries`
            // is reassigned wholesale every second, which would tear down and
            // recreate every delegate (Canvas faces vanish/reappear → the
            // "blinking"). With an int model the delegates persist and only
            // the live `modelData` binding below re-evaluates.
            model: full._single ? 0 : full._count

            delegate: Item {
                id: cell
                required property int index
                readonly property var modelData: world.entries[index] || ({})
                Layout.fillWidth: true
                Layout.fillHeight: true

                readonly property bool wide: full._wide
                readonly property real infoH: wide ? Math.round(height * 0.34) : 0
                // Inset between the face and its cell edges: 10px in the 2x2
                // grid, and a small wide-mode inset so adjacent 4x2 faces don't
                // crowd each other (margin between faces — faces stay full size).
                readonly property real _faceInset: wide ? Math.round(width * 0.08) : 10
                readonly property real faceSize: Math.max(0, Math.min(width - _faceInset, height - infoH))

                // Group the face + (wide) label and center it in the cell. The
                // group height is the face plus the label's REAL content height
                // (not the infoH reservation) so centerIn centers the visible
                // block instead of leaving dead space below the text.
                Item {
                    id: group
                    width: cell.faceSize
                    height: cell.faceSize + (cell.wide ? cityLabel.fullContentHeight
                                                             + Math.round(cell.faceSize * 0.04)
                                                       : 0)
                    anchors.centerIn: parent

                    ClockFace {
                        id: gridFace
                        width: cell.faceSize
                        height: cell.faceSize
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        showSeconds: true
                        thickSecond: true
                        // Grid faces step the second hand once per second
                        // (per-city secondAngle), not the 60fps sweep — the
                        // simultaneous per-frame Canvas repaints across all
                        // faces is what caused the blinking.
                        secondAngle: cell.modelData.secondAngle
                        hourAngle:   cell.modelData.hourAngle
                        minuteAngle: cell.modelData.minuteAngle
                        discVisible: true
                        discColor: full._discColor(cell.modelData.isDay)
                        markColor: full._markColor(cell.modelData.isDay)
                        markOpacity: 0.75
                        handOpacity: 0.92
                    }

                    // City code INSIDE the face, toward the TOP (same edge
                    // margin the bottom placement used), code only. It is
                    // drawn ON the disc in the disc's own ink, so it takes
                    // the face's mark opacity like its hour lines do — it
                    // used to compound a second 0.55 on top of the first
                    // ((isGlass ? 0.55 : 1.0) * 0.55 = 0.30 as glass), which
                    // is below MacOSColors.textQuiet and rendered as a ghost.
                    Text {
                        anchors.horizontalCenter: gridFace.horizontalCenter
                        y: gridFace.y + cell.faceSize * 0.30 - height / 2
                        text: cell.modelData.code
                        font.family: colors.uiFont
                        font.pixelSize: Math.max(7, cell.faceSize * 0.13)
                        font.weight: Font.Medium
                        color: full._markColor(cell.modelData.isDay)
                        opacity: gridFace.markOpacity
                    }

                    CityLabel {
                        id: cityLabel
                        visible: cell.wide
                        anchors.top: gridFace.bottom
                        anchors.topMargin: Math.round(cell.faceSize * 0.04)
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: fullContentHeight
                        mode: "full"
                        fontFamily: colors.uiFont
                        code: cell.modelData.code
                        // Prefer the user's typed label; it already falls
                        // back to the resolved city name when left blank.
                        name: cell.modelData.label
                        dayWord: cell.modelData.dayWord
                        offsetLabel: cell.modelData.offsetLabel
                        textColor: colors.foreground
                        primaryOpacity:   1.0
                        secondaryOpacity: colors.citySecondaryOpacity
                        baseFontSize: Math.max(8, cell.faceSize * 0.13)
                    }
                }
            }
        }
    }
}
