import QtQuick
import "../../components"
import "../../components/nothing"

// Network link, Nothing style.
//
// Strictly read-only: NetworkData is a client of NetworkManager and this
// face never asks it to scan, enable a radio or change a connection. The
// link facts arrive pushed, but the two figures it cannot push - the traffic
// rate and the latency - are measured by NetworkData on demand: the rate
// from two /proc/net/dev samples while this tile is visible, the latency
// from one ICMP echo when the tile wakes, when the link changes, or when the
// readout is tapped. The tap is the only control this face has, and it only
// asks for a fresh measurement.
//
// The accent carries exactly ONE meaning: OFFLINE. A weak-but-live link is
// dim dots, not a red alarm.
Item {
    id: full
    anchors.fill: parent

    // The three grid presets: 192x192, 400x192, 400x400.
    readonly property bool isWide: full.width >= full.height * 1.6
    readonly property bool isBig: !full.isWide && Math.min(full.width, full.height) >= 300

    NetworkData {
        id: net
        // Empty = follow the live link and show what the connection is
        // called, never which interface it runs over. Naming one here pins
        // the widget to that interface AND is what makes the interface name
        // itself worth putting on screen.
        preferred: plugin.settings.networkInterface
        // A hidden tile costs nothing: no /proc/net/dev sample is taken and
        // no ping survives the screen going off (see NetworkData's `active`).
        active: full.visible
    }

    readonly property bool offline: !net.connected

    readonly property var details: {
        if (full.offline)
            return [
                { k: "Wi-Fi radio", v: net.wifiEnabled ? "ON" : "OFF" },
                { k: "Address", v: "-" },
                { k: "Internet", v: "NONE" }
            ]
        var rows = []
        rows.push({ k: net.ipv4 !== "" ? "IPv4" : "Address", v: net.address !== "" ? net.address : "-" })
        if (net.preferred.trim() !== "" && net.interfaceName !== "")
            rows.push({ k: "Interface", v: net.interfaceName })
        if (net.isWifi)
            rows.push({ k: "Security", v: net.security !== "" ? net.security : "OPEN" })
        else
            rows.push({ k: "Link", v: net.linkSpeed > 0 ? net.linkSpeed + " Mb/s" : "-" })
        rows.push({ k: "Internet", v: net.connectivityKnown
            ? (net.online ? "REACHABLE" : "NO ROUTE")
            : "UNCHECKED" })
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

            readonly property real headTop: Math.max(header.implicitHeight, nothing.px(18)) + nothing.gap
            readonly property real rowH: nothing.px(22)
            readonly property real splitX: Math.round(body.width * 0.56)

            // ── Header: the kind of link, as the label line ────────────
            NLabel {
                id: header
                theme: nothing
                text: net.kind
                loud: full.offline
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
                visible: full.offline
                active: true
                label: "No link"
            }

            // ── Detail readout: side column when wide, bottom when large ─
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
                                // An IPv4 address is the whole point of the
                                // row; shrink it to fit before cutting digits
                                // off it, and only elide once even that fails.
                                fontSizeMode: Text.HorizontalFit
                                minimumPixelSize: Math.max(7, nothing.fMicro - 1)
                                anchors.left: parent.horizontalCenter
                                anchors.right: parent.right
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideLeft
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

            // ── Footer: four ascending bars, then the number ───────────
            Item {
                id: footer

                readonly property real barH: nothing.px(full.isBig ? 24 : 16)
                // The traffic readout is the footer's kind of figure - a live
                // measurement - so it rides a second line under the bars on
                // every preset, and the footer grows by exactly the line it
                // takes. The percentage keeps its place beside the bars and
                // the wired link rate keeps the right of that first line.
                readonly property real trafficH: trafficRow.visible
                    ? nothing.px(5) + trafficRow.implicitHeight : 0

                x: 0
                width: full.isWide ? Math.max(0, body.splitX - nothing.gap) : body.width
                height: footer.barH + footer.trafficH
                    + (full.isBig ? nothing.px(6) + nothing.px(5) : 0)
                y: (full.isBig && details.visible)
                    ? Math.max(0, details.y - nothing.gap - footer.height)
                    : Math.max(0, body.height - footer.height)

                Item {
                    id: bars

                    readonly property real bw: nothing.px(5)
                    readonly property real bg: nothing.px(3)

                    width: 4 * bars.bw + 3 * bars.bg
                    height: footer.barH
                    anchors.left: parent.left
                    anchors.top: parent.top

                    Repeater {
                        model: 4

                        Rectangle {
                            required property int index

                            width: bars.bw
                            // Ascending, so the shape reads even with every
                            // bar unlit - an offline meter still looks like
                            // a meter, not like a missing element.
                            height: bars.height * (0.4 + 0.2 * index)
                            x: index * (bars.bw + bars.bg)
                            y: bars.height - height
                            radius: nothing.rDot
                            color: index < net.bars ? nothing.on : nothing.onFaint

                            Behavior on color { ColorAnimation { duration: nothing.fast } }
                        }
                    }
                }

                NMono {
                    id: pct
                    theme: nothing
                    text: net.connected ? net.signal + "%" : "--"
                    color: net.connected ? nothing.on : nothing.onDim
                    font.pixelSize: full.isBig ? nothing.fTitle : nothing.fBody
                    anchors.left: bars.right
                    anchors.leftMargin: nothing.gap
                    anchors.bottom: bars.bottom
                }

                // The wired link rate. On the small tile there is no detail
                // column to carry it, so it rides here instead.
                NMono {
                    theme: nothing
                    visible: !full.isWide && !full.isBig && net.connected
                             && !net.isWifi && net.linkSpeed > 0
                    text: net.linkSpeed + "Mb/s"
                    color: nothing.onDim
                    font.pixelSize: nothing.fMicro
                    anchors.right: parent.right
                    anchors.bottom: bars.bottom
                }

                // ── Traffic, on the footer's second line ───────────────
                // Bytes per second in and out over the link this card shows,
                // with the latency beside them. NetworkData has no rate to
                // report until its second /proc/net/dev sample lands, and it
                // says so with "--" rather than a "0" that would read as an
                // idle link.
                Row {
                    id: trafficRow
                    visible: net.connected
                    anchors.left: parent.left
                    anchors.top: bars.bottom
                    anchors.topMargin: nothing.px(5)
                    spacing: nothing.gap

                    NMono {
                        id: rxRate
                        theme: nothing
                        text: "↓ " + net.rxShort
                        color: nothing.onDim
                        font.pixelSize: nothing.fLabel
                    }

                    NMono {
                        id: txRate
                        theme: nothing
                        text: "↑ " + net.txShort
                        color: nothing.onDim
                        font.pixelSize: nothing.fLabel
                    }
                }

                NMono {
                    id: latency
                    theme: nothing
                    visible: trafficRow.visible
                        // Measured, not estimated: the round trip is drawn
                        // only when the two rates' own width leaves room for
                        // it. On the narrow footer a 4-digit round trip would
                        // otherwise land on top of the out rate.
                        && latency.x >= trafficRow.width + nothing.gap
                    text: net.latencyLabel
                    // The one figure here that can go stale, so the one that
                    // admits it: it sits at the dim ink and lifts to full
                    // while the pointer is over the readout that re-measures
                    // it.
                    color: trafficHover.containsMouse ? nothing.on : nothing.onDim
                    font.pixelSize: nothing.fLabel
                    x: Math.max(0, footer.width - width)
                    y: trafficRow.y

                    Behavior on color { ColorAnimation { duration: nothing.fast } }
                }

                // The whole readout is the control: a 9 px "12 ms" is not a
                // target worth aiming at, and a tap anywhere on the line is
                // the same request for one fresh echo.
                MouseArea {
                    id: trafficHover
                    x: 0
                    y: trafficRow.y
                    width: footer.width
                    height: trafficRow.visible ? trafficRow.height : 0
                    acceptedButtons: Qt.LeftButton
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: net.pingNow()
                }

                NProgress {
                    theme: nothing
                    visible: full.isBig && net.connected
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: nothing.px(5)
                    segments: 20
                    value: net.signal / 100
                }

                // Offline: a rule, not a bar sitting at zero.
                NDivider {
                    theme: nothing
                    visible: full.isBig && !net.connected
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                }
            }

            // ── Hero: the connection, named ───────────────────────────
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

                    // The SSID, or the interface for a wired link, or
                    // NetworkData's own "Not connected" / "Wi-Fi off" -
                    // which is a sentence, not an empty tile.
                    NText {
                        id: heroName
                        theme: nothing
                        text: net.name
                        color: full.offline ? nothing.onDim : nothing.on
                        font.family: nothing.sansBold
                        font.pixelSize: full.isBig ? nothing.px(30)
                            : (full.isWide ? nothing.px(26) : nothing.px(20))
                        // A 30-character SSID must shrink, then elide - it
                        // may never push the card out of shape.
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: nothing.px(11)
                        elide: Text.ElideRight
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // Link quality as dots. Hidden only when the stage is
                    // too short for it to be legible.
                    Item {
                        width: parent.width
                        height: sig.implicitHeight
                        visible: stage.height >= nothing.px(88)

                        NDotMatrix {
                            id: sig
                            theme: nothing
                            anchors.centerIn: parent
                            text: net.connected ? String(net.signal) : "--"
                            onColor: net.connected ? nothing.on : nothing.onDim
                            dot: {
                                var cols = sig.colCount > 0 ? sig.colCount : 11
                                var budget = stage.height * 0.62
                                var byW = stage.width / (cols + 0.34 * (cols - 1))
                                var byH = budget / (7 + 0.34 * 6)
                                var d = Math.max(2, Math.min(byW, byH) * 0.92)
                                // "--" is a placeholder, not a reading: capped
                                // so an offline tile shows a dash rather than
                                // two rows of blobs.
                                return net.connected ? d : Math.min(d, nothing.px(8))
                            }
                            gap: Math.max(1, sig.dot * 0.34)
                        }
                    }
                }
            }
        }
    }
}
