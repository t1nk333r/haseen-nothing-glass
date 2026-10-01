import QtQuick
import "../../components"

// DeepSeek credit and spend, Liquid Glass.
//
// The Liquid Glass twin of widgets-nothing/deepseek/main.qml, carrying the
// same facts out of the same component: DeepSeekData reads the ledger the
// DeepSpend plugin (`t1nk33r.deepseek`) already writes on this machine. No
// API call, no key, no webhook - see that component's header for the file, the
// fields and why.
//
// The accent (`accentRed`) carries exactly ONE meaning here, as it does on the
// Nothing drawing: this balance needs attention - below the low-balance
// threshold the operator armed in DeepSpend's own config, or nothing left at
// all. An old reading is NOT an accent: it is the freshness line, "stale ·
// last read 22:16", which is part of the design rather than a diagnostic,
// because a colour cannot say "this number was taken an hour ago" and a
// balance that looks current when it is not is the one failure this widget
// must not have.
//
// The phone card this mirrors is three lines - the name and the verdict, the
// figure, the freshness line - and that is the tile:
//
//   192x192   those three lines. The number is the tile.
//   400x192   the same three lines on the left; the spend breakdown in a
//             column on the right, with the vertical rule the Nothing drawing
//             puts at the same split.
//   400x400   the same, with the breakdown in the bottom block and the
//             provenance line ("DeepSpend ledger") the operator allows in
//             place of the phone's endpoint.
//
// Everything that is not the figure is caption: the verdict's colour, the
// freshness line and the spend rows below it.
//
// A tile with no number is never a blank card and never a plausible-looking
// zero: the notice state names the reason ("DeepSpend has not written its
// ledger yet.", "The DeepSpend ledger is unreadable.", a ledger of a version
// this widget does not know, or a ledger with no sample in it yet).
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

    DeepSeekData {
        id: ds
        // An off-screen tile costs nothing - see the component's header.
        active: full.visible
    }

    // The family's one type and margin scale - see components/GlassScale.qml.
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
    readonly property bool isWide: gscale.isWide
    readonly property bool isBig: gscale.isBig
    // Read once per preset decision, exactly as the Nothing twin does it.
    readonly property bool isSmall: gscale.isSmall

    Item {
        id: body
        anchors.fill: parent
        anchors.margins: gscale.pad

        readonly property real splitX: Math.round(body.width * 0.52)
        readonly property bool split: full.isWide && ds.hasBalance
        readonly property real leftW: body.split
            ? Math.max(0, body.splitX - gscale.gap)
            : body.width

        // The header band is the taller of the title and the verdict, so the
        // stage below it does not shift when a verdict appears.
        readonly property real headH: Math.max(header.implicitHeight, verdict.implicitHeight)

        // One row per spend figure, sized like the Nothing drawing's row (its
        // own px(22) against fLabel). The rows themselves come from the
        // component, so the two drawings cannot word one differently.
        readonly property real rowH: Math.round(gscale.body * 1.35)
        // A short tile drops the tail of the list (peak/off-peak, then added)
        // rather than squeezing six rows into it: the ledger's six figures are
        // ranked by how much they are worth at a glance.
        readonly property int rowCap: full.isBig
            ? Math.max(1, Math.floor((body.height - body.headH - gscale.gap) / body.rowH))
            : Math.min(4, Math.max(1, Math.floor((body.height - body.headH - gscale.gap) / body.rowH)))
        readonly property var rows: ds.rows.slice(0, body.rowCap)

        // ── Header ───────────────────────────────────────────────────────
        Text {
            id: header
            textFormat: Text.PlainText
            text: "DeepSeek"
            color: colors.foreground
            opacity: 0.75
            font.family: colors.uiFont
            font.pixelSize: gscale.micro
            font.letterSpacing: gscale.micro * 0.10
            elide: Text.ElideRight
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: verdict.visible ? verdict.left : parent.right
            anchors.rightMargin: verdict.visible ? gscale.gap : 0
        }

        // The verdict, which the component only produces when it knows it:
        // "Running low" against the threshold the operator armed in DeepSpend,
        // or "Stale" when the ledger has stopped advancing. Neither is
        // invented - see the component's header on what a local ledger cannot
        // know ("is_available" is not in it). Loud only for the threshold.
        Text {
            id: verdict
            textFormat: Text.PlainText
            visible: text !== ""
            text: ds.verdict
            color: ds.alert ? colors.accentRed : colors.foreground
            opacity: ds.alert ? 1.0 : 0.75
            font.family: colors.uiFont
            font.pixelSize: gscale.micro
            font.weight: ds.alert ? Font.DemiBold : Font.Normal
            horizontalAlignment: Text.AlignRight
            anchors.top: parent.top
            anchors.right: parent.right
        }

        // ── Freshness, and where the figure came from ────────────────────
        // Hidden while there is no number: the notice speaks instead.
        Item {
            id: footer
            visible: ds.hasBalance
            x: 0
            width: body.leftW
            height: visible
                ? readout.implicitHeight
                    + (source.visible ? Math.round(gscale.tight * 0.6) + source.implicitHeight : 0)
                : 0
            y: (full.isBig && breakdownBlock.visible)
                ? Math.max(body.headH, breakdownBlock.y - gscale.gap - footer.height)
                : Math.max(body.headH, body.height - footer.height)

            // "stale · last read 22:16" / "last read 22:16" - the phone card's
            // own line. It is part of the design, not a debug string: the
            // figure comes out of a file the DeepSpend plugin fills in on its
            // own schedule, and the tile says how old that reading is.
            Text {
                id: readout
                textFormat: Text.PlainText
                text: ds.footnote
                color: colors.foreground
                opacity: 0.8
                font.family: colors.uiFont
                font.pixelSize: gscale.body
                elide: Text.ElideRight
                width: parent.width
                anchors.top: parent.top
            }

            // The provenance line the operator allows in place of the phone's
            // endpoint: the local source, named - never the iOS plumbing. Only
            // the large tile has room for it.
            Text {
                id: source
                textFormat: Text.PlainText
                visible: full.isBig
                text: ds.sourceLabel
                color: colors.foreground
                opacity: 0.55
                font.family: colors.uiFont
                font.pixelSize: gscale.micro
                width: parent.width
                elide: Text.ElideRight
                anchors.top: readout.bottom
                anchors.topMargin: Math.round(gscale.tight * 0.6)
            }
        }

        // ── The spend breakdown ──────────────────────────────────────────
        // Wide: a column to the right of the balance. Large: a block along the
        // bottom. Small: gone; at 192x192 the balance and its age are the
        // tile.
        Item {
            id: breakdownBlock
            visible: body.split || (full.isBig && ds.hasBalance)

            x: body.split ? body.splitX + gscale.gap : 0
            width: body.split ? Math.max(0, body.width - breakdownBlock.x) : body.width
            height: body.rows.length * body.rowH
            y: body.split
                ? Math.max(0, Math.round((body.height - breakdownBlock.height) / 2))
                : Math.max(0, body.height - breakdownBlock.height)

            Column {
                width: parent.width

                Repeater {
                    model: body.rows

                    Item {
                        id: row
                        required property var modelData
                        required property int index

                        width: breakdownBlock.width
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
                            visible: row.index < body.rows.length - 1
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

        // ── Stage: the balance, or the reason there is none ──────────────
        Item {
            id: stage
            x: 0
            y: body.headH + gscale.gap
            width: body.leftW
            height: Math.max(0, footer.y - gscale.gap - stage.y)

            // Measured, never estimated: the hero is sized so the longest
            // figure DeepSeek can send fits the stage, off the face that will
            // draw it (PORTING.md item 9). advanceWidth is linear in
            // pixelSize, so one measurement at 100 px scales exactly.
            // 0.97 keeps the last glyph off the edge.
            TextMetrics {
                id: figureMetrics
                font.family: colors.uiFont
                font.pixelSize: 100
                text: ds.figureLabel
            }

            readonly property real heroFit: figureMetrics.advanceWidth > 0
                ? stage.width * 0.97 * 100 / figureMetrics.advanceWidth
                : gscale.hero

            readonly property real heroSize: Math.max(12, Math.round(Math.min(
                gscale.hero,
                stage.height * 0.84,
                stage.heroFit)))

            // ── With a number ────────────────────────────────────────────
            // No width bound: `heroSize` is what fits it (above), and a figure
            // that has been shrunk to fit must not then be elided - an
            // ellipsis in a balance reads as a different balance.
            Text {
                id: hero
                textFormat: Text.PlainText
                visible: ds.hasBalance
                text: ds.figureLabel
                color: ds.alert ? colors.accentRed : colors.foreground
                font.family: colors.uiFont
                font.pixelSize: stage.heroSize
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
            }

            // ── Without one ──────────────────────────────────────────────
            // One red line and the reason, on every preset: a card that shows
            // nothing says why, and it never draws a figure it does not have.
            Column {
                id: notice
                visible: !ds.hasBalance
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.round(gscale.tight * 0.5)

                Text {
                    id: noticeHeadline
                    textFormat: Text.PlainText
                    text: ds.noticeHeadline
                    color: colors.accentRed
                    font.family: colors.uiFont
                    font.pixelSize: gscale.body
                    font.weight: Font.DemiBold
                    width: notice.width
                    elide: Text.ElideRight
                }

                Text {
                    id: noticeDetail
                    textFormat: Text.PlainText
                    visible: text !== ""
                    text: ds.noticeDetail
                    color: colors.foreground
                    opacity: 0.7
                    font.family: colors.uiFont
                    font.pixelSize: gscale.micro
                    width: notice.width
                    wrapMode: Text.WordWrap
                    maximumLineCount: full.isBig ? 3 : 2
                    elide: Text.ElideRight
                }
            }
        }
    }
}
