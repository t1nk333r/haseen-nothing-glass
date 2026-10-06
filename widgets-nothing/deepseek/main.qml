import QtQuick
import "../../components"
import "../../components/nothing"

// DeepSeek credit and spend, Nothing style.
//
// The Nothing twin of widgets/deepseek/main.qml: one data source
// (DeepSeekData, which reads the ledger the DeepSpend poller in
// `t1nk33r.agents` already writes on this machine) and no timer of its own -
// the freshness rule, the row list and the wording live in the component, so
// the two drawings cannot disagree about what the account holds.
//
// The accent carries exactly ONE meaning on this face, as on the glass one:
// this balance needs attention - below the threshold the operator armed in
// DeepSpend's own config, or nothing left at all. It marks the badge and
// nothing else. An old reading is NOT red: it is the freshness line, "stale ·
// last read 22:16", which is part of the design rather than a diagnostic,
// because a colour cannot say "this number was taken an hour ago".
//
// The hero is TYPE, not NDotMatrix: the dot-matrix glyph set is digits, ".",
// "-", "%" and ":", so it has no "$" and no "¥" - the same finding
// widgets-nothing/codeburn/main.qml records for its own money hero. The mark
// is drawn beside the figure at the amount's painted edge.
//
// Presets, as everywhere in this tree: 192x192, 400x192, 400x400.
Item {
    id: full
    anchors.fill: parent

    readonly property bool isWide: full.width >= full.height * 1.6
    readonly property bool isBig: !full.isWide && Math.min(full.width, full.height) >= 300

    DeepSeekData {
        id: ds
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

            // Every band below is derived from these, so the same file lays
            // out at 192 and at 400 without a magic number anywhere.
            readonly property real headTop:
                Math.max(header.implicitHeight, verdictBadge.height) + nothing.gap
            readonly property real rowH: nothing.px(22)
            readonly property real splitX: Math.round(body.width * 0.56)
            readonly property bool split: full.isWide && ds.hasBalance
            readonly property real leftW:
                body.split ? Math.max(0, body.splitX - nothing.gap) : body.width

            // The rows come from the component, so the two drawings cannot
            // word one differently. A short tile drops the tail of the list
            // (peak/off-peak, then added) rather than squeezing six rows in.
            //
            // Large: the rows sit along the bottom, under the balance and its
            // footer, so they get what is left once those two have their
            // room. Counting the whole tile below the header handed the rows
            // everything at the larger scales, and the balance was drawn over
            // the footer and the first row.
            readonly property var rows: {
                var cap = full.isBig
                    ? Math.max(1, Math.floor((body.height - body.headTop - hero.height
                        - nothing.gap - footer.height - nothing.gap) / body.rowH))
                    : Math.min(4, Math.max(1, Math.floor((body.height - body.headTop - nothing.gap) / body.rowH)))
                return ds.rows.slice(0, cap)
            }

            // ── Header ────────────────────────────────────────────────
            NLabel {
                id: header
                theme: nothing
                text: "DeepSeek"
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: verdict.left
                anchors.rightMargin: nothing.gap
                elide: Text.ElideRight
            }

            // The component's own verdict, and only when it knows it:
            // "Running low" against the operator's armed threshold, "Stale"
            // when the ledger has stopped advancing. A threshold crossing is
            // louder than an old reading, and this style's short form for a
            // state is the badge - a spelled-out "RUNNING LOW" beside the
            // title is 11 tracked uppercase glyphs competing with it.
            NLabel {
                id: verdict
                theme: nothing
                visible: !ds.alert && ds.verdict !== ""
                text: ds.verdict
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.left: parent.left
                anchors.leftMargin: Math.round(body.width * 0.45)
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }

            NBadge {
                id: verdictBadge
                theme: nothing
                visible: ds.alert
                anchors.top: parent.top
                anchors.right: parent.right
                active: true
                label: ds.alertShort
            }

            // ── Freshness, and where the figure came from ──────────────
            Item {
                id: footer
                visible: ds.hasBalance
                x: 0
                width: body.leftW
                height: visible
                    ? readout.implicitHeight
                        + (source.visible ? nothing.px(4) + source.implicitHeight : 0)
                    : 0
                y: (full.isBig && details.visible)
                    ? Math.max(body.headTop, details.y - nothing.gap - footer.height)
                    : Math.max(body.headTop, body.height - footer.height)

                // "stale · last read 22:16" / "last read 22:16" - the phone
                // card's own line, part of the design: the figure comes out of
                // a file the DeepSpend plugin fills in on its own schedule, and
                // the tile says how old that reading is.
                NMono {
                    id: readout
                    theme: nothing
                    text: ds.footnote
                    color: nothing.onDim
                    font.pixelSize: nothing.fLabel
                    width: parent.width
                    elide: Text.ElideRight
                    anchors.top: parent.top
                }

                // The provenance line, in place of the phone's endpoint: the
                // local source, named. Only the large tile has room for it.
                NText {
                    id: source
                    theme: nothing
                    visible: full.isBig
                    text: ds.sourceLabel
                    color: nothing.onDim
                    opacity: 0.75
                    font.pixelSize: nothing.fMicro
                    width: parent.width
                    elide: Text.ElideRight
                    anchors.top: readout.bottom
                    anchors.topMargin: nothing.px(4)
                }
            }

            // ── The spend breakdown ───────────────────────────────────
            // Wide: a column to the right of the balance. Large: a block along
            // the bottom. Small: gone; the balance and its age are the tile.
            Item {
                id: details
                visible: body.split || (full.isBig && ds.hasBalance)

                x: body.split ? body.splitX + nothing.gap : 0
                width: body.split ? Math.max(0, body.width - details.x) : body.width
                height: body.rows.length * body.rowH
                y: body.split
                    ? Math.max(0, Math.round((body.height - details.height) / 2))
                    : Math.max(0, body.height - details.height)

                Column {
                    width: parent.width

                    Repeater {
                        model: body.rows

                        Item {
                            id: row
                            required property var modelData
                            required property int index

                            width: details.width
                            height: body.rowH

                            NLabel {
                                theme: nothing
                                text: row.modelData.k
                                font.pixelSize: nothing.fMicro
                                anchors.left: parent.left
                                anchors.right: rowValue.left
                                anchors.rightMargin: nothing.gap
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                            }

                            NMono {
                                id: rowValue
                                theme: nothing
                                text: row.modelData.v
                                font.pixelSize: nothing.fLabel
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            NDivider {
                                theme: nothing
                                visible: row.index < body.rows.length - 1
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                            }
                        }
                    }
                }
            }

            NDivider {
                theme: nothing
                vertical: true
                visible: body.split
                x: body.splitX
                y: body.headTop
                height: Math.max(0, body.height - body.headTop)
            }

            // ── Stage: the balance, or the reason there is none ────────
            Item {
                id: stage
                x: 0
                y: body.headTop
                width: body.leftW
                height: Math.max(0, footer.y - nothing.gap - stage.y)

                // ── With a number ─────────────────────────────────────
                Item {
                    id: hero
                    visible: ds.hasBalance
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: amount.implicitHeight

                    NText {
                        id: amount
                        theme: nothing
                        text: ds.amountLabel
                        color: ds.alert ? nothing.red : nothing.on
                        font.family: nothing.sansBold
                        // A four-figure balance shrinks to fit rather than
                        // pushing the card out of shape.
                        font.pixelSize: full.isBig
                            ? nothing.px(44) : (full.isWide ? nothing.px(40) : nothing.px(34))
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: nothing.px(14)
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // The currency mark, smaller so it names the figure
                    // without competing with it - anchored to the amount's
                    // PAINTED edge, since the amount is centred inside a fit
                    // box as wide as the stage (widgets-nothing/codeburn
                    // learned this the hard way; see its hero comment).
                    NText {
                        id: mark
                        theme: nothing
                        visible: ds.symbol !== ""
                        text: ds.symbol
                        color: nothing.onDim
                        font.family: nothing.sansBold
                        font.pixelSize: Math.round(amount.font.pixelSize * 0.46)
                        anchors.right: amount.left
                        anchors.rightMargin: nothing.px(3)
                            - Math.round((amount.width - amount.contentWidth) / 2)
                        anchors.baseline: amount.baseline
                    }
                }

                // ── Without one ───────────────────────────────────────
                // One red line and the reason, on every preset: a card that
                // shows nothing says why, and it never draws a figure it does
                // not have.
                Column {
                    id: notice
                    visible: !ds.hasBalance
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: nothing.px(6)

                    NText {
                        id: noticeHeadline
                        theme: nothing
                        text: ds.noticeHeadline
                        color: nothing.red
                        font.family: nothing.sansBold
                        font.pixelSize: nothing.fBody
                        width: notice.width
                        elide: Text.ElideRight
                    }

                    NText {
                        id: noticeDetail
                        theme: nothing
                        visible: text !== ""
                        text: ds.noticeDetail
                        color: nothing.onDim
                        font.pixelSize: nothing.fMicro
                        width: notice.width
                        wrapMode: Text.WordWrap
                        maximumLineCount: full.isBig ? 3 : 2
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
