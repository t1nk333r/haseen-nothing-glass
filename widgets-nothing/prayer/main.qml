import QtQuick
import "../../components"
import "../../components/nothing"

// Prayer times, Nothing style.
//
// The engine is components/PrayerTimes.qml, exactly as the Liquid Glass
// prayer tile uses it: one instance, one tick, the schedule computed offline
// from the operator's own omaprayers settings. Nothing is re-derived here and
// components/PrayerCard.qml - which the lock screen shares - is deliberately
// NOT used: that card is the Liquid Glass drawing, and this file is the other
// drawing of the same numbers.
//
// Nothing terms: the next prayer as a tracked label, its time as dot-matrix
// digits, the countdown in mono red, the window from the previous prayer to
// the next as a segmented bar (a tick ring at the large size), and the day's
// six rows as a dense mono list with the past dimmed and the next accented.
//
// Arabic is handled the way the twin handles it: the names come from the
// row's `ar` field, they are set in Noto Kufi Arabic, and every line that can
// hold them flips to right alignment. Letter-spacing and forced uppercase are
// dropped in that case - tracking out an Arabic string breaks the joins.
Item {
    id: full
    anchors.fill: parent

    // The three grid presets: 192x192 (small), 400x192 (wide), 400x400 (big).
    readonly property bool isWide: full.width >= full.height * 1.6
    readonly property bool isBig: !full.isWide && Math.min(full.width, full.height) >= 300
    readonly property bool isSmall: !full.isWide && !full.isBig

    PrayerTimes { id: prayers }

    readonly property string arabicFamily: "Noto Kufi Arabic"

    function nameOf(row) {
        if (!row) return ""
        return prayers.isArabic ? row.ar : row.en
    }

    // The clock time of the next prayer, split so the digits can go into the
    // dot matrix (which knows digits, ":" and "-") and the meridiem can sit
    // beside them as a label. In 24-hour mode the suffix is simply empty.
    readonly property string nextTimeText: prayers.next ? prayers.next.timeText : "--:--"
    readonly property string nextDigits:
        prayers.next ? full.nextTimeText.replace(/[^0-9:]/g, "") : "--:--"
    readonly property string nextSuffix: full.nextTimeText.replace(/[0-9:\s]/g, "")

    readonly property string afterLine: prayers.after
        ? full.nameOf(prayers.after) + "  " + prayers.after.timeText
        : (prayers.ok ? "" : prayers.error)

    // Header line: where these times are for, plus the twin's "tomorrow"
    // qualifier - after Isha the rows belong to the next day and six times
    // with no date would be ambiguous exactly then.
    readonly property string whereLine: prayers.showsTomorrow
        ? prayers.locationLabel + "  ·  " + (prayers.isArabic ? "غدًا" : "tomorrow")
        : prayers.locationLabel

    // Dot columns a time string occupies: five per digit or dash, three for
    // the colon, plus a one-dot gutter between glyphs.
    function matrixCols(s) {
        var str = String(s)
        var cols = 0
        for (var i = 0; i < str.length; i++) {
            cols += (str[i] === ":") ? 3 : 5
            if (i > 0) cols += 1
        }
        return Math.max(1, cols)
    }

    NCard {
        id: card
        theme: nothing
        anchors.fill: parent
        clip: true

        // ── Small square: the next athan and how long is left ────────────
        Item {
            id: smallLayout
            visible: full.isSmall
            anchors.fill: parent
            anchors.margins: nothing.pad

            NBadge {
                id: sDot
                theme: nothing
                active: true
                anchors.top: parent.top
                anchors.topMargin: nothing.px(3)
                anchors.right: parent.right
            }

            // Tracked uppercase in English; in Arabic the tracking and the
            // forced case come off, because both break the joins.
            NLabel {
                id: sHeader
                theme: nothing
                text: prayers.isArabic ? "التالي" : "Next"
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: sDot.left
                anchors.rightMargin: nothing.gap
                font.family: prayers.isArabic ? full.arabicFamily : nothing.sans
                font.letterSpacing: prayers.isArabic ? 0 : nothing.trackLabel
                font.capitalization: prayers.isArabic ? Font.MixedCase : Font.AllUppercase
                horizontalAlignment: prayers.isArabic ? Text.AlignRight : Text.AlignLeft
                elide: Text.ElideRight
            }

            Item {
                id: sStage
                anchors.top: sHeader.bottom
                anchors.topMargin: nothing.gap
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: sFooter.top
                anchors.bottomMargin: nothing.gap

                // The meridiem sits beside the digits and inside the tile:
                // its width comes out of the clock's budget, or "AM" would
                // hang over the card's edge at 192 px.
                readonly property real suffixRoom:
                    full.nextSuffix !== "" ? nothing.px(18) : 0

                // A four-glyph clock in dot matrix needs 21 dot columns; at
                // 192 px that is a five-pixel dot and the ghost grid wins
                // over the number. This size gets the mono readout instead -
                // the dot matrix is the hero at 400x400, where it has the
                // room to be a display rather than a texture.
                readonly property real clockSize: Math.max(nothing.px(14),
                    Math.min(sStage.height * 0.66,
                             (sStage.width - sStage.suffixRoom)
                                / Math.max(1, full.nextDigits.length * 0.62)))

                Row {
                    anchors.centerIn: parent
                    spacing: nothing.px(4)

                    NMono {
                        id: sTime
                        theme: nothing
                        text: full.nextDigits
                        color: nothing.on
                        font.pixelSize: Math.round(sStage.clockSize)
                    }

                    NLabel {
                        theme: nothing
                        anchors.bottom: sTime.bottom
                        anchors.bottomMargin: Math.round(sStage.clockSize * 0.12)
                        visible: full.nextSuffix !== ""
                        text: full.nextSuffix
                        font.pixelSize: nothing.fMicro
                    }
                }
            }

            Column {
                id: sFooter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: nothing.px(5)

                NText {
                    theme: nothing
                    width: parent.width
                    text: full.nameOf(prayers.next)
                    color: nothing.on
                    font.family: prayers.isArabic ? full.arabicFamily : nothing.sans
                    font.pixelSize: nothing.fTitle
                    font.letterSpacing: prayers.isArabic ? 0 : nothing.trackLabel
                    font.capitalization: prayers.isArabic
                        ? Font.MixedCase : Font.AllUppercase
                    horizontalAlignment: prayers.isArabic ? Text.AlignRight : Text.AlignLeft
                    elide: Text.ElideRight
                }

                NProgress {
                    theme: nothing
                    width: parent.width
                    height: nothing.px(4)
                    segments: 20
                    accent: false
                    value: prayers.progress
                }

                NMono {
                    theme: nothing
                    width: parent.width
                    text: prayers.ok ? prayers.remainingText : prayers.error
                    color: prayers.ok ? nothing.red : nothing.onDim
                    font.pixelSize: nothing.fMicro
                    horizontalAlignment: prayers.isArabic ? Text.AlignRight : Text.AlignLeft
                    elide: Text.ElideRight
                }
            }
        }

        // ── Wide: the next athan on the left, the whole day beside it ────
        Item {
            id: wideLayout
            visible: full.isWide
            anchors.fill: parent
            anchors.margins: nothing.pad

            Item {
                id: wLeft
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                width: Math.round(parent.width * 0.44)

                NLabel {
                    id: wHeader
                    theme: nothing
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    text: prayers.isArabic ? "التالي" : "Next"
                    font.family: prayers.isArabic ? full.arabicFamily : nothing.sans
                    font.letterSpacing: prayers.isArabic ? 0 : nothing.trackLabel
                    font.capitalization: prayers.isArabic
                        ? Font.MixedCase : Font.AllUppercase
                    horizontalAlignment: prayers.isArabic ? Text.AlignRight : Text.AlignLeft
                    elide: Text.ElideRight
                }

                // Same reasoning as the small tile: the side list takes the
                // horizontal room a 21-column matrix would need, so the
                // clock is mono here.
                readonly property real suffixRoom:
                    full.nextSuffix !== "" ? nothing.px(20) : 0
                readonly property real clockSize: Math.max(nothing.px(14),
                    Math.min(wLeft.height * 0.34,
                             (wLeft.width - wLeft.suffixRoom)
                                / Math.max(1, full.nextDigits.length * 0.62)))

                Row {
                    anchors.top: wHeader.bottom
                    anchors.topMargin: nothing.gap
                    anchors.left: parent.left
                    spacing: nothing.px(4)

                    NMono {
                        id: wTime
                        theme: nothing
                        text: full.nextDigits
                        color: nothing.on
                        font.pixelSize: Math.round(wLeft.clockSize)
                    }

                    NLabel {
                        theme: nothing
                        anchors.bottom: wTime.bottom
                        anchors.bottomMargin: Math.round(wLeft.clockSize * 0.12)
                        visible: full.nextSuffix !== ""
                        text: full.nextSuffix
                        font.pixelSize: nothing.fMicro
                    }
                }

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    spacing: nothing.px(4)

                    NText {
                        theme: nothing
                        width: parent.width
                        text: full.nameOf(prayers.next)
                        color: nothing.on
                        font.family: prayers.isArabic ? full.arabicFamily : nothing.sans
                        font.pixelSize: nothing.fTitle
                        font.letterSpacing: prayers.isArabic ? 0 : nothing.trackLabel
                        font.capitalization: prayers.isArabic
                            ? Font.MixedCase : Font.AllUppercase
                        horizontalAlignment: prayers.isArabic ? Text.AlignRight : Text.AlignLeft
                        elide: Text.ElideRight
                    }

                    NProgress {
                        theme: nothing
                        width: parent.width
                        height: nothing.px(4)
                        segments: 20
                        accent: false
                        value: prayers.progress
                    }

                    NMono {
                        theme: nothing
                        width: parent.width
                        text: prayers.ok ? prayers.remainingText : prayers.error
                        color: prayers.ok ? nothing.red : nothing.onDim
                        font.pixelSize: nothing.fMicro
                        horizontalAlignment: prayers.isArabic ? Text.AlignRight : Text.AlignLeft
                        elide: Text.ElideRight
                    }
                }
            }

            NDivider {
                id: wRule
                theme: nothing
                vertical: true
                anchors.left: wLeft.right
                anchors.leftMargin: nothing.pad
                anchors.top: parent.top
                anchors.bottom: parent.bottom
            }

            PrayerRows {
                anchors.left: wRule.right
                anchors.leftMargin: nothing.pad
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
            }
        }

        // ── Big square: ring, next athan, then the day in full ───────────
        Item {
            id: bigLayout
            visible: full.isBig
            anchors.fill: parent
            anchors.margins: nothing.pad

            NLabel {
                id: bWhere
                theme: nothing
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                text: full.whereLine
                loud: true
                horizontalAlignment: prayers.isArabic ? Text.AlignRight : Text.AlignLeft
                elide: Text.ElideRight
            }

            NMono {
                id: bHijri
                theme: nothing
                anchors.top: bWhere.bottom
                anchors.topMargin: nothing.px(2)
                anchors.left: parent.left
                anchors.right: parent.right
                text: prayers.hijriDisplay
                color: nothing.onDim
                font.family: prayers.isArabic ? full.arabicFamily : nothing.mono
                font.pixelSize: nothing.fMicro
                horizontalAlignment: prayers.isArabic ? Text.AlignRight : Text.AlignLeft
                elide: Text.ElideRight
            }

            Item {
                id: bHero
                anchors.top: bHijri.bottom
                anchors.topMargin: nothing.gap
                anchors.left: parent.left
                anchors.right: parent.right
                height: Math.round(full.height * 0.28)

                // The window between the previous prayer and the next one,
                // as ticks rather than a sweep.
                NDial {
                    id: bDial
                    theme: nothing
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(bHero.height, Math.round(full.width * 0.24))
                    height: bDial.width
                    ticks: 48
                    majorEvery: 6
                    accent: false
                    value: prayers.progress

                    // The countdown lives inside the ring the countdown is
                    // drawing: one number, one place.
                    NMono {
                        anchors.centerIn: parent
                        theme: nothing
                        width: parent.width * 0.78
                        text: prayers.ok ? prayers.remainingText : "--:--"
                        color: nothing.on
                        font.pixelSize: nothing.fLabel
                        horizontalAlignment: Text.AlignHCenter
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: nothing.px(7)
                    }
                }

                NDotMatrix {
                    id: bTime
                    theme: nothing
                    anchors.left: bDial.right
                    anchors.leftMargin: nothing.pad
                    anchors.top: parent.top
                    text: full.nextDigits
                    dot: bHero.dotSize
                    gap: Math.max(1, bHero.dotSize * 0.34)
                    onColor: nothing.on
                }

                readonly property real dotSize: {
                    var cols = full.matrixCols(full.nextDigits)
                    var avail = bHero.width - bDial.width - nothing.px(28)
                    var byW = (avail - (cols - 1) * 2) / cols
                    var byH = (bHero.height * 0.62 - 6 * 2) / 7
                    return Math.max(2, Math.min(byW, byH) * 0.92)
                }

                NLabel {
                    theme: nothing
                    anchors.left: bTime.right
                    anchors.leftMargin: nothing.px(4)
                    anchors.bottom: bTime.bottom
                    visible: full.nextSuffix !== ""
                    text: full.nextSuffix
                    font.pixelSize: nothing.fMicro
                }

                NText {
                    id: bName
                    theme: nothing
                    anchors.left: bDial.right
                    anchors.leftMargin: nothing.pad
                    anchors.right: parent.right
                    anchors.bottom: bAfter.top
                    anchors.bottomMargin: nothing.px(2)
                    text: full.nameOf(prayers.next)
                    color: nothing.on
                    font.family: prayers.isArabic ? full.arabicFamily : nothing.sans
                    font.pixelSize: nothing.fTitle
                    font.letterSpacing: prayers.isArabic ? 0 : nothing.trackLabel
                    font.capitalization: prayers.isArabic ? Font.MixedCase : Font.AllUppercase
                    horizontalAlignment: prayers.isArabic ? Text.AlignRight : Text.AlignLeft
                    elide: Text.ElideRight
                }

                NMono {
                    id: bAfter
                    theme: nothing
                    anchors.left: bDial.right
                    anchors.leftMargin: nothing.pad
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    text: prayers.ok
                        ? (full.afterLine !== ""
                            ? (prayers.isArabic ? "ثم  " : "THEN  ") + full.afterLine : "")
                        : prayers.error
                    color: nothing.onDim
                    font.family: prayers.isArabic ? full.arabicFamily : nothing.mono
                    font.pixelSize: nothing.fMicro
                    horizontalAlignment: prayers.isArabic ? Text.AlignRight : Text.AlignLeft
                    elide: Text.ElideRight
                }
            }

            NDivider {
                id: bRule
                theme: nothing
                anchors.top: bHero.bottom
                anchors.topMargin: nothing.gap
                anchors.left: parent.left
                anchors.right: parent.right
            }

            PrayerRows {
                anchors.top: bRule.bottom
                anchors.topMargin: nothing.gap
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                showTimeOfDay: true
            }
        }
    }

    // ── The day's six rows, used by the wide and the big layouts ─────────
    // Dense mono: a marker column, the name, the clock time. Past prayers
    // dim out, the next one is the single red thing in the list, and Sunrise
    // - which is not a prayer - stays quieter than the five that are.
    component PrayerRows: Item {
        id: rows

        // Big only: the sunrise/sunset pair under the list, which the wide
        // layout has no vertical room for.
        property bool showTimeOfDay: false

        readonly property real rowFont: nothing.fLabel
        readonly property real rowH: {
            var count = Math.max(1, prayers.rows.length)
            var avail = rows.height - (rows.showTimeOfDay ? nothing.px(18) : 0)
            return Math.max(nothing.px(14), avail / count)
        }

        Column {
            id: rowsColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 0
            visible: prayers.rows.length > 0

            Repeater {
                model: prayers.rows

                Item {
                    id: row
                    required property var modelData

                    readonly property bool isNext: !!row.modelData.isNext
                    readonly property bool dim: row.modelData.isPast && !row.isNext

                    width: rowsColumn.width
                    height: rows.rowH

                    // A filled red square for the next one, a hairline dot
                    // for everything else. No bars, no pills.
                    Rectangle {
                        id: rowMark
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: nothing.px(6)
                        height: nothing.px(6)
                        radius: row.isNext ? nothing.rDot : width / 2
                        color: row.isNext ? nothing.red
                            : (row.dim ? nothing.onFaint : nothing.onDim)
                    }

                    NText {
                        theme: nothing
                        anchors.left: rowMark.right
                        anchors.leftMargin: nothing.px(7)
                        anchors.right: rowTime.left
                        anchors.rightMargin: nothing.gap
                        anchors.verticalCenter: parent.verticalCenter
                        text: full.nameOf(row.modelData)
                        color: row.isNext ? nothing.red
                            : (row.dim ? nothing.onQuiet
                                       : (row.modelData.isPrayer ? nothing.on : nothing.onDim))
                        font.family: prayers.isArabic ? full.arabicFamily : nothing.sans
                        font.pixelSize: rows.rowFont
                        font.letterSpacing: prayers.isArabic ? 0 : nothing.trackLabel
                        font.capitalization: prayers.isArabic
                            ? Font.MixedCase : Font.AllUppercase
                        horizontalAlignment: prayers.isArabic ? Text.AlignRight : Text.AlignLeft
                        elide: Text.ElideRight
                    }

                    NMono {
                        id: rowTime
                        theme: nothing
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.timeText
                        color: row.isNext ? nothing.red
                            : (row.dim ? nothing.onQuiet : nothing.on)
                        font.pixelSize: rows.rowFont
                    }

                    NDivider {
                        theme: nothing
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        visible: rows.rowH >= nothing.px(20)
                        opacity: 0.6
                    }
                }
            }
        }

        // Sunrise and sunset, which PrayerTimes already computes: the day's
        // shape in one line under the list.
        NMono {
            theme: nothing
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            visible: rows.showTimeOfDay && prayers.ok
            text: (prayers.isArabic ? "شروق " : "RISE ") + prayers.sunriseText
                + (prayers.isArabic ? "   غروب " : "   SET ") + prayers.sunsetText
            color: nothing.onDim
            font.pixelSize: nothing.fMicro
            horizontalAlignment: prayers.isArabic ? Text.AlignRight : Text.AlignLeft
            elide: Text.ElideRight
        }

        // The schedule can fail (no omaprayers settings, no timezone): say
        // why, rather than showing six blank rows.
        NText {
            theme: nothing
            anchors.fill: parent
            visible: prayers.rows.length === 0
            text: prayers.ok ? "" : prayers.error
            color: nothing.onDim
            font.pixelSize: nothing.fLabel
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
