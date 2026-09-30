import QtQuick
import Quickshell.Io
import Quickshell.Networking

// The live network link, as numbers and short strings. Read-only client of
// NetworkManager through Quickshell.Networking - no bus name is claimed and
// no scan is started by this file (starting a Wi-Fi scan is a side effect on
// a shared radio; a desktop widget has no business doing that).
QtObject {
  id: net

  // Precedence: a connected wired link wins over Wi-Fi, because that is what
  // the traffic is actually using when both are up.
  readonly property var _wired: {
    var ds = Networking.devices ? Networking.devices.values : []
    for (var i = 0; i < ds.length; i++)
      if (ds[i].type === DeviceType.Wired && ds[i].connected) return ds[i]
    return null
  }

  readonly property var _wifi: {
    var ds = Networking.devices ? Networking.devices.values : []
    for (var i = 0; i < ds.length; i++)
      if (ds[i].type === DeviceType.Wifi && ds[i].connected) return ds[i]
    return null
  }

  // The association behind a Wi-Fi link. Signal and security belong to the
  // NETWORK, not to the device: Quickshell's NetworkDevice exposes neither
  // property (`signalStrength` and `security` are declared on WifiNetwork,
  // and reach us through `device.networks`). Reading them off the device
  // yields undefined, which is why a healthy WPA2 link used to report 0% and
  // "OPEN" - the view's fallback for an empty string. The connected entry is
  // preferred; failing that the strongest, because a link can be up before
  // its listing marks it connected.
  readonly property var _wifiNetwork: {
    if (!net.connected || !net.isWifi) return null
    var ns = net.device.networks ? net.device.networks.values : []
    var best = null
    for (var i = 0; i < ns.length; i++) {
      if (ns[i].connected) return ns[i]
      if (!best || Number(ns[i].signalStrength) > Number(best.signalStrength)) best = ns[i]
    }
    return best
  }

  // Pin a device by interface name. Empty = automatic (a connected wired
  // link, else a connected Wi-Fi one), which is what the tile uses unless
  // someone names an interface in its settings.
  property string preferred: ""

  // False while nothing is watching - the tile is hidden, or its screen is
  // switched off. Both reads this file starts on a schedule are gated on it:
  // the traffic sample (no sample is taken, and no counters are kept, while
  // it is false) and the on-demand latency ping (a ping in flight is killed
  // outright). A view binds it to its own `visible`, the way the storage and
  // weather tiles already do; the failure mode is a sample, never a blank
  // readout, so the default is true.
  property bool active: true

  readonly property var _pinned: {
    var want = net.preferred.trim()
    if (want === "") return null
    var ds = Networking.devices ? Networking.devices.values : []
    for (var i = 0; i < ds.length; i++)
      if (String(ds[i].name) === want) return ds[i]
    return null
  }

  // True when an interface was named but no such device exists - a typo, or
  // a dock that is not plugged in. The view says so rather than silently
  // falling back to a different link and reporting it as this one.
  readonly property bool pinnedMissing: net.preferred.trim() !== "" && net._pinned === null

  readonly property var device: net._pinned ? net._pinned
    : (net.preferred.trim() !== "" ? null : (net._wired ? net._wired : net._wifi))
  readonly property bool connected: !!net.device && !!net.device.connected
  readonly property bool isWifi: !!net.device && net.device.type === DeviceType.Wifi
  readonly property bool wifiEnabled: !!Networking.wifiEnabled

  // 0..100. A wired link has no signal strength; it reports 100 so a single
  // meter in the view means "link quality" for both kinds.
  readonly property int signal: {
    if (!net.connected) return 0
    if (!net.isWifi) return 100
    var n = net._wifiNetwork
    if (!n) return 0
    // WifiNetwork.signalStrength is a 0..1 ratio, not a percentage.
    var v = Number(n.signalStrength)
    return isFinite(v) ? Math.max(0, Math.min(100, Math.round(v * 100))) : 0
  }

  // The SSID for Wi-Fi, the interface name for wired.
  // What the link is CALLED, which is not the same as which interface it
  // runs over: an SSID for Wi-Fi, and for a wired link the word "Ethernet"
  // rather than `enp14s0`. The interface name is an implementation detail of
  // the machine, not a thing the desktop should announce, so it appears only
  // when the widget was pointed at one deliberately (`preferred`).
  readonly property string name: {
    if (net.pinnedMissing) return "No " + net.preferred.trim()
    if (!net.connected) return net.wifiEnabled ? "Not connected" : "Wi-Fi off"
    if (net.isWifi) {
      var n = net._wifiNetwork
      if (n && n.name) return String(n.name)
      return net.preferred.trim() !== "" ? String(net.device.name) : "Wi-Fi"
    }
    return net.preferred.trim() !== "" ? String(net.device.name || "Ethernet") : "Ethernet"
  }

  // The interface behind it, for the views that want to show it explicitly.
  readonly property string interfaceName: net.connected ? String(net.device.name || "") : ""

  readonly property string kind: net.connected ? (net.isWifi ? "WI-FI" : "ETHERNET") : "OFFLINE"
  // NetworkManager's device `address` is the HARDWARE address - Quickshell's
  // NetworkDevice exposes no IP at all. A widget row labelled "address" that
  // prints a MAC is a small lie, so the interface's IPv4 is read separately,
  // once per connection change, from `ip -4 -j addr`. One short-lived process
  // on an event, never a poll.
  readonly property string hwAddress: net.connected ? String(net.device.address || "") : ""

  property string ipv4: ""

  readonly property string _iface: net.connected ? String(net.device.name || "") : ""
  // A new link invalidates every measurement taken on the old one: the IPv4
  // address, the two traffic counters (another interface keeps its own, and
  // a re-created one starts them at zero) and the latency figure. All three
  // are re-read or re-demanded here rather than left looking current.
  on_IfaceChanged: net._linkChanged()
  onConnectedChanged: net._linkChanged()

  function _linkChanged() {
    net._refreshIp()
    net._resetTraffic()
    net.latencyMs = -1
    net.pingNow()
  }

  function _refreshIp() {
    net.ipv4 = ""
    if (net._iface === "") return
    ipProc.command = ["ip", "-4", "-j", "addr", "show", "dev", net._iface]
    ipProc.running = true
  }

  property Process _ipProc: Process {
    id: ipProc
    stdout: StdioCollector {
      onStreamFinished: {
        var addr = ""
        try {
          var arr = JSON.parse(String(this.text || "[]"))
          for (var i = 0; i < arr.length && addr === ""; i++) {
            var info = arr[i].addr_info || []
            for (var j = 0; j < info.length; j++) {
              if (info[j].family === "inet" && info[j].local) { addr = String(info[j].local); break }
            }
          }
        } catch (e) {
          addr = ""
        }
        net.ipv4 = addr
      }
    }
  }

  // What a view should print for "address": the IPv4 when the interface has
  // one, the hardware address only as a last resort.
  readonly property string address: net.ipv4 !== "" ? net.ipv4 : net.hwAddress

  Component.onCompleted: {
    net._refreshIp()
    net.pingNow()
  }
  // The security of the association, as the view's short label. Empty means
  // unknown - the view prints its own "OPEN" for that, so an unrecognised
  // value must not be reported as OPEN here, or a WPA link would be announced
  // as open. Enum order is Quickshell's WifiSecurityType.
  readonly property string security: {
    var n = net._wifiNetwork
    if (!n) return ""
    switch (Number(n.security)) {
    case WifiSecurityType.Owe: return "OWE"
    case WifiSecurityType.Open: return "OPEN"
    case WifiSecurityType.StaticWep:
    case WifiSecurityType.DynamicWep: return "WEP"
    case WifiSecurityType.Leap: return "LEAP"
    case WifiSecurityType.WpaPsk: return "WPA"
    case WifiSecurityType.WpaEap: return "WPA-ENT"
    case WifiSecurityType.Wpa2Psk: return "WPA2"
    case WifiSecurityType.Wpa2Eap: return "WPA2-ENT"
    case WifiSecurityType.Sae: return "WPA3"
    case WifiSecurityType.Wpa3SuiteB192: return "WPA3-192"
    default: return ""
    }
  }

  // Mbit/s for a wired link, 0 when unknown or wireless.
  readonly property int linkSpeed: {
    if (!net.connected || net.isWifi) return 0
    var v = Number(net.device.linkSpeed)
    return isFinite(v) && v > 0 ? Math.round(v) : 0
  }

  // Whether the machine actually reaches the internet, as opposed to merely
  // holding an address. Unknown on backends that cannot check.
  readonly property bool online: Networking.connectivity === NetworkConnectivity.Full
  readonly property bool connectivityKnown: !!Networking.canCheckConnectivity
                                            && !!Networking.connectivityCheckEnabled

  readonly property int bars: {
    var s = net.signal
    if (!net.connected) return 0
    if (s >= 75) return 4
    if (s >= 50) return 3
    if (s >= 25) return 2
    return 1
  }

  // ── Traffic ─────────────────────────────────────────────────────────
  //
  // What the chosen interface is carrying right now, in bytes per second,
  // from /proc/net/dev. This is the one figure in this file that cannot be
  // pushed: a rate is a DELTA, and a delta needs two moments, so it is the
  // one read here that runs on a schedule. It is written to cost as little
  // as it can - one re-read of a ~1 KB procfs file per `sampleMs` while
  // `active` and connected, and not one byte while it is either not - and
  // every rate is divided by the interval that ACTUALLY elapsed between the
  // two samples, never by the nominal one.
  //
  // The interface is `_iface`: the same device the rest of this file
  // reports, so the two numbers describe the link the signal meter above
  // them belongs to. Traffic on another interface (a container bridge, the
  // tailnet) is not this link's traffic and is not added in.
  property int sampleMs: 1000
  property bool ratesKnown: false
  property real rxRate: 0
  property real txRate: 0

  property var _prev: null      // { rx, tx, at } - the previous sample

  // The two counters wanted out of /proc/net/dev's table for one interface.
  // A row is `iface: rxBytes rxPackets errs drop fifo frame compressed
  // multicast | txBytes ...`, so they are the first and the ninth field
  // after the colon - which is what the header above the table names.
  function _counters(text, iface) {
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var c = lines[i].indexOf(":")
      if (c < 0) continue
      if (lines[i].slice(0, c).trim() !== iface) continue
      var f = lines[i].slice(c + 1).trim().split(/\s+/)
      if (f.length < 9) return null
      var rx = Number(f[0]), tx = Number(f[8])
      if (!isFinite(rx) || !isFinite(tx)) return null
      return { rx: rx, tx: tx }
    }
    return null
  }

  function _resetTraffic() {
    net._prev = null
    net.ratesKnown = false
    net.rxRate = 0
    net.txRate = 0
  }

  function _read() {
    if (net.active && net.connected) devFile.reload()
  }

  function _sample(text) {
    if (!net.active || net._iface === "") { net._resetTraffic(); return }
    var now = net._counters(text, net._iface)
    if (!now) { net._resetTraffic(); return }
    var at = Date.now()
    var prev = net._prev
    net._prev = { rx: now.rx, tx: now.tx, at: at }
    if (!prev) return
    var dt = (at - prev.at) / 1000
    // A sample landing hard on the heels of the last one - the FileView's own
    // first load beside the timer's - would divide by nearly nothing. Keep
    // the baseline and wait for a real interval.
    if (dt < net.sampleMs / 2000) return
    // The counters are 64-bit and monotonic per interface, but a re-created
    // interface restarts them: a negative delta means the baseline is stale,
    // not that traffic went backwards.
    var drx = now.rx - prev.rx
    var dtx = now.tx - prev.tx
    if (drx < 0 || dtx < 0) return
    net.rxRate = drx / dt
    net.txRate = dtx / dt
    net.ratesKnown = true
  }

  // Decimal, not binary: a link is sold and reported in decimal Mbit/s, and
  // the tile prints this interface's negotiated rate in those same Mb/s
  // (`linkSpeed`), so "1.0 MB/s" here is 1,000,000 bytes/s - one ruler for
  // both figures rather than two.
  function _rate(bps) {
    if (!isFinite(bps) || bps < 0) return ""
    var v = bps, u = 0
    while (v >= 1000 && u < 3) { v /= 1000; u++ }
    var num = (u === 0 || v >= 100) ? String(Math.round(v)) : String(Math.round(v * 10) / 10)
    return num + " " + ["B", "kB", "MB", "GB"][u] + "/s"
  }

  // The same number for a column too narrow for the unit word - the narrow
  // Liquid Glass column (small and medium) and the Nothing footer line on
  // every preset. "1.2M/s". At 12 px in the system face the spelled-out pair
  // measures 82 + 74 px plus a 9 px gap, against a 160 px column; this form
  // measures 67 + 59.
  function _rateShort(bps) {
    if (!isFinite(bps) || bps < 0) return ""
    var v = bps, u = 0
    while (v >= 1000 && u < 3) { v /= 1000; u++ }
    var num = (u === 0 || v >= 100) ? String(Math.round(v)) : String(Math.round(v * 10) / 10)
    return num + ["B/s", "k/s", "M/s", "G/s"][u]
  }

  // "--" until the second sample lands, never "0 B/s": a zero is a reading,
  // and this file has not taken one yet.
  readonly property string rxLabel: net.ratesKnown ? net._rate(net.rxRate) : "--"
  readonly property string txLabel: net.ratesKnown ? net._rate(net.txRate) : "--"
  readonly property string rxShort: net.ratesKnown ? net._rateShort(net.rxRate) : "--"
  readonly property string txShort: net.ratesKnown ? net._rateShort(net.txRate) : "--"

  property FileView _devFile: FileView {
    id: devFile
    path: "/proc/net/dev"
    printErrors: false
    onLoaded: net._sample(text())
  }

  property Timer _rateTick: Timer {
    interval: net.sampleMs
    // The first tick is the baseline, and it is taken at once rather than an
    // interval from now. A link that is down is not sampled at all: there is
    // no counter to read, and the re-start when it comes back re-baselines
    // without waiting for a tick.
    running: net.active && net.connected
    repeat: true
    triggeredOnStart: true
    onTriggered: net._read()
  }

  // ── Latency, on demand ──────────────────────────────────────────────
  //
  // One ICMP echo when something asks for one, and at no other time: there
  // is deliberately no repeating ping in this file, so nothing goes to a
  // third party merely because the tile is on screen. What asks is the tile
  // waking up, the link changing under it, and a click on the readout - the
  // views wire that last one.
  //
  // The cost of the choice, stated: between demands the figure can be stale,
  // and the readout admits it the only way a tile can - the same readout is
  // the control that re-measures, and it brightens under the pointer. A ping
  // every 30-60 s was rejected: the freshness it buys is not worth an echo
  // against a third party for the whole life of the desktop.
  //
  // `-n` skips the reverse lookup, which would otherwise be measured as
  // latency; `-c 1` is one echo; `-W 1` gives up after a second, so a
  // black-holed link cannot hold the process open. The target is a public
  // anycast resolver - an address and not a name, reachable from
  // practically anywhere, and, unlike the LAN gateway, a round trip that
  // says something about the internet rather than about the switch in the
  // hall.
  readonly property string pingTarget: "1.1.1.1"
  property int latencyMs: -1

  readonly property bool latencyKnown: net.latencyMs >= 0
  readonly property string latencyLabel: net.latencyKnown ? net.latencyMs + " ms" : "--"

  // Ask for one measurement. Cheap and safe to call twice: a ping already in
  // flight is left alone, and a hidden tile never starts one.
  function pingNow() {
    if (!net.active || !net.connected || pingProc.running) return
    pingProc.running = true
  }

  property Process _pingProc: Process {
    id: pingProc
    command: ["ping", "-n", "-c", "1", "-W", "1", net.pingTarget]
    stdout: StdioCollector {
      onStreamFinished: {
        // The reply carries `time=13.2 ms`, the summary's rtt line the same
        // number. A refused or black-holed echo prints neither, and that is
        // a measurement too: "--", never the last value kept looking current.
        var m = /time=([0-9.]+)\s*ms/.exec(String(this.text || ""))
        net.latencyMs = m ? Math.max(0, Math.round(Number(m[1]))) : -1
      }
    }
  }

  onActiveChanged: {
    if (net.active) { net.pingNow(); return }
    // Nothing stays running behind a hidden tile: the tick is stopped by its
    // own `running` binding, a ping in flight is killed rather than left to
    // finish, and the counters are dropped - a delta taken across a hidden
    // interval would be a lie about the rate.
    pingProc.running = false
    net._resetTraffic()
    net.latencyMs = -1
  }
}
