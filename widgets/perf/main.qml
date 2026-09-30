import QtQuick
import "../../components"

// What the machine is doing, Liquid Glass.
//
// The glass twin of widgets-nothing/perf/main.qml, carrying the same facts out
// of the same engine: PerfData reads /proc/stat, /proc/meminfo and the hwmon
// temperature files, and owns the family's one timer. Its `active` is bound to
// this widget's `visible`, so a tile on a workspace nobody is looking at reads
// nothing at all.
//
// The accent carries exactly ONE meaning here, as it does on the Nothing
// drawing: the processor pinned at 90% or more. `colors.accentRed` marks the
// HIGH chip, the load figure and the load meter's fill, and nothing else. A
// temperature is never red - a reading about the machine's cooling is not a
// verdict on it, and two meanings on one colour is how a status widget stops
// being readable at a glance.
//
// Three layouts, one per grid preset (WidgetRegistry.sizes):
//   192x192   the load as the hero over its meter, and one footer line:
//             memory in use on the left, the primary sensor on the right.
//   400x192   the hero and the memory block in the left column; the sensor
//             rows on the right, behind the column rule the battery drawing
//             puts at the same split.
//   400x400   the hero on the large stage, then the memory block, then the
//             sensor rows.
//
// Facts first, layout second: the Nothing drawing carries the same set, and a
// new figure in PerfData belongs on both.
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

    // The only thing here that reads the machine, and the only timer.
    PerfData {
        id: perf
        active: full.visible
    }

    // The family's one type and margin scale - see components/GlassScale.qml.
    // `gscale` and not `scale`: `scale` is Item's own transform property, and
    // an unqualified outer id loses to it inside a Repeater delegate.
    GlassScale {
        id: gscale
        tileWidth: full.width
        tileHeight: full.height
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

    // ── The three presets ────────────────────────────────────────────────
    readonly property bool isWide: gscale.isWide
    readonly property bool isBig: gscale.isBig

    // The one fact the accent means.
    readonly property bool high: perf.cpuReady && perf.cpuPercent >= 90

    // A percentage is whole: the tenth the store measures is under the noise
    // of where a glance lands on the number.
    readonly property string cpuText: perf.cpuReady ? String(Math.round(perf.cpuPercent)) : "--"
    readonly property string memPctText: perf.memReady ? Math.round(perf.memPercent) + "%" : "--"

    // The namespaced reading the small tile's footer carries. The chip is
    // named there because a bare "58°" would not say which one it belongs to.
    readonly property string footTempText: perf.tempsReady
        ? perf.temps[0].name.toUpperCase() + " " + perf.temps[0].text : "--"

    Item {
        id: body
        anchors.fill: parent
        anchors.margins: gscale.pad

        // Every band below is derived from these, so the same file lays out at
        // 160x120 and at 400x400 without a literal picked by eye.
        readonly property real headH: Math.max(header.implicitHeight, badge.implicitHeight)
        readonly property real barH: Math.max(3, Math.round(gscale.tight * 0.36))
        // The sensor rows are a value line each (the family's `1.35` row ratio
        // is the battery drawing's; this face has no meter under a row, so a
        // little tighter).
        readonly property real rowH: Math.round(gscale.body * 1.25)
        readonly property real splitX: Math.round(body.width * 0.54)
        readonly property bool split: full.isWide
        readonly property real leftW: body.split
            ? Math.max(0, body.splitX - gscale.gap)
            : body.width

        // Label line, use, meter - a block whose height is their sum rather
        // than a number that can drift from what it draws.
        readonly property real memLineH: Math.round(gscale.body * 1.2)
        readonly property real memBlockH: body.memLineH + gscale.gap + body.barH

        // One row per sensor the store read (three at most), and the hero's
        // share of the large tile: the taller of a floor and what those rows
        // leave, capped at 42% so a hero can never eat the tile either.
        readonly property real sensorRowsH: perf.temps.length * body.rowH
        readonly property real bigStageH: Math.max(Math.round(gscale.hero * 0.55),
            Math.min(Math.round(body.height * 0.42),
                body.height - body.headH - gscale.gap - body.memBlockH
                    - gscale.gap - body.sensorRowsH - gscale.gap))

        // ── Header ──────────────────────────────────────────────────────
        Text {
            id: header
            text: "System"
            color: colors.foreground
            opacity: 0.75
            font.family: colors.uiFont
            font.pixelSize: gscale.micro
            font.letterSpacing: gscale.micro * 0.10
            elide: Text.ElideRight
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: badge.visible ? badge.left : parent.right
            anchors.rightMargin: badge.visible ? gscale.gap : 0
        }

        // The one red thing a tile can carry: the processor pinned at 90% or
        // more. The hero figure and the load meter carry the same fact, drawn
        // once more - never a second meaning.
        Text {
            id: badge
            visible: full.high
            text: "HIGH"
            color: colors.accentRed
            font.family: colors.uiFont
            font.pixelSize: gscale.micro
            font.letterSpacing: gscale.micro * 0.14
            font.weight: Font.DemiBold
            anchors.top: parent.top
            anchors.right: parent.right
        }

        // ── The load: the hero on every preset ──────────────────────────
        Item {
            id: stage
            x: 0
            y: body.headH + gscale.gap
            width: body.leftW
            // Small and wide: everything the footer and the memory block need
            // is reserved first, and the hero takes what is left. Large: the
            // same idea with a ceiling - the hero may have 42% of the tile, or
            // whatever the memory band and one row per sensor leave, whichever
            // is less. Sizing the hero first is what pushed the third sensor
            // off the large tile.
            height: full.isBig
                ? body.bigStageH
                : Math.max(0, (full.isWide && memBlock.visible
                        ? memBlock.y
                        : footer.visible ? footer.y : body.height) - gscale.gap - stage.y)

            // The family's hero role is the ceiling; the stage is what keeps
            // the figure off the rows under it. 1.3 is the line box a font
            // pixel size actually draws at, plus the label and meter the same
            // column carries.
            readonly property real labelH: Math.round(gscale.micro * 1.3)
            readonly property real heroSize: {
                var use = stage.height - stage.labelH - body.barH - 2 * Math.round(gscale.tight * 0.5)
                return Math.max(12, Math.round(Math.min(gscale.hero, use / 1.3)))
            }

            Column {
                id: hero
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.round(gscale.tight * 0.5)

                // Names the figure under it, the way the header names the tile.
                Text {
                    text: "CPU"
                    color: colors.foreground
                    opacity: 0.6
                    font.family: colors.uiFont
                    font.pixelSize: gscale.micro
                    font.letterSpacing: gscale.micro * 0.10
                }

                // The unit FOLLOWS the number - "12 %", not "%12": it is a
                // percentage, and a mark on the wrong side of the figure is
                // read as a different quantity. It shares the number's
                // baseline rather than its top, which is what a Row would do.
                Item {
                    id: heroLine
                    width: parent.width
                    height: heroAmount.implicitHeight

                    Text {
                        id: heroAmount
                        text: full.cpuText
                        color: full.high ? colors.accentRed : colors.foreground
                        opacity: perf.cpuReady ? 1.0 : 0.4
                        font.family: colors.uiFont
                        font.pixelSize: stage.heroSize
                        anchors.left: parent.left
                        anchors.top: parent.top
                    }
                    Text {
                        id: heroMark
                        visible: perf.cpuReady
                        text: "%"
                        color: heroAmount.color
                        opacity: 0.7
                        font.family: colors.uiFont
                        font.pixelSize: Math.round(stage.heroSize * 0.46)
                        anchors.left: heroAmount.right
                        anchors.leftMargin: Math.round(gscale.tight * 0.25)
                        anchors.baseline: heroAmount.baseline
                    }
                }

                // The load meter: the one fact a glance reads without the
                // number. It is drawn even before the first reading, at zero,
                // because the track is what makes the empty part readable.
                Item {
                    id: loadMeter
                    width: parent.width
                    height: body.barH

                    Rectangle {
                        id: loadTrack
                        anchors.fill: parent
                        radius: height / 2
                        color: colors.foreground
                        opacity: 0.20
                    }
                    Rectangle {
                        anchors.left: loadTrack.left
                        anchors.top: loadTrack.top
                        height: loadTrack.height
                        radius: loadTrack.radius
                        width: Math.round(loadTrack.width
                            * Math.max(0, Math.min(1, perf.cpuPercent / 100)))
                        color: full.high ? colors.accentRed : colors.foreground
                        opacity: full.high ? 1.0 : 0.8
                    }
                }
            }
        }

        // ── Memory, under the hero (wide and large) ─────────────────────
        // The same three parts the sensor rows carry, with a meter: memory has
        // a total, so a fraction of it is a reading. A temperature does not.
        Item {
            id: memBlock
            visible: perf.memReady && (full.isWide || full.isBig)
            x: 0
            width: body.leftW
            height: body.memBlockH
            y: full.isWide
                ? Math.max(0, body.height - body.memBlockH)
                : Math.max(0, stage.y + stage.height + gscale.gap)

            Text {
                id: memLabel
                text: "Mem"
                color: colors.foreground
                opacity: colors.textQuiet
                font.family: colors.uiFont
                font.pixelSize: gscale.micro
                elide: Text.ElideRight
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: memValue.left
                anchors.rightMargin: gscale.gap
            }
            Text {
                id: memValue
                text: perf.memText
                color: colors.foreground
                opacity: 0.85
                font.family: colors.uiFont
                font.pixelSize: gscale.body
                anchors.top: parent.top
                anchors.right: parent.right
            }
            Rectangle {
                id: memTrack
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: body.barH
                radius: height / 2
                color: colors.foreground
                opacity: 0.20
            }
            Rectangle {
                anchors.left: memTrack.left
                anchors.bottom: memTrack.bottom
                height: memTrack.height
                radius: memTrack.radius
                width: Math.round(memTrack.width
                    * Math.max(0, Math.min(1, perf.memPercent / 100)))
                color: colors.foreground
                opacity: 0.8
            }
        }

        // ── The sensors ─────────────────────────────────────────────────
        // One row per chip: its name, its reading, a hairline. Wide: a column
        // to the right of the hero, behind the battery drawing's rule. Large:
        // a block under the memory band. Small: gone - the footer line carries
        // the primary sensor, and one reading is all that tile has room for.
        Item {
            id: sensorBlock
            visible: full.isWide || full.isBig
            x: full.isWide ? body.splitX + gscale.gap : 0
            width: full.isWide ? Math.max(0, body.width - sensorBlock.x) : body.width

            // Where the block starts. Wide: the top of the column, so the
            // centring below is centring. Large: right under the memory band.
            // Computed from the bands above it, never from `height` - a cap
            // taken from the block's own height would be a binding loop. Wide:
            // as many rows as the column holds. Large: all of them, because
            // `bigStageH` sized the hero to leave exactly this much room. The
            // small tile has no block at all, so it builds no rows.
            readonly property real topY: full.isWide
                ? 0
                : Math.max(0, memBlock.y + memBlock.height + gscale.gap)
            readonly property bool shown: full.isWide || full.isBig
            readonly property int cap: !sensorBlock.shown ? 0
                : full.isWide
                    ? Math.max(0, Math.floor((body.height - sensorBlock.topY) / body.rowH))
                    : perf.temps.length
            readonly property var rows: perf.temps.slice(0, sensorBlock.cap)
            // Where the rows sit when they do not fill their band. A list that
            // is a pixel short of the tile's foot and a list with a hand's
            // width of space under it are the same list; what is not the same
            // is a block clinging to the memory band with two centimetres of
            // nothing beneath it.
            readonly property real slack: Math.max(0,
                body.height - sensorBlock.topY - sensorBlock.height)

            height: sensorBlock.rows.length * body.rowH
            // Wide: centred against the hero, as the family's other side
            // columns are, but never above the header. Large: centred in what
            // the bands above it left.
            y: full.isWide
                ? Math.max(body.headH + gscale.gap,
                    Math.round((body.height - sensorBlock.height) / 2))
                : sensorBlock.topY + Math.round(sensorBlock.slack / 2)

            Column {
                width: parent.width

                Repeater {
                    model: sensorBlock.rows

                    Item {
                        id: row
                        required property var modelData
                        required property int index

                        width: sensorBlock.width
                        height: body.rowH

                        Text {
                            text: row.modelData.name
                            color: colors.foreground
                            opacity: colors.textQuiet
                            font.family: colors.uiFont
                            font.pixelSize: gscale.micro
                            elide: Text.ElideRight
                            anchors.left: parent.left
                            anchors.right: rowValue.left
                            anchors.rightMargin: gscale.gap
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            id: rowValue
                            text: row.modelData.text
                            color: colors.foreground
                            opacity: 0.85
                            font.family: colors.uiFont
                            font.pixelSize: gscale.body
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Rectangle {
                            visible: row.index < sensorBlock.rows.length - 1
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 1
                            color: colors.separator
                        }
                    }
                }
            }
        }

        // The column rule, at the split the Nothing drawing puts its own
        // vertical at: from the header's foot to the tile's foot.
        Rectangle {
            id: columnRule
            visible: body.split
            x: body.splitX
            y: body.headH
            width: 1
            height: Math.max(0, body.height - body.headH)
            color: colors.separator
        }

        // ── Footer: the small tile's two readings ───────────────────────
        // The tile that carries no memory block and no sensor rows states both
        // facts on one line, each with its own name.
        Item {
            id: footer
            visible: !full.isWide && !full.isBig
            x: 0
            width: body.width
            height: Math.max(footMem.implicitHeight, footTemp.implicitHeight)
            y: Math.max(0, body.height - footer.height)

            Text {
                id: footMem
                text: "MEM " + full.memPctText
                color: colors.foreground
                opacity: colors.textQuiet
                font.family: colors.uiFont
                font.pixelSize: gscale.micro
                font.letterSpacing: gscale.micro * 0.10
                elide: Text.ElideRight
                anchors.left: parent.left
                anchors.right: footTemp.left
                anchors.rightMargin: gscale.gap
                anchors.bottom: parent.bottom
            }
            Text {
                id: footTemp
                text: full.footTempText
                color: colors.foreground
                opacity: colors.textQuiet
                font.family: colors.uiFont
                font.pixelSize: gscale.micro
                font.letterSpacing: gscale.micro * 0.10
                elide: Text.ElideRight
                anchors.right: parent.right
                anchors.bottom: parent.bottom
            }
        }
    }
}
