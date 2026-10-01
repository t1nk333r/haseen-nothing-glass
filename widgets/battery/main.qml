import QtQuick
import "../../components"

// Battery, Liquid Glass.
//
// The Liquid Glass twin of widgets-nothing/battery/main.qml, carrying the same
// facts out of the same engine: BatteryData is a push-based UPower client, so
// neither drawing has a timer of its own.
//
// The accent carries exactly ONE meaning here, as it does on the Nothing
// drawing: LOW CHARGE (<= 20%). `accentRed` marks the state chip, the hero
// percentage and the level meter's fill, and nothing else. Charging is loud
// type - DemiBold at full opacity - never a second colour on the same glyph:
// two meanings on one colour is how a status widget stops being readable at a
// glance.
//
// Three layouts, one per grid preset (WidgetRegistry.sizes):
//   192x192   the level, the state and the estimate; no list at all - the
//             number is the tile.
//   400x192   the same on the left; the estimates in a column on the right,
//             capped by height, with the vertical rule the Nothing drawing
//             puts at the same split.
//   400x400   the hero on the large stage, then the state line and the meter,
//             then the estimates - the bottom stack the Nothing drawing uses,
//             where Health is a large-tile row only.
//
// A machine with no battery is a state with a name, never a blank card: "--",
// "No battery", "AC power", "MAINS" and a hairline where the meter would be
// (a meter at zero reads as a fault).
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

    BatteryData { id: bat }

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

    // ── Layout state ─────────────────────────────────────────────────────
    // The same three presets and the same thresholds as the Nothing drawing's
    // `isWide`/`isBig`, read from the family scale rather than re-derived.
    readonly property bool isWide: gscale.isWide
    readonly property bool isBig: gscale.isBig

    // The one thing the accent means.
    readonly property bool low: bat.present && bat.percent <= 20
    readonly property string pctText: bat.present ? String(Math.round(bat.percent)) : "--"

    // Signed watts: the direction the energy is going, which BatteryData
    // deliberately does not decide for us.
    readonly property string rateText: {
        if (!bat.present || bat.ratePower <= 0)
            return ""
        var w = Math.round(bat.ratePower * 10) / 10
        return (bat.charging ? "+" : "-") + w + "W"
    }

    // The rows the side column and the bottom block slice. Same rows, same
    // wording as the Nothing drawing: a value the two styles disagree about
    // would be a bug in one of them. Health is a large-tile row only - at
    // 400x192 the two live numbers (time and draw) are worth more than a
    // constant.
    readonly property var details: {
        if (!bat.present)
            return [{ k: "Source", v: "AC mains" }, { k: "Battery", v: "None" }]
        var rows = []
        if (bat.timeLabel !== "")
            rows.push({ k: bat.charging ? "To full" : "Remaining", v: bat.timeLabel })
        if (full.rateText !== "")
            rows.push({ k: "Power", v: full.rateText })
        if (full.isBig && bat.healthKnown)
            rows.push({ k: "Health", v: Math.round(bat.health) + "%" })
        // UPower reports no estimate and no rate on a freshly woken machine;
        // an empty column would read as a broken widget.
        if (rows.length === 0)
            rows.push({ k: "Level", v: Math.round(bat.percent) + "%" })
        return rows
    }

    Item {
        id: body
        anchors.fill: parent
        anchors.margins: gscale.pad

        // The wide tile splits only when the right column has rows to hold -
        // the absent state has its own two (Source / Battery), so the rule
        // never stands over a void.
        readonly property real splitX: Math.round(body.width * 0.52)
        readonly property bool split: full.isWide && full.details.length > 0
        readonly property real leftW: body.split
            ? Math.max(0, body.splitX - gscale.gap)
            : body.width

        // The level meter: the glass family's bar thickness (codeburn's share
        // bars), a little heavier because this is the one fact a glance reads
        // without the number.
        readonly property real barH: Math.max(4, Math.round(gscale.tight * 0.42))

        // The header band is the taller of the title and the state chip, so
        // the stage below it does not shift when a chip appears.
        readonly property real headH: Math.max(header.implicitHeight, badge.height)

        // One row per estimate, sized from `body` - the same ratio the Nothing
        // drawing's px(22) row carries against its fLabel.
        readonly property real rowH: Math.round(gscale.body * 1.35)
        readonly property int rowCap: full.isWide
            ? Math.max(1, Math.floor((body.height - body.headH - gscale.gap) / body.rowH))
            : 4
        readonly property var rows: full.details.slice(0, body.rowCap)

        // True wherever the estimates are on the tile as rows.
        readonly property bool showsRows: full.details.length > 0 && (full.isWide || full.isBig)

        // The footer's estimate, on the tile that has no list to carry it.
        // Two rules, both about not printing one fact twice:
        //  - where the side column or the bottom block already states the
        //    time and the draw, the footer says nothing (the Nothing drawing's
        //    footer readout appears on all three presets; this face keeps it
        //    only where nothing else states it);
        //  - and it never falls back to the level, because this hero carries
        //    its own "%" on every preset. The Nothing twin's third fallback
        //    exists only because its small hero drops the unit, which left
        //    the footer as the level's one printing.
        readonly property string footText: body.showsRows ? ""
            : (bat.present
                ? (bat.timeLabel !== "" ? bat.timeLabel
                    : (full.rateText !== "" ? full.rateText : ""))
                : "MAINS")

        // ── Header ───────────────────────────────────────────────────────
        Text {
            id: header
            textFormat: Text.PlainText
            text: "Battery"
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

        // The state chip. It appears for the two states that are worth a
        // marker, and the accent fills its words only for the low one.
        Item {
            id: badge
            visible: bat.present && (full.low || bat.charging)
            width: badgeLabel.implicitWidth + 2 * Math.round(gscale.tight * 0.9)
            height: Math.round(gscale.micro * 1.55)
            anchors.top: parent.top
            anchors.right: parent.right

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: colors.cardBackground
                opacity: colors.cardBackgroundOpacity
            }
            Text {
                id: badgeLabel
                textFormat: Text.PlainText
                text: full.low ? "Low" : "Chg"
                color: full.low ? colors.accentRed : colors.foreground
                opacity: full.low ? 1.0 : 0.75
                font.family: colors.uiFont
                font.pixelSize: Math.round(gscale.micro * 0.9)
                anchors.centerIn: parent
            }
        }

        // ── Footer: state, estimate, level ───────────────────────────────
        // Above the estimates on the large tile, at the bottom of the tile
        // everywhere else - the Nothing drawing's own order.
        Item {
            id: footer
            x: 0
            width: body.leftW
            height: stateLine.implicitHeight + Math.round(gscale.tight * 0.5) + body.barH
            y: (full.isBig && details.visible)
                ? Math.max(0, details.y - gscale.gap - footer.height)
                : Math.max(0, body.height - footer.height)

            Text {
                id: stateLine
                textFormat: Text.PlainText
                text: bat.present ? bat.stateLabel : "AC power"
                color: colors.foreground
                opacity: bat.present && bat.charging ? 1.0 : 0.75
                font.family: colors.uiFont
                font.pixelSize: gscale.body
                font.weight: bat.present && bat.charging ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: readout.visible ? readout.left : parent.right
                anchors.rightMargin: readout.visible ? gscale.gap : 0
            }

            Text {
                id: readout
                textFormat: Text.PlainText
                visible: text !== ""
                text: body.footText
                color: colors.foreground
                opacity: 0.8
                font.family: colors.uiFont
                font.pixelSize: gscale.body
                anchors.top: parent.top
                anchors.right: parent.right
            }

            Rectangle {
                id: meterTrack
                visible: bat.present
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: body.barH
                radius: height / 2
                color: colors.separator
            }
            Rectangle {
                visible: bat.present
                anchors.left: meterTrack.left
                anchors.bottom: meterTrack.bottom
                height: meterTrack.height
                radius: meterTrack.radius
                width: Math.round(meterTrack.width
                    * Math.max(0, Math.min(1, bat.percent / 100)))
                color: full.low ? colors.accentRed : colors.foreground
                opacity: full.low ? 1.0 : 0.65
            }
            // No battery: no meter, one rule, the same swap the Nothing
            // drawing makes.
            Rectangle {
                visible: !bat.present
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: colors.separator
            }
        }

        // ── The estimates ────────────────────────────────────────────────
        // Wide: a column to the right of the hero. Large: a block along the
        // bottom. Small: gone, the tile shows the number only.
        Item {
            id: details
            visible: body.showsRows
            readonly property var rows: body.rows

            x: full.isWide ? body.splitX + gscale.gap : 0
            width: full.isWide ? Math.max(0, body.width - details.x) : body.width
            height: details.rows.length * body.rowH
            // Wide: centred against the hero, as the glass family's other
            // side columns are (codeburn's models) - parked at the header's
            // foot, the block left a void under itself. Large: along the
            // bottom of the tile.
            y: full.isWide
                ? Math.max(0, Math.round((body.height - details.height) / 2))
                : Math.max(0, body.height - details.height)

            Column {
                width: parent.width

                Repeater {
                    model: details.rows

                    Item {
                        id: row
                        required property var modelData
                        required property int index

                        width: details.width
                        height: body.rowH

                        Text {
                            textFormat: Text.PlainText
                            text: row.modelData.k
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
                            textFormat: Text.PlainText
                            text: row.modelData.v
                            color: colors.foreground
                            opacity: 0.85
                            font.family: colors.uiFont
                            font.pixelSize: gscale.body
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Rectangle {
                            visible: row.index < details.rows.length - 1
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

        // ── Hero ─────────────────────────────────────────────────────────
        Item {
            id: stage
            x: 0
            y: body.headH + gscale.gap
            width: body.leftW
            height: Math.max(0, footer.y - gscale.gap - stage.y)

            // Sized from the stage, not fixed: the Nothing drawing sizes its
            // dot hero from the same budget, so this is the same glyph at 192
            // and at 400. The family's hero role is the ceiling; the stage is
            // what keeps it off the footer. The 0.62 is the twin's own rule
            // for the placeholder - "--" must read as a dash, not as a hero.
            readonly property real heroSize: Math.round(Math.min(
                gscale.hero,
                stage.height * 0.84 * (bat.present ? 1.0 : 0.62)))

            Column {
                id: hero
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.round(gscale.tight * 0.5)

                // The unit FOLLOWS the number - "62 %", not "%62": it is a
                // percentage, and a mark on the wrong side of the figure is
                // read as a different quantity. It shares the number's
                // baseline rather than its top, which is what a Row would do.
                Item {
                    id: heroLine
                    width: parent.width
                    height: heroAmount.implicitHeight

                    Text {
                        id: heroAmount
                        textFormat: Text.PlainText
                        text: full.pctText
                        color: full.low ? colors.accentRed : colors.foreground
                        opacity: bat.present ? 1.0 : 0.4
                        font.family: colors.uiFont
                        font.pixelSize: stage.heroSize
                        // No width bound: a level is at most "100", so the
                        // figure and its unit are always inside the stage.
                        anchors.left: parent.left
                        anchors.top: parent.top
                    }
                    Text {
                        id: heroMark
                        textFormat: Text.PlainText
                        visible: bat.present
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

                // The state this desktop will actually show. Named, not blank
                // - "--" alone would look like a stalled reading.
                Text {
                    textFormat: Text.PlainText
                    visible: !bat.present
                    text: "No battery"
                    color: colors.foreground
                    opacity: 0.9
                    font.family: colors.uiFont
                    font.pixelSize: gscale.body
                    width: parent.width
                    elide: Text.ElideRight
                }
            }
        }
    }
}
