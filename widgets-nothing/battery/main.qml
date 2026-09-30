import QtQuick
import "../../components"
import "../../components/nothing"

// Battery, Nothing style.
//
// One data source (BatteryData, the same push-based UPower client a future
// Liquid Glass battery would read) and no timer of its own: UPower pushes.
//
// The accent carries exactly ONE meaning on this face: LOW CHARGE (<= 20%).
// Charging is loud type, not red - two meanings on one colour is how a
// status widget stops being readable at a glance.
Item {
    id: full
    anchors.fill: parent

    // The three grid presets: 192x192, 400x192, 400x400.
    readonly property bool isWide: full.width >= full.height * 1.6
    readonly property bool isBig: !full.isWide && Math.min(full.width, full.height) >= 300

    BatteryData { id: bat }

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

    // The side/bottom readout. Health is a large-tile row only: at 400x192
    // the two live numbers (time and draw) are worth more than a constant.
    readonly property var details: {
        if (!bat.present)
            return [{ k: "Source", v: "AC MAINS" }, { k: "Battery", v: "NONE" }]
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

            // Every band below is derived from these two, so the same file
            // lays out at 192 and at 400 without a magic number anywhere.
            readonly property real headTop: Math.max(header.implicitHeight, nothing.px(18)) + nothing.gap
            readonly property real rowH: nothing.px(22)
            readonly property real splitX: Math.round(body.width * 0.56)

            // ── Header ────────────────────────────────────────────────
            NLabel {
                id: header
                theme: nothing
                text: "Battery"
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: badge.visible ? badge.left : parent.right
                anchors.rightMargin: badge.visible ? nothing.gap : 0
                elide: Text.ElideRight
            }

            NBadge {
                id: badge
                theme: nothing
                anchors.verticalCenter: header.verticalCenter
                anchors.right: parent.right
                visible: bat.present && (full.low || bat.charging)
                active: full.low
                label: full.low ? "Low" : "Chg"
            }

            // ── Detail readout ────────────────────────────────────────
            // Wide: a column to the right of the hero. Large: a block along
            // the bottom. Small: gone, the tile shows the number only.
            NDivider {
                theme: nothing
                vertical: true
                visible: full.isWide
                x: body.splitX
                y: body.headTop
                height: Math.max(0, body.height - body.headTop)
            }

            Item {
                id: details
                visible: full.isWide || full.isBig

                readonly property int cap: full.isWide
                    ? Math.max(1, Math.floor((body.height - body.headTop) / body.rowH))
                    : 4
                readonly property var rows: full.details.slice(0, details.cap)

                x: full.isWide ? body.splitX + nothing.gap : 0
                width: full.isWide ? Math.max(0, body.width - details.x) : body.width
                height: details.rows.length * body.rowH
                y: full.isWide ? body.headTop : Math.max(0, body.height - details.height)

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

                            NLabel {
                                theme: nothing
                                text: row.modelData.k
                                font.pixelSize: nothing.fMicro
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            NMono {
                                theme: nothing
                                text: row.modelData.v
                                font.pixelSize: nothing.fLabel
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            NDivider {
                                theme: nothing
                                visible: row.index < details.rows.length - 1
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                            }
                        }
                    }
                }
            }

            // ── Footer: state, estimate, level ────────────────────────
            Item {
                id: footer
                x: 0
                width: full.isWide ? Math.max(0, body.splitX - nothing.gap) : body.width
                height: stateLine.implicitHeight + nothing.px(6) + nothing.px(5)
                y: (full.isBig && details.visible)
                    ? Math.max(0, details.y - nothing.gap - footer.height)
                    : Math.max(0, body.height - footer.height)

                NLabel {
                    id: stateLine
                    theme: nothing
                    text: bat.present ? bat.stateLabel : "AC power"
                    loud: bat.present && bat.charging
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: footMono.left
                    anchors.rightMargin: nothing.gap
                    elide: Text.ElideRight
                }

                NMono {
                    id: footMono
                    theme: nothing
                    text: bat.present
                        ? (bat.timeLabel !== ""
                            ? bat.timeLabel
                            : (full.rateText !== "" ? full.rateText : Math.round(bat.percent) + "%"))
                        : "MAINS"
                    color: nothing.onDim
                    font.pixelSize: nothing.fLabel
                    anchors.top: parent.top
                    anchors.right: parent.right
                }

                NProgress {
                    theme: nothing
                    visible: bat.present
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: nothing.px(5)
                    segments: (full.isWide || full.isBig) ? 20 : 10
                    value: bat.percent / 100
                    accent: full.low
                }

                // A meter at zero would read as a fault; on a desk machine
                // there is no level to show, so the band is just a rule.
                NDivider {
                    theme: nothing
                    visible: !bat.present
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                }
            }

            // ── Hero ──────────────────────────────────────────────────
            Item {
                id: stage
                x: 0
                y: body.headTop
                width: full.isWide ? Math.max(0, body.splitX - nothing.gap) : body.width
                height: Math.max(0, footer.y - nothing.gap - stage.y)

                Column {
                    anchors.centerIn: parent
                    width: stage.width
                    spacing: nothing.gap

                    NDotMatrix {
                        id: hero
                        theme: nothing
                        anchors.horizontalCenter: parent.horizontalCenter
                        // The unit sign only earns its dots on the large tile.
                        text: full.pctText + ((full.isBig && bat.present) ? "%" : "")
                        onColor: bat.present
                            ? (full.low ? nothing.red : nothing.on)
                            : nothing.onDim
                        // Dots are sized from the stage, never fixed: this is
                        // the same glyph at 192 and at 400.
                        dot: {
                            var cols = hero.colCount > 0 ? hero.colCount : 11
                            var budget = stage.height * (bat.present ? 1 : 0.62)
                            var byW = stage.width / (cols + 0.34 * (cols - 1))
                            var byH = budget / (7 + 0.34 * 6)
                            var d = Math.max(2, Math.min(byW, byH) * 0.92)
                            // The "--" placeholder is not a hero number: it is
                            // capped so the no-battery state reads as a dash,
                            // not as eleven blobs filling the card.
                            return bat.present ? d : Math.min(d, nothing.px(8))
                        }
                        gap: Math.max(1, hero.dot * 0.34)
                    }

                    // The state this desktop will actually show. Named, not
                    // blank - "--" alone would look like a stalled reading.
                    NLabel {
                        theme: nothing
                        visible: !bat.present
                        loud: true
                        text: "No battery"
                        width: stage.width
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }
}
