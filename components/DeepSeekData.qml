import QtQuick
import Quickshell
import Quickshell.Io
import "JsonRead.js" as JsonRead

// DeepSeek credit and spend, read out of the DeepSpend plugin's own ledger.
//
// Where the number comes from
// ---------------------------
// `t1nk33r.deepseek` (display name "DeepSeek", the plugin the operator calls
// DeepSpend) is installed and running on this machine as a bar widget. Its
// manifest declares `kinds: ["bar-widget"]` only - no service entry point - so
// `shell.serviceFor("t1nk33r.deepseek")` is null and its parsed balance lives
// in private properties of its own BarWidget.qml. Same shape, and the same
// answer, as the weather / prayer / tailscale / codeburn components
// (PORTING.md items 17 and 25): go to the source that plugin reads and writes,
// and depend on nothing of it being installed, enabled or running.
//
// That source is the ledger it already writes:
//
//   $XDG_STATE_HOME/t1nk33r.deepseek/usage.state
//   -> ~/.local/state/t1nk33r.deepseek/usage.state
//
// one JSON line, mode 0600, written atomically (a same-directory temp file and
// a rename, so a reader sees the old ledger or the new one, never half of
// either). Its own header in Model.js/BarWidget.qml describes it, and this is
// the body verbatim - the field names below are read from it, not guessed:
//
//   {"version":2,"currency":"USD","firstSeenAt":1789144294532,
//    "lastAt":1789329579289,"lastTotal":16.2,
//    "spent":30.68,"spentPeak":0,"spentOffPeak":30.68,"added":25.96,
//    "days":[{"date":"2026-09-13","spent":14.2,"spentPeak":0,
//             "spentOffPeak":14.2,"added":0,"samples":1350}]}
//
//   * `lastTotal` is the balance from the last SUCCESSFUL poll - so the ledger
//     publishes both numbers this widget shows: the credit balance, and the
//     spend measured from the balance moving between samples. There is no
//     usage endpoint in DeepSeek's public API (the plugin's README says so),
//     so the spend is measured, not reported - a drop between two samples is
//     spend, a rise is a top-up, counted separately in `added`.
//   * `days` is one row per LOCAL day, `spentPeak`/`spentOffPeak` split the
//     spend by DeepSeek's own double-rate window (the pricing half of the
//     plugin), and `firstSeenAt` is the start of the series.
//   * `version` is the plugin's USAGE_VERSION (2). A ledger of another version
//     is reported as such rather than parsed on a guess - a misread balance is
//     worse than no balance.
//
// Freshness, and what is NOT here
// -------------------------------
// The plugin records a sample on every successful poll (its default is 60 s)
// and flushes the file at most every 300 s, plus promptly on the first sample
// and on shutdown. So `lastAt` - the time of the last sample, in ms - is the
// local freshness signal, and a healthy ledger's is never more than about one
// flush window behind. `staleAfterSec` is two of those windows: past it, the
// plugin is not sampling or not running, and the tile says so rather than
// passing the number off as current.
//
// Deliberately NOT available: DeepSeek's own `is_available` verdict. The API
// answers it, the ledger does not record it, and no reader on this machine
// writes it anywhere. So this component never claims the account is
// "available" or "exhausted" - the two states it can state are the balance
// itself and the plugin's own configured low-balance threshold, read from
// `~/.config/deepspend/config.json` (`lowBalanceThreshold`, 0 = alert off).
// That config is read for three presentation fields and nothing else: the key
// it holds is never read, stored, logged or copied anywhere by this file.
//
// Nothing here calls the DeepSeek API, holds a key, runs the webhook, or
// spawns a process: one file read, and a re-read on a slow clock.
QtObject {
  id: ds

  // False only while the monitor is switched off - the one "not being drawn"
  // state the shell can see. No re-read runs while it is false.
  property bool active: true

  // Two of the plugin's 300 s flush windows. See the header.
  property int staleAfterSec: 600
  // How often the ledger is re-read while the tile is drawn. The plugin's own
  // writes arrive every few minutes at most, so this is the freshness clock
  // rather than a poll - a 535-byte file read, no process, no network.
  property int rereadMs: 60000

  // ── Paths ───────────────────────────────────────────────────────────
  // XDG-aware exactly as the plugin's own paths are (BarWidget.qml builds them
  // from XDG_STATE_HOME/XDG_CONFIG_HOME with a HOME fallback), so a machine
  // that moved its state directory still finds the same ledger.
  readonly property string stateDir: {
    var base = Quickshell.env("XDG_STATE_HOME")
    if (!base || base === "") base = (Quickshell.env("HOME") || "") + "/.local/state"
    return base + "/t1nk33r.deepseek"
  }
  readonly property string ledgerPath: ds.stateDir + "/usage.state"
  readonly property string configPath: {
    var base = Quickshell.env("XDG_CONFIG_HOME")
    if (!base || base === "") base = (Quickshell.env("HOME") || "") + "/.config"
    return base + "/deepspend/config.json"
  }

  // ── Source state ────────────────────────────────────────────────────
  property bool loaded: false
  property bool ledgerFound: false
  // "" unless there is no number to show, and then exactly why.
  property string errorMessage: ""
  property int ledgerVersion: 0

  // ── The ledger ──────────────────────────────────────────────────────
  property bool hasBalance: false
  property string currency: ""
  property real total: 0
  property real spent: 0
  property real spentPeak: 0
  property real spentOffPeak: 0
  property real added: 0
  property real spentToday: 0
  // Epoch ms: the last sample's time, and the start of the series.
  property real sampledAtMs: 0
  property real firstSeenMs: 0

  // ── The plugin's own presentation knobs ─────────────────────────────
  // `lowBalanceThreshold` in its config file, in the account's currency;
  // 0 (its default) means the alert is off, and this widget then has no low
  // state at all rather than inventing a threshold of its own.
  property real lowBalance: 0
  readonly property bool lowArmed: ds.lowBalance > 0
  readonly property bool low: ds.hasBalance && ds.lowArmed && ds.total <= ds.lowBalance

  // ── Freshness ───────────────────────────────────────────────────────
  property real _nowMs: Date.now()
  readonly property int ageSeconds: ds.sampledAtMs > 0
    ? Math.max(0, Math.round((ds._nowMs - ds.sampledAtMs) / 1000)) : -1
  readonly property bool stale: ds.hasBalance && ds.ageSeconds > ds.staleAfterSec

  // "11 Sep", with the year only once the series has crossed one - the same
  // rule and month names as the plugin's own usageSinceText().
  readonly property string sinceLabel: {
    if (ds.firstSeenMs <= 0) return ""
    var d = new Date(ds.firstSeenMs)
    if (isNaN(d.getTime())) return ""
    var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    var text = d.getDate() + " " + months[d.getMonth()]
    if (new Date(ds._nowMs).getFullYear() !== d.getFullYear())
      text += " " + d.getFullYear()
    return text
  }

  // ── Verdict ─────────────────────────────────────────────────────────
  // The phone card's own line: "Available" when the account holds credit,
  // "Running low" when the threshold the operator armed in DeepSpend is
  // crossed, "No credit" when the last sample was zero. It is a statement
  // about the BALANCE - which the ledger carries - never about DeepSeek's
  // `is_available`, which it does not (see the header).
  readonly property string verdict: {
    if (!ds.hasBalance) return ""
    if (ds.total <= 0) return "No credit"
    if (ds.low) return "Running low"
    return "Available"
  }
  // The one thing the accent means on both drawings: this balance needs
  // attention - nothing left, or below the operator's own threshold.
  readonly property bool alert: ds.hasBalance && (ds.total <= 0 || ds.low)
  // The Nothing drawing's badge form of the same verdict - this style's short
  // state marker, worded here so the two drawings cannot disagree about it.
  readonly property string alertShort: !ds.alert ? "" : (ds.total <= 0 ? "Empty" : "Low")

  // ── The freshness line ──────────────────────────────────────────────
  // Part of the design, not a debug string: the figure is read from a file
  // the plugin fills in on its own schedule, and the tile says how old the
  // reading is. `sampledAtMs` is the plugin's own `lastAt` - the time of the
  // last successful poll - never when this file was read.
  readonly property string readLabel: {
    if (ds.sampledAtMs <= 0) return ""
    var t = new Date(ds.sampledAtMs)
    return t.getHours() + ":" + (t.getMinutes() < 10 ? "0" : "") + t.getMinutes()
  }
  // "stale · last read 22:16" / "last read 22:16" - the phone card's own line,
  // word for word.
  readonly property string footnote: !ds.hasBalance
    ? ""
    : (ds.stale ? "stale · last read " + ds.readLabel
                : "last read " + ds.readLabel)

  // What the figure was read from, for a tile with room to name it: the
  // plugin that owns the ledger, not this widget.
  readonly property string sourceLabel: "DeepSpend ledger"

  // The "no number at all" state: a headline and the reason, every path named.
  readonly property string noticeHeadline: ds.hasBalance ? "" : "No reading"
  readonly property string noticeDetail: {
    if (ds.hasBalance) return ""
    if (!ds.loaded) return "Reading the DeepSpend ledger…"
    if (!ds.ledgerFound) return "DeepSpend has not written its ledger yet."
    if (ds.errorMessage !== "") return ds.errorMessage
    return "DeepSpend has no balance sample yet."
  }

  // ── The figures ─────────────────────────────────────────────────────
  readonly property string symbol: ds._symbolFor(ds.currency)
  readonly property string amountLabel: ds.hasBalance ? ds._amountLabel(ds.total) : ""
  readonly property string figureLabel: ds.hasBalance
    ? ds.symbol + ds._amountLabel(ds.total) : ""
  readonly property string spentTodayLabel: ds.symbol + ds._amountLabel(ds.spentToday)
  readonly property string spentLabel: ds.symbol + ds._amountLabel(ds.spent)
  readonly property string addedLabel: ds.symbol + ds._amountLabel(ds.added)
  readonly property string offPeakLabel: ds.symbol + ds._amountLabel(ds.spentOffPeak)
  readonly property string peakLabel: ds.symbol + ds._amountLabel(ds.spentPeak)

  // One row list, so the two drawings cannot disagree about what a label says.
  // A row whose figure is not known is absent, never a zero: "Added $0.00" on
  // an account that has never been topped up is a fact, "Off-peak $0.00" on a
  // series with no peak spend is noise - hence the conditions.
  readonly property var rows: {
    var out = []
    if (!ds.hasBalance) return out
    out.push({ k: "Spent today", v: ds.spentTodayLabel })
    out.push({ k: "Spent total", v: ds.spentLabel })
    if (ds.firstSeenMs > 0) out.push({ k: "Since", v: ds.sinceLabel })
    if (ds.added > 0) out.push({ k: "Added", v: ds.addedLabel })
    if (ds.spentPeak > 0) {
      out.push({ k: "Off-peak", v: ds.offPeakLabel })
      out.push({ k: "Peak", v: ds.peakLabel })
    }
    return out
  }

  function _symbolFor(code) {
    switch (String(code || "")) {
      case "CNY": return "¥"
      case "USD": return "$"
    }
    return ""
  }

  // `87.42`, or an em dash when the ledger holds nothing usable.
  function _amountLabel(v) {
    var n = Number(v)
    return isFinite(n) ? n.toFixed(2) : "—"
  }

  // The plugin's own local day key: `2026-09-13`, the operator's day, the
  // same rule as its usageDayKey() - local, never UTC.
  function _dayKey(epochMs) {
    var d = new Date(epochMs)
    if (isNaN(d.getTime())) return ""
    var m = d.getMonth() + 1
    var day = d.getDate()
    return d.getFullYear() + "-" + (m < 10 ? "0" + m : m)
      + "-" + (day < 10 ? "0" + day : day)
  }

  // ── Reading ─────────────────────────────────────────────────────────
  function refresh() { if (ds.active) ledgerView.reload() }

  // A QtObject root has no default property, so the two FileViews are
  // properties - the same shape StorageData/TailscaleData give their Process
  // and Timer children.
  property FileView ledgerView: FileView {
    id: ledgerView
    path: ds.ledgerPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: ds._applyLedger(text())
    onFileChanged: reload()
    onLoadFailed: {
      ds.loaded = true
      ds.ledgerFound = false
      ds._clear()
      ds.errorMessage = ""
    }
  }

  // The plugin writes with `mv` over the same path, and a watcher on a path
  // whose inode was replaced is not something to bet a number on: the slow
  // re-read is the backstop, exactly as CodeburnData re-stats its cache.
  property Timer _reread: Timer {
    interval: ds.rereadMs
    repeat: true
    triggeredOnStart: true
    running: ds.active
    onTriggered: {
      ds._nowMs = Date.now()
      ds.refresh()
    }
  }

  function _clear() {
    ds.hasBalance = false
    ds.currency = ""
    ds.total = 0
    ds.spent = 0
    ds.spentPeak = 0
    ds.spentOffPeak = 0
    ds.added = 0
    ds.spentToday = 0
    ds.sampledAtMs = 0
    ds.firstSeenMs = 0
    ds.ledgerVersion = 0
  }

  // The ledger keeps one small row per day; 4 MiB is decades of them, and a
  // file over it is refused unparsed and reads as unreadable. The config is a
  // handful of fields and gets 1 MiB (JsonRead.js).
  property int maxLedgerBytes: 4 * JsonRead.MiB
  property int maxConfigBytes: JsonRead.MiB

  function _applyLedger(raw) {
    ds.loaded = true
    ds._nowMs = Date.now()
    if (JsonRead.tooLarge(raw, ds.maxLedgerBytes)) {
      ds.ledgerFound = true
      ds._clear()
      ds.errorMessage = "The DeepSpend ledger is too large."
      return
    }
    var text = String(raw == null ? "" : raw).trim()
    if (text === "") {
      ds.ledgerFound = false
      ds._clear()
      ds.errorMessage = ""
      return
    }

    var parsed = JsonRead.parseOrNull(text)
    ds.ledgerFound = true
    if (parsed === null || typeof parsed !== "object") {
      ds._clear()
      ds.errorMessage = "The DeepSpend ledger is unreadable."
      return
    }

    // The plugin's USAGE_VERSION. Report a stranger's shape rather than read
    // its fields on a guess.
    var version = JsonRead.num(parsed.version, 0)
    if (version !== 2) {
      ds._clear()
      ds.ledgerVersion = version
      ds.errorMessage = "The DeepSpend ledger is version " + version
        + ", which this widget does not know."
      return
    }

    ds.ledgerVersion = version
    ds.errorMessage = ""
    ds.currency = typeof parsed.currency === "string" ? parsed.currency : ""
    ds.firstSeenMs = JsonRead.num(parsed.firstSeenAt, 0)
    ds.sampledAtMs = JsonRead.num(parsed.lastAt, 0)
    ds.spent = JsonRead.num(parsed.spent, 0)
    ds.spentPeak = JsonRead.num(parsed.spentPeak, 0)
    ds.spentOffPeak = JsonRead.num(parsed.spentOffPeak, 0)
    ds.added = JsonRead.num(parsed.added, 0)

    // `lastTotal` is null until the first successful poll, and `Number(null)`
    // is 0 - which would draw a confident $0.00 balance for an account that
    // has simply never been sampled.
    var total = (parsed.lastTotal === null || parsed.lastTotal === undefined)
      ? NaN : Number(parsed.lastTotal)
    ds.hasBalance = isFinite(total)
    ds.total = ds.hasBalance ? total : 0

    // Today's row, by the plugin's own local day key; a ledger whose newest
    // day is not today has no spend for today yet.
    var key = ds._dayKey(ds._nowMs)
    ds.spentToday = 0
    var days = parsed.days instanceof Array ? parsed.days : []
    for (var i = 0; i < days.length; i++) {
      var row = days[i]
      if (!row || row.date !== key) continue
      ds.spentToday = JsonRead.num(row.spent, 0)
      break
    }
  }

  // ── The plugin's config: three presentation fields, never the key ────
  // Read-only, and parsed field by field: the parsed object is never stored
  // whole, so there is no path by which `apiKey` could reach a property, a
  // log line or a drawing. A missing or broken file is not an error here -
  // the ledger already answers the balance; the config only decides whether
  // the operator armed a low-balance threshold.
  property FileView configView: FileView {
    id: configView
    path: ds.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: ds._applyConfig(text())
    onFileChanged: reload()
    onLoadFailed: ds.lowBalance = 0
  }

  function _applyConfig(raw) {
    if (JsonRead.tooLarge(raw, ds.maxConfigBytes)) {
      ds.lowBalance = 0
      return
    }
    var text = String(raw == null ? "" : raw).trim()
    if (text === "") {
      ds.lowBalance = 0
      return
    }
    var parsed = JsonRead.parseOrNull(text)
    if (!parsed || typeof parsed !== "object") {
      ds.lowBalance = 0
      return
    }
    var threshold = Number(parsed.lowBalanceThreshold)
    ds.lowBalance = (isFinite(threshold) && threshold > 0) ? threshold : 0
  }
}
