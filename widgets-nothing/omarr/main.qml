import QtQuick
import "../../components"
import "../../components/nothing"

// The omarr fleet and its queue, Nothing style.
//
// The Nothing twin of widgets/omarr/main.qml: one data source (OmarrData,
// which reads the feed the `t1nk33r.omarr` plugin publishes at
// `~/.local/state/omarchy/omarr/feed.json`) and no timer of its own - the
// freshness rule, the fleet summary and the wording live in the component, so
// the two drawings cannot disagree about what the fleet is doing.
//
// The tile answers ONE question - "is anything wrong, and is anything
// moving?" - and its hero is that answer, resolved once in OmarrData
// (`heroKind`/`heroLabel`/`heroDetail`) so the two faces cannot disagree:
//
//   * the OFFENDER NAMED, when a service is not answering - "SONARR DOWN", or
//     "2 DOWN" with the names on the detail line. The first
//     preset-independent answer to "which one";
//   * the count that is MOVING, with its speed on the detail line;
//   * the depth that is NOT moving ("6 QUEUED");
//   * what is on next, when nothing is wrong and nothing is moving;
//   * the fleet COUNTED, claiming nothing about its health, LAST ("6
//     SERVICES"): it is the one fact that never moves - it used to own the
//     largest type while a six-deep queue sat unread in the same document;
//   * no state the feed did not send, in any of those. `health` "unknown" is
//     omarr having no reading yet for that service - what the board's status
//     column draws as a dash - and not a third state: it drives no branch of
//     this chain, and a fleet of six unknowns is never "6 WAITING" or "6 UP";
//   * the detail line under the hero is the hero's own (the names, the speed)
//     when it has one, and omarr's own summary string otherwise - minus the
//     bare fleet count, which this tile already draws;
//   * the fleet strip: one pip per service, in the feed's own order, at every
//     preset. At 192 it is the only per-service surface there is, which is
//     what makes naming at most one offender at that size acceptable;
//   * the per-service board on the two presets with a second column, sorted
//     exception-first (a down service leads), each row carrying its service's
//     STATUS in the value column and nothing else in it - up, down, paused, or
//     a dash while omarr has no reading - so the column is one kind of datum
//     on every row and can be scanned down. The queue depth rides with the
//     name as a small count beside it ("SONARR 6"), because being busy is a
//     property of the service and not of its status, and no version is drawn
//     anywhere on this tile (the feed still publishes it).
//
// The accent carries exactly ONE meaning on this face, as on the glass one: a
// service is not answering, or omarr's badge is urgent. It marks the hero, the
// one board row that IS a failure, the one pip that is down, and the badge -
// and nothing else. An old feed is NOT red: it is the freshness line, and this
// style marks it the way the Nothing claude tile marks an old record, with
// `NBadge`/`NLabel`'s `loud` rather than with a colour. Nothing OS has one
// accent and no amber, and spending the red on "this reading is four minutes
// old" would spend it on the one state it is not for.
//
// The HERO is TYPE, not NDotMatrix: the dot-matrix glyph set is digits, ".",
// "-", "%" and ":" (components/nothing/dots.js), so it can draw "6 SERVICES"
// but it cannot draw "SONARR DOWN" or "NEXT: <title>", which the hero now is -
// the same finding widgets-nothing/deepseek/main.qml and codeburn record for
// their own heroes. The dot matrix is still where the text is known to be digits,
// and the strip is now the second such place: one `NDotMatrix` over a 1x1
// pattern per service is the style's own primitive used as a pip, not a new
// one.
//
// Presets, as everywhere in this tree, from components/GlassScale.qml's own
// table: 192x192 is the strip, the hero, its detail line and the download;
// 400x192 adds the per-service board in a column on the right; 400x400 is the
// same with air and the lead download's time left and speed back.
Item {
    id: full
    anchors.fill: parent

    readonly property bool isWide: full.width >= full.height * 1.6
    readonly property bool isBig: !full.isWide && Math.min(full.width, full.height) >= 300
    readonly property bool isList: om.ready && (full.isWide || full.isBig)

    OmarrData {
        id: om
        active: full.visible
    }

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

            readonly property real splitX: Math.round(body.width * 0.54)
            readonly property real leftW: full.isList
                ? Math.max(0, body.splitX - nothing.gap)
                : body.width
            readonly property real rightW: full.isList
                ? Math.max(0, body.width - body.splitX - nothing.gap)
                : 0

            // One row of the board, and its footer. Both fixed by the style's
            // own type scale rather than by the tile: Nothing's `px()` is a
            // per-style scale, not a per-size one, so the board reads the same
            // at 192 and at 400. Sized so the operator's six-row fleet fits
            // both presets that draw a board (6 x 17 px plus a 14 px footer is
            // 116 px of the 122 px a 400x192 tile gives the board); a larger
            // fleet caps and says so under it.
            readonly property real rowH: nothing.px(17)
            readonly property real listFootH: nothing.px(14)

            // ── Header ────────────────────────────────────────────────────
            NLabel {
                id: header
                theme: nothing
                text: "omARR"
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: badge.visible ? badge.left : parent.right
                anchors.rightMargin: badge.visible ? nothing.gap : 0
                elide: Text.ElideRight
            }

            // The bar item's own badge, in this style's short form: red when
            // omarr called it urgent (a service unreachable), a faint outline
            // otherwise.
            NBadge {
                id: badge
                theme: nothing
                visible: om.ready && om.badgeVisible
                anchors.top: parent.top
                anchors.right: parent.right
                active: om.badgeUrgent
                label: String(om.badgeNumber)
            }

            // ── Freshness, and where the numbers came from ─────────────────
            Item {
                id: footer
                visible: om.freshnessText !== ""
                x: 0
                width: body.width
                height: readout.implicitHeight
                    + (source.visible ? nothing.px(4) + source.implicitHeight : 0)
                y: Math.max(0, body.height - footer.height)

                // "as of 12s ago" / "stale · as of 4m ago" - the write time of
                // the feed, never "when we read it". An old reading is `loud`
                // (full ink) rather than coloured: see the header.
                NLabel {
                    id: readout
                    theme: nothing
                    text: om.freshnessText
                    loud: om.stale
                    font.pixelSize: nothing.fMicro
                    width: parent.width
                    elide: Text.ElideRight
                    anchors.top: parent.top
                }

                // The provenance line the large preset has room for: the local
                // source, named.
                NText {
                    id: source
                    theme: nothing
                    visible: full.isBig
                    text: om.sourceLabel
                    color: nothing.onQuiet
                    font.pixelSize: nothing.fMicro
                    width: parent.width
                    elide: Text.ElideRight
                    anchors.top: readout.bottom
                    anchors.topMargin: nothing.px(4)
                }
            }

            // ── Stage: the fleet, the queue, and the reason there is neither
            Item {
                id: stage
                x: 0
                y: header.implicitHeight + nothing.gap
                width: body.width
                height: Math.max(0, footer.y - nothing.gap - stage.y)

                readonly property real heroW: body.leftW

                // ── The block the stage centres ───────────────────────────
                // The hero, omarr's line and the download are ONE block,
                // centred in whatever the header and the freshness line leave -
                // the same treatment as the glass drawing and the rest of this
                // style's hero tiles. Every band joins it only if the space
                // left for it covers its own height.
                readonly property real statusGap: nothing.px(2)
                readonly property real leadGap: nothing.px(4)
                readonly property bool leadWanted: om.ready && om.lead !== null

                // One line of the caption under the hero, measured on the face
                // that draws it - NOT `Text.lineHeight`, which is a multiplier
                // in Qt 6 and not a pixel height. The floor is PORTING item 9's
                // rule.
                TextMetrics {
                    id: statusMetrics
                    font.family: nothing.mono
                    font.pixelSize: nothing.fMicro
                    text: stage.captionText
                }
                readonly property real statusLineH:
                    Math.max(nothing.px(11), Math.ceil(statusMetrics.height))

                // The one line under the hero. It is the hero's OWN detail when
                // the hero has one - the names behind "2 down", the speed
                // behind "2 downloading" - and omarr's own summary line when it
                // does not. Both are resolved in OmarrData; this only picks
                // which of the two the tile has room for, and both drawings
                // pick it the same way.
                readonly property string captionText:
                    om.heroDetail !== "" ? om.heroDetail : om.statusLineText

                // Everything drawn above the caption - the strip, and the hero.
                // The room the caption is judged against is measured from this
                // rather than from the hero alone, or the strip would be the
                // one band the fit test does not know it paid for.
                readonly property real aboveH: (stage.stripH > 0 ? stage.stripH + stage.stripGap : 0)
                    + hero.implicitHeight

                // How many lines the caption gets: two when the stage holds
                // them, one when it holds only that, none when the hero alone
                // has filled it. Decided from the FEED and from measured
                // heights, never from the Text's own `visible`, which is what it
                // decides. Measured at 160x120: a two-line summary here ran
                // through the freshness line before this rule existed.
                readonly property int statusLines: (om.ready && stage.captionText === "") ? 0 : (
                    (stage.height - stage.aboveH - stage.statusGap)
                        >= 2 * stage.statusLineH ? 2 : (
                    (stage.height - stage.aboveH - stage.statusGap)
                        >= stage.statusLineH ? 1 : 0))

                readonly property real leadRoom: Math.max(0, stage.height
                    - stage.aboveH
                    - (statusLine.visible ? stage.statusGap + statusLine.implicitHeight : 0)
                    - stage.leadGap)

                // The time-left/speed line is the large preset's, and the FIRST
                // thing the download gives up - the title and its meter are the
                // reading. It joins only when the room covers it and its own
                // measured advance fits the column; both heights are measured
                // without reading `visible`, so neither can loop.
                readonly property bool metaWanted: full.isBig && om.lead !== null
                    && (om.lead.timeleft !== "" || om.lead.speedLabel !== "")
                    && leadMeta.implicitWidth <= stage.heroW
                readonly property real leadH: stage.metaWanted && stage.leadRoom >= lead.hWithMeta
                    ? lead.hWithMeta : lead.hNoMeta
                readonly property bool leadShown: stage.leadWanted && stage.leadRoom >= stage.leadH

                readonly property real blockH: stage.aboveH
                    + (statusLine.visible ? stage.statusGap + statusLine.implicitHeight : 0)
                    + (stage.leadShown ? stage.leadGap + stage.leadH : 0)
                readonly property real blockTop: Math.max(0, Math.round((stage.height - stage.blockH) / 2))

                // ── The fleet strip ───────────────────────────────────────
                // One pip per service, in the feed's own order: the ONLY
                // per-service surface at 192, where the board is gone and the
                // hero names at most one offender. The hero says what is
                // wrong; the strip says how much of the fleet it is.
                //
                // Drawn with the style's own primitive - NDotMatrix over a
                // 1x1 pattern is one lit dot - rather than a new one, and
                // never below 3 px: the dot floor is the STOP rule for this
                // band, so it holds at any `uiScale`. The gap is elastic
                // because the fleet's size is the operator's, not the tile's:
                // it opens to px(4) when the column can afford it and closes
                // to 2 px before the pips would run past it.
                readonly property int pipDot: Math.max(3, nothing.px(3))
                readonly property real pipGap: {
                    var n = om.serviceCount
                    if (n < 2) return 0
                    var room = stage.heroW - n * stage.pipDot
                    return Math.max(2, Math.min(nothing.px(4), Math.floor(room / (n - 1))))
                }
                readonly property real stripH: om.ready ? stage.pipDot : 0
                readonly property real stripGap: nothing.px(4)

                Item {
                    id: strip
                    visible: om.ready
                    x: 0
                    width: stage.heroW
                    height: stage.stripH
                    y: hero.y - stage.stripH - stage.stripGap

                    Row {
                        spacing: stage.pipGap
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter

                        Repeater {
                            model: om.services

                            NDotMatrix {
                                required property var modelData
                                theme: nothing
                                pattern: ["1"]
                                dot: stage.pipDot
                                // Red for a service that is not answering,
                                // full ink for one that is, and the faint ink
                                // that is drawn rather than read for the state
                                // that has not answered yet.
                                onColor: modelData.down ? nothing.red
                                    : (modelData.waiting ? nothing.onFaint : nothing.on)
                            }
                        }
                    }
                }

                // ── With a feed ───────────────────────────────────────────
                // The hero: the tile's one answer to "is anything wrong, and is
                // anything moving?" - the offender's name when a service is
                // down, then the count of what is moving, then the depth of
                // what is not, then what is on deck, and the fleet counted,
                // with nothing said about its health, when there is nothing
                // else to say. No branch in it speaks for a state the feed did
                // not send: a service omarr has no reading for is not a
                // waiting service. The order lives in OmarrData (`heroKind`),
                // so this face and the glass one cannot answer differently.
                //
                // Sized from the style's own roles rather than a literal, and
                // never elided: an ellipsis in "SONARR DOWN" would hide the one
                // word the tile is for. A long name is shrunk to fit by
                // `HorizontalFit` down to the style's floor rather than cut.
                NText {
                    id: hero
                    theme: nothing
                    visible: om.ready
                    text: om.heroLabel
                    color: om.alert ? nothing.red : nothing.on
                    font.family: nothing.sansBold
                    font.pixelSize: full.isBig
                        ? nothing.px(46) : (full.isWide ? nothing.px(40) : nothing.px(34))
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: nothing.px(12)
                    width: stage.heroW
                    x: 0
                    y: stage.blockTop
                    horizontalAlignment: Text.AlignLeft
                }

                // The caption: the hero's own detail when it has one, omarr's
                // own summary line when it does not (see `stage.captionText`).
                // Red only when omarr itself is calling something unreachable;
                // otherwise it is a readout, not a warning. Wrapped to two lines
                // wherever the stage holds them. Only a tile that cannot hold
                // two elides it, and only one that cannot hold one drops it.
                NMono {
                    id: statusLine
                    theme: nothing
                    visible: om.ready && text !== "" && stage.statusLines > 0
                    text: stage.captionText
                    color: om.alert ? nothing.red : nothing.on
                    // A caption under the hero, set at the caption size so the
                    // download below it still fits - the glass drawing's rule,
                    // and its measurement.
                    font.pixelSize: nothing.fMicro
                    wrapMode: Text.WordWrap
                    maximumLineCount: Math.max(1, stage.statusLines)
                    elide: Text.ElideRight
                    width: stage.heroW
                    x: 0
                    y: hero.y + hero.implicitHeight + stage.statusGap
                }

                // ── The leading download ──────────────────────────────────
                // The feed's own first active row - the plugin's own merge
                // order, never re-sorted here. The meter is the style's
                // segmented bar: the segments are the Nothing tell and they
                // make the fill readable without the number beside it.
                Item {
                    id: lead
                    x: 0
                    width: stage.heroW
                    y: hero.y + hero.implicitHeight
                        + (statusLine.visible ? stage.statusGap + statusLine.implicitHeight : 0)
                        + stage.leadGap

                    readonly property real progress: om.lead ? om.lead.progress : 0

                    // The two heights the block can have, from what it holds
                    // and never from its own `visible`: the fit test IS
                    // `visible`.
                    readonly property real hNoMeta: leadTitle.implicitHeight
                        + nothing.px(4) + progress.implicitHeight
                    readonly property real hWithMeta: lead.hNoMeta
                        + nothing.px(3) + leadMeta.implicitHeight

                    visible: stage.leadShown
                    height: visible ? stage.leadH : 0

                    NText {
                        id: leadTitle
                        theme: nothing
                        // `om.lead` is null on the frame the feed arrives with
                        // an empty queue; the binding must not read through it.
                        text: om.lead ? om.lead.title : ""
                        color: nothing.on
                        font.pixelSize: nothing.fMicro
                        elide: Text.ElideRight
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: leadPercent.left
                        anchors.rightMargin: nothing.gap
                    }

                    // The one number on this face that IS digits, so the dot
                    // matrix draws it - the style's own readout, not a font.
                    NDotMatrix {
                        id: leadPercent
                        theme: nothing
                        text: om.lead ? String(om.lead.percent) + "%" : ""
                        dot: nothing.px(2)
                        gap: nothing.px(2)
                        anchors.right: parent.right
                        anchors.verticalCenter: leadTitle.verticalCenter
                    }

                    NProgress {
                        id: progress
                        theme: nothing
                        value: lead.progress
                        segments: full.isBig ? 28 : 18
                        implicitHeight: nothing.px(6)
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: leadTitle.bottom
                        anchors.topMargin: nothing.px(4)
                    }

                    // What is left of it and how fast it is going - the two
                    // fields omarr's own progress toast shows. Never invented:
                    // an empty field draws nothing.
                    NMono {
                        id: leadMeta
                        theme: nothing
                        visible: stage.metaWanted
                        text: {
                            var parts = []
                            if (om.lead && om.lead.timeleft !== "") parts.push(om.lead.timeleft + " left")
                            if (om.lead && om.lead.speedLabel !== "") parts.push(om.lead.speedLabel)
                            return parts.join("  ·  ")
                        }
                        color: nothing.onDim
                        font.pixelSize: nothing.fMicro
                        width: parent.width
                        elide: Text.ElideRight
                        anchors.top: progress.bottom
                        anchors.topMargin: nothing.px(4)
                    }
                }

                // ── Nothing to draw: say why ──────────────────────────────
                // Every state that is not a readable feed. Not red: an absent
                // file is not a service going down, and the status board below
                // is where this style spends its accent.
                Column {
                    id: notice
                    visible: !om.ready && om.noticeHeadline !== ""
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: nothing.px(5)

                    NText {
                        id: noticeHeadline
                        theme: nothing
                        text: om.noticeHeadline
                        font.family: nothing.sansBold
                        font.pixelSize: nothing.fBody
                        width: notice.width
                        elide: Text.ElideRight
                    }

                    NText {
                        id: noticeDetail
                        theme: nothing
                        text: om.noticeDetail
                        color: nothing.onDim
                        font.pixelSize: nothing.fMicro
                        width: notice.width
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }

                // ── The per-service status board ──────────────────────────
                // The two presets with a second column. Rows come from
                // OmarrData already sorted exception-first and each carrying the
                // row's own live fact, so the two drawings' boards cannot order
                // or word differently. Capped to the height it has, and never a
                // cut list without a count under it.
                Item {
                    id: board
                    visible: full.isList
                    x: body.splitX + nothing.gap
                    y: 0
                    width: body.rightW
                    height: stage.height
                    readonly property int cap: Math.max(0, Math.floor(
                        (board.height - body.listFootH) / body.rowH))
                    readonly property var rows: om.boardRows.slice(0, board.cap)

                    NDivider {
                        theme: nothing
                        vertical: true
                        x: body.splitX - Math.round(nothing.gap / 2)
                        y: stage.y
                        height: Math.max(0, body.height - stage.y)
                    }

                    Column {
                        id: boardCol
                        width: board.width
                        y: Math.round((board.height - (board.cap * body.rowH + body.listFootH)) / 2)

                        Repeater {
                            model: board.rows

                            Item {
                                id: boardRow
                                required property var modelData
                                required property int index

                                width: board.width
                                height: body.rowH

                                NLabel {
                                    id: rowLabel
                                    theme: nothing
                                    text: boardRow.modelData.label
                                    font.pixelSize: nothing.fMicro
                                    // The NAME keeps the room it needs and
                                    // gives back only what the row's other two
                                    // faces actually take: the badge and the
                                    // status are read from the row's right
                                    // edge, and the name fills whatever is
                                    // left of them - the glass drawing's rule,
                                    // and the same reason. At this style's
                                    // fixed 9 px readout both always fit, and
                                    // the rule is here so the two faces stay
                                    // one drawing.
                                    readonly property real freeW: Math.max(0, parent.width
                                        - rowStatus.implicitWidth
                                        - (rowActivity.visible
                                            ? rowActivity.implicitWidth + nothing.gap : 0)
                                        - nothing.gap)
                                    width: Math.min(implicitWidth, rowLabel.freeW)
                                    elide: Text.ElideRight
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                // How much work the service is holding, riding
                                // with the NAME: being busy is a property of the
                                // service, not of its status, and putting it in
                                // the value column is what made that column say
                                // three different things. It sits directly after
                                // the label - "SONARR 6", the name's own badge
                                // and not a second value column, which is why
                                // the step between them is this style's tight
                                // internal one and not its column gap - and a
                                // service with nothing queued draws no badge at
                                // all, so the name keeps the whole row. The
                                // count is the style's own readout face, and it
                                // is resolved in OmarrData (`activity`).
                                NMono {
                                    id: rowActivity
                                    theme: nothing
                                    visible: boardRow.modelData.activity > 0
                                    text: String(boardRow.modelData.activity)
                                    color: nothing.onDim
                                    font.pixelSize: nothing.fMicro
                                    anchors.left: rowLabel.right
                                    anchors.leftMargin: nothing.px(4)
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                // The value column: the row's STATUS, and one
                                // kind of datum on every row and in every state
                                // - UP, DOWN, PAUSED, or the dash omarr's own
                                // "unknown" resolves to while it has no reading
                                // for the service. Never a count and never a
                                // version: a column with three meanings has
                                // none.
                                //
                                // The dash is drawn in the ink for what is NOT
                                // read - `onQuiet`, one step under the row's own
                                // `onDim` - so the absence of a reading is
                                // quieter than any word in the column instead of
                                // reading as a fifth status. A down service is
                                // still the one red word.
                                NLabel {
                                    id: rowStatus
                                    theme: nothing
                                    text: boardRow.modelData.status
                                    color: boardRow.modelData.alert ? nothing.red
                                        : (boardRow.modelData.absent
                                            ? nothing.onQuiet : nothing.onDim)
                                    loud: boardRow.modelData.alert
                                    font.pixelSize: nothing.fMicro
                                    horizontalAlignment: Text.AlignRight
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                NDivider {
                                    theme: nothing
                                    visible: boardRow.index < board.rows.length - 1
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                }
                            }
                        }
                    }

                    // "6 services" / "3 of 6 services" - the same wording the
                    // glass drawing and the storage board use, so a capped list
                    // reads the same wherever it appears in this tree.
                    NMono {
                        id: boardFoot
                        theme: nothing
                        visible: board.rows.length > 0
                        text: board.rows.length < om.serviceCount
                            ? board.rows.length + " of " + om.serviceCount + " services"
                            : om.serviceCount + (om.serviceCount === 1 ? " service" : " services")
                        color: nothing.onDim
                        font.pixelSize: nothing.fMicro
                        elide: Text.ElideRight
                        width: board.width
                        anchors.top: boardCol.bottom
                        anchors.left: parent.left
                    }
                }
            }
        }
    }
}
