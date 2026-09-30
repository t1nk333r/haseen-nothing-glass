import QtQuick
import "../../components"
import "../../components/nothing"

// The tailnet, Nothing style.
//
// Strictly read-only. TailscaleData polls the `tailscale` CLI (status,
// serve, derp-map); this file never asks it to change anything - no
// `up`/`down`, no exit-node switch, no login. A widget that can drop your
// network from a mis-click is not a widget.
//
// Nothing else is shown either: hostnames, MagicDNS names, tailnet
// addresses, OS names and DERP region names only. No node keys, no login
// emails - those exist in the status payload and deliberately never reach
// this file's bindings.
//
// `active` follows `visible`, so a tile on another workspace stops the poll
// entirely (see TailscaleData's header). The one timer
// in this file is the node web's settle, and it runs only while a released
// node is on its way home - see the interaction block there. At rest this
// tile has no timer running and repaints nothing.
//
// The accent carries exactly TWO meanings on its own, and never at once in
// the normal case: the state dot is red when the tailnet is NOT up, and a
// service dot is red when that service is on the public internet through
// Funnel. An idle-but-connected tailnet - which is what a tailnet nobody is
// talking to looks like all day - is not a fault and gets no red anywhere.
// The third red is the user's own and exists only while they make it: a
// pinned node in the web, which is a state you can only see because you
// just created it.
Item {
    id: full
    anchors.fill: parent

    // The three grid presets: 192x192 (small), 400x192 (wide), 400x400 (big).
    readonly property bool isWide: full.width >= full.height * 1.6
    readonly property bool isBig: !full.isWide && Math.min(full.width, full.height) >= 300
    readonly property bool isSmall: !full.isWide && !full.isBig

    TailscaleData {
        id: ts
        // An off-screen tile costs nothing - see the component's header.
        active: full.visible
    }

    // Everything the numeric faces need: a reachable backend, a running
    // tailnet, and an address on it. Anything else is a named state below,
    // never a blank card.
    readonly property bool ready: ts.loaded && ts.errorMessage === ""
        && ts.up && ts.selfIp !== ""

    // Why the tile is not showing numbers, in the widget's own words. The
    // header already carries tailscaled's state word; this line says what
    // that state means for this machine.
    readonly property string detailLine: {
        if (!ts.loaded) return "Reading tailscaled"
        if (ts.errorMessage !== "") return ts.errorMessage
        switch (ts.backendState) {
            case "Stopped": return "Tailscale is stopped"
            case "NeedsLogin": return "This machine is not logged in"
            case "Starting": return "Backend starting"
            case "NoState": return "No tailnet configured"
        }
        if (ts.up) return "No tailnet address yet"
        return ts.backendState === "" ? "No status from tailscaled" : ts.backendState
    }

    // "Direct · Riyadh": how this machine's traffic is carried right now,
    // and the DERP region it calls home. "Idle" is the honest word for a
    // tailnet with no live session - it is not "Relay" and not an error.
    readonly property string pathText: ts.pathLabel
        + (ts.homeRelayName !== "" ? " · " + ts.homeRelayName : "")

    readonly property string whoText: {
        var parts = []
        if (ts.selfName !== "") parts.push(ts.selfName)
        if (ts.selfOs !== "") parts.push(ts.selfOs)
        return parts.join(" · ")
    }

    // The hero, at the two sizes that have one: how much of the tailnet is
    // up. The count IS the connection; the address is a detail, and it is
    // printed as one at every size.
    readonly property string countCaption:
        "of " + ts.peerCount + (ts.peerCount === 1 ? " peer" : " peers")

    readonly property var bigStats: {
        var rows = [
            { k: "Peers", v: ts.onlineCount + "/" + ts.peerCount },
            { k: "Direct", v: String(ts.directCount) },
            { k: "Relayed", v: String(ts.relayCount) }
        ]
        if (ts.exitNodeActive)
            rows.push({ k: "Exit", v: ts.exitNodeName !== "" ? ts.exitNodeName : "on" })
        return rows
    }

    // The node web draws at most this many peers. Sixteen is where labels
    // stop fitting round a 400px tile; past it the tile says "+N more"
    // rather than stacking names on top of each other.
    readonly property int webCap: 16
    readonly property var webPeers: ts.peers.slice(0, full.webCap)
    readonly property int webHidden: Math.max(0, ts.peerCount - full.webCap)

    // What one peer is doing, in one word, with the semantics the data
    // layer defines: `active` is a LIVE WireGuard session, and only then
    // does direct-vs-DERP mean anything. An online peer with no session is
    // idle, which is the normal state of a tailnet, not a fault - and an
    // idle peer is never called "relayed", because its home region is not
    // a live path.
    function pathWord(p) {
        if (!p) return ""
        if (p.active) return p.direct ? "Direct" : "Derp"
        return p.online ? "Idle" : "Offline"
    }

    // The same fact as a phrase, for the one node the pointer is on:
    // "Direct · 192.168.100.10:41641", "Via DERP Riyadh", "Idle",
    // "Offline · last seen 3 h". The endpoint comes last because it is the
    // first thing a narrow line may cut and the last thing that matters.
    function nodePhrase(nd) {
        if (!nd) return ""
        if (nd.active) {
            if (nd.direct)
                return nd.endpoint !== "" ? "Direct · " + nd.endpoint : "Direct"
            return nd.relayName !== "" ? "Via DERP " + nd.relayName : "Via DERP"
        }
        if (nd.online) return "Idle"
        var ago = full._ago(nd.lastSeen)
        return ago === "" ? "Offline" : "Offline · last seen " + ago
    }

    // Who a node is, in the order worth keeping when the line runs out:
    // the MagicDNS name, the tailnet address, the OS. Nothing else from the
    // status payload comes this far.
    function _ident(fqdn, ip, os) {
        var parts = []
        if (fqdn !== "") parts.push(fqdn)
        if (ip !== "") parts.push(ip)
        if (os !== "") parts.push(os)
        return parts.join("  ")
    }

    // How long ago, coarsely. Read when the readout line is rebuilt - on a
    // hover, not on a clock - so it deliberately does not tick.
    function _ago(iso) {
        var s = String(iso || "")
        if (s === "" || s.indexOf("0001-01-01") === 0) return ""
        var t = Date.parse(s)
        if (isNaN(t)) return ""
        var mins = Math.floor(Math.max(0, Date.now() - t) / 60000)
        if (mins < 1) return "just now"
        if (mins < 60) return mins + " min"
        var hrs = Math.floor(mins / 60)
        return hrs < 24 ? hrs + " h" : Math.floor(hrs / 24) + " d"
    }

    // One peer row: the full MagicDNS name, and what it is doing. The name
    // elides on its tail, so the hostname - the first label, the part worth
    // reading - always survives; a row that kept "…tailnet.ts.net" and
    // dropped "media-server" would be a row about the tailnet's name.
    Component {
        id: peerLine

        Item {
            id: pr
            required property var modelData

            anchors.left: parent.left
            anchors.right: parent.right
            height: nothing.px(17)

            NLabel {
                id: prWord
                theme: nothing
                text: full.pathWord(pr.modelData)
                loud: !!pr.modelData.active
                font.pixelSize: nothing.fMicro
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
            }

            NMono {
                theme: nothing
                text: String(pr.modelData.fqdn || pr.modelData.name || "")
                color: pr.modelData.active ? nothing.on
                    : (pr.modelData.online ? nothing.onDim : nothing.onQuiet)
                font.pixelSize: nothing.fMicro
                anchors.left: parent.left
                anchors.right: prWord.left
                anchors.rightMargin: nothing.gap
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
                // The FQDN is what this row exists to spell out in full -
                // the map above can only carry the first label (see the
                // comment on `peerLine`'s word). The widest name on the
                // tailnet measures 161.7 px against the 160.5 px the word
                // leaves it in system-font mode, so it shrinks into the box
                // first and elides only past the floor.
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: Math.max(7, nothing.fMicro - 1)
            }
        }
    }

    // One service line: a red dot when Funnel has it on the public
    // internet, its handler path, and what it points at.
    Component {
        id: serviceLine

        Item {
            id: svc
            required property var modelData

            anchors.left: parent.left
            anchors.right: parent.right
            height: nothing.px(15)

            Rectangle {
                id: funnelMark
                visible: !!svc.modelData.funnel
                width: nothing.px(5)
                height: nothing.px(5)
                radius: width / 2
                // Reachable from outside the tailnet: the one fact here
                // worth the accent.
                color: nothing.red
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
            }

            NLabel {
                id: svcName
                theme: nothing
                text: String(svc.modelData.label)
                loud: !!svc.modelData.funnel
                font.pixelSize: nothing.fMicro
                anchors.left: funnelMark.visible ? funnelMark.right : parent.left
                anchors.leftMargin: funnelMark.visible ? nothing.px(4) : 0
                anchors.verticalCenter: parent.verticalCenter
            }

            NMono {
                theme: nothing
                text: "→ " + String(svc.modelData.target)
                color: nothing.onDim
                font.pixelSize: nothing.fMicro
                anchors.left: svcName.right
                anchors.leftMargin: nothing.gap
                anchors.right: parent.right
                horizontalAlignment: Text.AlignRight
                // A proxy target is a URL; losing its middle beats losing
                // the port at the end.
                elide: Text.ElideMiddle
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    NCard {
        id: card
        theme: nothing
        anchors.fill: parent
        clip: true

        NDotField {
            theme: nothing
            anchors.fill: parent
            anchors.margins: nothing.pad
            intensity: 0.3
            visible: full.isBig && !full.ready
        }

        Item {
            id: body
            anchors.fill: parent
            anchors.margins: nothing.pad

            readonly property real rowH: nothing.px(17)

            // ── Header: tailscaled's state word, and the state dot ──────
            NBadge {
                id: stateDot
                theme: nothing
                label: ""
                // Red for "the tailnet is not up" only. Not while the first
                // status read is still in flight: a tile that flashes red
                // on every workspace switch teaches you to ignore red.
                active: ts.loaded && !ts.up
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: Math.max(0, (header.implicitHeight - implicitHeight) / 2)
            }

            NBadge {
                id: pathBadge
                theme: nothing
                visible: !full.isSmall && full.ready
                // Never accented: how traffic is carried is a fact, not an
                // alarm, and "Idle" is the healthy resting state.
                active: false
                label: full.pathText
                anchors.verticalCenter: stateDot.verticalCenter
                anchors.right: stateDot.left
                anchors.rightMargin: nothing.gap
            }

            NLabel {
                id: header
                theme: nothing
                text: ts.stateLabel
                loud: true
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: pathBadge.visible ? pathBadge.left : stateDot.left
                anchors.rightMargin: nothing.gap
                elide: Text.ElideRight
            }

            Item {
                id: content
                anchors.top: header.bottom
                anchors.topMargin: nothing.gap
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom

                // ── 192: the connection itself ──────────────────────────
                // The hero is how much of the tailnet is up, as dot-matrix
                // digits with the total spelled under them. The path word
                // gets one labelled row; the address gets the other, under
                // this node's short name. Nothing else fits.
                Item {
                    id: smallFace
                    visible: full.isSmall && full.ready
                    anchors.fill: parent

                    Column {
                        id: smallRows
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        spacing: 0

                        Item {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: nothing.px(16)

                            NLabel {
                                id: pathKey
                                theme: nothing
                                text: "Path"
                                font.pixelSize: nothing.fMicro
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            // The whole rest of the row, not half of it: the
                            // value is right-aligned either way, so a wider
                            // box paints identical pixels while the path fits
                            // and gives the text somewhere to shrink into when
                            // it does not. In system-font mode "Direct ·
                            // Riyadh" is 98.7 px against the old 82 px half
                            // and elided to "DIRECT · RI..". `HorizontalFit`
                            // with a floor, then elide - see PORTING.md item
                            // 9 and network/main.qml's own row.
                            NLabel {
                                theme: nothing
                                text: full.pathText
                                loud: true
                                font.pixelSize: nothing.fMicro
                                anchors.left: pathKey.right
                                anchors.leftMargin: nothing.gap
                                anchors.right: parent.right
                                horizontalAlignment: Text.AlignRight
                                fontSizeMode: Text.HorizontalFit
                                minimumPixelSize: nothing.px(7)
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        NDivider {
                            theme: nothing
                            anchors.left: parent.left
                            anchors.right: parent.right
                        }

                        Item {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: nothing.px(16)

                            // The short name on the tight tile: the full
                            // MagicDNS name is for the two sizes with room
                            // to carry it without shrinking the address.
                            NLabel {
                                id: smallWho
                                theme: nothing
                                text: ts.selfName !== "" ? ts.selfName : "Address"
                                font.pixelSize: nothing.fMicro
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            NMono {
                                theme: nothing
                                text: ts.selfIp
                                color: nothing.onDim
                                font.pixelSize: nothing.fLabel
                                anchors.left: smallWho.right
                                anchors.leftMargin: nothing.gap
                                anchors.right: parent.right
                                horizontalAlignment: Text.AlignRight
                                // Shrink before cutting an octet off it.
                                fontSizeMode: Text.HorizontalFit
                                minimumPixelSize: Math.max(7, nothing.fMicro - 1)
                                elide: Text.ElideLeft
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    Item {
                        id: smallStage
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: smallRows.top
                        anchors.bottomMargin: nothing.gap

                        // Dot-matrix digits need height to stay digits. At
                        // the registry's 160x120 minimum there is none, so
                        // the count is set in mono instead and carries the
                        // total itself - a 14px blob of dots is not a
                        // reading.
                        readonly property bool heroDots: smallStage.height >= nothing.px(58)

                        Column {
                            anchors.centerIn: parent
                            width: smallStage.width
                            spacing: nothing.px(3)

                            Item {
                                id: smallHeroBox
                                visible: smallStage.heroDots
                                width: parent.width
                                height: Math.max(nothing.px(14),
                                    Math.min(nothing.px(44), smallStage.height - nothing.px(18)))

                                NDotMatrix {
                                    theme: nothing
                                    anchors.centerIn: parent
                                    text: String(ts.onlineCount)
                                    onColor: nothing.on
                                    fitWidth: smallHeroBox.width
                                    fitHeight: smallHeroBox.height
                                }
                            }

                            NMono {
                                theme: nothing
                                visible: !smallStage.heroDots
                                width: parent.width
                                text: ts.onlineCount + "/" + ts.peerCount
                                font.pixelSize: Math.max(nothing.fLabel,
                                    Math.min(nothing.px(22), Math.round(smallStage.height * 0.6)))
                                horizontalAlignment: Text.AlignHCenter
                            }

                            NLabel {
                                theme: nothing
                                visible: smallStage.heroDots
                                width: parent.width
                                text: full.countCaption
                                font.pixelSize: nothing.fMicro
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                // ── 400x192: the count, this node, and the peers ────────
                // Left: the hero count, with this machine's address and its
                // MagicDNS name as the quiet detail under it. Right: the
                // peers by full name, live sessions first, and what this
                // machine serves along the bottom.
                Item {
                    id: wideFace
                    visible: full.isWide && full.ready
                    anchors.fill: parent

                    readonly property real splitX: Math.round(width * 0.42)

                    NDivider {
                        theme: nothing
                        vertical: true
                        x: wideFace.splitX
                        height: wideFace.height
                    }

                    Item {
                        id: wLeft
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        width: Math.max(0, wideFace.splitX - nothing.gap)

                        Column {
                            id: wWho
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            spacing: 0

                            NMono {
                                theme: nothing
                                anchors.left: parent.left
                                anchors.right: parent.right
                                text: ts.selfIp
                                color: nothing.onDim
                                font.pixelSize: nothing.fLabel
                                fontSizeMode: Text.HorizontalFit
                                minimumPixelSize: Math.max(7, nothing.fMicro - 1)
                                elide: Text.ElideLeft
                            }

                            NLabel {
                                theme: nothing
                                anchors.left: parent.left
                                anchors.right: parent.right
                                text: ts.selfFqdn !== "" ? ts.selfFqdn : full.whoText
                                font.pixelSize: nothing.fMicro
                                elide: Text.ElideRight
                            }
                        }

                        Item {
                            id: wStage
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: wWho.top
                            anchors.bottomMargin: nothing.gap

                            Column {
                                anchors.centerIn: parent
                                width: wStage.width
                                spacing: nothing.px(3)

                                Item {
                                    id: wideHeroBox
                                    width: parent.width
                                    height: Math.max(nothing.px(14),
                                        Math.min(nothing.px(52), wStage.height - nothing.px(18)))

                                    NDotMatrix {
                                        theme: nothing
                                        anchors.centerIn: parent
                                        text: String(ts.onlineCount)
                                        onColor: nothing.on
                                        fitWidth: wideHeroBox.width
                                        fitHeight: wideHeroBox.height
                                    }
                                }

                                NLabel {
                                    theme: nothing
                                    width: parent.width
                                    text: full.countCaption
                                    font.pixelSize: nothing.fMicro
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    Item {
                        id: wRight
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        x: wideFace.splitX + nothing.gap
                        width: Math.max(0, wideFace.width - x)

                        readonly property int svcShown: Math.min(2, ts.services.length)
                        readonly property real svcHeight: ts.hasServices
                            ? wRight.svcShown * nothing.px(15) + nothing.px(6) : 0
                        // Rows that fit, and then one row given back to the
                        // "+N more" line when there is one - otherwise the
                        // overflow line lands on the services divider.
                        readonly property int capRaw: Math.max(1,
                            Math.floor((wRight.height - wRight.svcHeight) / body.rowH))
                        readonly property int cap: ts.peerCount > wRight.capRaw
                            ? Math.max(1, wRight.capRaw - 1) : wRight.capRaw
                        readonly property var rows: ts.peers.slice(0, wRight.cap)

                        Column {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right

                            Repeater {
                                model: wRight.rows
                                delegate: peerLine
                            }

                            // A tailnet of one is a real answer.
                            NLabel {
                                theme: nothing
                                visible: ts.peerCount === 0
                                anchors.left: parent.left
                                anchors.right: parent.right
                                text: "No peers"
                                font.pixelSize: nothing.fMicro
                            }

                            // Never hide a peer silently: when the column
                            // cannot hold the list, it says how many it is
                            // not showing.
                            NLabel {
                                theme: nothing
                                visible: ts.peerCount > wRight.rows.length
                                anchors.left: parent.left
                                anchors.right: parent.right
                                text: "+" + (ts.peerCount - wRight.rows.length) + " more"
                                font.pixelSize: nothing.fMicro
                            }
                        }

                        Column {
                            id: wServices
                            visible: ts.hasServices
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            spacing: 0

                            NDivider {
                                theme: nothing
                                anchors.left: parent.left
                                anchors.right: parent.right
                            }

                            Repeater {
                                // Two lines is what the wide tile carries;
                                // the big one lists more.
                                model: ts.services.slice(0, 2)
                                delegate: serviceLine
                            }
                        }
                    }
                }

                // ── 400x400: everything, with the node web in the middle ─
                Item {
                    id: bigFace
                    visible: full.isBig && full.ready
                    anchors.fill: parent

                    // This machine, named once, above the map it is the
                    // centre of: short name and OS, the address as a quiet
                    // mono detail, and the full MagicDNS name under them -
                    // the one place the tile spells it out, which is what
                    // lets the map's own labels stay short.
                    Item {
                        id: bIdent
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: bWho.implicitHeight + bFqdn.implicitHeight

                        NMono {
                            id: bIp
                            theme: nothing
                            text: ts.selfIp
                            color: nothing.onDim
                            font.pixelSize: nothing.fLabel
                            anchors.top: parent.top
                            anchors.right: parent.right
                        }

                        NLabel {
                            id: bWho
                            theme: nothing
                            text: full.whoText
                            loud: true
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: bIp.left
                            anchors.rightMargin: nothing.gap
                            elide: Text.ElideRight
                        }

                        NMono {
                            id: bFqdn
                            theme: nothing
                            text: ts.selfFqdn
                            color: nothing.onDim
                            font.pixelSize: nothing.fMicro
                            anchors.top: bWho.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            elide: Text.ElideRight
                        }
                    }

                    // Footer: the tailnet as numbers, inline.
                    Row {
                        id: bStats
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        spacing: nothing.px(14)

                        Repeater {
                            model: full.bigStats

                            Row {
                                id: pair
                                required property var modelData

                                spacing: nothing.px(5)

                                NLabel {
                                    theme: nothing
                                    text: pair.modelData.k
                                    font.pixelSize: nothing.fMicro
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                NMono {
                                    theme: nothing
                                    text: pair.modelData.v
                                    font.pixelSize: nothing.fLabel
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }

                    // tailscaled's own warning text, verbatim, one line.
                    NLabel {
                        id: bHealth
                        theme: nothing
                        visible: ts.health.length > 0
                        text: String(ts.health[0])
                            + (ts.health.length > 1 ? "  +" + (ts.health.length - 1) : "")
                        font.pixelSize: nothing.fMicro
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: bStats.top
                        anchors.bottomMargin: nothing.px(5)
                        elide: Text.ElideRight
                    }

                    Column {
                        id: bServices
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: bHealth.visible ? bHealth.top : bStats.top
                        anchors.bottomMargin: nothing.px(5)
                        spacing: 0

                        // Said out loud rather than hidden: "this machine
                        // serves nothing on the tailnet" is information.
                        NLabel {
                            theme: nothing
                            anchors.left: parent.left
                            anchors.right: parent.right
                            text: ts.hasServices
                                ? (ts.services.length > 2
                                    ? "Serving · " + ts.services.length
                                    : "Serving")
                                : "No services"
                            font.pixelSize: nothing.fMicro
                            elide: Text.ElideRight
                        }

                        Repeater {
                            model: ts.services.slice(0, 2)
                            delegate: serviceLine
                        }
                    }

                    // The head of the peer list - live sessions first, by
                    // the data layer's own sort - spelled out in full,
                    // which is exactly what the map's short labels cannot.
                    Column {
                        id: bPeers
                        visible: ts.peerCount > 0
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: bServices.top
                        anchors.bottomMargin: nothing.px(5)
                        spacing: 0

                        Repeater {
                            model: ts.peers.slice(0, 2)
                            delegate: peerLine
                        }
                    }

                    // ── The map's readout line ──────────────────────────
                    // The peer list's caption, doing a second job.
                    //
                    // At rest it is exactly what it was: the word over the
                    // list beneath it. Hover a node in the web and this
                    // line becomes that node's identity and path; click one
                    // and the answer lands on the line UNDER it - where the
                    // pointer has left, this line names the node the ping
                    // measured, so the two still read as one block. A
                    // RESERVED pair of lines rather than a tooltip, on
                    // purpose - a tooltip floating over the web would cover
                    // the thing it describes, and the shape the web makes is
                    // the whole point of it.
                    //
                    // The style's metadata voice, unchanged: the key on the
                    // left in tracked caps, the technical value in mono on
                    // the right. The key is capped at half the line so the
                    // path WORD always survives.
                    Item {
                        id: bReadout
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: bPeers.visible ? bPeers.top : bServices.top
                        anchors.bottomMargin: bPeers.visible ? 0 : nothing.px(5)
                        // Two rows: the line that names the node (key left,
                        // identity right) and, immediately under it, the ping
                        // answer. The second row is reserved at ALL times,
                        // empty or not, because the web above is anchored to
                        // this box's top: a box that grew only when an answer
                        // was up would resize the whole map every time the
                        // pointer moved from one node to another.
                        readonly property real lineH: nothing.px(15)
                        readonly property real pingH: Math.round(nothing.fTitle * 1.3)
                        height: bReadout.lineH + bReadout.pingH

                        Item {
                            id: bReadLine
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: bReadout.lineH

                            NLabel {
                                id: bReadKey
                                theme: nothing
                                text: web.readKey
                                loud: web.readLoud
                                font.pixelSize: nothing.fMicro
                                width: Math.min(bReadKey.implicitWidth, parent.width * 0.5)
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                            }

                            NMono {
                                theme: nothing
                                text: web.readValue
                                color: nothing.onDim
                                font.pixelSize: nothing.fMicro
                                anchors.left: bReadKey.right
                                anchors.leftMargin: nothing.gap
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                // Shrink before cutting the address out of the
                                // identity; elide only when even 7px will not
                                // hold it.
                                fontSizeMode: Text.HorizontalFit
                                minimumPixelSize: 7
                                elide: Text.ElideRight
                            }
                        }

                        // The answer, in the row under the node it measured.
                        // Mono and at the title size, because it is a
                        // measurement and it is the one thing on this tile
                        // that reading status will never produce. Held to the
                        // box's own width: it shrinks into it first and elides
                        // only past the body size.
                        NMono {
                            id: bReadPing
                            theme: nothing
                            text: web.pingPhrase
                            visible: web.pingOnBlock && web.pingPhrase !== ""
                            // Dim while it is out, ink when it answers, and
                            // red only where this tile reds a fault: one that
                            // failed.
                            color: ts.pinging ? nothing.onDim
                                              : (web.pingFault ? nothing.red : nothing.on)
                            font.pixelSize: nothing.fTitle
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: bReadLine.bottom
                            anchors.bottom: parent.bottom
                            verticalAlignment: Text.AlignVCenter
                            fontSizeMode: Text.HorizontalFit
                            minimumPixelSize: nothing.fBody
                            elide: Text.ElideRight
                        }
                    }

                    // ── The node web ────────────────────────────────────
                    // THIS machine at the centre, its peers on one or two
                    // rings around it, because every fact drawn here -
                    // direct or DERP, live or idle - is measured from here
                    // and nowhere else.
                    //
                    // The geometry lives in exactly two properties: `_nodes`
                    // (one entry per drawn peer, in Canvas pixels) and
                    // `_center` (this machine). `_rebuild()` is the only
                    // thing that computes them, called from the size and
                    // `peers` handlers - the TickRing precedent. `onPaint`
                    // reads those two and draws; it computes no positions
                    // and never touches `peers`, so a later layer can nudge
                    // a node's x/y and call `requestPaint()` without going
                    // anywhere near the painter. Deterministic by
                    // construction: no physics, no jitter, no per-frame
                    // repaint.
                    //
                    // The pointer layer added on top keeps that split: it
                    // perturbs `_nodes[i].x/y`, moves ONE label by an
                    // offset, and asks for a repaint. See the interaction
                    // block below for the rule it obeys - the map wakes on
                    // touch and sleeps otherwise.
                    Item {
                        id: web
                        // Same measured trap as the glass twin's `web`: with
                        // `top: bIdent.bottom` against `bottom: bReadout.top`
                        // the two cross on the 160x120 tile, so the height
                        // goes negative - measured Item and Canvas both
                        // w=132 h=-53 - and it is inherent, not a resize
                        // artefact (creating the tile at 160x120 and
                        // resizing it to the same size reproduces h=-53).
                        // Inert only because `bigFace` above is gated on
                        // `full.isBig`; making this map visible at 192, or
                        // anchoring `bIdent` lower, is what surfaces it.
                        anchors.top: bIdent.bottom
                        anchors.topMargin: nothing.gap
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: bReadout.top
                        anchors.bottomMargin: nothing.gap

                        // [{ id, name, x, y, r, online, active, direct,
                        //    relayName, style, label, lx, ly, lw, labelH,
                        //    align }] - the first nine are the node, the
                        // rest are where its name goes. `style` is the four
                        // link cases, resolved here so the painter branches
                        // instead of deducing: 3 = live and direct,
                        // 2 = live via DERP, 1 = online but idle, 0 = offline.
                        property var _nodes: []
                        // { x, y, r, name, label, lx, ly, lw, labelH }
                        property var _center: null

                        readonly property var srcPeers: full.webPeers
                        readonly property real linkWidth:
                            Math.max(1, Math.min(web.width, web.height) * 0.008)
                        // The palette can change under a running widget
                        // (Follow the Omarchy theme); one repaint, no rebuild.
                        readonly property color ink: nothing.on

                        // How wide a hostname actually is, in the face that
                        // will draw it.
                        //
                        // The solver below used to size every name from a
                        // family-specific constant - "Barlow at fMicro
                        // averages ~0.55em per character, plus the label
                        // tracking" - which is a fair guess for the bundled
                        // face and wrong by construction for the desktop's
                        // own: measured here at fMicro 9, "TAILSCALE-PVE" is
                        // 60.2 px in Barlow and 85.5 px in system-font mode,
                        // so every label box came up short and `elide` ate
                        // the tail ("TAILSCALE-P…").
                        //
                        // `toUpperCase()` is required: the drawn labels are
                        // NLabels with `Font.AllUppercase`, and TextMetrics
                        // has no capitalisation of its own. `letterSpacing`
                        // is required too, or every name measures short by
                        // one pixel per character. `advanceWidth` is
                        // readable in the same statement that sets `text`
                        // (it is 0.0 for ""), so `_rebuild()` needs no
                        // change signal.
                        TextMetrics {
                            id: labelMetrics
                            font.family: nothing.sans
                            font.pixelSize: nothing.fMicro
                            font.letterSpacing: nothing.trackLabel
                        }

                        onSrcPeersChanged: web._rebuild()
                        onWidthChanged: web._rebuild()
                        onHeightChanged: web._rebuild()
                        onInkChanged: canvas.requestPaint()
                        Component.onCompleted: web._rebuild()

                        // ── Interaction ─────────────────────────────────
                        // The rule this layer is built to: the map WAKES ON
                        // TOUCH and sleeps otherwise. No idle animation, no
                        // physics, no per-frame repaint - at rest the web
                        // costs exactly what it cost before, which is
                        // nothing. Every property below is written by a
                        // pointer event and by nothing else; `homeSettle`
                        // is the only timer, it starts on a release and
                        // stops itself the frame the node is within half a
                        // pixel of home.
                        //
                        // The painter's contract is untouched: hover and
                        // ping are held as INDICES as well as ids, so
                        // `onPaint` compares integers and never asks what
                        // is under the cursor.
                        //
                        // Input the desktop already owns is left alone.
                        // Placement.qml has right-drag (move the tile), the
                        // bottom-right grip (resize) and right-click (the
                        // settings sheet). This layer takes the LEFT button,
                        // hover and the wheel, and only inside the web -
                        // the grip sits in the card's corner, four rows of
                        // text below the bottom edge of this item.

                        // Ring scale from the wheel: 0.6x - 1.4x of the
                        // computed radius, per session.
                        property real spread: 1.0
                        // Pins: peer id -> { fx, fy }, held as a fraction of
                        // the box so a resize keeps them. Session state on
                        // purpose - a pin is a gesture, not a setting, and
                        // nothing here goes near the store.
                        property var pins: ({})
                        property bool _hasPins: false

                        property string hoverId: ""
                        property int hoverIdx: -1
                        property bool hoverSelf: false

                        // The one node the pointer is moving, as an offset
                        // from its solved home: one node at a time, so one
                        // pair of numbers is the whole animation state.
                        property string dragId: ""
                        property int dragIdx: -1
                        property real dragDx: 0
                        property real dragDy: 0
                        property var _dragNode: null
                        property bool _dragMoved: false
                        property bool _dbl: false
                        property real _pressX: 0
                        property real _pressY: 0
                        property real _grabX: 0
                        property real _grabY: 0

                        // Which node the ping belongs to, held as an INDEX as
                        // well as an id: the painter compares integers and
                        // never asks what is under the pointer. The answer
                        // itself is not drawn on the map any more - it is the
                        // second row of the readout line below the web, under
                        // the node's own name and MagicDNS name.
                        property int pingIdx: -1

                        // The accent can change under a running widget the
                        // same way the ink can: one repaint, no rebuild.
                        readonly property color mark: nothing.red
                        onMarkChanged: canvas.requestPaint()
                        onSpreadChanged: web._rebuild()

                        // The peer the ping data is about: the target while
                        // it is in flight, the result's owner afterwards.
                        readonly property string pingId:
                            ts.pinging ? ts.pingTarget : ts.pingResultId
                        onPingIdChanged: web._syncPing()

                        // "15 ms direct", "1.0 s via DERP Riyadh", the
                        // error, or a static "Pinging …" while it is out.
                        // Static on purpose: a pulsing pending marker would
                        // be an animation running while the user does
                        // nothing, which is the one thing this layer may
                        // not do - and it would cost a repaint a frame to
                        // say what three dots say for free.
                        readonly property string pingPhrase: {
                            if (web.pingId === "") return ""
                            if (ts.pinging) return "Pinging …"
                            if (ts.pingError !== "") return ts.pingError
                            if (ts.pingMs <= 0) return "No answer"
                            var t = ts.pingMs >= 1000
                                ? (ts.pingMs / 1000).toFixed(1) + " s"
                                : Math.round(ts.pingMs) + " ms"
                            if (ts.pingVia === "direct") return t + " direct"
                            if (ts.pingVia.indexOf("derp ") === 0)
                                return t + " via DERP " + ts.pingVia.substring(5)
                            return t
                        }

                        // The answer's own line, under the line that names
                        // the node. It is up while this block IS the pinged
                        // node's block: the pointer is on that node, or it is
                        // away and the readout has fallen back to `pingIdx` -
                        // the same fallback `readKey` already makes, which is
                        // what keeps the answer readable after the pointer
                        // leaves.
                        readonly property bool pingOnBlock:
                            web._focus !== null && web._focus.id === web.pingId
                        // Red wherever this tile reds a fault, and nowhere
                        // else: a ping that never answered is one, a
                        // measurement is not.
                        readonly property bool pingFault: web.pingId !== ""
                            && !ts.pinging && (ts.pingError !== "" || ts.pingMs <= 0)

                        // What the reserved line says. Hover wins over a
                        // ping result, so moving the pointer always answers
                        // the pointer; with nothing hovered the last ping
                        // stays readable.
                        readonly property int focusIdx: web.hoverIdx >= 0
                            ? web.hoverIdx : (web.hoverSelf ? -1 : web.pingIdx)
                        readonly property var _focus: (!web.hoverSelf
                            && web.focusIdx >= 0 && web.focusIdx < web._nodes.length)
                                ? web._nodes[web.focusIdx] : null

                        readonly property string readKey: {
                            if (web.hoverSelf)
                                return ts.homeRelayName !== ""
                                    ? "Home · " + ts.homeRelayName : "This node"
                            var nd = web._focus
                            if (!nd) return ts.peerCount > 0 ? "Peers" : "This node"
                            // The node's own words, always: the ping answer is
                            // not spelled out here any more, it has its own
                            // line under this one.
                            return full.nodePhrase(nd)
                        }

                        readonly property string readValue: {
                            if (web.hoverSelf)
                                return full._ident(ts.selfFqdn, ts.selfIp, ts.selfOs)
                            var nd = web._focus
                            if (!nd) return ""
                            return full._ident(nd.fqdn !== "" ? nd.fqdn : nd.name,
                                               nd.ip, nd.os)
                        }

                        readonly property bool readLoud:
                            web.hoverSelf || web._focus !== null

                        function _indexOf(id) {
                            var nodes = web._nodes
                            for (var i = 0; i < nodes.length; i++)
                                if (nodes[i].id === id) return i
                            return -1
                        }

                        // The node under (mx, my), or -1. Linear over at
                        // most sixteen nodes, run on a pointer move and
                        // never on a paint. The grab radius has a floor, so
                        // an offline node - deliberately the smallest thing
                        // on the map - is still catchable.
                        function _hit(mx, my) {
                            var nodes = web._nodes
                            var grab = nothing.px(9)
                            var best = -1
                            var bestD = Infinity
                            for (var i = 0; i < nodes.length; i++) {
                                var nd = nodes[i]
                                var dx = mx - nd.x
                                var dy = my - nd.y
                                var d = dx * dx + dy * dy
                                var rr = Math.max(nd.r + nothing.px(3), grab)
                                if (d <= rr * rr && d < bestD) {
                                    bestD = d
                                    best = i
                                }
                            }
                            return best
                        }

                        // The centre is a square, so its hit box is one.
                        function _hitSelf(mx, my) {
                            var c = web._center
                            if (!c) return false
                            var rr = Math.max(c.r + nothing.px(3), nothing.px(9))
                            return Math.abs(mx - c.x) <= rr
                                && Math.abs(my - c.y) <= rr
                        }

                        function _setHover(idx, self) {
                            if (web.hoverIdx === idx && web.hoverSelf === self) return
                            web.hoverIdx = idx
                            web.hoverSelf = self
                            web.hoverId = (idx >= 0 && idx < web._nodes.length)
                                ? web._nodes[idx].id : ""
                            canvas.requestPaint()
                        }

                        // The drawn position of the node being moved, and
                        // the ONLY place the pointer writes geometry.
                        function _apply() {
                            var nd = web._dragNode
                            if (!nd) return
                            nd.x = nd.hx + web.dragDx
                            nd.y = nd.hy + web.dragDy
                        }

                        function _cancelDrag() {
                            homeSettle.running = false
                            web._dragNode = null
                            web.dragId = ""
                            web.dragIdx = -1
                            web.dragDx = 0
                            web.dragDy = 0
                            web._dragMoved = false
                        }

                        // Land whatever is in flight, at once.
                        function _snapHome() {
                            if (web._dragNode) {
                                web.dragDx = 0
                                web.dragDy = 0
                                web._apply()
                                canvas.requestPaint()
                            }
                            web._cancelDrag()
                        }

                        function _grab(idx) {
                            var nd = web._nodes[idx]
                            web.dragId = nd.id
                            web.dragIdx = idx
                            web._dragNode = nd
                            web._grabX = nd.x
                            web._grabY = nd.y
                            web.dragDx = nd.x - nd.hx
                            web.dragDy = nd.y - nd.hy
                        }

                        function _moveTo(mx, my) {
                            var nd = web._dragNode
                            if (!nd) return
                            // Clamped inside the web: a node dragged off
                            // the card is a node you cannot get back.
                            var tx = Math.max(nd.r, Math.min(web.width - nd.r,
                                web._grabX + mx - web._pressX))
                            var ty = Math.max(nd.r, Math.min(web.height - nd.r,
                                web._grabY + my - web._pressY))
                            web.dragDx = tx - nd.hx
                            web.dragDy = ty - nd.hy
                            web._apply()
                            canvas.requestPaint()
                        }

                        // Home in ~350 ms, exponentially: 0.79 per 16 ms
                        // frame puts a 100 px throw inside half a pixel in
                        // about 360 ms, and THAT is where the timer stops
                        // itself. No spring constant, no overshoot, no
                        // frame after the one that arrives.
                        function _settleStep() {
                            var dx = web.dragDx * 0.79
                            var dy = web.dragDy * 0.79
                            if (Math.abs(dx) < 0.5 && Math.abs(dy) < 0.5) {
                                web._snapHome()
                                return
                            }
                            web.dragDx = dx
                            web.dragDy = dy
                            web._apply()
                            canvas.requestPaint()
                        }

                        function _pinAt(id, x, y) {
                            var next = {}
                            for (var k in web.pins) next[k] = web.pins[k]
                            next[id] = { fx: x / web.width, fy: y / web.height }
                            web.pins = next
                            web._cancelDrag()
                            // ONE full label solve, here - never per frame.
                            web._rebuild()
                        }

                        function _togglePin(idx) {
                            var nd = web._nodes[idx]
                            var id = nd.id
                            if (!web.pins[id]) {
                                web._pinAt(id, nd.x, nd.y)
                                return
                            }
                            var wasX = nd.x
                            var wasY = nd.y
                            var next = {}
                            for (var k in web.pins) if (k !== id) next[k] = web.pins[k]
                            web.pins = next
                            web._cancelDrag()
                            web._rebuild()
                            // Unpinning reads as a release: it springs from
                            // where it was left to the slot it just got
                            // back, over the same 350 ms.
                            var back = web._indexOf(id)
                            if (back < 0) return
                            web.dragId = id
                            web.dragIdx = back
                            web._dragNode = web._nodes[back]
                            web.dragDx = wasX - web._dragNode.hx
                            web.dragDy = wasY - web._dragNode.hy
                            web._apply()
                            homeSettle.running = true
                        }

                        // Which node the ping belongs to, as an index for the
                        // painter - the link it measured comes forward in the
                        // ink, so the map still points at the node the answer
                        // is about. The words are not here: they are on the
                        // readout line below the web, under the node's name.
                        function _syncPing() {
                            web.pingIdx = web.pingId === ""
                                ? -1 : web._indexOf(web.pingId)
                            canvas.requestPaint()
                        }

                        // `peers` changes under a drag - a ping re-reads
                        // status, and what comes back is a NEW array. The
                        // pointer state is anchored by id, so a rebuild
                        // keeps the drag, the hover, the pins and the ping
                        // pointing at the same machines, and drops the ones
                        // that left the tailnet rather than moving a node
                        // that is no longer there.
                        function _resync() {
                            var hi = web.hoverId === ""
                                ? -1 : web._indexOf(web.hoverId)
                            if (web.hoverId !== "" && hi < 0) web.hoverId = ""
                            web.hoverIdx = hi
                            var di = web.dragId === ""
                                ? -1 : web._indexOf(web.dragId)
                            if (di < 0) {
                                web._cancelDrag()
                            } else {
                                web.dragIdx = di
                                web._dragNode = web._nodes[di]
                                web._apply()
                            }
                            web._syncPing()
                        }

                        function _resetInput() {
                            web._cancelDrag()
                            web._setHover(-1, false)
                        }

                        // The angles of one ring's slots, spaced by ARC and
                        // not by angle.
                        //
                        // On a circle the two are the same thing, and that
                        // fast path is what the map draws at rest - the
                        // same picture as before, to the pixel. A ring the
                        // wheel has pushed against one of the clamps is an
                        // ellipse, and equal ANGLES on an ellipse crowd its
                        // long ends: spreading the ring would push its
                        // nodes TOGETHER, which is precisely the thing the
                        // wheel is there to undo. So a spread ring is
                        // sampled once (128 steps, on a rebuild, never on a
                        // frame) and the slots are cut at equal arc length.
                        function _ringAngles(rx, ry, count, offset) {
                            var out = []
                            var i
                            var n = Math.max(1, count)
                            if (count <= 0) return out
                            if (Math.abs(rx - ry) < 0.001) {
                                for (i = 0; i < count; i++)
                                    out.push(-Math.PI / 2
                                        + ((i + offset) / n) * Math.PI * 2)
                                return out
                            }

                            var steps = 128
                            var cum = [0]
                            var px = 0
                            var py = -ry
                            for (i = 1; i <= steps; i++) {
                                var a = -Math.PI / 2 + (i / steps) * Math.PI * 2
                                var qx = Math.cos(a) * rx
                                var qy = Math.sin(a) * ry
                                cum.push(cum[i - 1] + Math.sqrt((qx - px) * (qx - px)
                                                                + (qy - py) * (qy - py)))
                                px = qx
                                py = qy
                            }

                            var total = cum[steps]
                            var k = 1
                            for (i = 0; i < count; i++) {
                                var want = ((i + offset) / n) * total
                                while (k < steps && cum[k] < want) k++
                                var lo = cum[k - 1]
                                var hi = cum[k]
                                var f = hi > lo ? (want - lo) / (hi - lo) : 0
                                out.push(-Math.PI / 2
                                    + ((k - 1 + f) / steps) * Math.PI * 2)
                            }
                            return out
                        }

                        function _rebuild() {
                            var w = web.width
                            var h = web.height
                            var peers = web.srcPeers
                            if (w <= 0 || h <= 0) {
                                web._center = null
                                web._nodes = []
                                web._resync()
                                return
                            }

                            var cx = w / 2
                            var cy = h / 2
                            var side = Math.min(w, h)
                            var rBase = Math.max(2, side * 0.022)
                            var rMax = Math.max(rBase * 2, side / 2 - rBase * 2.4)
                            // How far the wheel may push a ring before it
                            // would leave the box, per axis - because the
                            // box is not square. A 400px tile's web is
                            // twice as wide as it is tall, so a spread ring
                            // stretches into the room it actually has
                            // instead of clipping off the top. At spread 1
                            // neither clamp bites and the ring is the same
                            // circle it always was.
                            var wMax = Math.max(rBase * 2, w / 2 - rBase * 2.4)
                            var hMax = Math.max(rBase * 2, h / 2 - rBase * 2.4)

                            var labelH = Math.round(nothing.fMicro * 1.5)
                            var pad = nothing.px(2)
                            var cr = Math.max(2, rBase * 1.3)

                            // The centre carries this machine's short name,
                            // directly beneath its square. Its box is
                            // claimed before every peer label, so no name
                            // lands on it - and it is only claimed at all
                            // if no NODE lies there either, which the wheel
                            // can arrange by pulling the inner ring in on
                            // top of it.
                            var selfShort = ts.selfName !== "" ? ts.selfName : "this node"
                            // Measured, but never narrower than the
                            // arithmetic the bundled map was solved against:
                            // a measurement alone would shrink every box the
                            // moment the bundled face measures narrower than
                            // the constant, re-solve the collision pass and
                            // move the default map.
                            labelMetrics.text = selfShort.toUpperCase()
                            var selfW = Math.round(Math.max(selfShort.length
                                * (nothing.fMicro * 0.55 + nothing.trackLabel),
                                labelMetrics.advanceWidth)) + pad
                            var selfX = Math.max(0, Math.min(w - selfW, cx - selfW / 2))
                            var selfY = cy + cr + nothing.px(4)
                            var selfLabel = selfY + labelH <= h
                            var selfBox = { x0: selfX - pad, y0: selfY,
                                            x1: selfX + selfW + pad, y1: selfY + labelH }

                            var boxes = [{ x0: cx - cr - pad, y0: cy - cr - pad,
                                           x1: cx + cr + pad, y1: cy + cr + pad }]

                            // One ring up to eight peers; beyond that an
                            // inner ring for the interesting ones (the sort
                            // order puts live sessions first) and an outer
                            // ring for the rest, half a step out of phase so
                            // no two nodes share a spoke.
                            var n = peers.length
                            var rings = []
                            if (n <= 8) {
                                rings.push({ count: n, radius: rMax * 0.84, offset: 0 })
                            } else {
                                var inner = Math.ceil(n * 0.38)
                                rings.push({ count: inner, radius: rMax * 0.54, offset: 0 })
                                rings.push({ count: n - inner, radius: rMax * 0.97, offset: 0.5 })
                            }

                            // The ring radii, resolved once, from the
                            // OUTSIDE in: the wheel scales them, the box
                            // clamps them per axis, and a ring that hit a
                            // clamp pushes back on the ring inside it so
                            // the pair keeps the separation it was drawn
                            // with. Without that, spreading a two-ring web
                            // pulls the inner ring up against a pinned-down
                            // outer one and the wheel crowds the map it is
                            // there to open up.
                            //
                            // The push-back is a CAP, never a pull: its
                            // floor is the ring's own scaled radius, so
                            // contracting the web is exactly the scale it
                            // says it is and spread 1 is the picture the
                            // map has always drawn.
                            for (var rj = rings.length - 1; rj >= 0; rj--) {
                                var rg = rings[rj]
                                var scaled = rg.radius * web.spread
                                rg.rx = Math.min(scaled, wMax)
                                rg.ry = Math.min(scaled, hMax)
                                if (rj < rings.length - 1) {
                                    var outer = rings[rj + 1]
                                    var sep = outer.radius - rg.radius
                                    var floor = rg.radius * Math.min(1, web.spread)
                                    rg.rx = Math.min(rg.rx,
                                        Math.max(floor, outer.rx - sep))
                                    rg.ry = Math.min(rg.ry,
                                        Math.max(floor, outer.ry - sep))
                                }
                            }

                            // Pass one: where every node sits. Positions
                            // first and complete, so pass two can treat
                            // EVERY node disc as an obstacle - placing a
                            // label against a half-built map is how a name
                            // ends up lying across a node drawn later.
                            var pins = web.pins
                            var hasPins = false
                            var out = []
                            var idx = 0
                            for (var ri = 0; ri < rings.length; ri++) {
                                var ring = rings[ri]
                                // Per ring, not per node: the radii are the
                                // ring's, and its slots come from one
                                // arc-length pass over it.
                                var rx = ring.rx
                                var ry = ring.ry
                                var slots = web._ringAngles(rx, ry, ring.count, ring.offset)
                                for (var i = 0; i < ring.count; i++) {
                                    var p = peers[idx]
                                    idx++
                                    if (!p) continue

                                    var a = slots[i]
                                    var x = cx + Math.cos(a) * rx
                                    var y = cy + Math.sin(a) * ry
                                    var r = p.active ? rBase * 1.7
                                        : (p.online ? rBase * 1.15 : rBase * 0.8)

                                    // A pin overrides the computed slot and
                                    // IS this node's home for as long as it
                                    // is held: the solver below places its
                                    // name at the pin, and a drag springs
                                    // back to it.
                                    var pin = pins[String(p.id)]
                                    if (pin) {
                                        hasPins = true
                                        x = Math.max(r, Math.min(w - r, pin.fx * w))
                                        y = Math.max(r, Math.min(h - r, pin.fy * h))
                                    }

                                    out.push({ id: String(p.id),
                                               // Short names on the map:
                                               // sixteen MagicDNS names
                                               // would be sixteen copies of
                                               // the same tailnet suffix.
                                               // The full name is above the
                                               // map, once.
                                               name: String(p.name || p.host || ""),
                                               // Who this node is, for the
                                               // readout line: names,
                                               // addresses, OS and DERP
                                               // regions only.
                                               fqdn: String(p.fqdn || ""),
                                               ip: String(p.ip || ""),
                                               os: String(p.os || ""),
                                               endpoint: String(p.endpoint || ""),
                                               lastSeen: String(p.lastSeen || ""),
                                               // `hx`/`hy` is home, `x`/`y`
                                               // is where it is drawn: the
                                               // pointer moves the second
                                               // and never the first.
                                               x: x, y: y, hx: x, hy: y, r: r,
                                               pinned: !!pin,
                                               pinS: Math.max(nothing.px(2), r * 0.6),
                                               online: !!p.online, active: !!p.active,
                                               direct: !!p.direct,
                                               relayName: String(p.relayName || ""),
                                               // The four link cases,
                                               // resolved here so the
                                               // painter branches instead of
                                               // deducing.
                                               style: p.active ? (p.direct ? 3 : 2)
                                                               : (p.online ? 1 : 0),
                                               label: false, lx: 0, ly: 0, align: 0,
                                               lw: 0, labelH: labelH })
                                    boxes.push({ x0: x - r - pad, y0: y - r - pad,
                                                 x1: x + r + pad, y1: y + r + pad })
                                }
                            }

                            // Now that every node is placed: does this
                            // machine's own name still have room? A
                            // contracted web can put a peer where the name
                            // goes, and a name under a node is worse than
                            // no name - the full identity is spelled out
                            // above the map either way.
                            if (selfLabel) {
                                for (var sb = 1; sb < boxes.length; sb++) {
                                    if (selfBox.x0 < boxes[sb].x1
                                        && selfBox.x1 > boxes[sb].x0
                                        && selfBox.y0 < boxes[sb].y1
                                        && selfBox.y1 > boxes[sb].y0) {
                                        selfLabel = false
                                        break
                                    }
                                }
                            }
                            if (selfLabel) boxes.push(selfBox)

                            // Pass two: the names, in the order the data
                            // layer sorted the peers - live sessions first -
                            // so the interesting nodes keep their names when
                            // something has to give. This is the O(n^2) pass
                            // and it runs HERE only: on a size change, a
                            // `peers` change, a wheel notch, a pin and a
                            // settled release. Never on a pointer move.
                            for (var k = 0; k < out.length; k++) {
                                var nd = out[k]
                                // Measured, floored by the arithmetic the
                                // bundled map was solved against - see the
                                // labelMetrics comment above. A measurement
                                // can only ever widen a box here.
                                labelMetrics.text = nd.name.toUpperCase()
                                var lw = Math.round(Math.max(nd.name.length
                                    * (nothing.fMicro * 0.55 + nothing.trackLabel),
                                    labelMetrics.advanceWidth)) + pad
                                var off = nothing.px(4)

                                // Four places a name may go, tried in
                                // order: outward from the centre first
                                // (which is what makes the web read
                                // radially), then inward, then above, then
                                // below. align 0/1/2 = left/right/centre
                                // inside its own box.
                                var cands = [
                                    { lx: nd.x + nd.r + off, ly: nd.y - labelH / 2, align: 0 },
                                    { lx: nd.x - nd.r - off - lw, ly: nd.y - labelH / 2, align: 1 },
                                    { lx: nd.x - lw / 2, ly: nd.y - nd.r - off - labelH, align: 2 },
                                    { lx: nd.x - lw / 2, ly: nd.y + nd.r + off, align: 2 }
                                ]
                                if (nd.x < cx) {
                                    var swap = cands[0]
                                    cands[0] = cands[1]
                                    cands[1] = swap
                                }

                                // A name is drawn only if the node is big
                                // enough to own one - an offline node is
                                // deliberately too small - and one of the
                                // four places is free: inside the web, and
                                // clear of every node and every name
                                // already placed.
                                var spot = null
                                if (nd.name !== "" && nd.r >= rBase) {
                                    for (var ci = 0; ci < cands.length && spot === null; ci++) {
                                        var cd = cands[ci]
                                        if (cd.lx < 0 || cd.lx + lw > w
                                            || cd.ly < 0 || cd.ly + labelH > h) continue
                                        var free = true
                                        for (var b = 0; b < boxes.length && free; b++) {
                                            if (cd.lx < boxes[b].x1 && cd.lx + lw > boxes[b].x0
                                                && cd.ly < boxes[b].y1
                                                && cd.ly + labelH > boxes[b].y0)
                                                free = false
                                        }
                                        if (free) spot = cd
                                    }
                                }
                                if (spot === null) continue

                                nd.label = true
                                nd.lx = spot.lx
                                nd.ly = spot.ly
                                nd.align = spot.align
                                nd.lw = lw
                                boxes.push({ x0: spot.lx - pad, y0: spot.ly,
                                             x1: spot.lx + lw + pad, y1: spot.ly + labelH })
                            }

                            web._center = { x: cx, y: cy, r: cr, name: selfShort,
                                            label: selfLabel, lx: selfX, ly: selfY,
                                            lw: selfW, labelH: labelH }
                            web._hasPins = hasPins
                            web._nodes = out
                            // Re-anchor the pointer to the rebuilt array:
                            // the ids are the identity, the indices are not.
                            web._resync()
                            canvas.requestPaint()
                        }

                        // Hand-stepped dashes: the same picture on every Qt
                        // build, without depending on setLineDash.
                        function _dash(ctx, x0, y0, x1, y1) {
                            var dx = x1 - x0
                            var dy = y1 - y0
                            var len = Math.sqrt(dx * dx + dy * dy)
                            if (len <= 0) return
                            var ux = dx / len
                            var uy = dy / len
                            var on = nothing.px(4)
                            var off = nothing.px(3)
                            ctx.beginPath()
                            for (var t = 0; t < len; t += on + off) {
                                var e = Math.min(len, t + on)
                                ctx.moveTo(x0 + ux * t, y0 + uy * t)
                                ctx.lineTo(x0 + ux * e, y0 + uy * e)
                            }
                            ctx.stroke()
                        }

                        Canvas {
                            id: canvas
                            anchors.fill: parent
                            antialiasing: true

                            onPaint: {
                                var ctx = canvas.getContext("2d")
                                ctx.reset()

                                var c = web._center
                                if (!c) return
                                var nodes = web._nodes
                                var ink = web.ink
                                // Read once, compared per node: hover and
                                // ping arrive as INDICES, so the painter
                                // does no string compares and never asks
                                // what is under the pointer.
                                var hi = web.hoverIdx
                                var pi = web.pingIdx
                                var lit
                                var i
                                var nd

                                // Links first, so a node sits on top of its
                                // own spoke. The style IS the fact: solid =
                                // a live peer-to-peer session, dashed = a
                                // live session carried by DERP, faint = up
                                // on the tailnet but idle (the normal state,
                                // not a fault), barely there = offline. A
                                // link's geometry is the node position and
                                // nothing else - centre to (nd.x, nd.y) -
                                // so a dragged node re-draws its own spoke
                                // for free.
                                ctx.strokeStyle = ink
                                for (i = 0; i < nodes.length; i++) {
                                    nd = nodes[i]
                                    // Hovered, or carrying a ping answer:
                                    // full ink, full weight.
                                    lit = (i === hi || i === pi)
                                    if (nd.style === 3) {
                                        ctx.globalAlpha = lit ? 1 : 0.85
                                        ctx.lineWidth = web.linkWidth
                                        ctx.beginPath()
                                        ctx.moveTo(c.x, c.y)
                                        ctx.lineTo(nd.x, nd.y)
                                        ctx.stroke()
                                    } else if (nd.style === 2) {
                                        ctx.globalAlpha = lit ? 1 : 0.75
                                        ctx.lineWidth = web.linkWidth
                                        web._dash(ctx, c.x, c.y, nd.x, nd.y)
                                    } else {
                                        ctx.globalAlpha = lit ? 1
                                            : (nd.style === 1 ? 0.16 : 0.06)
                                        ctx.lineWidth = lit ? web.linkWidth
                                            : Math.max(1, web.linkWidth * 0.7)
                                        ctx.beginPath()
                                        ctx.moveTo(c.x, c.y)
                                        ctx.lineTo(nd.x, nd.y)
                                        ctx.stroke()
                                    }
                                }

                                // This machine: a filled square, the one
                                // node that is not a peer.
                                ctx.globalAlpha = 1
                                ctx.fillStyle = ink
                                ctx.fillRect(c.x - c.r, c.y - c.r, c.r * 2, c.r * 2)
                                if (web.hoverSelf) {
                                    // Its ink is already full, so hover
                                    // marks it with a hairline box. No glow,
                                    // no shadow - this style does not own
                                    // either.
                                    ctx.lineWidth = 1
                                    var sr = c.r + nothing.px(4)
                                    ctx.beginPath()
                                    ctx.rect(c.x - sr, c.y - sr, sr * 2, sr * 2)
                                    ctx.stroke()
                                }

                                for (i = 0; i < nodes.length; i++) {
                                    nd = nodes[i]
                                    lit = (i === hi)
                                    if (nd.style === 0) {
                                        // Offline: an empty ring, so the
                                        // node is present without claiming
                                        // any ink - at full strength while
                                        // the pointer is on it.
                                        ctx.globalAlpha = lit ? 1 : 0.3
                                        ctx.lineWidth = Math.max(1, web.linkWidth * 0.8)
                                        ctx.beginPath()
                                        ctx.arc(nd.x, nd.y, nd.r, 0, Math.PI * 2)
                                        ctx.stroke()
                                    } else {
                                        ctx.globalAlpha = lit ? 1
                                            : (nd.style === 1 ? 0.5 : 1)
                                        ctx.beginPath()
                                        ctx.arc(nd.x, nd.y, nd.r, 0, Math.PI * 2)
                                        ctx.fill()
                                        if (nd.style === 2) {
                                            // Live via DERP: the halo repeats
                                            // at the node what the dashes say
                                            // on the link.
                                            ctx.globalAlpha = lit ? 1 : 0.45
                                            ctx.lineWidth = 1
                                            ctx.beginPath()
                                            ctx.arc(nd.x, nd.y, nd.r + nothing.px(3), 0, Math.PI * 2)
                                            ctx.stroke()
                                        }
                                    }
                                    if (lit) {
                                        ctx.globalAlpha = 1
                                        ctx.lineWidth = 1
                                        ctx.beginPath()
                                        ctx.arc(nd.x, nd.y, nd.r + nothing.px(5), 0, Math.PI * 2)
                                        ctx.stroke()
                                    }
                                }

                                // Pinned: a filled square in the accent, the
                                // centre's own device borrowed for the one
                                // state the USER made. Skipped entirely
                                // when nothing is pinned, which is almost
                                // always.
                                if (web._hasPins) {
                                    ctx.globalAlpha = 1
                                    ctx.fillStyle = web.mark
                                    for (i = 0; i < nodes.length; i++) {
                                        nd = nodes[i]
                                        if (!nd.pinned) continue
                                        ctx.fillRect(nd.x - nd.pinS, nd.y - nd.pinS,
                                                     nd.pinS * 2, nd.pinS * 2)
                                    }
                                }

                                ctx.globalAlpha = 1
                            }
                        }

                        NLabel {
                            theme: nothing
                            visible: !!web._center && !!web._center.label
                            loud: true
                            text: web._center ? web._center.name : ""
                            font.pixelSize: nothing.fMicro
                            x: web._center ? web._center.lx : 0
                            y: web._center ? web._center.ly : 0
                            width: web._center ? web._center.lw : 0
                            height: web._center ? web._center.labelH : 0
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        Repeater {
                            model: web._nodes

                            NLabel {
                                id: nodeLabel
                                required property var modelData
                                required property int index

                                theme: nothing
                                visible: nodeLabel.modelData.label
                                text: nodeLabel.modelData.name
                                font.pixelSize: nothing.fMicro
                                color: nodeLabel.modelData.style >= 2 ? nothing.on
                                    : (nodeLabel.modelData.style === 1 ? nothing.onDim : nothing.onQuiet)
                                // The solved position, plus the offset of
                                // the ONE node the pointer is moving. A drag
                                // therefore costs one label's x/y - not a
                                // re-solve of every label against every
                                // other one, which is what an O(n^2) pass
                                // per mouse move would be. That pass runs
                                // once, in `_rebuild()`.
                                x: nodeLabel.modelData.lx
                                    + (nodeLabel.index === web.dragIdx ? web.dragDx : 0)
                                y: nodeLabel.modelData.ly
                                    + (nodeLabel.index === web.dragIdx ? web.dragDy : 0)
                                width: nodeLabel.modelData.lw
                                height: nodeLabel.modelData.labelH
                                horizontalAlignment: nodeLabel.modelData.align === 1
                                    ? Text.AlignRight
                                    : (nodeLabel.modelData.align === 2
                                        ? Text.AlignHCenter : Text.AlignLeft)
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                        }

                        // A one-machine tailnet is a real answer, and the
                        // capped case says how much it is not showing.
                        NLabel {
                            theme: nothing
                            visible: ts.peerCount === 0
                            text: "Only this node"
                            font.pixelSize: nothing.fMicro
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                        }

                        NLabel {
                            theme: nothing
                            visible: full.webHidden > 0
                            text: "+" + full.webHidden + " more"
                            font.pixelSize: nothing.fMicro
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                        }

                        // The only timer in this file, and it runs ONLY
                        // while a released node is on its way home:
                        // `_settleStep` stops it the frame the node is
                        // within half a pixel. At rest it is not running, so
                        // at rest the web repaints zero times.
                        Timer {
                            id: homeSettle
                            interval: 16
                            repeat: true
                            running: false
                            onTriggered: web._settleStep()
                        }

                        // The answer used to be drawn here, on the link it was
                        // measured over. It is on the readout line now, under
                        // the node's own name: one place, big enough to read
                        // without hunting for it in the map. The map still
                        // answers the pointer - the measured node's link comes
                        // forward in the ink (`pingIdx`, above).

                        // ── The pointer ─────────────────────────────────
                        // Loaded ONLY at 400x400, where the map exists. At
                        // 192x192 and 400x192 this Loader is inactive and
                        // there is no MouseArea in the scene at all - not a
                        // disabled one, not a hidden one, none.
                        Loader {
                            id: mapInput
                            anchors.fill: parent
                            active: full.isBig && full.ready
                            sourceComponent: mapPointer
                            onActiveChanged: if (!mapInput.active) web._resetInput()
                        }

                        Component {
                            id: mapPointer

                            MouseArea {
                                id: area
                                anchors.fill: parent
                                // LEFT ONLY, and only over the web. Right-
                                // drag moves the tile and right-click opens
                                // the settings sheet - both belong to
                                // Placement.qml, and accepting RightButton
                                // here would take the desktop's own gestures
                                // away from it.
                                acceptedButtons: Qt.LeftButton
                                hoverEnabled: true
                                cursorShape: (web.hoverIdx >= 0 || web.hoverSelf)
                                    ? Qt.PointingHandCursor : Qt.ArrowCursor

                                // A click that did not drag pings; a second
                                // click pins instead. One short one-shot
                                // decides which - not an animation: it runs
                                // once per click, only ever because a button
                                // went down, and never repeats.
                                Timer {
                                    id: clickArm
                                    property string pending: ""
                                    interval: 260
                                    repeat: false
                                    onTriggered: {
                                        if (clickArm.pending === "") return
                                        // The data layer owns the process;
                                        // this file only asks for a ping.
                                        ts.ping(clickArm.pending)
                                        clickArm.pending = ""
                                    }
                                }

                                onPressed: function (mouse) {
                                    clickArm.stop()
                                    clickArm.pending = ""
                                    web._dbl = false
                                    var idx = web._hit(mouse.x, mouse.y)
                                    // Grabbing anything else lands the node
                                    // that was still on its way home.
                                    if (web.dragId !== ""
                                        && (idx < 0 || web._nodes[idx].id !== web.dragId))
                                        web._snapHome()
                                    homeSettle.running = false
                                    web._pressX = mouse.x
                                    web._pressY = mouse.y
                                    web._dragMoved = false
                                    if (idx < 0) {
                                        web._cancelDrag()
                                        return
                                    }
                                    web._grab(idx)
                                    web._setHover(idx, false)
                                }

                                onPositionChanged: function (mouse) {
                                    if (area.pressed) {
                                        if (!web._dragNode) return
                                        if (!web._dragMoved) {
                                            var mdx = mouse.x - web._pressX
                                            var mdy = mouse.y - web._pressY
                                            // 4 px of dead zone, so a click
                                            // from a shaky hand is a click.
                                            if (mdx * mdx + mdy * mdy < 16) return
                                            web._dragMoved = true
                                        }
                                        web._moveTo(mouse.x, mouse.y)
                                        return
                                    }
                                    var idx = web._hit(mouse.x, mouse.y)
                                    web._setHover(idx,
                                        idx < 0 && web._hitSelf(mouse.x, mouse.y))
                                }

                                onReleased: function (mouse) {
                                    if (web._dbl) {
                                        // The pin (or unpin) already set the
                                        // state this release would clear.
                                        web._dbl = false
                                        return
                                    }
                                    if (!web._dragNode) return
                                    if (!web._dragMoved) {
                                        clickArm.pending = web.dragId
                                        clickArm.restart()
                                        web._cancelDrag()
                                        return
                                    }
                                    if (web.pins[web.dragId]) {
                                        // Pinned: it stays where it was
                                        // dropped, and the labels are
                                        // re-solved once, here.
                                        web._pinAt(web.dragId,
                                            web._dragNode.x, web._dragNode.y)
                                        return
                                    }
                                    // Springs home over ~350 ms and stops.
                                    homeSettle.running = true
                                }

                                onDoubleClicked: function (mouse) {
                                    clickArm.stop()
                                    clickArm.pending = ""
                                    web._dbl = true
                                    var idx = web._hit(mouse.x, mouse.y)
                                    if (idx < 0) return
                                    web._setHover(idx, false)
                                    web._togglePin(idx)
                                }

                                onExited: if (!area.pressed) web._setHover(-1, false)

                                onCanceled: {
                                    clickArm.stop()
                                    clickArm.pending = ""
                                    web._snapHome()
                                }

                                // Spreads the ring, 0.6x - 1.4x, so
                                // thirteen nodes can be pulled apart on a
                                // 400px tile. Accepted here and nowhere
                                // else - nothing under this area scrolls.
                                onWheel: function (wheel) {
                                    wheel.accepted = true
                                    var d = wheel.angleDelta.y !== 0
                                        ? wheel.angleDelta.y : wheel.angleDelta.x
                                    if (d === 0) return
                                    var step = Math.max(-1, Math.min(1, d / 120)) * 0.08
                                    var next = Math.max(0.6,
                                        Math.min(1.4, web.spread + step))
                                    if (Math.abs(next - web.spread) > 0.0005)
                                        web.spread = next
                                }
                            }
                        }
                    }
                }

                // ── Every other state, at every size ────────────────────
                // Checking, Unavailable, Stopped, Logged out, Not set up,
                // Starting: a dash where the number goes and one line of
                // plain words. Never a blank card, never a fake zero.
                Column {
                    id: notReady
                    visible: !full.ready
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: nothing.gap

                    Item {
                        id: waitingBox
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: nothing.px(24)

                        NDotMatrix {
                            theme: nothing
                            anchors.centerIn: parent
                            text: "--"
                            onColor: nothing.onDim
                            fitWidth: Math.min(waitingBox.width, nothing.px(56))
                            fitHeight: waitingBox.height
                        }
                    }

                    NLabel {
                        theme: nothing
                        anchors.left: parent.left
                        anchors.right: parent.right
                        text: full.detailLine
                        loud: true
                        font.pixelSize: full.isSmall ? nothing.fMicro : nothing.fLabel
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    // tailscaled's own words on why, when it has any and
                    // there is room to print them.
                    NLabel {
                        theme: nothing
                        anchors.left: parent.left
                        anchors.right: parent.right
                        visible: !full.isSmall && ts.health.length > 0
                        text: String(ts.health[0])
                        font.pixelSize: nothing.fMicro
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
