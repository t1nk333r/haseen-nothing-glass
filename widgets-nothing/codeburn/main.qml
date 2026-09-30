import QtQuick
import "../../components"
import "../../components/nothing"

// AI spend, Nothing style.
//
// CodeburnData owns the only work in this file: one short `stat` sweep of
// ~/.cache/codeburn every 150 s, and a re-read only when a file actually
// moved. Its `active` is bound to this widget's `visible` below, so a tile on
// another workspace spawns nothing. There is no timer here, and the 1.26 s
// `codeburn status` recompute is behind the SYNC button on the large tile -
// never on a clock.
//
// The number is money, so it is never abbreviated into a lie: the hero shows
// `costLabel` (which only abbreviates above 1000) and the large tile prints
// `costExactLabel` underneath whenever the two differ.
//
// The accent carries exactly ONE meaning: this period has already cost at
// least twice a typical completed day (CodeburnData.spike). Nothing else here
// is ever red - not a big number, not a stale file, not an empty cache.
//
// Staleness is shown, never hidden: nobody in this process refreshes the
// cache, so every tile carries `ageLabel` ("2 H OLD") and brightens it once
// the data is older than three upstream refreshes.
Item {
    id: full
    anchors.fill: parent

    // The three grid presets: 192x192, 400x192, 400x400.
    readonly property bool isWide: full.width >= full.height * 1.6
    readonly property bool isBig: !full.isWide && Math.min(full.width, full.height) >= 300

    CodeburnData {
        id: cb
        // An off-screen tile costs nothing - see the component's header.
        active: full.visible
    }

    readonly property bool ready: cb.loaded && cb.errorMessage === ""

    // What the total actually covers. "Today" when the source says today,
    // otherwise whatever it says - a day out of the rollup ("8 Sep") or a
    // longer window ("Last 7 days"). Never the word "today" over a number
    // that is not today's.
    readonly property string periodText: !cb.loaded
        ? "Codeburn"
        : (cb.isToday ? "Today" : (cb.periodLabel !== "" ? cb.periodLabel : "Codeburn"))

    // The currency mark travels with the figure but must not compete with
    // it, so it is split off and set smaller. Splitting rather than trimming
    // keeps the "<" of a sub-cent total ("<$0.01") attached to the mark.
    readonly property string heroMark: {
        var s = cb.costLabel
        var i = s.indexOf(cb.currency)
        return i < 0 ? "" : s.substring(0, i + cb.currency.length)
    }
    readonly property string heroAmount: {
        var s = cb.costLabel
        var i = s.indexOf(cb.currency)
        return i < 0 ? s : s.substring(i + cb.currency.length)
    }

    // The four token classes as one segmented bar. Cache reads dominate by
    // two orders of magnitude here, so the segments are ordered fresh-first
    // and shaded dim-toward-cache: the bar's job is to show that almost
    // nothing is fresh input, which is the interesting fact.
    readonly property var tokenParts: [
        { k: "In", v: cb.inputTokens, shade: 1.0 },
        { k: "Out", v: cb.outputTokens, shade: 0.72 },
        { k: "Cache rd", v: cb.cacheReadTokens, shade: 0.40 },
        { k: "Cache wr", v: cb.cacheWriteTokens, shade: 0.22 }
    ]

    // A row that cost nothing is dropped everywhere: a free or unpriced
    // model still appears in `topModels`, and "$0.00" beside a name says
    // less than the row costs in height.
    readonly property var paidModels: {
        var out = []
        for (var i = 0; i < cb.topModels.length; i++)
            if (cb.topModels[i].cost > 0) out.push(cb.topModels[i])
        return out
    }
    readonly property var paidProjects: {
        var out = []
        for (var i = 0; i < cb.topProjects.length; i++)
            if (cb.topProjects[i].cost > 0) out.push(cb.topProjects[i])
        return out
    }

    // Models first, then projects, in one list - the large tile has room for
    // both and they answer different questions ("what" and "where"). `kind`
    // is carried per row because the two are not the same sort of name: a
    // project is a directory the work happened in, a model is what ran, and
    // an unlabelled list of both reads as one list of one thing (a directory
    // name under three model names looks like a fourth model).
    readonly property var breakdown: {
        var out = []
        for (var i = 0; i < full.paidModels.length && i < 3; i++)
            out.push({ k: full.paidModels[i].name, v: full.paidModels[i].costLabel,
                       share: full.paidModels[i].share, kind: "model" })
        for (var j = 0; j < full.paidProjects.length && j < 2; j++)
            out.push({ k: full.paidProjects[j].name, v: full.paidProjects[j].costLabel,
                       share: full.paidProjects[j].share, kind: "project" })
        return out
    }

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

            readonly property real headTop: Math.max(header.implicitHeight, nothing.px(18)) + nothing.gap
            readonly property real rowH: nothing.px(30)
            readonly property real splitX: Math.round(body.width * 0.52)
            // The wide tile only splits when there is something to put in
            // the right column; a period that spent nothing gives the hero
            // the whole card rather than a rule with a void behind it.
            readonly property bool split: full.isWide && models.rows.length > 0
            // The large tile stacks a chart, a token split and this list in
            // one column, so its rows run tighter - four of them at 30 px
            // left the bars 47 px tall, which is a stripe, not a chart.
            // One fLabel line box, one step of air, the bar, one step of air.
            // Named so the air cannot collapse into the type again - that is
            // what left 2 px between a row's name and its bar. The sum is the
            // 26 px the list budget has always assumed.
            readonly property real rowNameH: nothing.px(14)
            readonly property real rowAir: nothing.px(4)
            readonly property real rowBarH: nothing.px(4)
            readonly property real bigRowH: body.rowNameH + body.rowAir
              + body.rowBarH + body.rowAir

            // ── Header: the period, named ──────────────────────────────
            NLabel {
                id: header
                theme: nothing
                text: full.periodText
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: badge.visible ? badge.left : parent.right
                anchors.rightMargin: badge.visible ? nothing.gap : 0
                elide: Text.ElideRight
            }

            // The one red thing: twice a typical day, already.
            NBadge {
                id: badge
                theme: nothing
                anchors.verticalCenter: header.verticalCenter
                anchors.right: parent.right
                visible: full.ready && cb.spike
                active: true
                label: "Spike"
            }

            // ── Footer ─────────────────────────────────────────────────
            // Small/wide: the call and session counts under the hero, with
            // the age marker beside them - or under them on the 192 tile,
            // where "2032 CALLS 23 SESS 3 MIN OLD" is three pixels wider
            // than the card and the marker would sit on the counts.
            // Large: the source, the age and the on-demand recompute.
            Item {
                id: footer

                readonly property bool twoRow: !full.isBig && !full.isWide
                    && ageSmall.visible

                x: 0
                width: body.split ? Math.max(0, body.splitX - nothing.gap) : body.width
                height: full.isBig
                    ? Math.max(sync.implicitHeight, ageBig.implicitHeight)
                    : counts.implicitHeight
                        + (footer.twoRow ? ageSmall.implicitHeight + nothing.px(2) : 0)
                y: Math.max(0, body.height - footer.height)

                // Small and wide tiles: "2032 CALLS  23 SESS". A Row lays
                // the pieces out on their tops, so the micro caps are
                // pushed to the digits' cap height with an explicit
                // baseline offset instead of floating above them.
                Row {
                    id: counts
                    visible: !full.isBig
                    spacing: nothing.px(5)
                    anchors.left: parent.left
                    anchors.top: parent.top

                    NMono {
                        id: callsNum
                        theme: nothing
                        text: full.ready ? String(cb.calls) : "--"
                        color: nothing.on
                        font.pixelSize: nothing.fLabel
                    }
                    NLabel {
                        theme: nothing
                        text: "calls"
                        font.pixelSize: nothing.fMicro
                        height: callsNum.height
                        verticalAlignment: Text.AlignBottom
                    }
                    Item { width: nothing.px(4); height: 1 }
                    NMono {
                        theme: nothing
                        text: full.ready ? String(cb.sessions) : "--"
                        color: nothing.on
                        font.pixelSize: nothing.fLabel
                    }
                    NLabel {
                        theme: nothing
                        text: "sess"
                        font.pixelSize: nothing.fMicro
                        height: callsNum.height
                        verticalAlignment: Text.AlignBottom
                    }
                }

                // The staleness marker. Dim while the gap is only the
                // upstream poll interval, bright once it is old enough to
                // mislead - never red, which means something else here.
                NLabel {
                    id: ageSmall
                    theme: nothing
                    visible: !full.isBig && full.ready && cb.ageLabel !== ""
                    text: cb.ageLabel
                    loud: cb.stale
                    font.pixelSize: nothing.fMicro
                    // Bottom right of the footer: the same line as the
                    // counts when the footer is one row tall, the line under
                    // them when it is two.
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                }

                NLabel {
                    id: sourceBig
                    theme: nothing
                    visible: full.isBig && full.ready
                    text: cb.sourceKind === "daily" ? "Daily cache"
                        : (cb.sourceKind === "live" ? "Recomputed" : "Snapshot")
                    font.pixelSize: nothing.fMicro
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                }

                NLabel {
                    id: ageBig
                    theme: nothing
                    visible: full.isBig && full.ready && cb.ageLabel !== ""
                    text: cb.ageLabel
                    loud: cb.stale
                    font.pixelSize: nothing.fMicro
                    anchors.left: sourceBig.right
                    anchors.leftMargin: nothing.gap
                    anchors.verticalCenter: parent.verticalCenter
                }

                // The only thing in this widget that spawns a process on
                // purpose. Measured 1.26 s warm, which is why it is a button
                // and not a timer.
                NButton {
                    id: sync
                    theme: nothing
                    visible: full.isBig
                    enabled: !cb.recomputing
                    label: cb.recomputing ? "Syncing" : "Sync"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: cb.recompute()
                }
            }

            // ── Content ────────────────────────────────────────────────
            Item {
                id: content
                x: 0
                y: body.headTop
                width: body.width
                height: Math.max(0, body.height - nothing.gap - footer.height - content.y)

                // ── The hero, on every size ───────────────────────────
                Item {
                    id: stage
                    x: 0
                    y: 0
                    width: body.split ? Math.max(0, body.splitX - nothing.gap) : content.width
                    // The large tile gives the rest of its height to the
                    // history, the token split and the list below.
                    height: full.isBig ? nothing.px(58) : content.height
                    visible: full.ready

                    Item {
                        id: hero
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: amount.implicitHeight
                            + (exact.visible ? exact.implicitHeight + nothing.px(2) : 0)

                        // A dot-matrix hero was tried here and rejected: the
                        // glyph set has no "$", and cents make the string six
                        // glyphs - 32 columns against the clock's 17, which
                        // is a 4 px dot on a 192 tile. Money keeps its cents,
                        // so the hero is type.
                        NText {
                            id: amount
                            theme: nothing
                            text: full.heroAmount
                            color: nothing.on
                            font.family: nothing.sansBold
                            font.pixelSize: full.isBig ? nothing.px(44)
                                : (full.isWide ? nothing.px(40) : nothing.px(34))
                            // A four-figure total shrinks to fit rather than
                            // pushing the card out of shape.
                            fontSizeMode: Text.HorizontalFit
                            minimumPixelSize: nothing.px(14)
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            horizontalAlignment: Text.AlignHCenter
                        }

                        // The currency mark, smaller so it names the figure
                        // without competing with it. Anchored to the amount's
                        // PAINTED edge rather than laid out beside it: the
                        // amount is centred inside a fit box as wide as the
                        // tile, so a Row stranded this glyph at the far left
                        // of that box - which is exactly how it rendered
                        // before this margin existed.
                        NText {
                            theme: nothing
                            text: full.heroMark
                            color: nothing.onDim
                            font.family: nothing.sansBold
                            font.pixelSize: Math.round(amount.font.pixelSize * 0.46)
                            anchors.right: amount.left
                            anchors.rightMargin: nothing.px(3)
                                - Math.round((amount.width - amount.contentWidth) / 2)
                            anchors.baseline: amount.baseline
                        }

                        // Only when the hero is abbreviated: the exact
                        // figure, to the cent, so a rounded form is never
                        // the only number on screen.
                        NMono {
                            id: exact
                            theme: nothing
                            visible: cb.costExactLabel !== cb.costLabel
                            text: cb.costExactLabel
                            color: nothing.onDim
                            font.pixelSize: nothing.fLabel
                            anchors.top: amount.bottom
                            anchors.topMargin: nothing.px(2)
                            anchors.left: parent.left
                            anchors.right: parent.right
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }

                // ── Wide: what is eating it, beside the hero ──────────
                // The 16-day history loses to the model split at this size:
                // after the header there are ~130 px to share with the hero,
                // which gives a sparkline 8 px a bar. The large tile carries
                // the history instead.
                NDivider {
                    theme: nothing
                    vertical: true
                    // No priced model to list - a period that spent nothing -
                    // leaves the hero the whole card instead of a rule with
                    // an empty column behind it.
                    visible: body.split && full.ready
                    x: body.splitX
                    y: 0
                    height: content.height
                }

                Item {
                    id: models
                    visible: full.isWide && full.ready

                    readonly property int cap: Math.max(1, Math.floor(content.height / body.rowH))
                    readonly property var rows: full.paidModels.slice(0, models.cap)

                    x: body.splitX + nothing.gap
                    width: Math.max(0, content.width - models.x)
                    height: models.rows.length * body.rowH
                    y: Math.max(0, Math.round((content.height - models.height) / 2))

                    Column {
                        width: parent.width

                        Repeater {
                            model: models.rows

                            Item {
                                id: modelRow
                                required property var modelData

                                width: models.width
                                height: body.rowH

                                NLabel {
                                    id: modelName
                                    theme: nothing
                                    text: modelRow.modelData.name
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.right: modelCost.left
                                    anchors.rightMargin: nothing.gap
                                    elide: Text.ElideRight
                                    // The model's name is the row; the price
                                    // beside it is the number. In system-font
                                    // mode "DeepSeek v4 Flash" measures
                                    // 132.8 px against this 130 px column and
                                    // loses its last glyph - with no slack in
                                    // the row to give it, shrink into the box
                                    // before eliding, as the rest of this
                                    // style does (PORTING.md item 9).
                                    fontSizeMode: Text.HorizontalFit
                                    minimumPixelSize: Math.max(7, nothing.fMicro - 1)
                                }

                                NMono {
                                    id: modelCost
                                    theme: nothing
                                    text: modelRow.modelData.costLabel
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
                                    anchors.bottomMargin: nothing.px(9)
                                    height: nothing.px(4)
                                    segments: 20
                                    value: modelRow.modelData.share
                                }
                            }
                        }
                    }
                }

                // ── Large: the history, the token split, the breakdown ─
                // Explicit geometry, not a Column: a Column inserts its
                // spacing between EVERY child, including each row a Repeater
                // appends, so a height budget computed beside it is always
                // wrong by a few gaps - which is how the first draft pushed
                // its last list row through the footer. Sized top-down with
                // the list adapting last, so a 300x300 tile drops rows
                // instead of overflowing the card.
                Item {
                    id: bigStack
                    visible: full.isBig && full.ready
                    x: 0
                    y: stage.height + nothing.gap
                    width: content.width
                    height: Math.max(0, content.height - bigStack.y)

                    readonly property real tokensH: nothing.px(44)
                    // What the chart and the list share.
                    readonly property real freeH: Math.max(0,
                        bigStack.height - bigStack.tokensH - 2 * nothing.gap)
                    // The chart keeps a floor: under ~56 px the bars stop
                    // being a chart, so the list is what gives way - and the
                    // row it drops is always the cheapest one.
                    // The heading's own line (an fMicro label measures 11 px in
                    // the shell's font settings) plus one step of air, so the
                    // band above a group's first row is not glued to either the
                    // row under it or the bar above it.
                    readonly property real headerH: nothing.px(16)
                    // One heading per group the slice draws: the first row
                    // always has one, and the models -> projects boundary has
                    // another. Charged here because the renderer charges it.
                    readonly property int modelRows: Math.min(full.paidModels.length, 3)
                    function rowsFor(bands) {
                      return Math.max(0, Math.min(full.breakdown.length,
                        Math.floor((bigStack.freeH - nothing.px(56)
                          - bands * bigStack.headerH) / body.bigRowH)))
                    }
                    // One estimate, then the headings that estimate implies.
                    // Charging the second can only shrink the list, so a single
                    // pass settles it; the one case it can overshoot - the
                    // charge dropping the slice back to models only - underfills
                    // by one band, which is the safe direction.
                    readonly property int headings: {
                      var n = bigStack.rowsFor(1)
                      return (bigStack.modelRows > 0 && n > bigStack.modelRows) ? 2 : 1
                    }
                    readonly property int listRows: bigStack.rowsFor(bigStack.headings)
                    readonly property var rows: full.breakdown.slice(0, bigStack.listRows)
                    // The list's height as the renderer builds it: every row is
                    // bigRowH and every heading is headerH. `chartH` takes what
                    // is left, so the column cannot overspend the box again.
                    readonly property real listH: bigStack.listRows * body.bigRowH
                      + bigStack.headings * bigStack.headerH
                    readonly property real chartH: Math.max(nothing.px(56),
                      bigStack.freeH - bigStack.listH)

                    // Daily cost, oldest left, newest right. The geometry is
                    // property arithmetic on a Repeater of rectangles - no
                    // Canvas, nothing repainted per frame, for the same
                    // reason TickRing precomputes its tick endpoints.
                    Item {
                        id: chart
                        x: 0
                        y: 0
                        width: parent.width
                        height: bigStack.chartH

                        readonly property real barsH: Math.max(0, chart.height - axis.height - nothing.px(3))
                        readonly property int count: cb.days.length
                        readonly property real slot: chart.count > 0 ? chart.width / chart.count : 0
                        readonly property real barW: Math.max(2, chart.slot - nothing.px(3))
                        readonly property real peak: cb.peakDailyCost > 0 ? cb.peakDailyCost : 1

                        // The typical completed day, as a hairline. It is
                        // what `spike` is measured against, so the rule the
                        // badge applies is visible rather than asserted.
                        Rectangle {
                            visible: cb.medianDailyCost > 0
                            width: chart.width
                            height: 1
                            color: nothing.onFaint
                            y: Math.round(chart.barsH
                                - chart.barsH * (cb.medianDailyCost / chart.peak))
                        }

                        Repeater {
                            model: cb.days

                            Rectangle {
                                required property var modelData
                                required property int index

                                readonly property bool newest: index === chart.count - 1

                                width: chart.barW
                                // A day with any spend at all keeps a visible
                                // stub: a 2 px bar is a small number, a
                                // missing bar is a missing day.
                                height: modelData.cost > 0
                                    ? Math.max(2, Math.round(chart.barsH
                                        * (modelData.cost / chart.peak)))
                                    : 1
                                x: Math.round(index * chart.slot)
                                y: chart.barsH - height
                                radius: nothing.rDot
                                color: newest
                                    ? (cb.spike ? nothing.red : nothing.on)
                                    : nothing.onFaint
                            }
                        }

                        Item {
                            id: axis
                            width: parent.width
                            height: nothing.px(12)
                            anchors.bottom: parent.bottom

                            NLabel {
                                theme: nothing
                                visible: chart.count > 0
                                text: chart.count > 0 ? cb.days[0].label : ""
                                font.pixelSize: nothing.fMicro
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            NLabel {
                                theme: nothing
                                visible: chart.count > 1
                                text: chart.count > 1 ? cb.days[chart.count - 1].label : ""
                                loud: true
                                font.pixelSize: nothing.fMicro
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    // The token split: the totals, one segmented bar, its
                    // legend. The cache hit rate rides on the header line
                    // because it is a property of this split, not a figure
                    // of its own.
                    Item {
                        id: tokens
                        x: 0
                        y: chart.height + nothing.gap
                        width: parent.width
                        height: bigStack.tokensH

                        readonly property real total: cb.totalTokens > 0 ? cb.totalTokens : 1
                        readonly property real barW: tokens.width

                        NLabel {
                            theme: nothing
                            text: "Tokens"
                            font.pixelSize: nothing.fMicro
                            anchors.top: parent.top
                            anchors.left: parent.left
                        }

                        NMono {
                            theme: nothing
                            text: cb.tokenLabel + "  ·  " + cb.cacheLabel + " cached"
                            color: nothing.onDim
                            font.pixelSize: nothing.fLabel
                            anchors.top: parent.top
                            anchors.right: parent.right
                        }

                        Item {
                            id: tokenBar
                            x: 0
                            y: nothing.px(17)
                            width: parent.width
                            height: nothing.px(6)

                            Repeater {
                                model: full.tokenParts

                                Rectangle {
                                    required property var modelData
                                    required property int index

                                    // Every class that spent a token keeps at
                                    // least a sliver: fresh input is 0.006%
                                    // of the corpus here, and rounding it to
                                    // nothing would hide the whole point.
                                    readonly property real frac: modelData.v / tokens.total

                                    width: modelData.v > 0
                                        ? Math.max(2, Math.round(tokens.barW * frac))
                                        : 0
                                    height: parent.height
                                    x: {
                                        var acc = 0
                                        for (var i = 0; i < index; i++) {
                                            var v = full.tokenParts[i].v
                                            if (v > 0)
                                                acc += Math.max(2, Math.round(
                                                    tokens.barW * (v / tokens.total)))
                                        }
                                        return acc
                                    }
                                    radius: nothing.rDot
                                    color: Qt.rgba(nothing.on.r, nothing.on.g,
                                                   nothing.on.b, modelData.shade)
                                }
                            }
                        }

                        Row {
                            x: 0
                            y: nothing.px(27)
                            width: parent.width
                            spacing: nothing.gap

                            Repeater {
                                model: full.tokenParts

                                Item {
                                    id: legend
                                    required property var modelData

                                    width: Math.max(0, (tokens.width - 3 * nothing.gap) / 4)
                                    height: nothing.px(14)

                                    NLabel {
                                        theme: nothing
                                        text: legend.modelData.k
                                        font.pixelSize: nothing.fMicro
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }

                                    NMono {
                                        theme: nothing
                                        text: cb.formatTokens(legend.modelData.v)
                                        // The bar under this legend keeps the
                                        // full ramp; the NUMBER is text and
                                        // may not read below the style's own
                                        // floor. `shade` bottoms out at 0.22,
                                        // which is `onFaint` by value - the
                                        // token NTheme documents as 1.93:1 and
                                        // says no Text may read - so "Cache wr
                                        // 0" measured 1.93:1 against the card
                                        // and was invisible. `onQuiet` (0.48,
                                        // 5.0:1) is the documented quietest
                                        // text weight.
                                        color: Qt.rgba(nothing.on.r, nothing.on.g,
                                                       nothing.on.b,
                                                       Math.max(legend.modelData.shade,
                                                                nothing.onQuiet.a))
                                        font.pixelSize: nothing.fLabel
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                    }
                                }
                            }
                        }
                    }

                    // Top models, then top projects: what, then where.
                    Column {
                        x: 0
                        y: tokens.y + tokens.height + nothing.gap
                        width: parent.width

                        Repeater {
                            model: bigStack.rows

                            Item {
                                id: bigRow
                                required property var modelData
                                required property int index

                                // The first row, and either side of the
                                // models/projects boundary, carry the label.
                                readonly property var prev: index > 0
                                    ? bigStack.rows[index - 1] : null
                                readonly property bool showKind: prev === null
                                    || String(prev.kind) !== String(bigRow.modelData.kind)

                                width: bigStack.width
                                height: body.bigRowH + (bigRow.showKind ? bigStack.headerH : 0)

                                NLabel {
                                    theme: nothing
                                    visible: bigRow.showKind
                                    text: bigRow.modelData.kind === "project"
                                        ? "Projects" : "Models"
                                    color: nothing.onQuiet
                                    font.pixelSize: nothing.fMicro
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                }

                                // The row's own three children keep their
                                // anchors: this wrapper is their parent now,
                                // and it is exactly the row's height.
                                Item {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: body.bigRowH

                                NLabel {
                                    theme: nothing
                                    text: bigRow.modelData.k
                                    height: body.rowNameH
                                    verticalAlignment: Text.AlignVCenter
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.right: bigRowCost.left
                                    anchors.rightMargin: nothing.gap
                                    elide: Text.ElideRight
                                }

                                NMono {
                                    id: bigRowCost
                                    theme: nothing
                                    text: bigRow.modelData.v
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
                                    // The tighter row gets a full air step
                                    // under the name, not what is left of it.
                                    anchors.bottomMargin: body.rowAir
                                    height: body.rowBarH
                                    segments: 24
                                    value: bigRow.modelData.share
                                }
                                }
                            }
                        }
                    }
                }

                // ── Before the first read, and when there is no cache ──
                // Codeburn simply not having run is a state with a name, not
                // an error and not a blank tile.
                Column {
                    visible: !full.ready
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: nothing.gap

                    Item {
                        width: parent.width
                        height: waiting.implicitHeight

                        NDotMatrix {
                            id: waiting
                            theme: nothing
                            anchors.centerIn: parent
                            text: "--"
                            onColor: nothing.onDim
                            // Capped, like the storage tile's: this is a
                            // placeholder, not a reading, and a "--" fitted
                            // to the whole stage is a slab of ghost dots.
                            fitWidth: Math.min(content.width * 0.55, nothing.px(70))
                            fitHeight: Math.min(content.height * 0.34, nothing.px(34))
                        }
                    }

                    NLabel {
                        theme: nothing
                        loud: true
                        text: !cb.loaded ? "Reading cache" : cb.errorMessage
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    // Room to say where it looked, on the tiles that have it.
                    NMono {
                        theme: nothing
                        visible: (full.isWide || full.isBig) && cb.errorMessage !== ""
                        text: cb.cacheDir
                        color: nothing.onDim
                        font.pixelSize: nothing.fMicro
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideLeft
                    }
                }
            }
        }
    }
}
