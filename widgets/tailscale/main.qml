import QtQuick
import "../../components"

// The tailnet, Liquid Glass.
//
// components/TailscaleData.qml is the only source: it owns the three polled
// `tailscale` CLI reads (status, serve, derp-map) on its 30 s timer, and its
// `active` is bound to this tile's `visible` below, so a widget on another
// workspace spawns no process and holds no socket. There is no timer and no
// `tailscale` call in this file, and nothing here can change the tailnet: the
// tile is a readout.
//
// Three layouts, one per grid preset (WidgetRegistry.sizes). The hero is
// always the connection - the state and how much of the tailnet is up -
// never the address: an IP answers a question nobody asked of a tile.
//   192x192   state + online/total, the tailnet as dots, name and address
//             on one quiet footer line.
//   400x192   the same hero and dots on the left with the full MagicDNS
//             name under them, the facts (path, address, live, serving) as
//             rows on the right.
//   400x400   state + the count as a number, the FQDN once above the node
//             web, the web itself, and two rows under it: the node the
//             pointer (or the last ping) names, and its path - or, for that
//             pinged node, the answer in big type.
//
// What is deliberately NOT on screen: node keys, auth keys, peer
// `endpoint`s, and `tailnet` - a personal tailnet is named after the account
// that owns it, so that string can carry a login address. MagicDNS names,
// hostnames, tailnet IPs, OS names and DERP region names only.
//
// The distinction the whole tile is built on: `online` is "this node is up on
// the tailnet", `active` is "there is a live WireGuard session with it right
// now". A tailnet nobody is talking to is entirely online and entirely idle,
// which is normal - so idle is drawn as quiet, never as a fault. And `direct`
// only means anything while `active`: an idle peer's `relay` is its home DERP
// region, not a path in use, so an idle peer is never labelled "relayed".
//
// The map is the one part of this tile you can touch, and only at 400x400.
// Left button, hover and the wheel are all it takes - right-drag (move),
// right-click (settings) and the corner grip (resize) belong to
// Placement.qml one layer up, so the MouseArea here accepts LeftButton only
// and lives inside the map's own rectangle, nowhere near the grip.
//
//   hover        the node and its link come forward in the accent, and its
//                two fact rows replace the tile's two facts
//   drag         the node follows the pointer, its link re-cut as it goes,
//                and springs home over 350 ms on release
//   double-click pins it where it lies (filled, ringed) - session state, not
//                stored - and again to unpin and send it home
//   click        asks the data layer for one `tailscale ping` and writes the
//                answer in that node's own row block, under the row that
//                names it - big, and still there when the pointer leaves
//   wheel        spreads the ring, 0.6x to 1.4x of its computed radius
//
// And the rule the whole layer is built to keep: it wakes on touch and
// sleeps otherwise. There is no idle timer, no physics loop and no repaint
// at rest. Hover and drag repaint from the event that caused them; the one
// Timer in the file runs only while a released node is settling and stops
// itself the frame every node is within half a pixel of home.
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

    TailscaleData {
        id: ts
        // An off-screen tile costs nothing - see the component's header.
        active: full.visible
    }

    // A ping starting, and a ping answering. The answer belongs to a node,
    // so it is put into words once, here, and drawn in that node's own block
    // under the map - see `_syncPing` and `pingOnBlock`.
    Connections {
        target: ts
        function onPingingChanged() { full._syncPing() }
        function onPingResultIdChanged() { full._syncPing() }
        function onPingMsChanged() { full._syncPing() }
    }

    // ── Layout state ─────────────────────────────────────────────────────
    readonly property real _minSide: Math.min(width, height)
    readonly property bool isWide: width >= height * 1.6
    readonly property bool isBig: !isWide && _minSide >= 300

    readonly property real _pad: Math.round(_minSide * (isBig ? 0.065 : 0.11))
    readonly property real _label: Math.max(9, Math.round(_minSide * (isBig ? 0.042 : 0.075)))
    readonly property real _hero: Math.round(_minSide * (isBig ? 0.085 : 0.15))
    readonly property real _row: Math.max(9, Math.round(_label * 0.94))
    readonly property real _rowH: Math.round(_row * 2.4)
    readonly property real _rowGap: Math.max(3, Math.round(_row * 0.35))
    // The ping answer's own size. It is the row block's headline, so it is
    // scaled off the tile like the hero it stands under and not off the
    // row's small text: 27 px at 400x400, sitting in the 38 px row slot it
    // takes (the row's own text is 16), and 23 px at the small and wide
    // presets, where the node block itself does not exist - the same ratio
    // at every size, so it grows with the widget instead of stepping over
    // it.
    readonly property real _ping: Math.max(12, Math.round(_hero * 0.8))

    // ── State, as words ──────────────────────────────────────────────────
    // "Checking" and "Starting" are transient and read as quiet; the four
    // real not-connected states and an unreachable daemon read as faults.
    readonly property bool pending: !ts.loaded || ts.backendState === "Starting"
    readonly property bool faulted: ts.loaded && !ts.up && !full.pending
    readonly property bool warned: ts.health.length > 0

    readonly property color stateColor: ts.up
        ? colors.accent
        : (full.faulted ? colors.accentRed : colors.foreground)

    // Why the tile is not showing a connected tailnet. Never a blank tile:
    // every state has a sentence, and every sentence is short enough for the
    // 192 tile to say it under the state word (the daemon's own error
    // messages are the longest, and they are quoted verbatim).
    readonly property string reason: {
        if (ts.errorMessage !== "") return ts.errorMessage
        if (!ts.loaded) return "reading tailscaled"
        switch (ts.backendState) {
        case "Running":    return ""
        case "Stopped":    return "tailscaled stopped"
        case "NeedsLogin": return "not logged in"
        case "NoState":    return "no tailnet configured"
        case "Starting":   return "backend starting"
        }
        return ts.backendState !== "" ? ts.backendState : "no state reported"
    }

    // The hero's second line. The headline fact of a tailnet tile is the
    // connection - the state and how much of the tailnet is up - so the
    // address is NOT the hero at any size: it never told anyone whether the
    // tailnet was working. It lives in the small tile's footer and in an
    // Address row on the two larger ones.
    readonly property string heroCount: {
        if (!ts.loaded || !ts.up) return full.reason
        if (ts.peerCount === 0) return "no other nodes"
        return ts.onlineCount + "/" + ts.peerCount + " peers online"
    }

    // This machine's full MagicDNS name - what another node types to reach
    // it, and the identity worth carrying wherever there is room. Where it
    // does not fit it loses its middle, never its first label: the hostname
    // identifies the node, the suffix is the same on every node.
    readonly property string identity: ts.selfFqdn !== "" ? ts.selfFqdn : ts.selfName

    // Small tile: the node and its address, both quiet, on one footer line.
    // The short name here on purpose - an FQDN in 150 px is a suffix.
    readonly property string footerLine: {
        if (ts.selfIp === "") return ts.selfName
        if (ts.selfName === "") return ts.selfIp
        return ts.selfName + "  ·  " + ts.selfIp
    }

    // The exit node's own full name, taken from the peer that claims it;
    // `exitNodeName` is only the short form.
    readonly property string exitNodeFqdn: {
        for (var i = 0; i < ts.peers.length; i++)
            if (ts.peers[i].isExitNode)
                return String(ts.peers[i].fqdn || ts.peers[i].name)
        return ts.exitNodeName
    }

    // "Direct", "Relay", "Mixed", "Idle" - plus the region this machine calls
    // home. "home" is in the string on purpose: the home DERP is where this
    // node is reachable, not necessarily a relay carrying traffic.
    readonly property string pathText: {
        if (!ts.up) return "-"
        if (ts.homeRelayName === "") return ts.pathLabel
        return ts.pathLabel + "  ·  home " + ts.homeRelayName
    }

    readonly property bool funnelOpen: {
        for (var i = 0; i < ts.services.length; i++) if (ts.services[i].funnel) return true
        return false
    }
    readonly property string servicesText: {
        if (!ts.hasServices) return ""
        var base = ts.services.length === 1
            ? String(ts.services[0].label)
            : ts.services.length + " endpoints"
        return full.funnelOpen ? base + "  ·  Funnel" : base
    }

    // The rows, in priority order - faults first, because the large tile
    // only has room for two of them and a health warning outranks a word
    // the web is already drawing. tone: "a" = accent (a live fact),
    // "w" = warning, "" = plain. `left` marks a value that is a node's full
    // name, and `echo` a row that only repeats the hero.
    readonly property var facts: {
        var out = []
        if (!ts.loaded) {
            out.push({ label: "State", value: full.reason, tone: "",
                       left: false, echo: true })
            return out
        }
        if (ts.up) {
            for (var h = 0; h < ts.health.length && h < 2; h++)
                out.push({ label: "Health", value: String(ts.health[h]), tone: "w", left: false })
            // An exit node reroutes everything this machine sends, so it
            // ranks above the path word it explains - and it is a node, so
            // it is named in full.
            if (ts.exitNodeActive)
                out.push({ label: "Exit node", value: full.exitNodeFqdn, tone: "a", left: true })
            out.push({ label: "Path", value: full.pathText,
                       tone: ts.activeCount > 0 ? "a" : "", left: false })
            // The online/total count is the hero's second line now, so it is
            // not repeated as a row; the address takes its place.
            if (ts.selfIp !== "")
                out.push({ label: "Address", value: ts.selfIp, tone: "", left: false })
            if (ts.activeCount > 0)
                out.push({ label: "Live",
                           value: ts.relayCount === 0
                               ? ts.directCount + " direct"
                               : (ts.directCount === 0
                                   ? ts.relayCount + " relayed"
                                   : ts.directCount + " direct, " + ts.relayCount + " relayed"),
                           tone: "a", left: false })
            if (ts.hasServices)
                out.push({ label: "Serving", value: full.servicesText,
                           tone: full.funnelOpen ? "w" : "", left: false })
        } else {
            // The hero already carries the reason, so the rows carry what it
            // cannot: the warnings, the address this machine still holds, and
            // how big the tailnet it is not talking to is.
            for (var k = 0; k < ts.health.length && k < 2; k++)
                out.push({ label: "Health", value: String(ts.health[k]), tone: "w", left: false })
            if (ts.selfIp !== "")
                out.push({ label: "Address", value: ts.selfIp, tone: "", left: false })
            if (ts.peerCount > 0)
                out.push({ label: "Tailnet", value: ts.peerCount + " known nodes",
                           tone: "", left: false })
            // A machine that was never set up has no address, no peers and no
            // warnings - so the state itself is the only row there is. It
            // echoes the hero, which is why the large tile filters it out
            // below rather than saying the same sentence three times.
            if (out.length === 0)
                out.push({ label: full.pending ? "State" : "Offline",
                           value: full.reason, tone: full.pending ? "" : "w",
                           left: false, echo: true })
        }
        return out
    }

    // The large tile drops the rows its own picture already carries: which
    // sessions are live is what the accented links in the web mean, and the
    // reason is already the line under the state word. Its two rows go to
    // facts that are nowhere else - a health warning, an exit node, the
    // path, the address.
    readonly property var visibleFacts: {
        if (!full.isBig) return full.facts
        var out = []
        for (var i = 0; i < full.facts.length; i++) {
            var f = full.facts[i]
            if (f.label === "Live" || f.echo === true) continue
            out.push(f)
        }
        return out
    }

    function toneColor(tone) {
        if (tone === "a") return colors.accent
        if (tone === "w") return colors.accentRed
        return colors.foreground
    }

    // ── The ping answer, as words ────────────────────────────────────────
    // The one node the last ping is about: the target while it is in
    // flight, the result's owner once it answers. TailscaleData holds one
    // ping at a time, so this is the node whose block carries the answer -
    // and what keeps that block standing, pointer or no pointer.
    readonly property string pingNodeId: ts.pinging ? ts.pingTarget : ts.pingResultId
    // What that ping said, finished: "pinging…" while it is out, the
    // measurement with the way it travelled when it answers, the daemon's
    // own words when it fails - plus whether it is a fault. Written by
    // _syncPing() and by nothing else; the readout below binds to it and no
    // painter recomputes it.
    property string pingText: ""
    property bool pingBad: false

    // The one place the answer is put into words. Runs when a ping starts,
    // when it answers, and when the map rebuilds (the error is cut to the
    // width it will land in, which a resize changes) - never on a frame,
    // and never on a hover.
    function _syncPing() {
        if (ts.pinging) {
            full.pingText = "pinging…"
            full.pingBad = false
            return
        }
        if (ts.pingResultId === "") {
            full.pingText = ""
            full.pingBad = false
            return
        }
        if (ts.pingMs > 0) {
            var t = ts.pingMs >= 1000
                ? (ts.pingMs / 1000).toFixed(1) + " s"
                : Math.round(ts.pingMs) + " ms"
            var v = ts.pingVia
            full.pingText = v === "direct"
                ? t + " direct"
                : (v.indexOf("derp ") === 0 ? t + " via DERP " + v.substring(5) : t)
            full.pingBad = false
        } else {
            // The daemon's own words, cut to what fits.
            full.pingText = web.clipLabel(ts.pingError !== "" ? ts.pingError : "no answer",
                                          rows.width, full._ping)
            full.pingBad = true
        }
    }

    // ── The hovered node, as rows ────────────────────────────────────────
    // A hover readout goes into the fact rows this tile already draws, NOT
    // into a floating tooltip: a tooltip over a 400 px map covers the thing
    // it is describing, and this tile already has a vocabulary for "a label
    // and a value". While the pointer is on a node its two rows stand in for
    // the two facts, and the facts come straight back when it leaves - two
    // rows either way, in a slot that reserves two rows' height, so the map
    // above never moves. Empty at every other size, and at 400x400 whenever
    // neither the pointer nor a ping names a node - which is what the
    // launcher preview (no pointer, ever) gets.
    //
    // Four facts, four slots, nothing sharing a value with anything else:
    // the OS names the node's row, the tailnet address names the path's, and
    // the two values are the two long strings - the MagicDNS name, which
    // loses its middle, and the path, which loses its tail. Packing them as
    // "a · b · c" instead cost the address and the OS to elision the moment
    // a peer answered on an IPv6 endpoint, which is most of them.
    readonly property var focusFacts: {
        if (!full.isBig || !full.webReady) return []
        if (web.hoverSelf) {
            return [
                { label: ts.selfOs !== "" ? ts.selfOs : "This machine",
                  value: full.identity, tone: "a", left: true },
                { label: ts.selfIp !== "" ? ts.selfIp : "Path",
                  value: ts.homeRelayName !== "" ? "home " + ts.homeRelayName
                                                 : "no home region",
                  tone: "", left: false }
            ]
        }
        // The pointer first, so moving it always answers the pointer. With
        // the pointer away the block names the node the last ping measured
        // instead, which is what keeps that node's answer on screen once the
        // pointer has left - and the answer then takes the block's second
        // row, where its address and path normally sit (see `pingOnBlock`).
        var id = web.hoverId !== "" ? web.hoverId : full.pingNodeId
        if (id === "") return []
        for (var i = 0; i < ts.peers.length; i++) {
            var p = ts.peers[i]
            if (String(p.id) !== id) continue
            return [
                { label: p.os !== "" ? p.os : "Node",
                  value: String(p.fqdn !== "" ? p.fqdn : p.name),
                  tone: "a", left: true },
                { label: p.ip !== "" ? p.ip : "Path",
                  value: full._peerPath(p),
                  tone: p.active ? "a" : (p.online ? "" : "w"), left: false }
            ]
        }
        return []
    }

    // True while the row block under the map is the pinged node's own block:
    // the pointer is on it, or the pointer is away and the block fell back to
    // it. The answer then takes that block's second row - the slot the node's
    // address and path normally fill - so it sits directly under the row that
    // names the node, and the block keeps the height the map was laid out
    // against. A row of its own instead would cost the map `_rowH + _rowGap`
    // (44 of its 159 px at 400x400), and it would stand empty whenever the
    // pointer brought any other node's block up.
    readonly property bool pingOnBlock: full.pingText !== "" && !web.hoverSelf
        && full.focusFacts.length > 0
        && (web.hoverId === "" || web.hoverId === full.pingNodeId)

    // The four honest answers to "how is this machine reaching that one":
    // a direct path and where to, a relay and which region, nothing right
    // now, or not at all - and when it was last seen. A peer's endpoint is
    // the one thing here that is not on the tile at rest: it is what
    // "direct" MEANS, and it is shown only to a pointer that asked for it.
    function _peerPath(p) {
        if (!p.online) {
            var ago = full._ago(String(p.lastSeen || ""))
            return ago === "" ? "offline" : "offline, last seen " + ago
        }
        if (!p.active) return "idle"
        if (p.direct) return p.endpoint !== "" ? "direct " + p.endpoint : "direct"
        var region = p.relayName !== "" ? p.relayName : p.relay
        return region !== "" ? "via DERP " + region : "via DERP"
    }

    // "20m ago". Tailscale writes a zero timestamp for a peer it has never
    // seen, and that is not "two thousand years ago", it is nothing to say.
    function _ago(iso) {
        if (iso === "") return ""
        var t = Date.parse(iso)
        if (isNaN(t) || t < 946684800000) return ""
        var s = (Date.now() - t) / 1000
        if (s < 60) return "just now"
        if (s < 5400) return Math.round(s / 60) + "m ago"
        if (s < 172800) return Math.round(s / 3600) + "h ago"
        return Math.round(s / 86400) + "d ago"
    }

    // The web draws itself only when there is a tailnet to draw. What takes
    // its place says something the hero has not already said: a tailnet of
    // one needs explaining, and a machine that is down but still has a name
    // gets its reason here (when it has no name either, the hero is already
    // carrying the reason and this stays empty rather than repeating it).
    readonly property bool webReady: ts.up && ts.peerCount > 0
    readonly property string webMessage: ts.up
        ? "This machine is the only node on the tailnet"
        : (full.identity !== "" ? full.reason : "")

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
        anchors.margins: full._pad

        // The hero column shares the tile with the facts panel when wide.
        readonly property real heroWidth: full.isWide
            ? Math.round(width * 0.46)
            : width

        // ── Header: TAILSCALE, the state dot, the health dot ─────────────
        Row {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            spacing: Math.round(full._label * 0.5)

            Text {
                text: "TAILSCALE"
                color: colors.foreground
                opacity: 0.6
                font.family: colors.uiFont
                font.pixelSize: full._label
                font.letterSpacing: full._label * 0.12
            }
            // Connected, transient, or faulted - the one mark that is always
            // on screen, at every size.
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(full._label * 0.62)
                height: width
                radius: width / 2
                color: full.stateColor
                opacity: full.pending ? 0.45 : 1.0
            }
            // tailscaled raised a health warning: never silent, even on the
            // small tile where there is no row to spell it out.
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(full._label * 0.44)
                height: width
                radius: width / 2
                visible: full.warned
                color: colors.accentRed
            }
        }

        // ── Hero: the state, then how much of the tailnet is up ──────────
        // The address is deliberately NOT the headline here - see the
        // `heroCount` comment: an IP says nothing about whether the tailnet
        // is working, and this tile's job is to answer exactly that.
        Column {
            id: heroCol
            anchors.top: header.bottom
            anchors.topMargin: Math.round(full._label * 0.35)
            anchors.left: parent.left
            width: full.isBig
                ? Math.round(content.width - peerBadge.width - full._label)
                : content.heroWidth
            spacing: 0

            Text {
                width: parent.width
                text: ts.stateLabel
                color: full.faulted ? colors.accentRed : colors.foreground
                opacity: full.pending ? 0.55 : 1.0
                font.family: colors.uiFont
                font.pixelSize: full._hero
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 11
                elide: Text.ElideRight
            }
            // On the large tile the count is the number beside the hero, so
            // this line carries this machine's full MagicDNS name instead -
            // once, right above the map every link is measured from. A name
            // that is too long loses its MIDDLE, never its first label: the
            // hostname is the part that identifies the node, the suffix is
            // the same on every node in the tailnet.
            Text {
                width: parent.width
                text: full.isBig
                    ? (full.identity !== "" ? full.identity : full.reason)
                    : full.heroCount
                color: colors.foreground
                opacity: full.isBig ? 0.5 : (ts.up ? 0.9 : 0.55)
                elide: Text.ElideMiddle
                // A daemon error is the longest thing this line ever says;
                // shrink to fit rather than cut a sentence in half.
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 10
                font.family: colors.uiFont
                font.pixelSize: Math.round(full._label * (full.isBig ? 1.0 : 1.15))
            }
        }

        // ── The tailnet as dots (small and wide tiles) ───────────────────
        // The band under the hero would otherwise be empty, and one dot per
        // node is the same language the large tile's web speaks: accent for a
        // live session, solid for online, faint for offline. The order is the
        // data layer's own sort, so it reads left to right as live, then up,
        // then down, and it does not reshuffle between refreshes.
        Row {
            id: peerStrip
            visible: !full.isBig && ts.peerCount > 0
                     && content.height > full._label * 7
            anchors.left: parent.left
            anchors.top: heroCol.bottom
            anchors.topMargin: Math.round(full._label * 0.95)
            spacing: Math.round(full._label * 0.3)

            readonly property real dot: Math.max(4, Math.round(full._label * 0.42))
            readonly property real avail: full.isWide ? content.heroWidth : content.width
            readonly property int cap: Math.max(4, Math.floor(avail / (dot + spacing)))
            readonly property int extra: Math.max(0, ts.peerCount - cap)

            Repeater {
                model: ts.peers.slice(0, peerStrip.cap)

                delegate: Rectangle {
                    required property var modelData

                    width: peerStrip.dot
                    height: peerStrip.dot
                    radius: width / 2
                    color: modelData.active ? colors.accent : colors.foreground
                    opacity: modelData.active ? 1.0 : (modelData.online ? 0.55 : 0.18)
                }
            }

            Text {
                visible: peerStrip.extra > 0
                text: "+" + peerStrip.extra
                color: colors.foreground
                opacity: colors.textQuiet
                font.family: colors.uiFont
                font.pixelSize: Math.round(full._label * 0.8)
            }
        }

        // ── Large tile: the peer count as a number ───────────────────────
        Column {
            id: peerBadge
            visible: full.isBig
            anchors.top: heroCol.top
            anchors.right: parent.right
            width: visible ? Math.max(countText.implicitWidth, countLabel.implicitWidth) : 0
            spacing: 0

            Text {
                id: countText
                anchors.right: parent.right
                text: ts.loaded ? ts.onlineCount + "/" + ts.peerCount : "--"
                color: colors.foreground
                opacity: ts.loaded ? 1.0 : 0.5
                font.family: colors.uiFont
                font.pixelSize: Math.round(full._hero * 1.05)
            }
            Text {
                id: countLabel
                anchors.right: parent.right
                text: "peers online"
                color: colors.foreground
                opacity: colors.textQuiet
                font.family: colors.uiFont
                font.pixelSize: Math.round(full._label * 0.9)
            }
        }

        // ── The quiet line at the foot of the tile ───────────────────────
        // Small: the node and its tailnet address, the two details the hero
        // gave up. Wide: the full MagicDNS name, which the hero column has
        // the width for and the small tile does not (at 150 px an FQDN is
        // mostly suffix, so the small tile keeps the short name).
        Text {
            id: peerFooter
            visible: !full.isBig
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: full.isWide ? content.heroWidth : content.width
            elide: full.isWide ? Text.ElideMiddle : Text.ElideRight
            text: full.isWide ? full.identity : full.footerLine
            color: colors.foreground
            opacity: 0.5
            font.family: colors.uiFont
            font.pixelSize: Math.round(full._label * 0.95)
            // The line names the node and then its address, and both halves
            // are digits or a hostname - there is nothing in either that
            // survives being cut. In system-font mode the small tile's
            // "node  ·  100.x.y.z" measures 185.1 px in the 150 px it has, so
            // it loses the last octet; the wide tile's full MagicDNS name
            // ("node.tailnet.ts.net") is 169.0 in 165.0 and loses the tailnet
            // suffix. Shrink into the box first and let `elide` be the last
            // resort - the same rule network's rows carry (PORTING.md item 9).
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: Math.max(8, Math.round(full._label * 0.7))
        }

        // ── The node web ─────────────────────────────────────────────────
        // This machine at the centre, the tailnet around it, on a fixed
        // ellipse: the same peers always land in the same places, because
        // the order comes from TailscaleData's sort and the angles come from
        // the count. No simulation, no jitter, and no per-frame work - the
        // geometry is rebuilt only when the size, the peer list or the font
        // changes (AGENTS.md's Canvas convention, as in TickRing's _rebuild).
        //
        // Link styles, and they are the honest facts and nothing more:
        //   solid accent        a live session carried peer-to-peer
        //   dashed accent       a live session carried by a DERP relay
        //   hairline separator  online, no session right now - the normal
        //                       state of a tailnet at rest
        //   dotted, very faint  offline
        Canvas {
            id: web
            visible: full.isBig && full.webReady
            // MEASURED TRAP, left in place on purpose. This slot is anchored
            // `top: heroCol.bottom` against `bottom: facts.top`, and in the
            // WIDE layout `facts` pins itself to the TILE top
            // (`facts._reanchor()` assigns `anchors.top = parent.top` and
            // releases the bottom), so on 400x192 the two anchors cross and
            // the height goes negative: measured Canvas w=358 h=-91, its
            // Loader h=-91, and `webEmpty` below w=358 h=-77.
            //
            // Inherent, not a resize artefact - the controls that established
            // it: creating the tile directly at 400x192 and resizing it to
            // the SAME size both reproduce h=-91 exactly, while 160x120 and
            // 400x400 created at size measure clean.
            //
            // Nothing paints today only because this slot is `visible:
            // full.isBig` (400x192 is wide, not big) and an invisible item
            // draws no child. Making this slot visible without re-anchoring
            // surfaces it, and so does moving `facts` back to a bottom
            // anchor. Not fixed here because re-anchoring this machinery is
            // what produced the released-anchor bug `_reanchor()` documents.
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: heroCol.bottom
            anchors.topMargin: Math.round(full._label * 0.5)
            anchors.bottom: facts.top
            anchors.bottomMargin: Math.round(full._label * 0.5)

            // Colours are looked up in the paint, so a theme change is a
            // repaint and never a rebuild.
            readonly property color ink: colors.foreground
            readonly property color live: colors.accent
            readonly property color hair: colors.separator
            readonly property color selfInk: full.stateColor
            readonly property color warn: colors.accentRed

            readonly property real nodeFont: Math.max(9, Math.round(full._label * 0.62))
            readonly property real lineH: Math.round(nodeFont * 1.2)
            readonly property string nodeFamily: colors.uiFont !== "" ? colors.uiFont : "sans-serif"

            // ── The only things the painter reads ────────────────────────
            // One peer per entry, in Canvas pixels:
            //   { id, name, x, y, r, online, active, direct, relayName,
            //     style, halo, label, lx, ly, align, x0, y0, x1, y1,
            //     dash, lineWidth }
            // The first nine are the node and its facts; the rest is the
            // geometry `_rebuild()` worked out for it - the link's trimmed
            // endpoints included - so a later layer can move a node's x/y,
            // fix up its x1/y1 and call requestPaint() without opening the
            // painter at all.
            property var _nodes: []
            // This machine. Always the centre, because every fact the data
            // layer has - direct, relay, endpoint, rx, tx - is measured from
            // here, so a link means "a path from this machine" and nothing
            // else would be true.
            property var _center: ({ x: 0, y: 0, r: 0, halo: 0,
                                     label: "", lx: 0, ly: 0 })
            // { text, x, y } when the tailnet is bigger than the cap.
            property var _more: null

            // ── What the pointer is doing ────────────────────────────────
            // Read by the paint, written by the MouseArea below. All of it
            // is per-session: a pin is a thing you did to this tile just
            // now, not a setting, and nothing here reaches the store.
            property string hoverId: ""     // peer id under the pointer
            property bool hoverSelf: false  // ... or the centre node
            property string dragId: ""      // peer id being dragged
            // id -> { fx, fy }, canvas fractions, so a pin survives a resize
            // and a peer-list rebuild.
            property var pins: ({})
            // The wheel's ring scale, clamped to the contract's 0.6x - 1.4x.
            property real spread: 1.0
            onSpreadChanged: web._rebuild()
            // How long a released node takes to fall back to its home.
            readonly property int settleMs: 350

            function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

            // Canvas has no eliding, and measureText needs a live context, so
            // the budget is a character count from the font's average advance.
            // (Not named `clip`: that is Item's own property.)
            function clipLabel(s, avail, px) {
                var max = Math.floor(avail / (px * 0.56))
                if (max < 3) return ""
                if (s.length <= max) return s
                return s.substring(0, max - 1) + "…"
            }

            function radiusFor(p, px) {
                if (p.active) return px * 0.44
                return p.online ? px * 0.34 : px * 0.27
            }

            // Every number the paint uses is computed here, on a size, peer
            // or font change - never per frame (AGENTS.md's Canvas rule, the
            // shape clock-square's TickRing._rebuild() set).
            function _rebuild() {
                var w = web.width
                var h = web.height
                if (w <= 8 || h <= 8) { web._nodes = []; web._more = null; return }

                var peers = ts.peers
                // More nodes than the labels can survive: draw the leading
                // ones (live sessions first, then online - that is the data
                // layer's sort) and count the rest off in the corner.
                var cap = 16
                var n = Math.min(peers.length, cap)

                // What the pointer had hold of before this rebuild. `peers`
                // is replaced whenever status is re-read - which a ping does
                // on purpose, right after you clicked a node - so a node
                // being dragged, a node mid-spring and a pinned node keep
                // their position across the rebuild. Everything else goes
                // to its computed home.
                var prev = {}
                for (var q = 0; q < web._nodes.length; q++) prev[web._nodes[q].id] = web._nodes[q]

                var px = web.nodeFont
                var lineH = web.lineH
                var cx = w / 2
                var cy = h / 2
                var selfR = px * 0.62
                // Room reserved outside the ellipse for the labels.
                var side = Math.max(px * 3.4, w * 0.16)
                var rx = Math.max(px * 2.0, cx - side)
                var ry = Math.max(px * 1.6, cy - lineH * 1.5)
                if (ry > rx) ry = rx
                // The wheel's spread, clamped so even 1.4x keeps every dot
                // on the canvas: it is the labels that give up room, not the
                // nodes that walk off the tile.
                rx = Math.min(Math.max(rx * web.spread, px * 1.2), cx - px * 0.9)
                ry = Math.min(Math.max(ry * web.spread, px * 1.0), cy - px * 0.9)

                var gap = Math.round(px * 0.85)
                var hair = Math.max(1, px * 0.09)
                var settling = false
                var out = []
                for (var i = 0; i < n; i++) {
                    var p = peers[i]
                    var a = -Math.PI / 2 + (i * 2 * Math.PI / n)
                    // Home: where this node belongs when nothing is holding
                    // it, and where the spring aims.
                    var hx = cx + Math.cos(a) * rx
                    var hy = cy + Math.sin(a) * ry
                    var r = web.radiusFor(p, px)
                    var style = p.active ? (p.direct ? "direct" : "relay")
                                         : (p.online ? "idle" : "off")

                    // Near the poles the label goes above or below, because
                    // horizontal text beside a pole node runs into its
                    // neighbours; elsewhere it goes outward, left or right.
                    var place = Math.abs(Math.cos(a)) < 0.30
                        ? (Math.sin(a) < 0 ? "top" : "bottom")
                        : (Math.cos(a) > 0 ? "right" : "left")

                    var lx = hx
                    var ly = hy
                    var avail
                    if (place === "right") {
                        lx = hx + r + gap
                        avail = w - lx - 2
                    } else if (place === "left") {
                        lx = hx - r - gap
                        avail = lx - 2
                    } else {
                        avail = Math.min(lx, w - lx) * 2 - 4
                        ly = place === "top" ? hy - r - lineH * 0.7 : hy + r + lineH * 0.7
                    }

                    // Where it actually sits right now.
                    var id = String(p.id)
                    var old = prev[id]
                    var pin = web.pins[id]
                    var x = hx
                    var y = hy
                    var live = false
                    if (pin) {
                        x = Math.max(r, Math.min(w - r, pin.fx * w))
                        y = Math.max(r, Math.min(h - r, pin.fy * h))
                    } else if (old && (id === web.dragId || old.settling)) {
                        x = old.x
                        y = old.y
                        live = !!old.settling
                    }
                    if (live) settling = true

                    out.push({
                        // The node and its facts.
                        id: id,
                        // The SHORT name here: a full MagicDNS name on every
                        // node would be thirteen copies of the same suffix.
                        // The tile carries the FQDN once, above the map, and
                        // once more in the row a hover fills in.
                        name: String(p.name),
                        x: x, y: y, r: r,
                        hx: hx, hy: hy,
                        online: !!p.online,
                        active: !!p.active,
                        // Only meaningful while active - an idle peer's relay
                        // is its home region, not a path in use.
                        direct: !!p.direct,
                        relayName: String(p.relayName || ""),
                        // The geometry.
                        style: style,
                        halo: p.active ? r * 2.1 : 0,
                        label: web.clipLabel(String(p.name), avail, px),
                        lx: lx, ly: ly, place: place,
                        // The label's offset from home, so a node that moves
                        // carries its own name instead of leaving it behind.
                        ldx: 0, ldy: 0,
                        align: place === "right" ? "left"
                             : (place === "left" ? "right" : "center"),
                        x0: 0, y0: 0, x1: 0, y1: 0,
                        // Pointer state, carried across this rebuild.
                        pinned: !!pin,
                        settling: live,
                        sx: live ? old.sx : x,
                        sy: live ? old.sy : y,
                        st: live ? old.st : 0,
                        dash: style === "relay" ? [px * 0.5, px * 0.42]
                            : (style === "off" ? [1, px * 0.34] : []),
                        lineWidth: style === "direct" ? Math.max(1.4, px * 0.15)
                                 : (style === "relay" ? Math.max(1.2, px * 0.13) : hair)
                    })
                }

                // Safety net: at 13 nodes the outward labels clear each other
                // on their own, but a fuller tailnet, a squat tile or a
                // contracted ring can close the gap, so each side's stack is
                // spread apart. Labels are placed from HOME, so they do not
                // reshuffle while a node is being dragged around.
                web._declutter(out, "right", lineH, h)
                web._declutter(out, "left", lineH, h)
                for (var j = 0; j < out.length; j++)
                    out[j].ly = Math.max(lineH * 0.6, Math.min(h - lineH * 0.6, out[j].ly))

                web._center = {
                    x: cx, y: cy, r: selfR, halo: selfR * 2.0,
                    label: web.clipLabel(ts.selfName, rx - selfR, px),
                    lx: cx, ly: cy + selfR * 2.0 + lineH * 0.9
                }
                web._nodes = out

                // The label offsets and the links, trimmed clear of both
                // dots - `_place` is the very same call a drag frame makes.
                for (var k = 0; k < out.length; k++) {
                    out[k].ldx = out[k].lx - out[k].hx
                    out[k].ldy = out[k].ly - out[k].hy
                    web._place(out[k])
                }

                web._more = peers.length > n
                    ? { text: "+" + (peers.length - n) + " more",
                        x: w - 1, y: h - lineH * 0.5 }
                    : null
                // Ends in requestPaint(), so there is exactly one repaint
                // for a rebuild. `_syncPing` re-cuts a failed answer to the
                // width it has now; the answer itself is not on the map.
                full._syncPing()
                web.requestPaint()
                // A node that was still falling when the list changed keeps
                // falling - to its new home.
                if (settling) settleClock.start()
            }

            // A node's link endpoints, trimmed clear of both dots.
            // Public on purpose: move a node and call this, then
            // requestPaint(). `_place` below does both.
            function _link(node, cx, cy, selfR) {
                var dx = node.x - cx
                var dy = node.y - cy
                var len = Math.sqrt(dx * dx + dy * dy)
                if (len < 1) {
                    node.x0 = cx; node.y0 = cy; node.x1 = cx; node.y1 = cy
                    return
                }
                var ux = dx / len
                var uy = dy / len
                node.x0 = cx + ux * (selfR + 2)
                node.y0 = cy + uy * (selfR + 2)
                node.x1 = node.x - ux * (node.r + 2)
                node.y1 = node.y - uy * (node.r + 2)
            }

            // A node has moved: its label follows it and its link is re-cut.
            // This is the only arithmetic that runs per frame, it runs for
            // ONE node, and only while a pointer is dragging or a spring is
            // settling.
            function _place(node) {
                node.lx = node.x + node.ldx
                node.ly = node.y + node.ldy
                web._link(node, web._center.x, web._center.y, web._center.r)
            }

            function _declutter(list, place, lineH, h) {
                var idx = []
                for (var i = 0; i < list.length; i++)
                    if (list[i].place === place) idx.push(i)
                if (idx.length < 2) return
                idx.sort(function (a, b) { return list[a].ly - list[b].ly })

                var top = lineH * 0.6
                var room = h - lineH * 1.2
                if ((idx.length - 1) * lineH > room) {
                    // Too many for one-line spacing: share the height evenly.
                    var step = room / (idx.length - 1)
                    for (var e = 0; e < idx.length; e++) list[idx[e]].ly = top + step * e
                    return
                }
                for (var k = 0; k < idx.length; k++) {
                    var cur = list[idx[k]]
                    if (k === 0) { if (cur.ly < top) cur.ly = top; continue }
                    var prev = list[idx[k - 1]]
                    if (cur.ly - prev.ly < lineH) cur.ly = prev.ly + lineH
                }
                var over = list[idx[idx.length - 1]].ly - (h - top)
                if (over > 0)
                    for (var m = 0; m < idx.length; m++) list[idx[m]].ly -= over
            }

            // Draw only: no geometry, no `ts.peers`, no per-frame maths. The
            // hover id is the one piece of pointer state it reads, and it
            // reads it as a comparison, not as a calculation.
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                if (width <= 0 || height <= 0) return

                var nodes = web._nodes
                var c = web._center
                var hot = web.hoverId
                ctx.lineCap = "round"

                // Links first, so every dot sits on top of its own line.
                for (var i = 0; i < nodes.length; i++) {
                    var nd = nodes[i]
                    web.dash(ctx, nd.dash)
                    if (nd.id === hot) {
                        // Hover is weight and colour, never an outline: the
                        // one link comes forward in the accent and every
                        // other line keeps its resting separator grey.
                        ctx.lineWidth = Math.max(nd.lineWidth, web.nodeFont * 0.16)
                        ctx.strokeStyle = web.live
                    } else {
                        ctx.lineWidth = nd.lineWidth
                        if (nd.style === "direct")     ctx.strokeStyle = web.alpha(web.live, 0.95)
                        else if (nd.style === "relay") ctx.strokeStyle = web.alpha(web.live, 0.85)
                        else if (nd.style === "idle")  ctx.strokeStyle = web.alpha(web.hair, 0.75)
                        else                           ctx.strokeStyle = web.alpha(web.hair, 0.32)
                    }
                    ctx.beginPath()
                    ctx.moveTo(nd.x0, nd.y0)
                    ctx.lineTo(nd.x1, nd.y1)
                    ctx.stroke()
                }
                web.dash(ctx, [])

                // Peers: soft filled dots, with a halo on the live ones, on
                // the hovered one, and a ring around the pinned ones.
                for (var j = 0; j < nodes.length; j++) {
                    var p = nodes[j]
                    var isHot = p.id === hot
                    var halo = p.halo > 0 ? p.halo : ((isHot || p.pinned) ? p.r * 2.1 : 0)
                    if (halo > 0) {
                        ctx.fillStyle = web.alpha(web.live, isHot ? 0.28 : 0.20)
                        ctx.beginPath()
                        ctx.arc(p.x, p.y, halo, 0, Math.PI * 2)
                        ctx.fill()
                    }
                    ctx.fillStyle = (p.active || isHot || p.pinned)
                        ? web.live
                        : web.alpha(web.ink, p.online ? 0.80 : 0.28)
                    ctx.beginPath()
                    ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2)
                    ctx.fill()
                    // Pinned: filled, and ringed, so "I put this one here"
                    // is legible without a word saying so.
                    if (p.pinned) {
                        ctx.lineWidth = Math.max(1, web.nodeFont * 0.1)
                        ctx.strokeStyle = web.alpha(web.live, 0.9)
                        ctx.beginPath()
                        ctx.arc(p.x, p.y, p.r + Math.max(2.5, web.nodeFont * 0.24), 0, Math.PI * 2)
                        ctx.stroke()
                    }
                }

                // This machine: bigger, ringed, and carrying the state colour.
                ctx.fillStyle = web.hoverSelf
                    ? web.alpha(web.live, 0.24)
                    : web.alpha(web.ink, 0.16)
                ctx.beginPath()
                ctx.arc(c.x, c.y, c.halo, 0, Math.PI * 2)
                ctx.fill()
                ctx.fillStyle = web.selfInk
                ctx.beginPath()
                ctx.arc(c.x, c.y, c.r, 0, Math.PI * 2)
                ctx.fill()

                // Labels last.
                ctx.font = web.nodeFont + "px \"" + web.nodeFamily + "\""
                ctx.textBaseline = "middle"
                for (var k = 0; k < nodes.length; k++) {
                    var q = nodes[k]
                    if (q.label === "") continue
                    ctx.textAlign = q.align
                    ctx.fillStyle = (q.id === hot || q.active)
                        ? web.live
                        : web.alpha(web.ink, q.online ? 0.72 : 0.36)
                    ctx.fillText(q.label, q.lx, q.ly)
                }

                if (c.label !== "") {
                    ctx.textAlign = "center"
                    ctx.fillStyle = web.selfInk
                    ctx.fillText(c.label, c.lx, c.ly)
                }

                if (web._more !== null) {
                    ctx.textAlign = "right"
                    ctx.fillStyle = web.alpha(web.ink, 0.5)
                    ctx.fillText(web._more.text, web._more.x, web._more.y)
                }
            }

            function dash(ctx, pattern) {
                if (typeof ctx.setLineDash === "function") ctx.setLineDash(pattern)
            }

            // ── The pointer ─────────────────────────────────────────────
            // Every function below runs because a pointer did something.
            // None of them is on a clock except `_settleStep`, and that one
            // turns itself off.

            function _at(id) {
                var nodes = web._nodes
                for (var i = 0; i < nodes.length; i++) if (nodes[i].id === id) return nodes[i]
                return null
            }

            // The nearest node under the pointer, or null. Generous by half
            // a font: an offline dot is 4 px across, and a 4 px target is
            // not a target.
            function _hitNode(mx, my) {
                var nodes = web._nodes
                var best = null
                var bestD = 0
                for (var i = 0; i < nodes.length; i++) {
                    var nd = nodes[i]
                    var dx = mx - nd.x
                    var dy = my - nd.y
                    var d = dx * dx + dy * dy
                    var reach = Math.max(nd.r + web.nodeFont * 0.55, 11)
                    if (d > reach * reach) continue
                    if (best === null || d < bestD) { best = nd; bestD = d }
                }
                return best
            }

            function _hitSelf(mx, my) {
                var c = web._center
                var dx = mx - c.x
                var dy = my - c.y
                var reach = Math.max(c.r + web.nodeFont * 0.55, 11)
                return dx * dx + dy * dy <= reach * reach
            }

            // One repaint per change of what is under the pointer - moving
            // across empty canvas costs a hit test and nothing else.
            function _hover(mx, my) {
                var nd = web._hitNode(mx, my)
                var id = nd !== null ? nd.id : ""
                var self = nd === null && web._hitSelf(mx, my)
                if (id === web.hoverId && self === web.hoverSelf) return
                web.hoverId = id
                web.hoverSelf = self
                web.requestPaint()
            }

            function _unhover() {
                if (web.hoverId === "" && !web.hoverSelf) return
                web.hoverId = ""
                web.hoverSelf = false
                web.requestPaint()
            }

            function _pinAt(nd) {
                var pins = web.pins
                pins[nd.id] = { fx: nd.x / web.width, fy: nd.y / web.height }
                web.pins = pins
            }

            function _drag(id, x, y) {
                var nd = web._at(id)
                if (nd === null) return
                nd.settling = false
                nd.x = Math.max(nd.r, Math.min(web.width - nd.r, x))
                nd.y = Math.max(nd.r, Math.min(web.height - nd.r, y))
                // A pinned node dragged elsewhere is pinned there instead.
                if (nd.pinned) web._pinAt(nd)
                web._place(nd)
                web.requestPaint()
            }

            function _spring(nd) {
                nd.sx = nd.x
                nd.sy = nd.y
                nd.st = Date.now()
                nd.settling = true
                settleClock.start()
            }

            function _release(id) {
                var nd = web._at(id)
                // Pinned is pinned: a release leaves it where the drag put
                // it. Everything else falls back to its computed home.
                if (nd !== null && !nd.pinned) web._spring(nd)
            }

            function _togglePin(id) {
                var nd = web._at(id)
                if (nd === null) return
                var pins = web.pins
                if (nd.pinned) {
                    delete pins[id]
                    web.pins = pins
                    nd.pinned = false
                    web._spring(nd)
                } else {
                    nd.pinned = true
                    nd.settling = false
                    web._pinAt(nd)
                }
                web.requestPaint()
            }

            // One frame of the spring-back. Ease-out over `settleMs`, and
            // rest is a POSITION, not a deadline: the moment a node is
            // inside half a pixel of home it is home, and when the last one
            // arrives the clock stops itself.
            function _settleStep() {
                var nodes = web._nodes
                var now = Date.now()
                var busy = false
                for (var i = 0; i < nodes.length; i++) {
                    var nd = nodes[i]
                    if (!nd.settling) continue
                    var t = (now - nd.st) / web.settleMs
                    if (t > 1) t = 1
                    var k = 1 - Math.pow(1 - t, 3)
                    var x = nd.sx + (nd.hx - nd.sx) * k
                    var y = nd.sy + (nd.hy - nd.sy) * k
                    if (t >= 1 || (Math.abs(nd.hx - x) < 0.5 && Math.abs(nd.hy - y) < 0.5)) {
                        x = nd.hx
                        y = nd.hy
                        nd.settling = false
                    } else {
                        busy = true
                    }
                    nd.x = x
                    nd.y = y
                    web._place(nd)
                }
                if (!busy) settleClock.stop()
                web.requestPaint()
            }

            // The tile went away - another workspace, or a resize to a size
            // with no map. Drop every pointer state and stop the clock;
            // an invisible tile must not be animating anything.
            function _rest() {
                settleClock.stop()
                web.hoverId = ""
                web.hoverSelf = false
                web.dragId = ""
                for (var i = 0; i < web._nodes.length; i++) web._nodes[i].settling = false
            }

            // The spring's clock, and the ONLY timer in this file. Started
            // by a release or an unpin, stopped by `_settleStep` the frame
            // everything has landed. A tile nobody is touching runs nothing.
            Timer {
                id: settleClock
                interval: 16
                repeat: true
                running: false
                onTriggered: web._settleStep()
            }

            // Input exists only where the map does. `web.visible` is
            // `isBig && webReady`, so at 192x192 and 400x192 this Loader
            // holds nothing and the tile carries no MouseArea at all. Where
            // it does exist it fills the MAP, which stops a fact row and a
            // margin short of the bottom-right resize grip, and it never
            // sees a right button - so move, resize and the settings sheet
            // are exactly as they were.
            //
            // In the launcher's preview the widget is scaled and gets no
            // pointer at all: this simply never fires, and nothing above
            // depends on it having fired.
            Loader {
                id: mapInput
                anchors.fill: parent
                active: web.visible
                sourceComponent: mapPointer
            }

            Component {
                id: mapPointer

                MouseArea {
                    id: area
                    anchors.fill: parent
                    // LEFT ONLY, deliberately: Placement.qml's move area
                    // takes RightButton and sits above this one, so a right
                    // press must never be accepted here.
                    acceptedButtons: Qt.LeftButton
                    hoverEnabled: true

                    property string pressId: ""
                    property string clickId: ""
                    property real pressX: 0
                    property real pressY: 0
                    property real grabDx: 0
                    property real grabDy: 0
                    property bool moved: false

                    onPositionChanged: function (mouse) {
                        if (area.pressed && area.pressId !== "") {
                            // A few pixels of slack, so a click that wobbles
                            // is still a click.
                            if (!area.moved
                                && Math.abs(mouse.x - area.pressX) < 4
                                && Math.abs(mouse.y - area.pressY) < 4) return
                            area.moved = true
                            web._drag(area.pressId, mouse.x + area.grabDx, mouse.y + area.grabDy)
                            return
                        }
                        web._hover(mouse.x, mouse.y)
                    }

                    onExited: web._unhover()

                    onPressed: function (mouse) {
                        area.moved = false
                        area.pressX = mouse.x
                        area.pressY = mouse.y
                        var nd = web._hitNode(mouse.x, mouse.y)
                        area.pressId = nd !== null ? nd.id : ""
                        if (nd === null) return
                        // Grab where it was taken, so the dot does not jump
                        // under the cursor on the first move.
                        area.grabDx = nd.x - mouse.x
                        area.grabDy = nd.y - mouse.y
                        web.dragId = nd.id
                        web._hover(mouse.x, mouse.y)
                    }

                    onReleased: {
                        web.dragId = ""
                        if (area.pressId !== "" && area.moved) web._release(area.pressId)
                    }

                    // A click that did not drag asks the data layer for one
                    // ping. It waits out the double-click window first, so
                    // pinning a node does not also spawn a process; a
                    // one-shot, started by a click, idle at every other
                    // moment. `clicked` is not emitted for the second click
                    // of a double click, which is what makes this work.
                    onClicked: {
                        if (area.pressId === "" || area.moved) return
                        area.clickId = area.pressId
                        pingDelay.restart()
                    }

                    onDoubleClicked: function (mouse) {
                        pingDelay.stop()
                        area.clickId = ""
                        var nd = web._hitNode(mouse.x, mouse.y)
                        if (nd !== null) web._togglePin(nd.id)
                    }

                    // The ring spreads and contracts under the wheel, so
                    // thirteen nodes can be pulled apart at 400 px. Accepted
                    // here, always, so it scrolls nothing else.
                    onWheel: function (wheel) {
                        var d = wheel.angleDelta.y
                        wheel.accepted = true
                        if (d === 0) return
                        web.spread = Math.min(1.4, Math.max(0.6,
                            web.spread * (d > 0 ? 1.08 : 1 / 1.08)))
                    }

                    Timer {
                        id: pingDelay
                        interval: 200
                        onTriggered: {
                            if (area.clickId === "") return
                            // The data layer owns the process, start to
                            // finish; this only asks.
                            ts.ping(area.clickId)
                            area.clickId = ""
                        }
                    }
                }
            }

            onWidthChanged: web._rebuild()
            onHeightChanged: web._rebuild()
            onVisibleChanged: {
                if (web.visible) web._rebuild()
                else web._rest()
            }
            Component.onCompleted: web._rebuild()

            Connections {
                target: ts
                function onPeersChanged() { web._rebuild() }
                function onSelfNameChanged() { web._rebuild() }
            }
            Connections {
                target: colors
                function onForegroundChanged() { web.requestPaint() }
                function onAccentChanged() { web.requestPaint() }
                function onSeparatorChanged() { web.requestPaint() }
            }
        }

        // Same slot as the web, for the tailnets that have no graph to draw:
        // logged out, stopped, unreachable, or a tailnet of one.
        Text {
            id: webEmpty
            visible: full.isBig && !full.webReady && full.webMessage !== ""
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: heroCol.bottom
            anchors.bottom: facts.top
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            text: full.webMessage
            color: colors.foreground
            opacity: colors.textQuiet
            font.family: colors.uiFont
            font.pixelSize: Math.round(full._label * 1.05)
        }

        // ── The facts: a right-hand column when wide, a footer when big ───
        // The wide tile shows facts rather than three of thirteen peers: at
        // 192 px tall only three rows fit, and three arbitrary hostnames say
        // less than the path, the count and what this machine serves. The
        // peers get their own picture on the large tile.
        Item {
            id: facts
            visible: full.isWide || full.isBig

            anchors.left: full.isWide ? heroCol.right : parent.left
            anchors.leftMargin: full.isWide ? Math.round(full._label) : 0
            anchors.right: parent.right
            // An anchor cannot be RELEASED from a binding: `x ? a : undefined`
            // leaves the last real anchor in place when the condition flips
            // back. Coming home from 400x192, `facts` therefore stayed pinned
            // to the top as well as the bottom, filled the tile, and the map -
            // which anchors to `facts.top` - collapsed to nothing. Assigning
            // `undefined` imperatively is the documented way to let one go, so
            // every anchor that switches with the layout is driven from here.
            readonly property bool wide: full.isWide
            function _reanchor() {
                facts.anchors.top = facts.wide ? parent.top : undefined
                rows.anchors.verticalCenter = facts.wide ? facts.verticalCenter : undefined
                rows.anchors.bottom = facts.wide ? undefined : facts.bottom
            }
            onWideChanged: facts._reanchor()
            Component.onCompleted: facts._reanchor()
            anchors.bottom: parent.bottom
            // Two rows' height, always, at 400x400: a hovered node replaces
            // the facts with its own two rows, and the map above must not
            // move a pixel when it does. The rows themselves stay anchored
            // to the bottom, so a tailnet with only one fact to state still
            // looks the way it did. The pinged node's answer is drawn in the
            // second of those two rows, which is why it costs the map no
            // height at all.
            readonly property real reservedH: full._rowH * 2 + full._rowGap
            height: full.isWide ? undefined : (full.isBig ? facts.reservedH : rows.height)

            // The large tile keeps two rows so the web gets the height; the
            // wide tile fills its column.
            readonly property int cap: full.isBig
                ? 2
                : Math.max(1, Math.floor(height / (full._rowH + full._rowGap)))

            Column {
                id: rows
                anchors.left: parent.left
                anchors.right: parent.right
                // verticalCenter / bottom are assigned by facts._reanchor(),
                // imperatively, for the reason spelled out there.
                spacing: full._rowGap

                Repeater {
                    // Hover fills these rows in with the node under the
                    model: full.focusFacts.length > 0
                        ? full.focusFacts
                        : full.visibleFacts.slice(0, facts.cap)

                    delegate: Item {
                        required property var modelData
                        required property int index

                        // The pinged node's own block: its answer takes this
                        // second row, right under the row that carries the
                        // node's identifier and its full MagicDNS name. The
                        // row's label and value stand down for it, so the
                        // answer gets the row's whole width and reads as the
                        // block's headline.
                        readonly property bool pingRow: full.pingOnBlock && index === 1

                        width: rows.width
                        height: full._rowH

                        Rectangle {
                            anchors.fill: parent
                            radius: height * 0.25
                            color: colors.cardBackground
                            opacity: colors.cardBackgroundOpacity
                        }

                        // The thin left pill: the row's own tone - and, on the
                        // ping row, the tone of the answer: the live accent
                        // for a measurement, the warning red for a failure.
                        // The same two the answer wore on the link.
                        Rectangle {
                            id: pill
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: Math.round(full._row * 0.5)
                            width: Math.max(2, Math.round(full._row * 0.18))
                            height: Math.round(parent.height * 0.52)
                            radius: width / 2
                            color: pingRow
                                ? (full.pingBad ? colors.accentRed : colors.accent)
                                : full.toneColor(modelData.tone)
                            opacity: (pingRow || modelData.tone !== "") ? 1.0 : 0.35
                        }

                        Text {
                            id: rowLabel
                            visible: !pingRow
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: pill.right
                            anchors.leftMargin: Math.round(full._row * 0.5)
                            text: modelData.label
                            color: colors.foreground
                            opacity: 0.6
                            font.family: colors.uiFont
                            font.pixelSize: full._row
                        }

                        Text {
                            visible: !pingRow
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            anchors.rightMargin: Math.round(full._row * 0.7)
                            anchors.left: rowLabel.right
                            anchors.leftMargin: Math.round(full._row * 0.6)
                            horizontalAlignment: Text.AlignRight
                            // A node's full name loses its MIDDLE, never its
                            // first label: the hostname identifies the node,
                            // and the tailnet suffix is the same on all of
                            // them, so cutting the tail is what a narrow
                            // column can afford.
                            elide: modelData.left ? Text.ElideMiddle : Text.ElideRight
                            text: modelData.value
                            color: full.toneColor(modelData.tone)
                            font.family: colors.uiFont
                            font.pixelSize: full._row
                            // The wide tile's facts column is 46% of the
                            // tile's width by design (the split network's
                            // tile shares, so two 400x192 System tiles read
                            // as one grid), which in system-font mode is
                            // 113.8 px for a value that measures 177.0 -
                            // "Direct  ·  home Riyadh" lost 63 px of itself
                            // and the address 23. The column cannot grow
                            // without breaking that shared split, so the
                            // value shrinks into it first and elides only
                            // past the 8 px floor; in the SF Pro Display cut
                            // this was measured against, every value fits and
                            // nothing moves.
                            fontSizeMode: Text.HorizontalFit
                            minimumPixelSize: Math.max(8, Math.round(full._row * 0.62))
                        }

                        // The answer itself, in the row the address and path
                        // normally fill: the block's headline, immediately
                        // under the row that names the node and its full
                        // MagicDNS name. Its size comes off the tile (`_ping`,
                        // scaled like the hero) and not off the row's text, so
                        // it grows with the widget; it is one line, so it
                        // holds to the same discipline as every value here -
                        // shrink into the row first, elide only past a floor
                        // that never drops below the row's own text.
                        Text {
                            visible: pingRow
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: rowLabel.left
                            anchors.right: parent.right
                            anchors.rightMargin: Math.round(full._row * 0.7)
                            text: full.pingText
                            color: full.pingBad ? colors.accentRed : colors.accent
                            font.family: colors.uiFont
                            font.pixelSize: full._ping
                            elide: Text.ElideRight
                            fontSizeMode: Text.HorizontalFit
                            minimumPixelSize: Math.max(full._row, Math.round(full._ping * 0.62))
                        }
                    }
                }
            }
        }
    }
}
