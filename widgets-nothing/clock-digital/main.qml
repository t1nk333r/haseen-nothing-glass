import QtQuick
import "../../components/nothing"

// Clock, Nothing style.
//
// Same instance, same store row, same `plugin.settings` as the Liquid
// Glass clock next door - only the drawing differs. Nothing here reads
// MacOSColors or LiquidGlass; everything visual comes from `nothing`, the
// NTheme injected by WidgetHost.
Item {
    id: full
    anchors.fill: parent

    // The three grid presets: 192x192, 400x192, 400x400.
    readonly property bool isWide: full.width >= full.height * 1.6
    readonly property bool isBig: !full.isWide && Math.min(full.width, full.height) >= 300

    // One minute tick, like the Liquid Glass clock: nothing on this face
    // moves per second, so a per-second timer would be a wake-up for nothing.
    property date now: new Date()
    // One wake-up a second, aligned to the wall-clock second so the colon
    // blinks ON the second rather than up to a second late. The digits
    // themselves still only change on the minute.
    property bool colonLit: true

    Timer {
        id: tick
        interval: 1000 - (Date.now() % 1000)
        repeat: false
        running: true
        onTriggered: {
            var n = new Date()
            full.colonLit = (n.getSeconds() % 2) === 0
            if (n.getMinutes() !== full.now.getMinutes() || n.getHours() !== full.now.getHours())
                full.now = n
            tick.interval = Math.max(50, 1000 - (Date.now() % 1000))
            tick.restart()
        }
    }

    readonly property string hh: Qt.formatDateTime(full.now, "HH")
    readonly property string mm: Qt.formatDateTime(full.now, "mm")
    readonly property string dayLine: Qt.formatDateTime(full.now, "ddd d MMM")

    // Progress through the day, which is what the dot field along the bottom
    // reads: lit dots are hours elapsed.
    readonly property int hourNow: full.now.getHours()

    NCard {
        id: card
        theme: nothing
        anchors.fill: parent

        NDotField {
            theme: nothing
            anchors.fill: parent
            anchors.margins: nothing.pad
            intensity: 0.5
            visible: full.isBig
        }

        // ── Header: the label line every Nothing surface carries ───────
        NLabel {
            id: header
            theme: nothing
            text: Qt.formatDateTime(full.now, "dddd")
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: nothing.pad
            elide: Text.ElideRight
        }

        NBadge {
            theme: nothing
            active: true
            label: Qt.formatDateTime(full.now, "AP")
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: nothing.pad
            visible: !full.isWide && full.width > nothing.px(150)
        }

        // ── The time ───────────────────────────────────────────────────
        // Wide: HH:MM on one line, dot matrix. Square: stacked, so the
        // digits can be as large as the tile allows.
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

            // No guessing at glyph widths here: each matrix is handed the box
            // it may occupy and works its own dot size out from the string it
            // is drawing. The stacked pair share a box split in two, minus
            // the spacing between them.
            readonly property real _rowGap: nothing.px(4)

            Column {
                anchors.centerIn: parent
                spacing: stage._rowGap
                visible: !full.isWide

                NDotMatrix {
                    theme: nothing
                    text: full.hh
                    fitWidth: stage.width
                    fitHeight: (stage.height - stage._rowGap) / 2
                    onColor: nothing.on
                }
                NDotMatrix {
                    theme: nothing
                    text: full.mm
                    fitWidth: stage.width
                    fitHeight: (stage.height - stage._rowGap) / 2
                    onColor: nothing.red
                }
            }

            // Wide: three matrices in a row rather than one "HH:MM", so the
            // separator can tick on its own - lit on the even second, ghosted
            // on the odd, the way a station clock blinks.
            //
            // `sizer` lays the whole string out but is never drawn: it exists
            // so the three visible matrices share ONE dot size, worked out
            // from the real glyph run. Row spacing reproduces the blank
            // column dots.js puts between glyphs inside a single matrix
            // (one dot wide, with a gap on each side), so the row is spaced
            // exactly as the undivided string would have been.
            NDotMatrix {
                id: sizer
                visible: false
                theme: nothing
                text: full.hh + ":" + full.mm
                fitWidth: stage.width
                fitHeight: stage.height
            }

            Row {
                anchors.centerIn: parent
                spacing: sizer.dot + sizer.gap * 2
                visible: full.isWide

                NDotMatrix {
                    theme: nothing
                    text: full.hh
                    dot: sizer.dot
                    gap: sizer.gap
                }
                NDotMatrix {
                    theme: nothing
                    text: ":"
                    dot: sizer.dot
                    gap: sizer.gap
                    onColor: full.colonLit ? nothing.on : nothing.onFaint
                }
                NDotMatrix {
                    theme: nothing
                    text: full.mm
                    dot: sizer.dot
                    gap: sizer.gap
                }
            }
        }

        // ── Footer: date, and the hours of the day as a bar ────────────
        Item {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: nothing.pad
            height: dateText.implicitHeight + (hours.visible ? hours.height + nothing.px(6) : 0)

            NMono {
                id: dateText
                theme: nothing
                text: full.dayLine
                color: nothing.onDim
                font.pixelSize: nothing.fLabel
                anchors.left: parent.left
                anchors.bottom: hours.visible ? hours.top : parent.bottom
                anchors.bottomMargin: hours.visible ? nothing.px(6) : 0
            }

            NProgress {
                id: hours
                theme: nothing
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: nothing.px(4)
                segments: 24
                value: (full.hourNow + full.now.getMinutes() / 60) / 24
                accent: true
                visible: full.height >= nothing.px(150)
            }
        }
    }
}
