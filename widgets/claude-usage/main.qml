import QtQuick
import "../../components"

// Claude Code's rate-limit windows, Liquid Glass.
//
// The information architecture is the phone widget's
// (`ios-widget-backends/claude-usage/scriptable/ClaudeBudget.js`), because it
// is the same three numbers and the operator reads both:
//
//   Claude                                        Week resets in 3h 20m
//   Session  ▏                                     0%
//   Week     ███████████████████████████████     100%
//   Fable    ███████████████████████████████     100%
//   stale · as of 23m ago
//
//   * the header names the tile and, on the right, says which window resets
//     next and when - the tightest one;
//   * one row per window, in the source's own order, each `label · bar ·
//     percentage`;
//   * the percentage carries the state: green with headroom, amber from 50%,
//     red from 80%. (The phone uses the API's own `severity` when it sends
//     one and 50/80 otherwise; this record carries no severity at all, so the
//     bands are the clients' fallback, applied to every source alike.)
//   * the freshness line is part of the design, not a debug string: the
//     numbers come from a record this machine wrote, and the tile says how
//     old that record is - in amber once it is older than two collector runs.
//
// Where the numbers come from: components/ClaudeUsageData.qml watches the
// local usage record (`~/.local/state/omarchy/agents/usage/claude.json`),
// which Omarchy's own `omarchy-agent-usage-claude` collector writes and
// `t1nk33r.agents` draws in the bar. No webhook, no token, no network call
// from this tile, and no settings key. A window whose reset has already
// passed is `—` with an empty bar, never the percentage of the window before
// it, and a record the collector flagged ("Sign-in expired") is drawn with
// its windows and the collector's own sentence beside them.
//
// Three layouts, one per grid preset (WidgetRegistry.sizes), the same three
// rows on all of them:
//   192x192   the rows, as-is; the header stacks its two halves when they do
//             not share a line, and the tile carries the freshness line but
//             no provenance footer - at this size the footer would be the
//             fourth line and the rows are the point.
//   400x192   the one-line header, one-line rows, freshness and the
//             provenance footer under them.
//   400x400   the same rows with air: the window's reset countdown and wall
//             clock on their own line under each bar.
//
// Every text that may elide is given a box first, and every fixed column is
// measured with a TextMetrics on the face that draws it rather than estimated
// - system-font mode is 1.5-1.7x wider. Nothing in this file may elide a
// percentage: the columns are sized from the measurement, and a measurement
// can only widen a box (PORTING.md item 9).
//
// There is no control on this tile. The numbers arrive when the collector
// writes them; re-probing the endpoint from a widget would be a second,
// competing client of a rate-limited API.
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

    ClaudeUsageData {
        id: cu
        // An off-screen tile stops the clock that ticks the countdowns.
        active: full.visible
    }

    // One type and margin scale for every glass tile - see
    // components/GlassScale.qml. The id is `gscale` and not `scale` on
    // purpose: `scale` is Item's own transform property, and inside a
    // Repeater delegate an unqualified outer id loses to it.
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
    // "There are numbers on screen". A record the collector flagged is still
    // ready: its windows are drawn, with the reason it flagged them beside.
    readonly property bool ready: cu.state === "ready"

    // The ink for a figure, from ClaudeUsageData's `level`: 0 normal, 1
    // warning, 2 critical. Green, amber, red - three tokens, no literal.
    //
    // A window with no live number is NOT green: green is a claim about
    // headroom, and a window whose reset has passed has no figure to make it
    // about - it is a dash in the quiet foreground, which is what the phone's
    // own client draws too (`colourFor(undefined)` is its secondary label).
    // Caught in a capture of the rolled state, where "-" came out green.
    function ink(level, percent) {
        if (percent < 0) return colors.foreground
        return level === 2 ? colors.accentRed
            : (level === 1 ? colors.accentAmber : colors.accentGreen)
    }

    // The window the header names, the freshness line and the provenance
    // footer are ClaudeUsageData's own now (`resetLine`, `freshnessText`,
    // `footerText`): they are sentences about the record, and the second
    // drawing draws the same ones from the same place rather than from a
    // copy of this file.
    readonly property color freshnessInk: cu.warned ? colors.accentRed
        : (cu.old ? colors.accentAmber : colors.foreground)

    // ── Measured columns ─────────────────────────────────────────────────
    // The fixed columns are measured on the face each is drawn with, and the
    // widest row is found by ADVANCE rather than by character count. Count was
    // not good enough: "resets in 2d 4h" and "resets in 3h 6m" are both
    // fifteen characters and measure 80 against 84 px, so the count-based pick
    // elided the countdown on a tile with room to spare. `advanceWidth` is
    // readable in the same statement that sets `text`, so the scan needs no
    // change signal - and because no binding reads it, no binding can loop.
    property real labelW: 0
    property real pctW: 0
    property real resetW: 0
    property real atW: 0

    TextMetrics {
        id: titleMetrics
        font.family: colors.uiFont
        font.pixelSize: gscale.label
        font.letterSpacing: gscale.label * 0.12
        text: "Claude"
    }
    TextMetrics {
        id: leadMetrics
        font.family: colors.uiFont
        font.pixelSize: gscale.micro
        text: cu.resetLine
    }
    TextMetrics {
        id: labelMetrics
        font.family: colors.uiFont
        font.pixelSize: gscale.label
        // The rows draw the name uppercase and tracked; the big tile's
        // leading line does too, at the same size.
        font.letterSpacing: gscale.label * 0.08
    }
    TextMetrics {
        id: pctMetrics
        // The rows draw the figure at `body`, the big tile's at 1.25x that.
        font.family: colors.uiFont
        font.pixelSize: full.isBig ? Math.round(gscale.body * 1.25) : gscale.body
    }
    TextMetrics {
        id: resetMetrics
        font.family: colors.uiFont
        font.pixelSize: full.isBig ? gscale.tight : gscale.micro
    }
    TextMetrics {
        id: atMetrics
        font.family: colors.uiFont
        font.pixelSize: gscale.tight
    }

    // The bounding width is the wider of the two metrics and is what a Text's
    // own implicitWidth matches; a box built only from `advanceWidth` came out
    // three pixels narrow. The floors are the estimates this layout was sized
    // from, kept so a measurement can only widen a column.
    function measure() {
        var lw = Math.round(gscale.label * 4.2)
        var pw = Math.round(gscale.body * 2.4)
        var rw = 0
        var aw = 0
        for (var i = 0; i < cu.windows.length; i++) {
            var w = cu.windows[i]
            labelMetrics.text = w.label.toUpperCase()
            lw = Math.max(lw, labelMetrics.advanceWidth, labelMetrics.width)
            pctMetrics.text = w.display
            pw = Math.max(pw, pctMetrics.advanceWidth, pctMetrics.width)
            resetMetrics.text = w.resetIn
            rw = Math.max(rw, resetMetrics.advanceWidth, resetMetrics.width)
            atMetrics.text = w.resetsAt
            aw = Math.max(aw, atMetrics.advanceWidth, atMetrics.width)
        }
        full.labelW = Math.ceil(lw)
        full.pctW = Math.ceil(pw)
        full.resetW = Math.ceil(rw)
        full.atW = Math.ceil(aw)
    }

    onIsWideChanged: full.measure()
    onIsBigChanged: full.measure()
    Component.onCompleted: full.measure()

    Connections {
        target: cu
        function onWindowsChanged() { full.measure() }
    }

    readonly property real titleW: Math.ceil(Math.max(titleMetrics.advanceWidth,
        titleMetrics.width))
    readonly property real leadW: Math.ceil(Math.max(leadMetrics.advanceWidth,
        leadMetrics.width))
    readonly property real barH: full.isBig
        ? Math.max(6, Math.round(gscale.tight * 1.1))
        : Math.max(4, Math.round(gscale.tight * 0.75))

    // ── Rows, as the reading and the room allow ──────────────────────────
    // One row per window the record carries: three on this plan (session,
    // week, and the model-scoped week), two where a plan has no scoped window.
    // The room decides the row height, never whether a row is drawn - all of
    // them are the point of the tile.
    readonly property real rowGap: full.isBig ? Math.round(gscale.label * 0.5) : gscale.gap
    // The row block takes the height it is given, up to a ceiling that scales
    // with the tile - a fixed row height left the tiles the operator actually
    // runs with a band of nothing under the rows (192x192 measured 36 px of
    // it; 400x400 leaves a row of air on each side instead). `maxRowH` is
    // where a row stops growing and the slack starts splitting evenly, so a
    // very tall tile gets symmetric air rather than a hole at the bottom.
    readonly property real maxRowH: full.isBig
        ? Math.round(gscale.label * 3.4)
        : Math.max(Math.round(gscale.body * 2.6), full.barH)
    // A row cannot be shorter than the figure it draws - a `body` line box is
    // 1.35x its pixel size on this face - nor than its bar.
    readonly property real minRowH: Math.max(Math.round(gscale.body * 1.35),
        full.barH + Math.round(gscale.tight * 0.5))
    readonly property int rowCount: Math.max(1, cu.windows.length)

    Item {
        id: content
        anchors.fill: parent
        anchors.margins: gscale.pad

        // ── Header: the tile, and which window resets next ───────────────
        Text {
            id: header
            text: "Claude"
            color: colors.foreground
            opacity: 0.75
            font.family: colors.uiFont
            font.pixelSize: gscale.label
            font.letterSpacing: gscale.label * 0.12
        }

        Text {
            id: lead
            text: cu.resetLine
            color: colors.foreground
            opacity: colors.textQuiet
            font.family: colors.uiFont
            font.pixelSize: gscale.micro
            elide: Text.ElideRight
            // Right-aligned beside the title when the two fit on a line -
            // which is how the phone draws it - and on its own line under it
            // when they do not, which is what system-font mode and the small
            // preset need. Measured, never guessed: eliding "Week resets in
            // 3h 20m" would drop the number this line exists for.
            x: full.headerTwoLine ? 0 : Math.max(0, content.width - width)
            y: full.headerTwoLine ? header.height + Math.round(gscale.tight * 0.3) : 0
            width: Math.min(implicitWidth, content.width)
        }

        // ── Rows ─────────────────────────────────────────────────────────
        Column {
            id: rows
            anchors.top: parent.top
            anchors.topMargin: full.rowsTop + full.slack
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: full.rowGap

            Repeater {
                model: cu.windows

                delegate: Item {
                    required property var modelData

                    readonly property real line1: Math.max(rLabel.implicitHeight,
                        rPct.implicitHeight)

                    width: rows.width
                    height: full.rowH

                    Text {
                        id: rLabel
                        x: 0
                        y: full.isBig ? 0 : Math.round((parent.height - implicitHeight) / 2)
                        width: full.labelW
                        text: modelData.label
                        color: colors.foreground
                        opacity: 0.75
                        font.family: colors.uiFont
                        font.pixelSize: gscale.label
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: gscale.label * 0.08
                        elide: Text.ElideRight
                    }

                    Text {
                        id: rPct
                        // Wide and small rows read name, bar, figure - the
                        // figure right-aligned in a measured column; the big
                        // tile's first line is name and figure.
                        x: parent.width - full.pctW
                        y: full.isBig ? 0 : Math.round((parent.height - implicitHeight) / 2)
                        width: full.pctW
                        text: modelData.display
                        color: full.ink(modelData.level, modelData.percent)
                        opacity: modelData.percent < 0 ? colors.textQuiet : 1.0
                        font.family: colors.uiFont
                        font.pixelSize: full.isBig ? Math.round(gscale.body * 1.25) : gscale.body
                        horizontalAlignment: Text.AlignRight
                    }

                    // The bar: big tile full width under the row's first line,
                    // small and wide between the name and the figure. Bigger
                    // on the big preset, where the row has height to spare.
                    Item {
                        id: rBar
                        x: full.isBig ? 0 : full.labelW + full.rowGap
                        // Big rows spread their three lines across the row:
                        // the name at the top, the reset at the foot, the bar
                        // in what is left. Anchored together under the name
                        // (the first cut) they bunched at the top of a row
                        // that had grown.
                        y: full.isBig
                            ? rLabel.implicitHeight + Math.round((Math.max(0,
                                parent.height - rLabel.implicitHeight - rReset.implicitHeight
                                    - height)) / 2)
                            : Math.round((parent.height - height) / 2)
                        width: full.isBig
                            ? parent.width
                            : Math.max(0, rPct.x - full.rowGap - (full.labelW + full.rowGap))
                        height: full.barH

                        Rectangle {
                            anchors.fill: parent
                            radius: Math.min(height / 2, 4)
                            color: colors.foreground
                            opacity: 0.16
                        }
                        Rectangle {
                            width: Math.round(rBar.width * modelData.barValue)
                            height: parent.height
                            radius: Math.min(height / 2, 4)
                            color: full.ink(modelData.level, modelData.percent)
                        }
                    }

                    // The reset, and the moment it lands - the two extra facts
                    // the big preset buys.
                    Text {
                        id: rReset
                        visible: full.isBig && modelData.resetIn !== ""
                        x: 0
                        y: full.isBig
                            ? Math.max(rBar.y + rBar.height,
                                parent.height - implicitHeight)
                            : rBar.y + rBar.height
                        width: full.resetW
                        text: modelData.resetIn
                        color: colors.foreground
                        opacity: colors.textQuiet
                        font.family: colors.uiFont
                        font.pixelSize: gscale.tight
                        elide: Text.ElideRight
                    }
                    Text {
                        id: rAt
                        visible: full.isBig && modelData.resetsAt !== ""
                        x: parent.width - full.atW
                        y: rReset.y
                        width: full.atW
                        text: modelData.resetsAt
                        color: colors.foreground
                        opacity: colors.textQuiet
                        font.family: colors.uiFont
                        font.pixelSize: gscale.tight
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // ── The freshness line, and the provenance under it ──────────────
        Text {
            id: footer
            visible: full.ready && (full.isWide || full.isBig)
            text: cu.footerText
            color: colors.foreground
            opacity: colors.textQuiet
            font.family: colors.uiFont
            font.pixelSize: gscale.micro
            elide: Text.ElideRight
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
        }

        Text {
            id: freshness
            visible: full.ready && cu.freshnessText !== ""
            text: cu.freshnessText
            color: full.freshnessInk
            opacity: cu.warned || cu.old ? 1.0 : colors.textQuiet
            font.family: colors.uiFont
            font.pixelSize: gscale.micro
            elide: Text.ElideRight
            anchors.bottom: footer.visible ? footer.top : parent.bottom
            anchors.bottomMargin: footer.visible ? Math.round(gscale.tight * 0.4) : 0
            anchors.left: parent.left
            anchors.right: parent.right
        }

        // ── Nothing to draw: say why ─────────────────────────────────────
        // Never a plausible number when the record has none. The headline is
        // ClaudeUsageData's own wording of the state ("No Claude record",
        // "Sign-in expired", "No limits in the record") and the line under it
        // says what to look at or what to do.
        Item {
            id: notice
            visible: !full.ready
            anchors.top: parent.top
            anchors.topMargin: header.height + Math.round(gscale.label * 0.5)
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right

            Column {
                width: parent.width
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.round(gscale.tight * 0.8)

                Text {
                    width: parent.width
                    text: cu.headline
                    color: cu.state === "loading" ? colors.foreground : colors.accentRed
                    font.family: colors.uiFont
                    font.pixelSize: gscale.body
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    visible: text !== ""
                    text: cu.detail
                    color: colors.foreground
                    opacity: colors.textQuiet
                    font.family: colors.uiFont
                    font.pixelSize: gscale.micro
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
            }
        }
    }

    // ── Geometry derived from the measured boxes ─────────────────────────
    // Declared after the items they read, and read by their bindings: QML
    // resolves ids across the whole document, so the order is only how it
    // reads.
    readonly property bool headerTwoLine: full.titleW + gscale.gap + full.leadW
        > content.width
    readonly property real rowsTop: header.height
        + (full.headerTwoLine ? Math.round(gscale.tight * 0.3) + lead.height : 0)
        + Math.round(gscale.label * (full.isBig ? 0.5 : 0.8))
    readonly property real footerH: footer.visible ? footer.height + gscale.gap : 0
    readonly property real freshnessH: (freshness.visible ? freshness.height : 0)
        + (footer.visible && freshness.visible ? Math.round(gscale.tight * 0.4) : 0)
    readonly property real rowsAvail: Math.max(0,
        content.height - full.rowsTop - full.footerH - full.freshnessH)
    // The row height the room allows, never below what a row needs: the tile
    // draws every window it was given, and the 160x120 minimum is where three
    // rows and the freshness line have to share 120 px.
    readonly property real rowH: {
        var room = Math.floor((full.rowsAvail - (full.rowCount - 1) * full.rowGap)
            / full.rowCount)
        return Math.max(full.minRowH, Math.min(full.maxRowH, room))
    }
    readonly property real blockH: full.rowCount * full.rowH
        + (full.rowCount - 1) * full.rowGap
    // Whatever the ceiling refuses to swallow is split above and below the
    // block, never left to collect under it.
    readonly property real slack: Math.max(0, Math.floor((full.rowsAvail - full.blockH) / 2))
}
