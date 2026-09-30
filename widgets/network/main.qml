import QtQuick
import "../../components"

// Network link, Liquid Glass.
//
// components/NetworkData.qml is the only source: it is a read-only client of
// NetworkManager through Quickshell.Networking - no bus name is claimed and
// no scan is started (starting a Wi-Fi scan is a side effect on a shared
// radio). NetworkManager pushes the link facts; the two figures it cannot
// push - the traffic rate and the latency - are the ones NetworkData
// measures itself, and it measures them on demand rather than on a poller:
// the rate from two /proc/net/dev samples while this tile is visible, the
// latency from a single ICMP echo when the tile wakes, when the link changes,
// or when the readout is clicked. Nothing in this file can change the link:
// the tile is a readout with one control, and that control only asks for a
// fresh measurement.
//
// The accent carries exactly ONE meaning: OFFLINE. accentRed appears in the
// header word, the status dot and the "No link" badge - three spellings of
// one fact - and nowhere else; a weak-but-live link is dim bars, never a red
// alarm. Every other colour is a MacOSColors token (foreground, textQuiet,
// cardBackground, separator), never a literal.
//
// Three layouts, one per grid preset (WidgetRegistry.sizes). The hero is
// always the connection, named - the SSID, "Ethernet", or NetworkData's own
// sentence ("Not connected", "Wi-Fi off", "No <interface>") - never the
// address: an IP answers a question nobody asked of a tile. Where there is
// room, the address is one fact row among several.
//   192x192   kind + status dot, the name, the signal meter (four ascending
//             bars and the percentage), the traffic readout above the footer,
//             and a footer line with the address and, for a wired link, the
//             negotiated rate.
//   400x192   the same on the left; the facts (address, interface, security
//             or link rate, internet) as rows on the right.
//   400x400   name and signal meter as the hero, a twenty-segment signal
//             track under them (a hairline rule instead when offline, never a
//             bar sitting at zero), the traffic readout, and the facts as
//             rows at the bottom.
//
// Facts first, layout second: the facts below are the Nothing drawing's
// facts, in its order and with its precedence
// (widgets-nothing/network/main.qml carries the same set), so a new figure in
// NetworkData belongs on both.
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

    NetworkData {
        id: net
        // Empty = follow the live link and show what the connection is
        // called, never which interface it runs over. Naming one here pins
        // the widget to that interface AND is what makes the interface name
        // itself worth putting on screen.
        preferred: plugin.settings.networkInterface
        // A hidden tile costs nothing: no /proc/net/dev sample is taken and
        // no ping is left running while the screen is off (see NetworkData's
        // `active`). Qt propagates the host's `visible` down to this item,
        // which is what makes the gate tell the truth.
        active: full.visible
    }

    // One type and margin scale for every glass tile - see
    // components/GlassScale.qml. The id is `gscale` and not `scale` on
    // purpose: `scale` is Item's own transform property, and inside a
    // Repeater delegate an unqualified outer id loses to it - the fact rows
    // below would then silently fall back to the default pixel size.
    GlassScale {
        id: gscale
        tileWidth: full.width
        tileHeight: full.height
    }

    readonly property bool isWide: gscale.isWide
    readonly property bool isBig: gscale.isBig
    readonly property bool offline: !net.connected

    // The Nothing drawing's facts, unchanged in content and order.
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

    Item {
        id: content
        anchors.fill: parent
        anchors.margins: gscale.pad

        // The hero column: the whole tile on the square presets, the left
        // 46% when wide - the split the tailscale tile uses, so two 400x192
        // System tiles on one desktop read as one grid.
        readonly property real heroWidth: full.isWide ? Math.round(width * 0.46) : width

        // How far the hero reaches down. The facts (400x400) start below
        // this and are anchored to the bottom, so they never crowd it.
        readonly property real topUsed: header.height + Math.round(gscale.label * 0.35)
            + heroName.height + Math.round(gscale.label * 0.3) + meter.height
            + (full.isBig ? Math.round(gscale.label * 0.6) + track.height : 0)

        // ── Header: the kind of link, the status dot, the offline badge ───
        Row {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            spacing: Math.round(gscale.label * 0.5)

            Text {
                text: net.kind
                color: full.offline ? colors.accentRed : colors.foreground
                opacity: full.offline ? 1.0 : 0.6
                font.family: colors.uiFont
                font.pixelSize: gscale.label
                font.letterSpacing: gscale.label * 0.12
            }

            // The dot says the same thing the word does - which is why it is
            // ink when there is a link and accentRed only when there is not.
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(gscale.label * 0.62)
                height: width
                radius: width / 2
                color: full.offline ? colors.accentRed : colors.foreground
                opacity: full.offline ? 1.0 : colors.textQuiet
            }
        }

        Text {
            id: noLink
            visible: full.offline
            anchors.right: parent.right
            anchors.verticalCenter: header.verticalCenter
            // "No link", the Nothing badge's own words. No chip is drawn
            // around it: the offline header word and this label are the same
            // sentence, and one of them in accentRed is enough.
            text: "No link"
            color: colors.accentRed
            font.family: colors.uiFont
            font.pixelSize: gscale.micro
        }

        // ── Hero: the connection, named ──────────────────────────────────
        Text {
            id: heroName
            anchors.top: header.bottom
            anchors.topMargin: Math.round(gscale.label * 0.35)
            anchors.left: parent.left
            width: content.heroWidth
            text: net.name
            color: colors.foreground
            // Offline keeps the sentence readable without shouting it: the
            // accentRed header is doing the shouting.
            opacity: full.offline ? colors.textQuiet : 1.0
            font.family: colors.uiFont
            font.pixelSize: Math.round(gscale.minSide * (full.isBig ? 0.14 : (full.isWide ? 0.20 : 0.22)))
            // A 30-character SSID must shrink, then elide - it may never push
            // the tile out of shape.
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: Math.max(9, Math.round(gscale.label * 0.8))
            elide: Text.ElideRight
        }

        // ── Signal: four ascending bars, then the number ─────────────────
        Item {
            id: meter
            anchors.top: heroName.bottom
            anchors.topMargin: Math.round(gscale.label * 0.3)
            anchors.left: parent.left
            width: content.heroWidth
            height: Math.max(bars.height, pct.implicitHeight)

            Item {
                id: bars
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter

                readonly property real bw: Math.max(2, Math.round(gscale.label * 0.34))
                readonly property real bgap: Math.max(1, Math.round(bars.bw * 0.6))

                width: 4 * bars.bw + 3 * bars.bgap
                height: Math.round(gscale.label * (full.isBig ? 1.35 : 1.25))

                Repeater {
                    model: 4

                    Rectangle {
                        required property int index

                        width: bars.bw
                        // Ascending, so the shape reads even with every bar
                        // unlit - an offline meter still looks like a meter,
                        // not like a missing element.
                        height: bars.height * (0.4 + 0.2 * index)
                        x: index * (bars.bw + bars.bgap)
                        y: bars.height - height
                        radius: width / 2
                        color: colors.foreground
                        opacity: index < net.bars ? 0.95 : 0.18

                        Behavior on opacity { NumberAnimation { duration: 180 } }
                    }
                }
            }

            Text {
                id: pct
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: bars.right
                anchors.leftMargin: Math.round(gscale.label * 0.7)
                text: net.connected ? net.signal + "%" : "--"
                color: colors.foreground
                opacity: net.connected ? 1.0 : colors.textQuiet
                font.family: colors.uiFont
                font.pixelSize: full.isBig ? Math.round(gscale.label * 1.3) : gscale.body
            }
        }

        // ── Signal track (400x400): the quality as a segmented rule ───────
        Item {
            id: track
            visible: full.isBig
            anchors.top: meter.bottom
            anchors.topMargin: Math.round(gscale.label * 0.6)
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.round(gscale.tight)

            Row {
                id: segments
                visible: net.connected
                anchors.fill: parent
                spacing: Math.round(gscale.tight * 0.6)

                Repeater {
                    model: 20

                    Rectangle {
                        required property int index

                        readonly property real w: Math.max(1,
                            Math.floor((segments.width - 19 * segments.spacing) / 20))

                        width: segments.width >= 20 ? w : 0
                        height: segments.height
                        radius: height / 2
                        color: colors.foreground
                        opacity: (index + 1) <= Math.round(net.signal / 100 * 20) ? 0.9 : 0.15
                    }
                }
            }

            // Offline: a rule, not a bar sitting at zero.
            Rectangle {
                visible: !net.connected
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 1
                color: colors.separator
            }
        }

        // ── Traffic: what the link carries now, and its latency ──────────
        //
        // The only figure on this tile measured over an interval, and so the
        // only one that can start blank: "--" until NetworkData's second
        // sample lands, never a "0 B/s" that would read as an idle link when
        // it only means "not known yet".
        //
        // One line, three numbers: bytes in, bytes out, and the round trip.
        // The narrow column (small and medium) gets the compact unit form,
        // measured rather than guessed: at 12 px in the system face the
        // spelled-out pair is 82 + 9 + 74 = 165 px against a 160 px column,
        // so it does not fit, while "11.4M/s / 279k/s" is 67 + 9 + 59 = 135
        // and leaves the round trip its slot whenever the face leaves room
        // for one. The large preset has the room for the words.
        //
        // A tap anywhere on the readout asks NetworkData for one fresh
        // latency echo. It is the only control this read-only tile has, and
        // it is deliberately not a timer - NetworkData's latency section
        // states the trigger and what that choice costs.
        Item {
            id: traffic

            readonly property real fs: full.isBig ? Math.round(gscale.micro * 0.8) : gscale.micro
            readonly property real lineH: Math.max(rateRow.implicitHeight, latencyText.implicitHeight)

            // What the hero leaves free. On the large preset the facts own
            // the bottom, so the band ends where they begin; on the two
            // narrow ones it ends at the footer - or at the box, when there
            // is no footer to stop at.
            readonly property real bandBottom: full.isBig
                ? facts.y
                : (footer.visible ? footer.y : content.height)
            readonly property real margin: 2

            // One line only, and dropped rather than drawn over the meter
            // when even that does not fit (the large preset has 24 px of
            // band, the 160x120 minimum 23, the system-font small tile 21).
            visible: net.connected
                && traffic.lineH + traffic.margin <= traffic.bandBottom - content.topUsed

            x: 0
            width: content.heroWidth
            height: traffic.lineH
            y: Math.max(content.topUsed, traffic.bandBottom - traffic.margin - traffic.lineH)

            Row {
                id: rateRow
                anchors.left: parent.left
                anchors.top: parent.top
                spacing: Math.round(gscale.label * 0.7)

                Text {
                    id: rxText
                    text: "↓ " + (full.isBig ? net.rxLabel : net.rxShort)
                    color: colors.foreground
                    opacity: 0.85
                    font.family: colors.uiFont
                    font.pixelSize: traffic.fs
                }

                Text {
                    id: txText
                    text: "↑ " + (full.isBig ? net.txLabel : net.txShort)
                    color: colors.foreground
                    opacity: 0.85
                    font.family: colors.uiFont
                    font.pixelSize: traffic.fs
                }
            }

            Text {
                id: latencyText
                text: net.latencyLabel
                // The one figure here that can go stale, so the one that
                // admits it: it sits at the quiet floor, and the pointer over
                // the readout - the tap that re-measures it - lifts it to
                // full.
                color: colors.foreground
                opacity: trafficHover.containsMouse ? 1.0 : colors.textQuiet
                font.family: colors.uiFont
                font.pixelSize: traffic.fs
                x: Math.max(0, parent.width - width)
                y: 0
                // Measured, never estimated: the round trip is drawn only
                // when the two rates' own painted width leaves room for it on
                // the line. In system-font mode on the 192 px tile it does
                // not, and the rates - the figures the tile is asked for -
                // keep the line to themselves.
                visible: latencyText.x >= rateRow.width + Math.round(gscale.label * 0.5)

                Behavior on opacity { NumberAnimation { duration: 140 } }
            }

            MouseArea {
                id: trafficHover
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: net.pingNow()
            }
        }

        // ── Footer (192x192): the address, and the wired link rate ───────
        Item {
            id: footer
            visible: !full.isWide && !full.isBig
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.max(addr.implicitHeight, rate.implicitHeight)

            Text {
                id: addr
                anchors.left: parent.left
                anchors.right: rate.visible ? rate.left : parent.right
                anchors.rightMargin: rate.visible ? Math.round(gscale.label * 0.6) : 0
                anchors.verticalCenter: parent.verticalCenter
                text: net.connected ? net.address : ""
                color: colors.foreground
                opacity: colors.textQuiet
                font.family: colors.uiFont
                font.pixelSize: gscale.micro
                elide: Text.ElideRight
                // Every octet is load-bearing and the dot-separators give
                // nothing to cut around: in system-font mode the address
                // measures 104.1 px in the 92.5 the rate leaves it, so the
                // last octet went missing. Shrink into the box before
                // eliding, as the fact rows below do.
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: Math.max(8, Math.round(gscale.micro * 0.85))
            }

            // On the square tiles there is no fact column to carry it.
            Text {
                id: rate
                visible: net.connected && !net.isWifi && net.linkSpeed > 0
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: net.linkSpeed + " Mb/s"
                color: colors.foreground
                opacity: colors.textQuiet
                font.family: colors.uiFont
                font.pixelSize: gscale.micro
            }
        }

        // ── Facts: a right-hand column when wide, a block when large ─────
        Item {
            id: facts
            visible: full.isWide || full.isBig

            // x/y/width/height are computed, never anchored: a layout switch
            // cannot release an anchor, and `x ? a : undefined` leaves the
            // last real anchor in place when the condition flips back.
            readonly property real rowH: Math.round(gscale.label * 1.45)
            readonly property int cap: {
                var avail = full.isWide
                    ? content.height
                    : content.height - content.topUsed - Math.round(gscale.label * 0.6)
                if (avail <= 0) return full.isWide ? 1 : 0
                return Math.max(1, Math.floor((avail + gscale.gap) / (facts.rowH + gscale.gap)))
            }
            readonly property var rows: full.details.slice(0, facts.cap)

            x: full.isWide ? content.heroWidth + Math.round(gscale.label * 0.8) : 0
            width: full.isWide ? Math.max(0, content.width - facts.x) : content.width
            height: facts.rows.length * facts.rowH + Math.max(0, facts.rows.length - 1) * gscale.gap
            y: full.isWide
                ? Math.max(0, Math.round((content.height - facts.height) / 2))
                : Math.max(0, content.height - facts.height)

            Column {
                id: rowsColumn
                width: parent.width
                spacing: gscale.gap

                Repeater {
                    model: facts.rows

                    delegate: Item {
                        required property var modelData

                        width: rowsColumn.width
                        height: facts.rowH

                        Rectangle {
                            anchors.fill: parent
                            radius: Math.max(2, Math.round(height * 0.25))
                            color: colors.cardBackground
                            opacity: colors.cardBackgroundOpacity
                        }

                        Text {
                            id: rowLabel
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: Math.round(gscale.label * 0.35)
                            text: modelData.k
                            color: colors.foreground
                            opacity: 0.6
                            font.family: colors.uiFont
                            font.pixelSize: gscale.micro
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            anchors.rightMargin: Math.round(gscale.label * 0.35)
                            anchors.left: rowLabel.right
                            anchors.leftMargin: Math.round(gscale.label * 0.4)
                            horizontalAlignment: Text.AlignRight
                            // An IPv4 address is the whole point of the row;
                            // it shrinks to fit before any digit is cut, and
                            // only then elides.
                            text: modelData.v
                            color: colors.foreground
                            font.family: colors.uiFont
                            font.pixelSize: gscale.body
                            elide: Text.ElideRight
                            fontSizeMode: Text.HorizontalFit
                            minimumPixelSize: Math.max(8, Math.round(gscale.micro * 0.85))
                        }
                    }
                }
            }
        }
    }
}
