import QtQuick
import Quickshell
import Quickshell.Io

// The tailnet, as numbers and short strings.
//
// Where this comes from, and why not from the plugin next door
// ------------------------------------------------------------
// `omarchy.tailscale` (the first-party panel plugin) exists and is enabled on
// this machine, but its manifest declares `kinds: ["bar-widget"]` only - no
// service entry point - so `shell.serviceFor(...)` is null and its Service.qml
// is a private child of its own Panel. Same shape as the weather and prayer
// plugins (PORTING.md item 17), same fix: go to the source those plugins go
// to. Nothing here depends on that plugin being installed, enabled, or
// running.
//
// The source is the `tailscale` CLI. This file used to curl tailscaled's
// LocalAPI over /run/tailscale/tailscaled.sock directly; the CLI prints the
// same documents, which is what the first-party plugin reads, and one data
// path beats two. Three one-shot reads, all polled:
//
//   status     `tailscale status --json` - the /status document: backend
//              state, self, every peer, health warnings.
//   serve      `tailscale serve status --json` - the /serve-config document:
//              what this machine serves on the tailnet, Funnel included.
//   derp-map   `tailscale debug derp-map` - the /derpmap document, for region
//              code -> human name ("ruh" -> "Riyadh"). `status` carries the
//              code only. Read once per load, when the map is still empty;
//              the subcommand self-describes as "not a stable interface", so
//              the raw code stays the fallback (`_regionName` returns it
//              whenever this read has produced nothing).
//
// The three documents are byte-identical to the LocalAPI ones apart from
// pretty-printing - same top-level, `Self` and `Peer` key sets, and the same
// values on every field the drawings read (checked against the live socket
// while this file still read it directly).
//
// Cadence is polling. A 30 s timer - the same interval the first-party plugin
// uses - plus a 2 s startup ramp that runs until the first status settles (or
// ~30 s, 15 ticks), so a shell restart does not sit on "Checking" while the
// slow timer waits. The push stream this file used to hold open
// (`watch-ipn-bus?mask=6`, one long-lived curl per widget) is gone: it was
// the fast path for peer online/offline changes, but the direct-vs-relay
// facts it cannot carry (CurAddr, Relay, Active, Rx/Tx) forced a status read
// behind every doorbell anyway, so the stream bought a second process per
// widget and a revive timer, not freshness. A read that never answers is
// dropped by a supervisor that holds each read to 15 s counted from its own
// launch - a read launched inside another read's window gets its own full
// bound, and one that ignores SIGTERM is escalated to SIGKILL rather than
// living on as a process every later poll has to step around. That bound has
// to sit above ~5.1 s, which is how long a `tailscale` invocation takes to
// exit 1 on a host where tailscaled is down (measured for all three
// subcommands), so a `--max-time 4`-style wrapper would cut a legitimate slow
// call short.
//
// What is deliberately NOT here: `netcheck` (1.2-2 s, far too slow for a
// poll) and per-peer `tailscale ping` (side-effectful: it nudges path
// discovery). Both are on-demand only, and the widget exposes ping as an
// explicit action rather than doing it behind the user's back.
//
// Two deliberate divergences from the first-party model, kept because the
// drawings depend on the behaviour: peers are NOT filtered to the online ones
// (an offline peer is still a row on the map) and the order stays
// `active desc, online desc, name asc` instead of alphabetical - both decide
// which node leads a tile and which slot it takes on the map. PORTING.md
// item 25 records the same divergence.
QtObject {
  id: ts

  // Poll interval. Nothing pushes: every read is a timer tick.
  property int intervalMs: 30000
  // `active` is what a view binds to its own `visible`, and it owns the poll
  // timers: false only while the monitor is switched off (DPMS) - the one
  // "not being drawn" state the shell can see, since a widget sits on every
  // workspace by design. Unknown reads as true, so the failure mode is a poll
  // nobody is looking at, never a blank tile.
  property bool active: true

  property bool loaded: false
  // "" when tailscaled answered, otherwise why it did not.
  property string errorMessage: ""

  // ── Self ────────────────────────────────────────────────────────────
  // "Running" | "Stopped" | "NeedsLogin" | "NoState" | "Starting" - backend
  // state as tailscaled reports it, not a guess from whether an IP exists.
  property string backendState: ""
  readonly property bool up: ts.backendState === "Running"
  readonly property string stateLabel: {
    if (ts.errorMessage !== "") return "Unavailable"
    if (!ts.loaded) return "Checking"
    switch (ts.backendState) {
      case "Running": return "Connected"
      case "Stopped": return "Stopped"
      case "NeedsLogin": return "Logged out"
      case "Starting": return "Starting"
      case "NoState": return "Not set up"
    }
    return ts.backendState
  }

  property string selfName: ""
  // The full MagicDNS name, trailing dot stripped: "node.tailnet.ts.net".
  // This is what you type at another machine, so it is the node's real
  // identity; `selfName` is only the short form for a tight label.
  property string selfFqdn: ""
  property string selfIp: ""
  property string selfOs: ""
  property string tailnet: ""
  property string magicDnsSuffix: ""
  property bool exitNodeActive: false
  property string exitNodeName: ""
  // Health warnings tailscaled itself raises (clock skew, no DERP, ...).
  property var health: []

  // ── Peers ───────────────────────────────────────────────────────────
  // [{ id, name, fqdn, host, os, ip, online, active, direct, endpoint, relay,
  //    relayName, rx, tx, lastSeen, exitNodeOption, isExitNode, tags }]
  property var peers: []

  readonly property int peerCount: ts.peers.length
  readonly property int onlineCount: {
    var n = 0
    for (var i = 0; i < ts.peers.length; i++) if (ts.peers[i].online) n++
    return n
  }
  // A peer with a live WireGuard session, split by how it is carried.
  readonly property int directCount: {
    var n = 0
    for (var i = 0; i < ts.peers.length; i++) if (ts.peers[i].active && ts.peers[i].direct) n++
    return n
  }
  readonly property int relayCount: {
    var n = 0
    for (var i = 0; i < ts.peers.length; i++) if (ts.peers[i].active && !ts.peers[i].direct) n++
    return n
  }
  readonly property int activeCount: ts.directCount + ts.relayCount

  // How THIS machine's traffic is being carried right now, as one word.
  // "Direct" when every live session is direct, "Relay" when none is, "Mixed"
  // when both, "Idle" when there is no live session at all - which is the
  // normal state of a tailnet nobody is talking to, and is not a fault.
  readonly property string pathLabel: {
    if (!ts.up) return "-"
    if (ts.activeCount === 0) return "Idle"
    if (ts.relayCount === 0) return "Direct"
    if (ts.directCount === 0) return "Relay"
    return "Mixed"
  }

  // The DERP region this machine calls home, as a code and a name.
  property string homeRelay: ""
  readonly property string homeRelayName: ts._regionName(ts.homeRelay)

  // ── Services ────────────────────────────────────────────────────────
  // What this machine SERVES on the tailnet: `tailscale serve` handlers, and
  // whether any of them is exposed to the public internet through Funnel.
  // [{ label, target, funnel }]
  property var services: []
  readonly property bool hasServices: ts.services.length > 0

  // ── Region names ────────────────────────────────────────────────────
  // Read once: region code -> human name ("ruh" -> "Riyadh").
  property var _regions: ({})
  function _regionName(code) {
    var c = String(code || "")
    if (c === "") return ""
    return ts._regions[c] ? ts._regions[c] : c
  }

  // One poll: ask whether the CLI is there at all until it has answered, then
  // launch the reads.
  function refresh() {
    if (!ts.active) return
    if (!ts._cliPresent) { ts._probeCli(); return }
    ts._read()
  }

  // ── Ping, on demand only ────────────────────────────────────────────
  // `tailscale ping` is the ONLY source of latency - it is not in status -
  // and it is side-effectful: it nudges path discovery, which is why it is
  // never in a poll loop and only ever runs because someone asked for it by
  // clicking a node.
  //
  // One ping at a time: a second call while one is in flight replaces the
  // target rather than queueing, so a user clicking around the map cannot
  // stack up processes. The replacement is started by the exit of the run it
  // replaces, never beside it: a cancelled run still ends its stdout collector
  // on the way out (Quickshell flushes what it read before it reports the
  // exit), so if the new target were already in `pingTarget` by then that
  // leftover output would be stamped with the new node's id - the cancelled
  // node's silence reported as the new node's answer. A replaced run is marked
  // `abandoned` and its output is dropped instead.
  property string pingTarget: ""      // peer id being pinged, "" when idle
  property string pingName: ""
  property bool pinging: false
  // Result of the last completed ping.
  property string pingResultId: ""
  property real pingMs: 0             // 0 = unreachable / timed out
  property string pingVia: ""         // "direct" | "derp <region>" | ""
  property string pingError: ""

  // The click that arrived while a ping was in flight; `_startPing` consumes
  // it from the running run's exit handler.
  property string _pingNextId: ""
  property string _pingNextName: ""
  property string _pingNextIp: ""

  function ping(peerId) {
    var id = String(peerId || "")
    var peer = null
    for (var i = 0; i < ts.peers.length; i++) if (ts.peers[i].id === id) { peer = ts.peers[i]; break }
    if (!peer) return false
    // The address comes from `tailscale status --json` and becomes the last
    // argv of `tailscale ping`, where anything starting with `-` is read as a
    // flag. Only a dotted quad is ever handed over; anything else is refused
    // with the reason, the same way a ping that got no answer reports one.
    if (!ts._isDottedQuad(peer.ip)) {
      ts.pingResultId = id
      ts.pingMs = 0
      ts.pingVia = ""
      ts.pingError = "no IPv4 address to ping"
      return false
    }
    ts._pingNextId = id
    ts._pingNextName = peer.name
    ts._pingNextIp = peer.ip
    if (pingProc.running) {
      pingProc.abandoned = true
      pingProc.running = false
      return true
    }
    ts._startPing()
    return true
  }

  // Four decimal octets, 0-255, no leading zeros beyond a lone 0 (a leading
  // zero is octal to inet_aton) - nothing else is an IPv4 address here.
  function _isDottedQuad(s) {
    var m = /^(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})$/.exec(String(s))
    if (!m) return false
    for (var i = 1; i <= 4; i++) if (Number(m[i]) > 255) return false
    return true
  }

  // Starts the ping the pending fields describe. Called by `ping()` when
  // nothing is in flight and by the exit handler of a replaced run, which is
  // what keeps the one-at-a-time promise.
  function _startPing() {
    if (!ts.active || ts._pingNextId === "") return
    ts.pingTarget = ts._pingNextId
    ts.pingName = ts._pingNextName
    ts.pingError = ""
    ts.pinging = true
    ts._pingNextId = ""
    ts._pingNextName = ""
    // -c 1: one probe. --timeout: give a DERP-only peer time to answer
    // (measured ~1 s) without hanging the readout if it never will.
    pingProc.command = ["tailscale", "ping", "-c", "1", "--timeout", "3s", ts._pingNextIp]
    ts._pingNextIp = ""
    ts._launch(pingProc)
  }

  property Process _pingProc: Process {
    id: pingProc
    // Run bookkeeping, as on the three reads (see `_launch`).
    property double launchedAt: 0
    property bool abandoned: false
    property bool started: false
    stdout: StdioCollector {
      onStreamFinished: {
        // A replaced run has nothing to say: its output belongs to the node
        // the click moved away from.
        if (pingProc.abandoned) return
        // "pong from node-a (100.x.y.z) via 192.168.100.10:41641 in 12ms"
        // "pong from node-b (100.x.y.z) via DERP(ruh) in 33ms"
        var line = String(this.text || "").trim()
        var ms = line.match(/in ([0-9]+(?:\.[0-9]+)?)ms/)
        var via = line.match(/via ([^ ]+) in /)
        ts.pingResultId = ts.pingTarget
        ts.pingMs = ms ? Number(ms[1]) : 0
        if (via) {
          var v = via[1]
          var derp = v.match(/^DERP\((.+)\)$/)
          ts.pingVia = derp ? ("derp " + ts._regionName(derp[1])) : "direct"
        } else {
          ts.pingVia = ""
        }
        if (!ms) ts.pingError = line === "" ? "no answer" : line.split("\n")[0]
        // A ping can change the path it just discovered, so re-read status.
        ts.refresh()
      }
    }
    onExited: {
      pingProc.abandoned = false
      ts.pinging = false
      ts.pingTarget = ""
      // No-op unless a click replaced this run; see `_startPing`.
      ts._startPing()
    }
    onStarted: pingProc.started = true
    onRunningChanged: {
      if (pingProc.running || pingProc.started || pingProc.abandoned) return
      // The exec itself failed - `which` found a file the kernel cannot run -
      // so no `exited` is coming and the readout would sit on "pinging"
      // forever. Put it back to idle and say what is wrong.
      ts.pinging = false
      ts.pingTarget = ""
      ts._cliUnrunnable()
    }
  }

  // ── Is the CLI there at all? ────────────────────────────────────────
  // A missing `tailscale` and an unreachable tailscaled are indistinguishable
  // from a failed status read alone (both exit 1), and they want different
  // words on the tile, so the CLI is probed first.
  property bool _cliPresent: false

  property Process _whichProc: Process {
    id: whichProc
    command: ["which", "tailscale"]
    // A process Quickshell cannot exec at all - nothing named `which` on an
    // empty PATH - does not reach `onExited` in 0.3.1: it logs a warning and
    // drops `running` with no exit code. Tracked here so the probe still
    // settles, instead of leaving the tile on "Checking" forever.
    property bool started: false
    property bool settled: false
    property double launchedAt: 0
    property bool abandoned: false
    onStarted: whichProc.started = true
    onExited: function (code) {
      // A probe the supervisor gave up on has already been settled by it.
      if (whichProc.abandoned) return
      whichProc.settled = true
      ts._settleCli(code === 0)
    }
    onRunningChanged: {
      if (whichProc.abandoned) return
      if (!whichProc.running && !whichProc.started && !whichProc.settled) ts._settleCli(false)
    }
  }

  function _probeCli() {
    if (whichProc.running) return
    whichProc.settled = false
    ts._launch(whichProc)
  }

  function _settleCli(present) {
    ts._cliPresent = present
    if (present) { ts._read(); return }
    ts.errorMessage = "tailscale not installed"
    ts.loaded = true
  }

  // `which` found a file the kernel cannot execute (a broken interpreter, a
  // replaced binary): the reads never start, so no `exited` ever arrives and
  // without this the tile would sit on "Checking" forever with an empty
  // errorMessage. `_cliPresent` goes back to false too - the probe only ever
  // claimed the CLI is on PATH - so the next poll asks again instead of the
  // latch staying true forever.
  function _cliUnrunnable() {
    ts._cliPresent = false
    ts.errorMessage = "tailscale not runnable"
    ts.loaded = true
  }

  // A read the supervisor gave up on: it was launched and never answered
  // within its bound. That is the widget's deadline expiring, not the
  // daemon's failure, so it is not worded as one.
  function _settleUnanswered() {
    ts.errorMessage = "tailscale did not answer"
    ts.loaded = true
  }

  // ── The three reads ─────────────────────────────────────────────────
  // Each one is skipped while its own process is still in flight, so a slow
  // daemon overlaps polls instead of stacking processes.
  //
  // `_launch` stamps every run with the moment it started, which is what the
  // supervisor below counts its bound from. A read the kernel cannot execute
  // never reaches `exited` and never ends a stdout collector - Quickshell only
  // drops `running` - so `started` is what tells that apart from a run that
  // ran and finished.
  function _launch(p) {
    p.abandoned = false
    p.started = false
    p.launchedAt = Date.now()
    p.running = true
  }

  function _read() {
    if (!ts.active) return
    if (!statusProc.running) {
      statusProc.outcome = ""
      ts._launch(statusProc)
    }
    if (!serveProc.running) ts._launch(serveProc)
    // The region table is a fixed document: once it has arrived it is never
    // re-read. It is only re-asked while it is still empty, which also covers
    // the read having failed.
    if (!derpProc.running && Object.keys(ts._regions).length === 0) ts._launch(derpProc)
  }

  property Process _statusProc: Process {
    id: statusProc
    command: ["tailscale", "status", "--json"]
    // Run bookkeeping, all reset by `_launch` at every launch: `launchedAt` is
    // this read's own deadline stamp, `abandoned` marks a run whose result
    // must be discarded (the supervisor gave up on it, or `active` went false
    // under it), `started` records whether the exec itself worked.
    property double launchedAt: 0
    property bool abandoned: false
    property bool started: false
    // What the last run's stdout held: "parsed", "unreadable" (stdout was not
    // JSON) or "" (no stdout at all). Quickshell's Process ends this collector
    // before it emits `exited`, so by the time the exit code is known this is
    // always final - there is no ordering to guess at.
    property string outcome: ""
    stdout: StdioCollector {
      onStreamFinished: {
        if (statusProc.abandoned) return
        statusProc.outcome = ts._applyStatus(String(this.text || ""))
      }
    }
    // One writer, one meaning: a failed run is worded here and nowhere else,
    // with the exit code deciding whether the CLI failed or merely printed
    // nothing. A run the widget cancelled is not the CLI's verdict and is not
    // reported as one.
    onExited: function (code) {
      if (statusProc.abandoned) return
      var message = ""
      if (code !== 0) message = "tailscaled not reachable"
      else if (statusProc.outcome === "unreadable") message = "unreadable status"
      else if (statusProc.outcome === "") message = "tailscaled returned nothing"
      if (message === "") return
      ts.errorMessage = message
      ts.loaded = true
    }
    onStarted: statusProc.started = true
    onRunningChanged: {
      if (statusProc.running || statusProc.started || statusProc.abandoned) return
      ts._cliUnrunnable()
    }
  }

  // Applies a status document, and reports what the text was so the exit
  // handler can word a failure. Nothing here writes an error: this runs while
  // the exit code is still unknown, so it must not claim one.
  function _applyStatus(text) {
    if (text.trim() === "") return ""
    var s
    try {
      s = JSON.parse(text)
    } catch (e) {
      return "unreadable"
    }

    ts.errorMessage = ""
    ts.backendState = String(s.BackendState || "")
    ts.health = Array.isArray(s.Health) ? s.Health : []
    ts.magicDnsSuffix = String(s.MagicDNSSuffix || "")
    ts.tailnet = (s.CurrentTailnet && s.CurrentTailnet.Name) ? String(s.CurrentTailnet.Name) : ""

    var self = s.Self || {}
    ts.selfName = ts._shortName(self)
    ts.selfFqdn = ts._fqdn(self)
    ts.selfOs = String(self.OS || "")
    ts.selfIp = ts._ipv4(self.TailscaleIPs)
    ts.homeRelay = String(self.Relay || "")

    var out = []
    var exitName = ""
    var peerMap = s.Peer || {}
    var keys = Object.keys(peerMap)
    for (var i = 0; i < keys.length; i++) {
      var p = peerMap[keys[i]] || {}
      var curAddr = String(p.CurAddr || "")
      var entry = {
        id: String(p.ID || keys[i]),
        name: ts._shortName(p),
        fqdn: ts._fqdn(p),
        host: String(p.HostName || ""),
        os: String(p.OS || ""),
        ip: ts._ipv4(p.TailscaleIPs),
        online: !!p.Online,
        // `Active` is "there is a live WireGuard session right now"; a peer
        // can be Online and idle, which is the usual case.
        active: !!p.Active,
        // A non-empty CurAddr IS the direct path. Empty with a live session
        // means it is being carried by DERP.
        direct: curAddr !== "",
        endpoint: curAddr,
        relay: String(p.Relay || ""),
        relayName: ts._regionName(p.Relay),
        rx: Number(p.RxBytes || 0),
        tx: Number(p.TxBytes || 0),
        lastSeen: String(p.LastSeen || ""),
        exitNodeOption: !!p.ExitNodeOption,
        isExitNode: !!p.ExitNode,
        tags: Array.isArray(p.Tags) ? p.Tags : []
      }
      if (entry.isExitNode) exitName = entry.name
      out.push(entry)
    }

    // Live sessions first, then everything online, then by name - so the
    // interesting nodes lead in every list and the map.
    out.sort(function (a, b) {
      if (a.active !== b.active) return a.active ? -1 : 1
      if (a.online !== b.online) return a.online ? -1 : 1
      return a.name.localeCompare(b.name)
    })

    ts.peers = out
    ts.exitNodeActive = exitName !== ""
    ts.exitNodeName = exitName
    ts.loaded = true
    return "parsed"
  }

  function _shortName(node) {
    var dns = String((node && node.DNSName) || "")
    if (dns !== "") {
      // "node.tailnet.ts.net." -> "node"
      var first = dns.split(".")[0]
      if (first !== "") return first
    }
    return String((node && node.HostName) || "")
  }

  // "node.tailnet.ts.net." -> "node.tailnet.ts.net". Falls back to the
  // hostname when MagicDNS is off, so the field is never empty for a node
  // that has a name at all.
  function _fqdn(node) {
    var dns = String((node && node.DNSName) || "")
    if (dns === "") return String((node && node.HostName) || "")
    return dns.charAt(dns.length - 1) === "." ? dns.substring(0, dns.length - 1) : dns
  }

  function _ipv4(list) {
    if (!Array.isArray(list)) return ""
    for (var i = 0; i < list.length; i++) {
      var ip = String(list[i])
      if (ts._isDottedQuad(ip)) return ip
    }
    return ""
  }

  // ── serve/funnel ────────────────────────────────────────────────────
  property Process _serveProc: Process {
    id: serveProc
    command: ["tailscale", "serve", "status", "--json"]
    // Run bookkeeping, as on the status read (see `_launch`).
    property double launchedAt: 0
    property bool abandoned: false
    property bool started: false
    stdout: StdioCollector {
      onStreamFinished: {
        // A run the widget gave up on is flushed half-written on its way out,
        // and half a serve document parses as "serves nothing".
        if (serveProc.abandoned) return
        var out = []
        try {
          var c = JSON.parse(String(this.text || "{}")) || {}
          var web = c.Web || {}
          var hosts = Object.keys(web)
          for (var i = 0; i < hosts.length; i++) {
            var handlers = (web[hosts[i]] || {}).Handlers || {}
            var paths = Object.keys(handlers)
            for (var j = 0; j < paths.length; j++) {
              var h = handlers[paths[j]] || {}
              out.push({
                label: hosts[i].split(":")[0].split(".")[0] + paths[j],
                target: String(h.Proxy || h.Path || h.Text || ""),
                // AllowFunnel is keyed by the same host:port as Web.
                funnel: !!(c.AllowFunnel && c.AllowFunnel[hosts[i]])
              })
            }
          }
          // Raw TCP forwards have no path; name them by port.
          var tcp = c.TCP || {}
          var ports = Object.keys(tcp)
          for (var k = 0; k < ports.length; k++) {
            var t = tcp[ports[k]] || {}
            if (t.HTTPS || t.HTTP) continue    // already covered by Web
            out.push({
              label: "tcp:" + ports[k],
              target: String(t.TCPForward || ""),
              funnel: false
            })
          }
        } catch (e) {
          out = []
        }
        ts.services = out
      }
    }
    onStarted: serveProc.started = true
    onRunningChanged: {
      if (serveProc.running || serveProc.started || serveProc.abandoned) return
      ts._cliUnrunnable()
    }
  }

  // ── DERP region names, read once ────────────────────────────────────
  property Process _derpProc: Process {
    id: derpProc
    command: ["tailscale", "debug", "derp-map"]
    // Run bookkeeping, as on the status read (see `_launch`).
    property double launchedAt: 0
    property bool abandoned: false
    property bool started: false
    stdout: StdioCollector {
      onStreamFinished: {
        // A run the widget gave up on may be flushed half-written; a half
        // region map would still be taken, and never re-read.
        if (derpProc.abandoned) return
        var map = {}
        try {
          var d = JSON.parse(String(this.text || "{}")) || {}
          var regions = d.Regions || {}
          var ids = Object.keys(regions)
          for (var i = 0; i < ids.length; i++) {
            var r = regions[ids[i]] || {}
            if (r.RegionCode) map[String(r.RegionCode)] = String(r.RegionName || r.RegionCode)
          }
        } catch (e) {
          map = {}
        }
        ts._regions = map
      }
    }
    onStarted: derpProc.started = true
    onRunningChanged: {
      if (derpProc.running || derpProc.started || derpProc.abandoned) return
      ts._cliUnrunnable()
    }
  }

  // ── Cadence ─────────────────────────────────────────────────────────
  // The poll. `triggeredOnStart` gives the widget a read the moment it is
  // created (and again whenever the tile comes back from DPMS), which is what
  // keeps the tile from showing a stale state after the screen wakes.
  property Timer _tick: Timer {
    id: tick
    interval: Math.max(5000, ts.intervalMs)
    running: ts.active
    repeat: true
    triggeredOnStart: true
    onTriggered: ts.refresh()
  }

  // Startup ramp: after a fresh boot the first poll can land before
  // tailscaled has connected, which would leave the tile stale until the 30 s
  // tick came round. Poll every 2 s until a status has settled, or give up
  // after 15 ticks (~30 s).
  property bool _rampDone: false

  property Timer _ramp: Timer {
    id: ramp
    property int ticks: 0
    interval: 2000
    repeat: true
    running: ts.active && !ts._rampDone
    onTriggered: {
      if (ts.loaded || ramp.ticks >= 15) { ts._rampDone = true; return }
      ramp.ticks++
      ts.refresh()
    }
  }

  // ── The bound ───────────────────────────────────────────────────────
  // Every read is skipped while its own process is in flight, so one that
  // never exits - tailscale can hang on a network that keeps coming and going
  // - would silently stop this file refreshing at all, and it would stay
  // stopped. The bound is therefore counted per read, from the moment that
  // read was launched: a read launched inside a window that is already
  // counting down gets its own full 15 s instead of inheriting what is left of
  // an earlier read's deadline and being killed while it is still working.
  //
  // `running = false` is SIGTERM, which a wedged read may ignore - and it
  // would then keep `running == true`, so the launch path would step around it
  // forever - so a reaped read is escalated to SIGKILL after a short grace.
  property int _readBoundMs: 15000
  property int _killGraceMs: 3000

  property Timer _supervisor: Timer {
    id: supervisor
    // Coarse on purpose: the bound is 15 s, and one pass is five cheap checks.
    interval: 1000
    repeat: true
    running: ts.active
    onTriggered: {
      ts._supervise(whichProc)
      ts._supervise(statusProc)
      ts._supervise(serveProc)
      ts._supervise(derpProc)
      ts._supervise(pingProc)
    }
  }

  function _supervise(p) {
    if (!p.running || p.launchedAt === 0) return
    var age = Date.now() - p.launchedAt
    if (age < ts._readBoundMs) return
    if (!p.abandoned) {
      p.abandoned = true
      if (p === whichProc) {
        // The probe owns a settle flag of its own; nothing else sets it, and
        // its exit must not be read as `which`'s verdict.
        whichProc.settled = true
        ts._settleUnanswered()
      } else if (p === statusProc) {
        // The one read whose silence the tile reports; serve and derp just
        // go stale until the next poll.
        ts._settleUnanswered()
      }
      p.running = false      // SIGTERM
      return
    }
    if (age >= ts._readBoundMs + ts._killGraceMs) ts._kill(p)
  }

  // SIGKILL, through Quickshell's own `signal()`. Guarded, because that call
  // hands the pid straight to kill(2) and a pid of 0 there means "every
  // process in my process group" - the shell itself.
  function _kill(p) {
    var pid = p.processId
    if (pid === null || pid === undefined || Number(pid) <= 0) return
    p.signal(9)
  }

  // `active` false means nothing is drawn: the poll timers stop with it (they
  // are bound to it) and nothing is left running behind a dark screen either.
  // SIGKILL rather than SIGTERM for the same reason the supervisor escalates:
  // these are short read-only queries, and one that ignores SIGTERM must not
  // outlive the screen it belongs to.
  onActiveChanged: {
    if (ts.active) return
    ts._drop(whichProc)
    ts._drop(statusProc)
    ts._drop(serveProc)
    ts._drop(derpProc)
    ts._drop(pingProc)
    // A click that has not been pinged yet is not worth a process on a dark
    // screen; the next click sets another one.
    ts._pingNextId = ""
    ts._pingNextName = ""
    ts._pingNextIp = ""
  }

  function _drop(p) {
    if (!p.running) return
    p.abandoned = true
    ts._kill(p)
    // Belt and braces: a launch that has not reached a pid yet is not
    // killable, and `running = false` (SIGTERM) is what reaps it in that
    // window.
    p.running = false
  }
}
