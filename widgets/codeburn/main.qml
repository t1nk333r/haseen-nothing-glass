import QtQuick
import "../../components"

// AI spend, Liquid Glass.
//
// components/CodeburnData.qml owns all the work in this file: one short
// `stat` sweep of ~/.cache/codeburn every 150 s, and a re-read only when a
// file actually moved. Its `active` is bound to this widget's `visible`
// below, so a tile on another workspace spawns nothing. There is no timer,
// no `date` process and no animation loop here; the 1.26 s
// `codeburn status` recompute is behind the Sync button on the large tile,
// never on a clock.
//
// The number is money, so it is never abbreviated into a lie: the hero shows
// `costLabel` (which only abbreviates above 1000) and the exact figure is
// printed under it whenever the two differ.
//
// The accent carries exactly ONE meaning: this period has already cost at
// least twice a typical completed day (CodeburnData.spike). `accentRed`
// appears in two places for it - the SPIKE word in the header and the newest
// bar in the history, the day the total is still being spent on - and
// nowhere else. A large total, a stale file and an empty cache are never red.
//
// Staleness is shown, never hidden: nobody in this process refreshes the
// cache, so every tile carries `ageLabel` ("2 h old") and brightens it once
// the data is older than three upstream refreshes (CodeburnData.stale).
//
// What the total covers is named, never assumed: "Today" when the source says
// today, otherwise whatever it says - a day out of the rollup ("8 Sep") or a
// longer window ("Last 7 days").
//
// Three layouts, one per grid preset (WidgetRegistry.sizes):
//   192x192   period, total (and the exact total when it differs), calls,
//             sessions, the age; the SPIKE word when it applies.
//   400x192   the same on the left; the priced models and their share of the
//             total on the right. The history needs more height than this
//             preset has and the model split is the more useful half.
//   400x400   period and total; the history with the median day as a
//             hairline; the token split with its cache-hit rate; the models
//             then the projects, a group heading over each; the source, the
//             age and the on-demand recompute.
//
// Facts first, layout second: the Nothing drawing
// (widgets-nothing/codeburn/main.qml) carries the same set, and a new figure
// in CodeburnData belongs on both.
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

    CodeburnData {
        id: cb
        // An off-screen tile costs nothing - see the component's header.
        active: full.visible
    }

    // The family's one type and margin scale - see components/GlassScale.qml.
    // The id is `gscale` and not `scale` on purpose: `scale` is Item's own
    // transform property, and inside a Repeater delegate an unqualified outer
    // id loses to it - every delegated text then silently falls back to the
    // default pixel size.
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

    // Before the first read, and with no cache at all, this is a state with
    // a name and not a blank card.
    readonly property bool ready: cb.loaded && cb.errorMessage === ""

    // What the total actually covers. "Today" only when the source says
    // today, otherwise whatever it says - never the word "today" over a
    // number that is not today's.
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
    // The large tile keeps the hero to a band so the history, the tokens and
    // the breakdown below it have height to live in; the smaller presets give
    // the hero the whole stage.
    readonly property real heroSize: full.isBig
        ? Math.round(gscale.label * 1.5)
        : Math.round(gscale.label * 3.0)

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

    // A row that cost nothing is dropped everywhere: a free or unpriced model
    // still appears in `topModels`, and "$0.00" beside a name says less than
    // the row costs in height.
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
    // an unlabelled list of both reads as one list of one thing.
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

    Item {
        id: body
        anchors.fill: parent
        anchors.margins: gscale.pad

        // The wide tile only splits when there is something to put in the
        // right column; a period that spent nothing gives the hero the whole
        // card rather than a rule with a void behind it.
        readonly property real splitX: Math.round(body.width * 0.52)
        readonly property bool split: full.isWide && models.rows.length > 0
        readonly property real leftW: body.split
            ? Math.max(0, body.splitX - gscale.gap)
            : body.width
        // Share bar thickness: 3 px on the two small presets, 5 px on the
        // large one, where a row is taller.
        readonly property real barH: Math.max(3, Math.round(gscale.tight * 0.36))

        // ── Header: the period, named ──────────────────────────────────
        Text {
            id: header
            text: full.periodText
            color: colors.foreground
            opacity: 0.75
            font.family: colors.uiFont
            font.pixelSize: gscale.micro
            font.letterSpacing: gscale.micro * 0.10
            elide: Text.ElideRight
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: spike.visible ? spike.left : parent.right
            anchors.rightMargin: spike.visible ? gscale.gap : 0
        }

        // The one red thing on a normal day's tile: twice a typical day,
        // already. The chart's newest bar is the same fact, drawn once more.
        Text {
            id: spike
            visible: full.ready && cb.spike
            text: "SPIKE"
            color: colors.accentRed
            font.family: colors.uiFont
            font.pixelSize: gscale.micro
            font.letterSpacing: gscale.micro * 0.14
            font.weight: Font.DemiBold
            anchors.top: parent.top
            anchors.right: parent.right
        }

        // ── Footer ─────────────────────────────────────────────────────
        // Small: the call and session counts, with the age marker under them
        // - at 192 px the counts and the marker on one line is three pixels
        // wider than the card.
        // Wide: counts on the left of the hero's column, the age beside them.
        // Large: the source, the age and the on-demand recompute.
        Item {
            id: footer
            readonly property bool twoRow: !full.isBig && !full.isWide && ageSmall.visible

            x: 0
            width: body.split ? Math.max(0, body.splitX - gscale.gap) : body.width
            height: full.isBig
                ? Math.max(sync.height, sourceBig.implicitHeight, ageBig.implicitHeight)
                : counts.implicitHeight
                    + (footer.twoRow ? ageSmall.implicitHeight + Math.round(gscale.tight * 0.3) : 0)
            anchors.bottom: parent.bottom

            // "11993 calls   125 sess". A Row lays the pieces out on their
            // tops, so the micro caps are pushed down to the numbers' cap
            // height instead of floating above them.
            Row {
                id: counts
                visible: !full.isBig
                spacing: Math.round(gscale.tight * 0.7)
                anchors.top: parent.top
                anchors.left: parent.left

                Text {
                    id: callsNum
                    text: full.ready ? String(cb.calls) : "--"
                    color: colors.foreground
                    font.family: colors.uiFont
                    font.pixelSize: gscale.body
                }
                Text {
                    text: "calls"
                    color: colors.foreground
                    opacity: 0.5
                    font.family: colors.uiFont
                    font.pixelSize: gscale.micro
                    height: callsNum.height
                    verticalAlignment: Text.AlignBottom
                }
                Item { width: Math.round(gscale.tight * 0.6); height: 1 }
                Text {
                    id: sessNum
                    text: full.ready ? String(cb.sessions) : "--"
                    color: colors.foreground
                    font.family: colors.uiFont
                    font.pixelSize: gscale.body
                }
                Text {
                    text: "sess"
                    color: colors.foreground
                    opacity: 0.5
                    font.family: colors.uiFont
                    font.pixelSize: gscale.micro
                    height: sessNum.height
                    verticalAlignment: Text.AlignBottom
                }
            }

            // The staleness marker. Dim while the gap is only the upstream
            // poll interval, bright once it is old enough to mislead - never
            // red, which means something else here.
            Text {
                id: ageSmall
                visible: !full.isBig && full.ready && cb.ageLabel !== ""
                text: cb.ageLabel
                color: colors.foreground
                opacity: cb.stale ? 0.9 : 0.45
                font.family: colors.uiFont
                font.pixelSize: gscale.micro
                anchors.right: parent.right
                anchors.bottom: parent.bottom
            }

            Text {
                id: sourceBig
                visible: full.isBig && full.ready
                text: cb.sourceKind === "daily" ? "Daily cache"
                    : (cb.sourceKind === "live" ? "Recomputed" : "Snapshot")
                color: colors.foreground
                opacity: 0.55
                font.family: colors.uiFont
                font.pixelSize: Math.round(gscale.tight * 0.92)
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                id: ageBig
                visible: full.isBig && full.ready && cb.ageLabel !== ""
                text: cb.ageLabel
                color: colors.foreground
                opacity: cb.stale ? 0.9 : 0.45
                font.family: colors.uiFont
                font.pixelSize: Math.round(gscale.tight * 0.92)
                anchors.left: sourceBig.right
                anchors.leftMargin: gscale.gap
                anchors.verticalCenter: parent.verticalCenter
            }

            // The only thing in this widget that spawns a process on purpose.
            // Measured 1.26 s warm, which is why it is a button and not a
            // timer. Left button only: right-click and the corner grip belong
            // to Placement.qml one layer up.
            Item {
                id: sync
                visible: full.isBig
                width: syncLabel.implicitWidth + 2 * Math.round(gscale.tight * 1.1)
                height: Math.round(gscale.tight * 2.0)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: colors.cardBackground
                    opacity: syncArea.pressed ? colors.cardPressOpacity
                        : (syncArea.containsMouse ? colors.cardHoverOpacity
                                                  : colors.cardBackgroundOpacity)
                }
                Text {
                    id: syncLabel
                    text: cb.recomputing ? "Syncing" : "Sync"
                    color: colors.foreground
                    opacity: cb.recomputing ? 0.5 : 0.9
                    font.family: colors.uiFont
                    font.pixelSize: Math.round(gscale.tight * 0.92)
                    anchors.centerIn: parent
                }
                MouseArea {
                    id: syncArea
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    hoverEnabled: true
                    enabled: full.ready && !cb.recomputing
                    cursorShape: Qt.PointingHandCursor
                    onClicked: cb.recompute()
                }
            }
        }

        // ── Content, between the header and the footer ─────────────────
        Item {
            id: content
            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: footer.top
            anchors.topMargin: gscale.gap
            anchors.bottomMargin: gscale.gap

            // ── The hero, on every size ────────────────────────────────
            Item {
                id: stage
                visible: full.ready
                x: 0
                y: 0
                width: full.isBig ? content.width : body.leftW
                height: full.isBig ? hero.implicitHeight : content.height

                Column {
                    id: hero
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Math.round(gscale.tight * 0.4)

                    // Mark and amount share a baseline: the mark is anchored
                    // to the amount's baseline rather than top-aligned beside
                    // it, which is what a Row would do.
                    Item {
                        id: heroLine
                        width: parent.width
                        height: amount.implicitHeight

                        Text {
                            id: mark
                            text: full.heroMark
                            color: colors.foreground
                            opacity: 0.7
                            font.family: colors.uiFont
                            font.pixelSize: Math.round(full.heroSize * 0.46)
                            anchors.left: parent.left
                            anchors.baseline: amount.baseline
                        }
                        Text {
                            id: amount
                            text: full.heroAmount
                            color: colors.foreground
                            font.family: colors.uiFont
                            font.pixelSize: full.heroSize
                            elide: Text.ElideRight
                            anchors.left: mark.right
                            anchors.leftMargin: Math.round(gscale.tight * 0.3)
                            anchors.right: parent.right
                            anchors.top: parent.top
                        }
                    }

                    // Only when the hero is abbreviated: the exact figure, to
                    // the cent, so a rounded form is never the only number on
                    // screen.
                    Text {
                        id: exact
                        visible: cb.costExactLabel !== cb.costLabel
                        text: cb.costExactLabel
                        color: colors.foreground
                        opacity: 0.55
                        font.family: colors.uiFont
                        font.pixelSize: Math.round(gscale.tight * 1.05)
                        width: parent.width
                        elide: Text.ElideRight
                    }
                }
            }

            // ── Wide: the priced models beside the hero ────────────────
            Rectangle {
                id: divider
                visible: body.split && full.ready
                x: body.splitX
                y: 0
                width: 1
                height: content.height
                color: colors.separator
            }

            Item {
                id: models
                visible: body.split
                readonly property real rowH: Math.round(gscale.body * 1.9)
                readonly property int cap: Math.max(1, Math.floor(content.height / models.rowH))
                readonly property var rows: full.paidModels.slice(0, models.cap)

                x: body.splitX + gscale.gap
                width: Math.max(0, content.width - models.x)
                height: models.rows.length * models.rowH
                y: Math.max(0, Math.round((content.height - models.height) / 2))

                Column {
                    width: parent.width

                    Repeater {
                        model: models.rows

                        Item {
                            id: modelRow
                            required property var modelData

                            width: models.width
                            height: models.rowH

                            Text {
                                id: modelName
                                text: modelRow.modelData.name
                                color: colors.foreground
                                font.family: colors.uiFont
                                font.pixelSize: gscale.body
                                elide: Text.ElideRight
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: modelCost.left
                                anchors.rightMargin: gscale.gap
                            }
                            Text {
                                id: modelCost
                                text: modelRow.modelData.costLabel
                                color: colors.foreground
                                opacity: 0.7
                                font.family: colors.uiFont
                                font.pixelSize: gscale.micro
                                anchors.top: parent.top
                                anchors.right: parent.right
                            }
                            Rectangle {
                                id: modelTrack
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: Math.round(gscale.tight * 0.8)
                                height: body.barH
                                radius: height / 2
                                color: colors.separator
                            }
                            Rectangle {
                                anchors.left: modelTrack.left
                                anchors.bottom: modelTrack.bottom
                                height: modelTrack.height
                                radius: modelTrack.radius
                                width: Math.round(modelTrack.width * modelRow.modelData.share)
                                color: colors.foreground
                                opacity: 0.65
                            }
                        }
                    }
                }
            }

            // ── Large: history, tokens, the breakdown ──────────────────
            // Explicit geometry, not a Column: a Column inserts its spacing
            // between EVERY child, including each row a Repeater appends, so a
            // height budget computed beside it is always wrong by a few gaps.
            // Sized top-down with the list adapting last, so the stack drops
            // rows instead of pushing them through the footer.
            Item {
                id: bigStack
                visible: full.isBig && full.ready
                x: 0
                y: stage.height + gscale.gap
                width: content.width
                height: Math.max(0, content.height - bigStack.y)

                readonly property real tokensH: Math.round(gscale.tight * 3.3)
                // What the history and the list share.
                readonly property real freeH: Math.max(0,
                    bigStack.height - bigStack.tokensH - 2 * gscale.gap)
                // The history keeps a floor: under ~40 px the bars stop being
                // a chart, so the list is what gives way.
                readonly property real chartFloor: Math.round(gscale.tight * 3.1)
                // One heading's own line plus air, so the band above a group's
                // first row is glued to neither the row under it nor the bar
                // above it. The renderer charges one per kind it draws.
                readonly property real headerH: Math.round(gscale.tight * 1.1)
                readonly property real rowNameH: Math.round(gscale.tight * 1.15)
                readonly property real rowAir: Math.max(2, Math.round(gscale.tight * 0.25))
                readonly property real rowH: bigStack.rowNameH + bigStack.rowAir
                    + body.barH + bigStack.rowAir

                // How many rows fit, given how many group headings the slice
                // will draw. Two headings is the worst case, so computing the
                // slice from that can only underfill - the safe direction.
                function rowsFor(bands) {
                    return Math.max(0, Math.min(full.breakdown.length,
                        Math.floor((bigStack.freeH - bigStack.chartFloor
                            - bands * bigStack.headerH) / bigStack.rowH)))
                }

                // Models then projects. When a project exists it reserves the
                // last row for one, so the models -> projects boundary - and
                // with it the second heading - is actually crossed instead of
                // the slice ending inside the models.
                function sliceRows(cap) {
                    var b = full.breakdown
                    var first = -1
                    for (var i = 0; i < b.length; i++)
                        if (b[i].kind === "project") { first = i; break }
                    var out = []
                    var n = (first > 0 && cap > 1)
                        ? Math.min(first, cap - 1) : Math.min(b.length, cap)
                    for (var m = 0; m < n; m++) out.push(b[m])
                    for (var j = first >= 0 ? first : b.length; j < b.length && out.length < cap; j++)
                        out.push(b[j])
                    return out
                }

                readonly property var rows: bigStack.sliceRows(bigStack.rowsFor(2))
                readonly property int headings: {
                    if (bigStack.rows.length === 0) return 0
                    return bigStack.rows[bigStack.rows.length - 1].kind
                        !== bigStack.rows[0].kind ? 2 : 1
                }
                readonly property real listH: bigStack.rows.length * bigStack.rowH
                    + bigStack.headings * bigStack.headerH
                readonly property real chartH: Math.max(bigStack.chartFloor,
                    bigStack.freeH - bigStack.listH)

                // Daily cost, oldest left, newest right. Geometry is property
                // arithmetic on a Repeater of rectangles - no Canvas and
                // nothing repainted per frame.
                Item {
                    id: chart
                    x: 0
                    y: 0
                    width: parent.width
                    height: bigStack.chartH

                    readonly property real axisH: Math.round(gscale.tight * 1.1)
                    readonly property real barsH: Math.max(0,
                        chart.height - chart.axisH - Math.round(gscale.tight * 0.25))
                    readonly property int count: cb.days.length
                    readonly property real slot: chart.count > 0 ? chart.width / chart.count : 0
                    readonly property real barW: Math.max(2,
                        chart.slot - Math.round(gscale.tight * 0.35))
                    readonly property real peak: cb.peakDailyCost > 0 ? cb.peakDailyCost : 1

                    // The typical completed day, as a hairline. It is what
                    // `spike` is measured against, so the rule the word
                    // applies is visible rather than asserted.
                    Rectangle {
                        visible: cb.medianDailyCost > 0
                        width: chart.width
                        height: 1
                        color: colors.separator
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
                            // stub: a 2 px bar is a small number, a missing
                            // bar is a missing day.
                            height: modelData.cost > 0
                                ? Math.max(2, Math.round(chart.barsH
                                    * (modelData.cost / chart.peak)))
                                : 1
                            x: Math.round(index * chart.slot)
                            y: chart.barsH - height
                            radius: Math.min(2, height / 2)
                            color: (chart.newest && cb.spike)
                                ? colors.accentRed : colors.foreground
                            opacity: chart.newest ? 1.0 : 0.35
                        }
                    }

                    Item {
                        id: axis
                        width: parent.width
                        height: chart.axisH
                        anchors.bottom: parent.bottom

                        Text {
                            visible: chart.count > 0
                            text: chart.count > 0 ? cb.days[0].label : ""
                            color: colors.foreground
                            opacity: 0.45
                            font.family: colors.uiFont
                            font.pixelSize: Math.round(gscale.tight * 0.85)
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            visible: chart.count > 1
                            text: chart.count > 1 ? cb.days[chart.count - 1].label : ""
                            color: colors.foreground
                            opacity: 0.7
                            font.family: colors.uiFont
                            font.pixelSize: Math.round(gscale.tight * 0.85)
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                // The token split: the totals, one segmented bar, its legend.
                // The cache hit rate rides on the header line because it is a
                // property of this split, not a figure of its own.
                Item {
                    id: tokens
                    x: 0
                    y: chart.y + chart.height + gscale.gap
                    width: parent.width
                    height: bigStack.tokensH

                    readonly property real total: cb.totalTokens > 0 ? cb.totalTokens : 1

                    Text {
                        text: "Tokens"
                        color: colors.foreground
                        opacity: 0.55
                        font.family: colors.uiFont
                        font.pixelSize: Math.round(gscale.tight * 0.92)
                        anchors.top: parent.top
                        anchors.left: parent.left
                    }
                    Text {
                        text: cb.tokenLabel + "  ·  " + cb.cacheLabel + " cached"
                        color: colors.foreground
                        opacity: 0.9
                        font.family: colors.uiFont
                        font.pixelSize: Math.round(gscale.tight * 0.92)
                        anchors.top: parent.top
                        anchors.right: parent.right
                    }

                    Item {
                        id: tokenBar
                        x: 0
                        y: Math.round(gscale.tight * 1.3)
                        width: parent.width
                        height: Math.max(3, Math.round(gscale.tight * 0.4))

                        Repeater {
                            model: full.tokenParts

                            Rectangle {
                                required property var modelData
                                required property int index

                                // Every class that spent a token keeps at
                                // least a sliver: fresh input is a fraction
                                // of a percent of the corpus here, and
                                // rounding it to nothing would hide the whole
                                // point of the bar.
                                readonly property real frac: modelData.v / tokens.total

                                width: modelData.v > 0
                                    ? Math.max(2, Math.round(tokens.width * frac))
                                    : 0
                                height: parent.height
                                x: {
                                    var acc = 0
                                    for (var i = 0; i < index; i++) {
                                        var v = full.tokenParts[i].v
                                        if (v > 0)
                                            acc += Math.max(2, Math.round(
                                                tokens.width * (v / tokens.total)))
                                    }
                                    return acc
                                }
                                radius: parent.height / 2
                                color: colors.foreground
                                opacity: modelData.shade
                            }
                        }
                    }

                    Row {
                        id: tokenLegend
                        x: 0
                        y: Math.round(gscale.tight * 2.05)
                        width: parent.width
                        spacing: gscale.gap

                        Repeater {
                            model: full.tokenParts

                            Item {
                                id: legend
                                required property var modelData

                                width: Math.max(0, (tokenLegend.width - 3 * gscale.gap) / 4)
                                height: Math.round(gscale.tight * 1.2)

                                Text {
                                    id: legendKey
                                    text: legend.modelData.k
                                    color: colors.foreground
                                    opacity: 0.5
                                    font.family: colors.uiFont
                                    font.pixelSize: Math.round(gscale.tight * 0.7)
                                    elide: Text.ElideRight
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.right: legendValue.left
                                    anchors.rightMargin: Math.round(gscale.tight * 0.3)
                                }
                                Text {
                                    id: legendValue
                                    text: cb.formatTokens(legend.modelData.v)
                                    color: colors.foreground
                                    // The bar under this legend keeps the full
                                    // ramp; the NUMBER is text, and the ramp
                                    // bottoms out at 0.22, which measured
                                    // 2.04:1 on the solid plate - "Cache wr 0"
                                    // was unreadable in both styles while the
                                    // two faces otherwise agree on this row.
                                    // `textQuiet` is the family's documented
                                    // floor for informative text.
                                    opacity: Math.max(legend.modelData.shade,
                                                      colors.textQuiet)
                                    font.family: colors.uiFont
                                    font.pixelSize: Math.round(gscale.tight * 0.85)
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                }
                            }
                        }
                    }
                }

                // Top models, then top projects: what, then where.
                Column {
                    id: bigList
                    x: 0
                    y: tokens.y + tokens.height + gscale.gap
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
                            readonly property bool showKind: bigRow.prev === null
                                || String(bigRow.prev.kind) !== String(bigRow.modelData.kind)

                            width: bigStack.width
                            height: bigStack.rowH
                                + (bigRow.showKind ? bigStack.headerH : 0)

                            Text {
                                visible: bigRow.showKind
                                text: bigRow.modelData.kind === "project"
                                    ? "Projects" : "Models"
                                color: colors.foreground
                                opacity: 0.45
                                font.family: colors.uiFont
                                font.pixelSize: Math.round(gscale.tight * 0.85)
                                anchors.left: parent.left
                                anchors.top: parent.top
                            }

                            // The row's own three children: this wrapper is
                            // their parent now, and it is exactly the row's
                            // height.
                            Item {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: bigStack.rowH

                                Text {
                                    id: bigName
                                    text: bigRow.modelData.k
                                    color: colors.foreground
                                    font.family: colors.uiFont
                                    font.pixelSize: bigStack.rowNameH
                                    height: bigStack.rowNameH
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.right: bigCost.left
                                    anchors.rightMargin: gscale.gap
                                }
                                Text {
                                    id: bigCost
                                    text: bigRow.modelData.v
                                    color: colors.foreground
                                    opacity: 0.7
                                    font.family: colors.uiFont
                                    font.pixelSize: Math.round(gscale.tight * 0.92)
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                }
                                Rectangle {
                                    id: bigTrack
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: bigStack.rowAir
                                    height: body.barH
                                    radius: height / 2
                                    color: colors.separator
                                }
                                Rectangle {
                                    anchors.left: bigTrack.left
                                    anchors.bottom: bigTrack.bottom
                                    height: bigTrack.height
                                    radius: bigTrack.radius
                                    width: Math.round(bigTrack.width * bigRow.modelData.share)
                                    color: colors.foreground
                                    opacity: 0.65
                                }
                            }
                        }
                    }
                }
            }

            // ── Before the first read, and when there is no cache ──────
            // Codeburn not having run is a state with a name, not an error
            // and not a blank tile.
            Column {
                id: notReady
                visible: !full.ready
                width: parent.width
                spacing: gscale.gap
                anchors.centerIn: parent

                Text {
                    width: parent.width
                    text: "--"
                    color: colors.foreground
                    opacity: 0.25
                    font.family: colors.uiFont
                    font.pixelSize: full.heroSize
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    width: parent.width
                    text: !cb.loaded ? "Reading cache" : cb.errorMessage
                    color: colors.foreground
                    opacity: 0.85
                    font.family: colors.uiFont
                    font.pixelSize: gscale.body
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
                // Room to say where it looked, on the tiles that have it.
                Text {
                    visible: (full.isWide || full.isBig) && cb.errorMessage !== ""
                    width: parent.width
                    text: cb.cacheDir
                    color: colors.foreground
                    opacity: 0.4
                    font.family: colors.uiFont
                    font.pixelSize: Math.round(gscale.micro * 0.9)
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideLeft
                }
            }
        }
    }
}
