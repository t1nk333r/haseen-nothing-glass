import QtQuick
import "../../components"
import "../../components/nothing"

// Claude Code's rate-limit windows, Nothing style.
//
// The same three numbers as the Liquid Glass drawing, from the same local
// record (components/ClaudeUsageData.qml watches
// `~/.local/state/omarchy/agents/usage/claude.json`, which Omarchy's own
// collector writes and `t1nk33r.agents` draws in the bar). No webhook, no
// token, no network call, no settings key.
//
// The information architecture is the phone widget's, which is also the glass
// drawing's, so the two desktop styles read as one family and the phone as
// their third size:
//
//   Claude                                   WEEK RESETS IN 3H 20M
//   SESSION  ··············                        0%
//   WEEK     █████████████████████████████       100%
//   FABLE    █████████████████████████████       100%
//   STALE · AS OF 41M AGO
//
// One deliberate difference from the glass twin, and it is this style's own
// rule rather than an oversight: Nothing has an ink and ONE red
// ("red marks state, never decoration"), so the percentage is drawn in `on`
// while there is headroom and in red once the window is in its warning band.
// The glass tile adds a green for headroom because its palette is the macOS
// one; adding a second accent here would give the style a colour it does not
// have, which is a bigger change than the tile is worth. The state still
// rides on the figure's colour, and the segmented bar carries the fraction.
//
// A window whose reset has already passed is `—` with an empty bar, never the
// percentage of the window before it. A record the collector flagged
// ("Sign-in expired") is drawn with its windows and the collector's sentence
// beside them - the last known figures, and why they are the last known ones.
//
// Three layouts, one per grid preset, the same rows on all of them:
//   192x192   the rows, the header (stacked when its two halves do not share
//             a line) and the freshness line.
//   400x192   the one-line header, one-line rows, the freshness line and a
//             provenance footer under it.
//   400x400   the same rows with air: each window's reset countdown and wall
//             clock on its own line under its bar, over the dot field.
//
// Facts first, layout second: widgets/claude-usage/main.qml carries the same
// set, in the same order.
Item {
    id: full
    anchors.fill: parent

    readonly property bool isWide: full.width >= full.height * 1.6
    readonly property bool isBig: !full.isWide && Math.min(full.width, full.height) >= 300

    ClaudeUsageData {
        id: cu
        // An off-screen tile stops the clock that ticks the countdowns.
        active: full.visible
    }

    // "There are numbers on screen". A record the collector flagged is still
    // ready: its windows are drawn, with the reason it flagged them beside.
    readonly property bool ready: cu.state === "ready"

    // The figure's ink. Only a window in its warning band reddens - the one
    // state this style's accent is for - and a window with no live number is
    // dim ink, not a bright one: a dash is the absence of a figure, and this
    // style says so with its own hierarchy rather than with the accent.
    function figureInk(level, percent) {
        if (percent < 0) return nothing.onDim
        return level >= 1 ? nothing.red : nothing.on
    }

    // The window the header names, the freshness line and the provenance
    // footer are ClaudeUsageData's own now (`resetLine`, `freshnessText`,
    // `footerText`). This style draws the same sentences the glass one does
    // because it reads them from the same place, not because someone kept two
    // copies in step.

    // ── Measured columns ─────────────────────────────────────────────────
    // The same rule as the glass drawing: measure on the face that draws it,
    // and measure the form it draws - NLabel uppercases and tracks. The widest
    // row is found by ADVANCE, not by character count ("resets in 2d 4h" and
    // "resets in 3h 6m" are the same length and 4 px apart). `advanceWidth` is
    // readable in the same statement that sets `text`, so the scan needs no
    // change signal and no binding reads it.
    property real labelW: 0
    property real pctW: 0
    property real resetW: 0
    property real atW: 0

    TextMetrics {
        id: titleMetrics
        font.family: nothing.sans
        font.pixelSize: nothing.fLabel
        font.letterSpacing: nothing.trackLabel
        text: "CLAUDE"
    }
    TextMetrics {
        id: leadMetrics
        font.family: nothing.sans
        font.pixelSize: nothing.fMicro
        font.letterSpacing: nothing.trackLabel
        text: cu.resetLine.toUpperCase()
    }
    TextMetrics {
        id: labelMetrics
        font.family: nothing.sans
        font.pixelSize: nothing.fLabel
        font.letterSpacing: nothing.trackLabel
    }
    TextMetrics {
        id: pctMetrics
        font.family: nothing.mono
        font.pixelSize: full.isBig ? nothing.fTitle : nothing.fBody
    }
    TextMetrics {
        id: resetMetrics
        font.family: nothing.sans
        font.pixelSize: nothing.fMicro
        font.letterSpacing: nothing.trackLabel
    }
    TextMetrics {
        id: atMetrics
        font.family: nothing.sans
        font.pixelSize: nothing.fMicro
        font.letterSpacing: nothing.trackLabel
    }

    function measure() {
        var lw = nothing.px(46)
        var pw = nothing.px(34)
        var rw = 0
        var aw = 0
        for (var i = 0; i < cu.windows.length; i++) {
            var w = cu.windows[i]
            labelMetrics.text = w.label.toUpperCase()
            lw = Math.max(lw, labelMetrics.advanceWidth, labelMetrics.width)
            pctMetrics.text = w.display
            pw = Math.max(pw, pctMetrics.advanceWidth, pctMetrics.width)
            resetMetrics.text = w.resetIn.toUpperCase()
            rw = Math.max(rw, resetMetrics.advanceWidth, resetMetrics.width)
            atMetrics.text = w.resetsAt.toUpperCase()
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

    // ── Rows ─────────────────────────────────────────────────────────────
    // One row per window the record carries - three on this plan - and the
    // room decides the row height, never whether a row is drawn: all of them
    // are the point of the tile.
    readonly property real rowGap: nothing.gap
    // The row block takes the height it is given, up to a ceiling that scales
    // with the tile: a fixed 24 px row left the 192x192 tile the operator runs
    // with a 36 px band of nothing under the rows, and the 400x400 preset a
    // 172 px one. Past the ceiling the slack splits evenly above and below the
    // block instead of collecting at the bottom.
    readonly property real maxRowH: full.isBig ? nothing.px(84) : nothing.px(44)
    // A row may never be shorter than the figure it draws: NMono at fBody is
    // an 18 px line box (measured), and a row shorter than that would push the
    // percentage out of its own row and into the neighbouring one.
    readonly property real minRowH: Math.max(nothing.px(18), nothing.px(10) + nothing.hair)
    readonly property int rowCount: Math.max(1, cu.windows.length)

    NCard {
        id: card
        theme: nothing
        anchors.fill: parent

        NDotField {
            theme: nothing
            anchors.fill: parent
            anchors.margins: nothing.pad
            intensity: 0.35
            visible: full.isBig
        }

        Item {
            id: body
            anchors.fill: parent
            anchors.margins: nothing.pad

            // ── Header: the tile, and which window resets next ───────────
            NLabel {
                id: header
                theme: nothing
                text: "Claude"
                font.pixelSize: nothing.fLabel
            }

            NLabel {
                id: lead
                theme: nothing
                visible: full.showLead
                text: cu.resetLine
                font.pixelSize: nothing.fMicro
                elide: Text.ElideRight
                // Right-aligned beside the title when the two fit on a line -
                // how the phone draws it - and on its own line under it when
                // they do not, which is what system-font mode needs. Measured,
                // never guessed: eliding the countdown would drop the number
                // this line exists for.
                x: full.headerTwoLine ? 0 : Math.max(0, body.width - width)
                y: full.headerTwoLine ? header.height + nothing.px(2) : 0
                width: Math.min(implicitWidth, body.width)
            }

            // ── Rows ─────────────────────────────────────────────────────
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

                        width: rows.width
                        height: full.rowH

                        NLabel {
                            id: rLabel
                            theme: nothing
                            x: 0
                            y: full.isBig ? 0 : Math.round((parent.height - implicitHeight) / 2)
                            width: full.labelW
                            text: modelData.label
                            font.pixelSize: full.isBig ? nothing.fLabel : nothing.fMicro
                            elide: Text.ElideRight
                        }

                        NMono {
                            id: rPct
                            theme: nothing
                            x: parent.width - full.pctW
                            y: full.isBig ? 0 : Math.round((parent.height - implicitHeight) / 2)
                            width: full.pctW
                            text: modelData.display
                            color: full.figureInk(modelData.level, modelData.percent)
                            font.pixelSize: full.isBig ? nothing.fTitle : nothing.fBody
                            horizontalAlignment: Text.AlignRight
                        }

                        // The segmented bar: this style's tell, and it makes a
                        // value readable without the number beside it. Full
                        // width under the row's first line on the big preset,
                        // between the name and the figure on the other two.
                        NProgress {
                            id: rBar
                            theme: nothing
                            x: full.isBig ? 0 : full.labelW + full.rowGap
                            // Big rows spread their three lines across the
                            // row - the name at the top, the reset at the
                            // foot, the bar in what is left - so a row that
                            // grew is filled rather than topped.
                            y: full.isBig
                                ? rLabel.implicitHeight + Math.round((Math.max(0,
                                    parent.height - rLabel.implicitHeight
                                        - rReset.implicitHeight - height)) / 2)
                                : Math.round((parent.height - height) / 2)
                            width: full.isBig
                                ? parent.width
                                : Math.max(0, rPct.x - full.rowGap - (full.labelW + full.rowGap))
                            value: modelData.barValue
                            accent: modelData.level >= 1
                            segments: full.isBig ? 32 : 20
                        }

                        // The reset, and the moment it lands - the two extra
                        // facts the big preset buys.
                        NLabel {
                            id: rReset
                            theme: nothing
                            visible: full.isBig && modelData.resetIn !== ""
                            x: 0
                            y: full.isBig
                                ? Math.max(rBar.y + rBar.implicitHeight,
                                    parent.height - implicitHeight)
                                : rBar.y + rBar.implicitHeight
                            width: full.resetW
                            text: modelData.resetIn
                            font.pixelSize: nothing.fMicro
                            elide: Text.ElideRight
                        }
                        NLabel {
                            id: rAt
                            theme: nothing
                            visible: full.isBig && modelData.resetsAt !== ""
                            x: parent.width - full.atW
                            y: rReset.y
                            width: full.atW
                            text: modelData.resetsAt
                            font.pixelSize: nothing.fMicro
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // ── The freshness line, and the provenance under it ──────────
            NLabel {
                id: footer
                theme: nothing
                visible: full.ready && (full.isWide || full.isBig)
                text: cu.footerText
                font.pixelSize: nothing.fMicro
                elide: Text.ElideRight
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
            }

            NLabel {
                id: freshness
                theme: nothing
                visible: full.showFreshness
                text: cu.freshnessText
                color: cu.warned ? nothing.red : nothing.on
                loud: cu.old
                font.pixelSize: nothing.fMicro
                elide: Text.ElideRight
                anchors.bottom: footer.visible ? footer.top : parent.bottom
                anchors.bottomMargin: footer.visible ? nothing.px(2) : 0
                anchors.left: parent.left
                anchors.right: parent.right
            }

            // ── Nothing to draw: say why ─────────────────────────────────
            // Never a plausible number when the record has none. The headline
            // is ClaudeUsageData's own wording of the state ("No Claude
            // record", "Sign-in expired", "No limits in the record") and the
            // line under it says what to look at or what to do.
            Item {
                id: notice
                visible: !full.ready
                anchors.top: parent.top
                anchors.topMargin: header.implicitHeight + nothing.px(6)
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right

                Column {
                    width: parent.width
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: nothing.px(4)

                    NLabel {
                        theme: nothing
                        width: parent.width
                        text: cu.headline
                        color: cu.state === "loading" ? nothing.on : nothing.red
                        font.pixelSize: nothing.fBody
                        font.capitalization: Font.MixedCase
                        font.letterSpacing: 0
                        elide: Text.ElideRight
                    }

                    NLabel {
                        theme: nothing
                        width: parent.width
                        visible: text !== ""
                        text: cu.detail
                        font.pixelSize: nothing.fMicro
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // ── Geometry derived from the measured boxes ─────────────────────────
    readonly property bool headerTwoLine: full.titleW + nothing.gap + full.leadW
        > (full.width - 2 * nothing.pad)
    readonly property real headerBlock: header.implicitHeight + nothing.px(8)
    readonly property real leadBlock: full.showLead
        ? (full.headerTwoLine ? nothing.px(2) + lead.implicitHeight
                              : Math.max(0, lead.implicitHeight - header.implicitHeight))
        : 0
    readonly property real rowsTop: full.headerBlock + full.leadBlock
    // What three rows need at their floor. Every band below is drawn only if
    // the rows still fit after it: the figures are the tile's job, so an old
    // record's age and the header's countdown give way first - at the 160x120
    // minimum the tile is the title and the three rows, which is what that
    // size can hold (measured: with either line drawn, the last row left the
    // tile).
    readonly property real rowsNeed: full.rowCount * full.minRowH
        + (full.rowCount - 1) * full.rowGap
    readonly property real freshnessBlock: full.showFreshness && freshness.implicitHeight > 0
        ? freshness.implicitHeight + (footer.visible ? nothing.px(2) : 0) : 0
    readonly property real band: full.bodyH - full.headerBlock
    readonly property bool showFreshness: full.ready && cu.freshnessText !== ""
        && full.band - freshness.implicitHeight >= full.rowsNeed
    readonly property real footerH: footer.visible
        ? footer.implicitHeight + nothing.px(4) : 0
    readonly property real freshnessH: full.freshnessBlock + full.footerH
    readonly property real bodyH: full.height - 2 * nothing.pad
    // The countdown shares the title's line whenever it fits there, and costs
    // nothing when it does; only when it needs a line of its own does it have
    // to earn one by leaving the rows enough.
    readonly property bool showLead: cu.resetLine !== ""
        && (!full.headerTwoLine || full.band - full.freshnessBlock
            - (nothing.px(2) + lead.implicitHeight) >= full.rowsNeed)
    readonly property real rowsAvail: Math.max(0,
        full.bodyH - full.rowsTop - full.footerH - full.freshnessH)
    readonly property real rowH: {
        var room = Math.floor((full.rowsAvail - (full.rowCount - 1) * full.rowGap)
            / full.rowCount)
        return Math.max(full.minRowH, Math.min(full.maxRowH, room))
    }
    readonly property real blockH: full.rowCount * full.rowH
        + (full.rowCount - 1) * full.rowGap
    readonly property real slack: Math.max(0, Math.floor((full.rowsAvail - full.blockH) / 2))
}
