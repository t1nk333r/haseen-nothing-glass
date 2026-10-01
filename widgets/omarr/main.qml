import QtQuick
import "../../components"

// The omarr fleet and its queue, Liquid Glass.
//
// The Liquid Glass twin of widgets-nothing/omarr/main.qml, carrying the same
// facts out of the same component: OmarrData reads the feed the
// `t1nk33r.omarr` plugin publishes (`~/.local/state/omarchy/omarr/feed.json`).
// No service lookup, no HTTP, no credential - see that component's header for
// the file, the contract and the writer's atomic rename.
//
// The tile is a glance, not omarr's panel, and it answers ONE question: "is
// anything wrong, and is anything moving?" The hero is that answer, resolved
// once in OmarrData and read by both drawings, in this order:
//
//   * the OFFENDER NAMED, when a service is not answering - "Sonarr down", or
//     "2 down" with the names on the line under it. The first
//     preset-independent answer to "which one", and the state this tile
//     exists for;
//   * the count that is MOVING, with its speed: "2 downloading";
//   * the depth that is NOT moving: "6 queued";
//   * what is on next, when nothing is wrong and nothing is moving;
//   * the fleet COUNTED, claiming nothing about its health, LAST ("6
//     services"): it is the one fact that never moves - it used to own the
//     largest type while a six-deep queue sat unread in the same document;
//   * no state the feed did not send, in any of those. `health` "unknown" is
//     omarr having no reading yet for that service - what the board's status
//     column draws as a dash - and not a third state: it drives no branch of
//     this chain, and a fleet of six unknowns is never "6 waiting" or "6 up";
//   * the line under the hero is the hero's own detail (the names, the speed)
//     when it has one, and omarr's own summary string otherwise - minus the
//     bare fleet count, which this tile already draws;
//   * the fleet strip: one pip per service, in the feed's own order, at every
//     preset. At 192 it is the only per-service surface there is;
//   * the queue: the lead download's title, its meter and its percentage, and
//     its time left and speed where there is room;
//   * the bar's badge, by the bar's own rule (unread events, else the count of
//     unreachable services), red when omarr itself calls it urgent;
//   * the per-service status board on the two presets wide enough for a list,
//     sorted exception-first (a down service leads), each row carrying its
//     service's STATUS in the value column and nothing else in it - up, down,
//     paused, or a dash while omarr has no reading - so the column is one kind
//     of datum on every row and can be scanned down. The queue depth rides
//     with the name as a small count beside it ("SONARR 6"), because being
//     busy is a property of the service and not of its status, and no version
//     is drawn anywhere on this tile (the feed still publishes it). Capped to
//     the height it has, with a footer that says how many of the fleet it is
//     showing.
//
// The accent (`accentRed`) carries exactly one meaning, as on the Nothing
// drawing: a service is not answering, or omarr's badge is urgent. An old feed
// is NOT the accent - it is the freshness line, "stale · as of 4m ago", in
// `accentAmber`, which is the same token the Claude tile uses for an old
// record. A colour cannot say "this was written four minutes ago", and a tile
// that looks current when it is not is the one failure this widget must not
// have.
//
// Layout, one per grid preset (the table in components/GlassScale.qml):
//   192x192   the strip, the hero, the line under it, and the lead download's
//             title over its meter. The board is gone: six rows at this type
//             size would BE the tile, and the answer is what a glance wants.
//   400x192   the strip, hero and line on the left, the queue under them; the
//             service board in a column on the right, with the vertical rule
//             at the split.
//   400x400   the same two columns with air, and the lead download gets its
//             time left and speed back.
//
// A tile with nothing to read is never a blank card and never a plausible-
// looking healthy fleet: the notice state names the reason ("No omarr feed",
// "Can't read the feed", a feed of a version this widget does not know, or a
// feed with no service in it). None of those is drawn in the accent - an
// absent file is not a service going down.
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

    OmarrData {
        id: om
        // An off-screen tile costs nothing - the watch and the freshness clock
        // both stop. See the component's header.
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

    readonly property bool isWide: gscale.isWide
    readonly property bool isBig: gscale.isBig
    // The two presets with room for the per-service board.
    readonly property bool isList: om.ready && (full.isWide || full.isBig)

    Item {
        id: body
        anchors.fill: parent
        anchors.margins: gscale.pad

        // The split the Nothing drawing puts its own vertical at.
        readonly property real splitX: Math.round(body.width * 0.54)
        readonly property real leftW: full.isList
            ? Math.max(0, body.splitX - gscale.gap)
            : body.width
        readonly property real rightW: full.isList
            ? Math.max(0, body.width - body.splitX - gscale.gap)
            : 0

        // One row of the board: the service's name and its live fact. Sized
        // from the two faces it holds rather than from a literal that can
        // drift from its own contents - and sized so the operator's six-row
        // fleet fits both presets that draw a board (measured: 6 x 16 px plus
        // the footer is 111 px of the 120 px a 400x192 tile gives the board,
        // 6 x 30 plus the footer is 209 px of the 224 px a 400x400 one gives
        // it). A larger fleet caps and says so, below.
        readonly property real rowH:
            Math.round(gscale.micro * 1.15) + Math.round(gscale.tight * 0.3)
        readonly property real listFootH: Math.round(gscale.micro * 1.25)

        // ── Header ────────────────────────────────────────────────────────
        // "omARR" is the name the bar item and the panel use; the tile answers
        // to the same one.
        Text {
            id: header
            textFormat: Text.PlainText
            text: "omARR"
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

        // The bar item's own badge, by the bar item's own rule (BarWidget.qml
        // lines 16-18): the unread count when there is one, the badge count
        // otherwise, and the accent when omarr called it urgent - which is what
        // `badgeUrgent` means (`Model.barBadge`: a service is unreachable).
        //
        // Drawn as ink rather than as a filled pill, which is how every other
        // glass tile in this tree carries a badge (storage's "FULL"): the
        // accent is a colour a widget may not hardcode an ink for, and a token
        // for the ink on a red fill does not exist here.
        Text {
            id: badge
            textFormat: Text.PlainText
            visible: om.ready && om.badgeVisible
            text: String(om.badgeNumber)
            color: om.badgeUrgent ? colors.accentRed : colors.foreground
            opacity: om.badgeUrgent ? 1.0 : colors.textQuiet
            font.family: colors.uiFont
            font.pixelSize: gscale.micro
            font.weight: om.badgeUrgent ? Font.DemiBold : Font.Normal
            horizontalAlignment: Text.AlignRight
            anchors.top: parent.top
            anchors.right: parent.right
        }

        // ── Freshness, and where the numbers came from ────────────────────
        Item {
            id: footer
            visible: om.freshnessText !== ""
            x: 0
            width: body.width
            height: readout.implicitHeight
                + (source.visible ? Math.round(gscale.tight * 0.6) + source.implicitHeight : 0)
            y: Math.max(0, body.height - footer.height)

            // "as of 12s ago" / "stale · as of 4m ago" - the write time of the
            // feed, never "when we read it". Part of the design, not a debug
            // string: the numbers come out of a file omarr fills in on its own
            // cadence (10 s on a change, 120 s idle), and past a few minutes
            // of that the tile says so instead of passing them off as current.
            Text {
                id: readout
                textFormat: Text.PlainText
                text: om.freshnessText
                color: om.stale ? colors.accentAmber : colors.foreground
                opacity: om.stale ? 1.0 : colors.textQuiet
                font.family: colors.uiFont
                font.pixelSize: gscale.micro
                elide: Text.ElideRight
                width: parent.width
                anchors.top: parent.top
            }

            // The provenance line, which the large preset has room for: the
            // local source, named.
            Text {
                id: source
                textFormat: Text.PlainText
                visible: full.isBig
                text: om.sourceLabel
                color: colors.foreground
                opacity: colors.textQuiet
                font.family: colors.uiFont
                font.pixelSize: gscale.micro
                width: parent.width
                elide: Text.ElideRight
                anchors.top: readout.bottom
                anchors.topMargin: Math.round(gscale.tight * 0.6)
            }
        }

        // ── Stage: the fleet, the queue, and the reason there is neither ──
        Item {
            id: stage
            x: 0
            y: body.height > 0 ? header.implicitHeight + gscale.gap : 0
            width: body.width
            height: Math.max(0, footer.y - gscale.gap - stage.y)

            // ── The hero: one number, measured to fit ─────────────────────
            // advanceWidth is linear in pixelSize, so one measurement at 100 px
            // scales exactly; 0.97 keeps the last glyph off the edge. The share
            // of the stage is per preset: at 400x400 the hero takes just over a
            // quarter of it, because the board beside it is the rest of the
            // tile, while the small presets have nothing else to give the
            // space to.
            TextMetrics {
                id: headlineMetrics
                font.family: colors.uiFont
                font.pixelSize: 100
                text: om.heroLabel
            }

            readonly property real heroShare: full.isBig ? 0.28 : 0.52
            readonly property real heroFit: headlineMetrics.advanceWidth > 0
                ? stage.heroW * 0.97 * 100 / headlineMetrics.advanceWidth
                : gscale.hero
            readonly property real heroSize: Math.max(11, Math.round(Math.min(
                gscale.hero,
                stage.height * stage.heroShare,
                stage.heroFit)))

            // The column the hero is drawn in: the left one whenever the board
            // takes the right.
            readonly property real heroW: body.leftW

            // ── The block the stage centres ───────────────────────────────
            // The hero, omarr's line and the download are ONE block, centred
            // vertically in whatever the header and the freshness line leave -
            // the family's own treatment of a hero tile (deepseek, codeburn,
            // battery). Every band joins it only if the space left for it
            // covers its own height: nothing here is estimated, and a band that
            // does not fit is omitted rather than squeezed.
            readonly property real statusGap: Math.round(gscale.tight * 0.5)
            readonly property real leadGap: gscale.tight
            readonly property bool leadWanted: om.ready && om.lead !== null

            // One line of omarr's summary, measured on the face that draws it.
            // NOT `Text.lineHeight`: in Qt 6 that is a MULTIPLIER (1.0 by
            // default), not a pixel height, and reading it here made every tile
            // believe a two-line summary was 2 px tall - which is exactly how
            // the Nothing 160x120 tile came to draw its second line through the
            // freshness line. The floor is PORTING item 9's rule: a measurement
            // may only widen the estimate, and this one is 0 until the face is
            // resolved.
            TextMetrics {
                id: statusMetrics
                font.family: colors.uiFont
                font.pixelSize: gscale.micro
                text: stage.captionText
            }
            readonly property real statusLineH:
                Math.max(Math.round(gscale.micro * 1.25), Math.ceil(statusMetrics.height))

            // The one line under the hero: the hero's OWN detail when it has one
            // - the names behind "2 down", the speed behind "2 downloading" -
            // and omarr's own summary line when it does not. Both are resolved
            // in OmarrData, so the two drawings cannot prefer differently.
            readonly property string captionText:
                om.heroDetail !== "" ? om.heroDetail : om.statusLineText

            // Everything drawn above the caption - the strip, and the hero - so
            // the room the caption is judged against is measured from what it
            // actually has rather than from the hero alone.
            readonly property real aboveH: (stage.stripH > 0 ? stage.stripH + stage.stripGap : 0)
                + hero.implicitHeight

            // How many lines the caption gets: two when the stage holds them,
            // one when it holds only that, none when the hero alone has filled
            // it. Decided from the FEED and from measured heights, never from
            // the Text's own `visible`, which is what it decides.
            readonly property int statusLines: (om.ready && stage.captionText === "") ? 0 : (
                (stage.height - stage.aboveH - stage.statusGap)
                    >= 2 * stage.statusLineH ? 2 : (
                (stage.height - stage.aboveH - stage.statusGap)
                    >= stage.statusLineH ? 1 : 0))

            // The room the download has, from what is drawn above it.
            readonly property real leadRoom: Math.max(0, stage.height
                - stage.aboveH
                - (statusLine.visible ? stage.statusGap + statusLine.implicitHeight : 0)
                - stage.leadGap)

            // The time-left/speed line is the large preset's and is the FIRST
            // thing the download gives up - the title and its meter are the
            // reading, the two fields under them are the detail. It joins only
            // when the room covers it AND its own measured advance fits the
            // column (measured: at 400x400 it is 221 px of the 170 px the glass
            // left column has, so it is dropped rather than elided, while the
            // Nothing drawing's 9 px type fits it in its own column). Both
            // heights are measured without reading `visible`, so neither can
            // loop.
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

            // ── The fleet strip ───────────────────────────────────────────
            // One pip per service in the feed's own order - the only
            // per-service surface at 192, where the board is gone and the hero
            // names at most one offender. `foreground` at 0.85 is how every
            // other glass tile carries a diagrammatic mark (the dial hands,
            // `annotationOpacity`); the accent is the token the accent always
            // is, and `textQuiet` the ink for a service that has not answered
            // yet. No colour is written here.
            //
            // The dot never goes below 3 px and the gap is elastic, because the
            // fleet's size is the operator's and not the tile's: it opens to
            // 0.8 of a `tight` step when the column can afford it, and closes
            // to 2 px before the pips would run past it.
            readonly property real pipDot: Math.max(3, Math.round(gscale.tight * 0.6))
            readonly property real pipGap: {
                var n = om.serviceCount
                if (n < 2) return 0
                var room = stage.heroW - n * stage.pipDot
                return Math.max(2, Math.min(Math.round(gscale.tight * 0.8),
                    Math.floor(room / (n - 1))))
            }
            readonly property real stripH: om.ready ? stage.pipDot : 0
            readonly property real stripGap: gscale.tight

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

                        Rectangle {
                            required property var modelData
                            width: stage.pipDot
                            height: stage.pipDot
                            radius: width / 2
                            color: modelData.down ? colors.accentRed : colors.foreground
                            opacity: modelData.down ? 1.0
                                : (modelData.waiting ? colors.textQuiet : 0.85)
                        }
                    }
                }
            }

            Text {
                id: hero
                textFormat: Text.PlainText
                visible: om.ready
                text: om.heroLabel
                color: om.alert ? colors.accentRed : colors.foreground
                font.family: colors.uiFont
                font.pixelSize: stage.heroSize
                // No `elide`: the size above is what fits it, and a fleet
                // count that has been shrunk to fit must not then be cut - an
                // ellipsis in "Sonarr down" would hide the one word the tile is
                // for.
                x: 0
                y: stage.blockTop
            }

            // ── The line under the hero ───────────────────────────────────
            // The hero's own detail, or omarr's summary string verbatim when
            // the hero has none (the bar item shows that same string, and two
            // places on one desktop must not word one line differently).
            // Wrapped to two lines wherever the stage holds them, because when
            // it IS omarr's line it is the tile's first-priority fact: "2
            // downloading · Radarr unreachable" measures 224 px against the
            // 160 px a 192x192 tile gives it, and a one-line box would cut it
            // at every preset. Only a tile that cannot hold two lines elides
            // it, and only a tile that cannot hold one drops it (see
            // `statusLines`).
            Text {
                id: statusLine
                textFormat: Text.PlainText
                visible: om.ready && text !== "" && stage.statusLines > 0
                text: stage.captionText
                color: om.alert ? colors.accentRed : colors.foreground
                opacity: om.alert ? 1.0 : colors.textQuiet
                font.family: colors.uiFont
                // A caption, not a headline: omarr's line sits UNDER the hero,
                // and it is set at the caption size so the download below it
                // still fits (measured: at 192x192 the body size wraps this
                // line to 2 x 18 px and leaves 18 px for a download that needs
                // 23, so the meter was being dropped from the one tile that
                // shows the fleet AND the queue together).
                font.pixelSize: gscale.micro
                wrapMode: Text.WordWrap
                maximumLineCount: Math.max(1, stage.statusLines)
                elide: Text.ElideRight
                width: stage.heroW
                x: 0
                y: hero.y + hero.implicitHeight + stage.statusGap
            }

            // ── The leading download ──────────────────────────────────────
            // The feed's own first active row, which is the plugin's own merge
            // order; nothing here re-sorts it. Its percentage is derived by the
            // component, so the two drawings round it the same way.
            Item {
                id: lead
                x: 0
                width: stage.heroW
                y: hero.y + hero.implicitHeight
                    + (statusLine.visible ? stage.statusGap + statusLine.implicitHeight : 0)
                    + stage.leadGap

                readonly property real meterH: Math.max(3, Math.round(gscale.tight * 0.55))
                readonly property real progress: om.lead ? om.lead.progress : 0

                // The two heights the block can have, from what it holds and
                // never from its own `visible`: the fit test IS `visible`.
                readonly property real hNoMeta: leadTitle.implicitHeight
                    + Math.round(gscale.tight * 0.5) + lead.meterH
                readonly property real hWithMeta: lead.hNoMeta
                    + Math.round(gscale.tight * 0.5) + leadMeta.implicitHeight

                visible: stage.leadShown
                height: visible ? stage.leadH : 0

                Text {
                    id: leadTitle
                    textFormat: Text.PlainText
                    // `om.lead` is null on the frame the feed arrives with an
                    // empty queue; the binding must not read through it.
                    text: om.lead ? om.lead.title : ""
                    color: colors.foreground
                    opacity: 0.9
                    font.family: colors.uiFont
                    font.pixelSize: gscale.micro
                    elide: Text.ElideRight
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: leadPercent.left
                    anchors.rightMargin: gscale.gap
                }

                Text {
                    id: leadPercent
                    textFormat: Text.PlainText
                    text: om.lead ? om.lead.percentLabel : ""
                    color: colors.foreground
                    font.family: colors.uiFont
                    font.pixelSize: gscale.micro
                    font.weight: Font.DemiBold
                    anchors.top: parent.top
                    anchors.right: parent.right
                }

                // The channel, not a divider: a meter whose empty part cannot
                // be seen says nothing about how much is left, and a download
                // at 0% would then draw no meter at all.
                Rectangle {
                    id: leadTrack
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: leadTitle.bottom
                    anchors.topMargin: Math.round(gscale.tight * 0.5)
                    height: lead.meterH
                    radius: height / 2
                    color: colors.foreground
                    opacity: 0.20
                }
                Rectangle {
                    anchors.left: leadTrack.left
                    anchors.top: leadTrack.top
                    height: leadTrack.height
                    radius: leadTrack.radius
                    width: Math.round(leadTrack.width * Math.max(0, Math.min(1, lead.progress)))
                    color: colors.foreground
                    opacity: 0.8
                }

                // What is left of it and how fast it is going - the same two
                // fields omarr's own progress toast shows, where the tile has
                // room for a line. Never invented: empty fields draw nothing.
                Text {
                    id: leadMeta
                    textFormat: Text.PlainText
                    visible: stage.metaWanted
                    text: {
                        var parts = []
                        if (om.lead && om.lead.timeleft !== "") parts.push(om.lead.timeleft + " left")
                        if (om.lead && om.lead.speedLabel !== "") parts.push(om.lead.speedLabel)
                        return parts.join("  ·  ")
                    }
                    color: colors.foreground
                    opacity: 0.7
                    font.family: colors.uiFont
                    font.pixelSize: gscale.micro
                    elide: Text.ElideRight
                    width: parent.width
                    anchors.top: leadTrack.bottom
                    anchors.topMargin: Math.round(gscale.tight * 0.5)
                }
            }

            // ── The notice: why there is no fleet to draw ─────────────────
            // Every state that is not a readable feed, in one place. The
            // headline is the component's own wording of the state and the
            // line under it says what to look at.
            Column {
                id: notice
                visible: !om.ready && om.noticeHeadline !== ""
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.round(gscale.tight * 0.5)

                Text {
                    id: noticeHeadline
                    textFormat: Text.PlainText
                    text: om.noticeHeadline
                    color: colors.foreground
                    font.family: colors.uiFont
                    font.pixelSize: gscale.body
                    font.weight: Font.DemiBold
                    width: notice.width
                    elide: Text.ElideRight
                }

                Text {
                    id: noticeDetail
                    textFormat: Text.PlainText
                    text: om.noticeDetail
                    color: colors.foreground
                    opacity: 0.7
                    font.family: colors.uiFont
                    font.pixelSize: gscale.micro
                    width: notice.width
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }

            // ── The per-service status board ──────────────────────────────
            // Only the two presets with a second column draw it. Rows come from
            // OmarrData already sorted exception-first, each carrying the row's
            // own live fact, so the two drawings' boards cannot order or word
            // differently. Capped to the height it is given - a fleet that
            // outgrows its tile is never cut silently, the footer says how many
            // rows are shown.
            Item {
                id: board
                visible: full.isList
                x: body.splitX + gscale.gap
                y: 0
                width: body.rightW
                height: stage.height
                // Never a cut list without a count under it: the footer is part
                // of the board, not an extra.
                readonly property int cap: Math.max(0, Math.floor(
                    (board.height - board.footH) / body.rowH))
                readonly property var rows: om.boardRows.slice(0, board.cap)

                readonly property real footH: body.listFootH

                Column {
                    id: boardCol
                    width: board.width
                    y: Math.round((board.height - (board.cap * body.rowH + board.footH)) / 2)

                    Repeater {
                        model: board.rows

                        Item {
                            id: boardRow
                            required property var modelData
                            required property int index

                            width: board.width
                            height: body.rowH

                            Text {
                                id: rowName
                                textFormat: Text.PlainText
                                text: boardRow.modelData.label
                                color: colors.foreground
                                opacity: 0.9
                                font.family: colors.uiFont
                                font.pixelSize: gscale.micro
                                // The NAME keeps the room it needs and gives
                                // back only what the row's other two faces
                                // actually take: the badge and the status are
                                // read from the row's right edge, and the name
                                // fills whatever is left of them. The value
                                // column is bounded now (four short words, and
                                // a count beside it), so a name is cut only
                                // when the row itself is too narrow for it -
                                // which is the one case where the alternative
                                // is worse: a row that cannot say which
                                // service it is has said nothing.
                                readonly property real freeW: Math.max(0, parent.width
                                    - rowStatus.implicitWidth
                                    - (rowActivity.visible
                                        ? rowActivity.implicitWidth + gscale.gap : 0)
                                    - gscale.gap)
                                width: Math.min(implicitWidth, rowName.freeW)
                                elide: Text.ElideRight
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            // How much work the service is holding, riding
                            // with the NAME: "how busy this is" is a property
                            // of the service, not of its status, and putting it
                            // in the value column is what made that column
                            // say three different things. It sits directly
                            // after the label - "SONARR 6", the name's own
                            // badge and not a second value column, which is why
                            // the step between them is the row's TIGHT internal
                            // one and not the column gap - and a service with
                            // nothing queued draws no badge at all, so the name
                            // keeps the whole row. The count is resolved in
                            // OmarrData (`activity`).
                            Text {
                                id: rowActivity
                                textFormat: Text.PlainText
                                visible: boardRow.modelData.activity > 0
                                text: String(boardRow.modelData.activity)
                                color: colors.foreground
                                opacity: colors.textQuiet
                                font.family: colors.uiFont
                                font.pixelSize: gscale.micro
                                anchors.left: rowName.right
                                anchors.leftMargin: Math.round(gscale.tight * 0.5)
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            // The value column: the row's STATUS, and one kind
                            // of datum on every row and in every state - "up",
                            // "down", "paused", or the dash omarr's own
                            // "unknown" resolves to while it has no reading for
                            // the service. Never a count and never a version:
                            // a column with three meanings has none.
                            //
                            // A down service is the one red word on the board,
                            // as before. The dash is drawn in the same quiet ink
                            // as the words, which is this face's ink for "not a
                            // reading" (the network tile's "--" placeholder):
                            // the character says "no value", the ink says
                            // "quiet", and neither of them makes the dash a
                            // status.
                            Text {
                                id: rowStatus
                                textFormat: Text.PlainText
                                text: boardRow.modelData.status
                                color: boardRow.modelData.alert
                                    ? colors.accentRed : colors.foreground
                                opacity: boardRow.modelData.alert ? 1.0 : colors.textQuiet
                                font.family: colors.uiFont
                                font.pixelSize: gscale.micro
                                horizontalAlignment: Text.AlignRight
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Rectangle {
                                visible: boardRow.index < board.rows.length - 1
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 1
                                color: colors.separator
                            }
                        }
                    }
                }

                // "6 services", or "3 of 6 services" when the tile is showing
                // part of the fleet - the storage board's own wording, so a
                // capped list reads the same wherever it appears in this tree.
                Text {
                    id: boardFoot
                    textFormat: Text.PlainText
                    visible: board.rows.length > 0
                    text: board.rows.length < om.serviceCount
                        ? board.rows.length + " of " + om.serviceCount + " services"
                        : om.serviceCount + (om.serviceCount === 1 ? " service" : " services")
                    color: colors.foreground
                    opacity: colors.textQuiet
                    font.family: colors.uiFont
                    font.pixelSize: gscale.micro
                    elide: Text.ElideRight
                    width: board.width
                    anchors.top: boardCol.bottom
                    anchors.left: parent.left
                }
            }
        }
    }
}
