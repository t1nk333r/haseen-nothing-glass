import QtQuick
import "../../components"
import "../../components/nothing"

// What the machine is doing, Nothing style.
//
// The Nothing drawing of the Liquid Glass tile next door, carrying the same
// facts out of the same engine: PerfData reads /proc/stat, /proc/meminfo and
// the hwmon temperature files, and owns the family's one timer. Its `active`
// is bound to this widget's `visible`, so a tile on a workspace nobody is
// looking at reads nothing at all. Nothing here reads MacOSColors or
// LiquidGlass; everything visual comes from `nothing`, the NTheme injected by
// WidgetHost.
//
// The accent carries exactly ONE meaning on this face: the processor pinned at
// 90% or more. The badge, the load figure and the load meter carry that one
// fact, and a temperature is never red - a reading about the machine's cooling
// is not a verdict on it.
//
// Three layouts, one per grid preset: 192x192, 400x192, 400x400.
Item {
    id: full
    anchors.fill: parent

    // The three grid presets, at the same thresholds as the glass twin.
    readonly property bool isWide: full.width >= full.height * 1.6
    readonly property bool isBig: !full.isWide && Math.min(full.width, full.height) >= 300

    // The only thing here that reads the machine, and the only timer.
    PerfData {
        id: perf
        active: full.visible
    }

    // The one fact the accent means.
    readonly property bool high: perf.cpuReady && perf.cpuPercent >= 90

    readonly property string cpuText: perf.cpuReady ? String(Math.round(perf.cpuPercent)) : "--"
    readonly property string memPctText: perf.memReady ? Math.round(perf.memPercent) + "%" : "--"

    // The namespaced reading the small tile's footer carries: a bare "58°"
    // would not say which chip it belongs to.
    readonly property string footTempText: perf.tempsReady
        ? perf.temps[0].name.toUpperCase() + " " + perf.temps[0].text : "--"

    NCard {
        id: card
        theme: nothing
        anchors.fill: parent

        NDotField {
            theme: nothing
            anchors.fill: parent
            anchors.margins: nothing.pad
            intensity: 0.45
            visible: full.isBig
        }

        Item {
            id: body
            anchors.fill: parent
            anchors.margins: nothing.pad

            // Every band below is derived from these two, so the same file
            // lays out at 160x120 and at 400x400.
            readonly property real headTop: Math.max(header.implicitHeight, nothing.px(18)) + nothing.gap
            readonly property real rowH: nothing.px(24)
            readonly property real splitX: Math.round(body.width * 0.54)
            readonly property bool split: full.isWide
            readonly property real leftW: body.split
                ? Math.max(0, body.splitX - nothing.gap)
                : body.width
            // Label line, use, meter - a band whose height is their sum rather
            // than a number that can drift from what it draws. The 6 + 5 is
            // the same spacing the battery drawing's footer block uses.
            readonly property real memLineH: Math.max(memLabel.implicitHeight, memValue.implicitHeight)
            readonly property real memBlockH: body.memLineH + nothing.px(6) + nothing.px(5)

            // One row per sensor the store read (three at most), and the hero's
            // share of the large tile: the taller of a floor and what those rows
            // leave, capped at 42% so a hero can never eat the tile either.
            // Sizing the hero from a fixed fraction first is what left the third
            // sensor off the large tile.
            readonly property real sensorRowsH: perf.temps.length * body.rowH
            readonly property real bigStageH: Math.max(nothing.px(80),
                Math.min(Math.round(body.height * 0.42),
                    body.height - body.headTop - nothing.gap - body.memBlockH
                        - nothing.gap - body.sensorRowsH - nothing.gap))

            // ── Header ────────────────────────────────────────────────
            NLabel {
                id: header
                theme: nothing
                text: "System"
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: badge.visible ? badge.left : parent.right
                anchors.rightMargin: badge.visible ? nothing.gap : 0
                elide: Text.ElideRight
            }

            NBadge {
                id: badge
                theme: nothing
                anchors.verticalCenter: header.verticalCenter
                anchors.right: parent.right
                visible: full.high
                active: true
                label: "High"
            }

            // ── The load: the hero on every preset ────────────────────
            Item {
                id: stage
                x: 0
                y: body.headTop
                width: body.leftW
                height: full.isBig
                    ? body.bigStageH
                    : Math.max(0, (full.isWide && memBlock.visible
                            ? memBlock.y
                            : footer.visible ? footer.y : body.height) - nothing.gap - stage.y)

                // The hero and its meter share the stage: the meter is pinned
                // to its foot and the figure takes what is left, so the two
                // cannot overlap however tall the tile is.
                NProgress {
                    id: loadMeter
                    theme: nothing
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: nothing.px(5)
                    segments: full.isBig ? 24 : 12
                    value: perf.cpuPercent / 100
                    accent: full.high
                }

                // Centred here, where the glass twin's hero is left-aligned:
                // the two styles each centre their own large tile's figure.
                Item {
                    id: heroBox
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: loadMeter.top
                    anchors.bottomMargin: nothing.gap

                    NDotMatrix {
                        theme: nothing
                        anchors.centerIn: parent
                        // The unit is part of the reading on this face too, and
                        // the matrix lays the glyph run out itself - the dot
                        // size comes from the box it is handed, never from a
                        // guess at how wide "12%" is.
                        text: full.cpuText + (perf.cpuReady ? "%" : "")
                        fitWidth: heroBox.width
                        fitHeight: heroBox.height
                        onColor: full.high ? nothing.red : nothing.on
                    }
                }
            }

            // ── Memory, under the hero (wide and large) ──────────────
            Item {
                id: memBlock
                visible: perf.memReady && (full.isWide || full.isBig)
                x: 0
                width: body.leftW
                height: body.memBlockH
                y: full.isWide
                    ? Math.max(0, body.height - body.memBlockH)
                    : Math.max(0, stage.y + stage.height + nothing.gap)

                NLabel {
                    id: memLabel
                    theme: nothing
                    text: "Mem"
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: memValue.left
                    anchors.rightMargin: nothing.gap
                    elide: Text.ElideRight
                }

                NMono {
                    id: memValue
                    theme: nothing
                    text: perf.memText
                    color: nothing.onDim
                    font.pixelSize: nothing.fLabel
                    anchors.top: parent.top
                    anchors.right: parent.right
                }

                NProgress {
                    theme: nothing
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: nothing.px(5)
                    segments: (full.isWide || full.isBig) ? 20 : 10
                    value: perf.memPercent / 100
                }
            }

            // ── The sensors ───────────────────────────────────────────
            // One row per chip. Wide: the right column. Large: under the
            // memory band. Small: gone - the footer line carries the primary
            // sensor, and one reading is all that tile has room for.
            Item {
                id: sensorBlock
                visible: full.isWide || full.isBig
                x: full.isWide ? body.splitX + nothing.gap : 0
                width: full.isWide ? Math.max(0, body.width - sensorBlock.x) : body.width

                // Computed from the bands above it, never from `height`: a cap
                // taken from the block's own height would be a binding loop.
                // Wide: as many rows as the column holds. Large: all of them,
                // because `bigStageH` sized the hero to leave this much room.
                // The small tile has no block at all, so it builds no rows.
                readonly property real topY: full.isWide
                    ? 0
                    : Math.max(0, memBlock.y + memBlock.height + nothing.gap)
                readonly property bool shown: full.isWide || full.isBig
                readonly property int cap: !sensorBlock.shown ? 0
                    : full.isWide
                        ? Math.max(0, Math.floor((body.height - sensorBlock.topY) / body.rowH))
                        : perf.temps.length
                readonly property var rows: perf.temps.slice(0, sensorBlock.cap)
                // What the bands above left over: the rows are centred in it
                // rather than clinging to the memory band.
                readonly property real slack: Math.max(0,
                    body.height - sensorBlock.topY - sensorBlock.height)

                height: sensorBlock.rows.length * body.rowH
                y: full.isWide
                    ? Math.max(body.headTop, Math.round((body.height - sensorBlock.height) / 2))
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

                            NLabel {
                                theme: nothing
                                text: row.modelData.name
                                height: body.rowH
                                verticalAlignment: Text.AlignVCenter
                                anchors.left: parent.left
                                anchors.right: rowValue.left
                                anchors.rightMargin: nothing.gap
                                elide: Text.ElideRight
                            }

                            NMono {
                                id: rowValue
                                theme: nothing
                                text: row.modelData.text
                                color: nothing.on
                                font.pixelSize: nothing.fLabel
                                height: body.rowH
                                verticalAlignment: Text.AlignVCenter
                                anchors.right: parent.right
                            }

                            NDivider {
                                theme: nothing
                                visible: row.index < sensorBlock.rows.length - 1
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                            }
                        }
                    }
                }
            }

            // The column rule, at the split both drawings use.
            NDivider {
                theme: nothing
                vertical: true
                visible: body.split
                x: body.splitX
                y: body.headTop
                height: Math.max(0, body.height - body.headTop)
            }

            // ── Footer: the small tile's two readings ─────────────────
            Item {
                id: footer
                visible: !full.isWide && !full.isBig
                x: 0
                width: body.width
                height: Math.max(footMem.implicitHeight, footTemp.implicitHeight)
                y: Math.max(0, body.height - footer.height)

                NMono {
                    id: footMem
                    theme: nothing
                    text: "MEM " + full.memPctText
                    color: nothing.onDim
                    font.pixelSize: nothing.fLabel
                    elide: Text.ElideRight
                    anchors.left: parent.left
                    anchors.right: footTemp.left
                    anchors.rightMargin: nothing.gap
                    anchors.bottom: parent.bottom
                }

                NMono {
                    id: footTemp
                    theme: nothing
                    text: full.footTempText
                    color: nothing.onDim
                    font.pixelSize: nothing.fLabel
                    elide: Text.ElideRight
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                }
            }
        }
    }
}
