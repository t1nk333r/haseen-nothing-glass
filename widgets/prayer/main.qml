import QtQuick
import "../../components"

// Prayer times, in the shape of the card on this machine's lock screen
// (`t1nk33r.lock/LockView.qml:144-233`): a progress ring with a mosque glyph
// top-left, the next athan's clock time top-right, and the next prayer's name
// with the one after it stacked at the bottom. The ring fills with how far
// the day has moved from the previous prayer toward the next.
//
// Differences from that card, all deliberate:
//   * it shows a countdown, because the omaprayers bar widget the operator
//     already runs is configured as "Strip + countdown" and that is the
//     number one looks at;
//   * it has three layouts, one per grid size (WidgetRegistry.sizes): the
//     lock card at Small, card + the day's six rows at Medium and Large;
//   * the numbers are real. The lock card feeds on
//     `python3 ~/.config/waybar/scripts/prayer-times.py`, a path that does
//     not exist on this machine, so it renders `--:--`; this reads
//     components/PrayerTimes.qml, which computes offline from the operator's
//     own omaprayers settings (see that file's header).
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

    PrayerTimes { id: prayers }

    readonly property string arabicFamily: "Noto Kufi Arabic"

    readonly property real _minSide: Math.min(width, height)
    readonly property bool isWide: width >= height * 1.6
    readonly property bool isBig: !isWide && _minSide >= 320

    // The lock card's proportions, driven off the short side so the block
    // looks the same in all three layouts. It is a square in all of them:
    // beside the list when wide, above the list when tall (where it takes
    // 45% of the height, or the rows would have nowhere to go), and the
    // whole tile at the small size.
    readonly property real cardSide: isWide
        ? Math.min(height, width * 0.42)
        : (isBig ? Math.min(width, height * 0.45) : _minSide)
    readonly property real pad: Math.round(cardSide * 0.11)
    readonly property real ringSize: Math.round(cardSide * 0.32)

    function nameOf(row) {
        if (!row) return ""
        return prayers.isArabic ? row.ar : row.en
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

    // ── The card, shared verbatim with the lock screen ───────────────────
    // components/PrayerCard.qml is the single implementation; the lock plugin
    // keeps a copy of it next to copies of LiquidGlass/MacOSColors so both
    // surfaces render the same pixels (they had already drifted apart once).
    PrayerCard {
        id: card
        prayers: prayers
        colors: colors
        fontFamily: colors.uiFont

        width: full.cardSide
        height: full.cardSide
        // Placed with x/y, never with a vertical anchor. The card carries an
        // explicit width AND height, and QML's anchor layout writes x/y/width/
        // height straight over those bindings when the anchor set on that axis
        // changes - here `anchors.top` was always set while a conditional
        // `anchors.verticalCenter` appeared in the wide preset, which is a
        // conflict the layout cannot honour. Measured across a resize: the
        // height froze at the tile's own height (180x400 where cardSide is
        // 180x180, and 160x400 inside a 160x160 tile), and because
        // `listPanel.anchors.top` hangs off `card.bottom`, the panel started at
        // y=400 in the big preset with a height of -20 and the day's six rows
        // were laid out entirely below the tile. Creating the same widget at
        // 400x400 is correct, which is why a preset-by-preset render called it
        // clean. The wide preset was wrong even on direct creation: the card
        // measured 168x192 there, not the 168x168 `cardSide` asks for.
        x: 0
        y: full.isWide ? Math.round((full.height - height) / 2) : 0
    }

    // ── The day's rows, next to the card (Medium) or under it (Large) ─────
    Item {
        id: listPanel
        visible: full.isWide || full.isBig

        anchors.left: full.isWide ? card.right : parent.left
        anchors.right: parent.right
        anchors.top: full.isWide ? parent.top : card.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: full.isWide ? 0 : full.pad
        anchors.rightMargin: full.pad
        anchors.topMargin: full.isWide ? full.pad : 0
        anchors.bottomMargin: full.pad

        readonly property real rowFont: Math.max(9, Math.round(full.cardSide * 0.075))

        Column {
            id: rowsColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round(listPanel.rowFont * 0.42)

            // Header: where these times are for, and the hijri date. Only the
            // taller layout has room.
            Column {
                width: parent.width
                visible: !full.isWide
                spacing: 0

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    elide: Text.ElideRight
                    horizontalAlignment: prayers.isArabic ? Text.AlignRight : Text.AlignLeft
                    // After Isha the rows are tomorrow's, so say so - six
                    // times with no date is ambiguous exactly then.
                    text: prayers.showsTomorrow
                        ? prayers.locationLabel + "  ·  " + (prayers.isArabic ? "غدًا" : "tomorrow")
                        : prayers.locationLabel
                    color: colors.foreground
                    font.family: colors.uiFont
                    font.pixelSize: Math.round(listPanel.rowFont * 1.05)
                }
                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    elide: Text.ElideRight
                    horizontalAlignment: prayers.isArabic ? Text.AlignRight : Text.AlignLeft
                    text: prayers.hijriDisplay
                    color: colors.foreground
                    opacity: colors.textQuiet
                    font.family: prayers.isArabic ? full.arabicFamily : colors.uiFont
                    font.pixelSize: Math.round(listPanel.rowFont * 0.85)
                }
            }

            Repeater {
                model: prayers.rows

                Item {
                    required property var modelData
                    readonly property bool dim: modelData.isPast && !modelData.isNext

                    width: rowsColumn.width
                    height: Math.round(listPanel.rowFont * 1.6)

                    // A thin accent bar marks the next prayer, the way the
                    // omaprayers compact panel marks its row.
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        width: Math.max(2, Math.round(listPanel.rowFont * 0.16))
                        height: Math.round(listPanel.rowFont * 1.1)
                        radius: width / 2
                        visible: modelData.isNext
                        color: colors.todayAccent
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Math.round(listPanel.rowFont * 0.5)
                        text: full.nameOf(modelData)
                        color: modelData.isNext ? colors.todayAccent : colors.foreground
                        // A past prayer is dimmed, not discarded: the name and
                        // the time are still the tile's data. 0.40 measured
                        // 3.66:1 against a black backdrop, under both the
                        // 4.5:1 floor and MacOSColors.textQuiet (0.55), which
                        // is the lowest opacity informative text may be drawn
                        // at - the same rule that took this file's 0.5s to the
                        // token. The Nothing twin dims the same rows to
                        // `onQuiet`, 5.0:1 on its own surface.
                        opacity: dim ? colors.textQuiet : 1.0
                        font.family: prayers.isArabic ? full.arabicFamily : colors.uiFont
                        font.pixelSize: listPanel.rowFont
                        font.weight: modelData.isNext ? Font.DemiBold : Font.Normal
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        text: modelData.timeText
                        color: modelData.isNext ? colors.todayAccent : colors.foreground
                        opacity: dim ? colors.textQuiet : 1.0
                        font.family: colors.uiFont
                        font.pixelSize: listPanel.rowFont
                        font.weight: modelData.isNext ? Font.DemiBold : Font.Normal
                    }
                }
            }

            // Never an empty panel: if the schedule failed, say why here
            // rather than leaving six blank rows.
            Text {
                textFormat: Text.PlainText
                width: parent.width
                visible: !prayers.ok
                text: prayers.error
                color: colors.foreground
                opacity: colors.textQuiet
                wrapMode: Text.WordWrap
                font.family: colors.uiFont
                font.pixelSize: listPanel.rowFont
            }
        }
    }
}
