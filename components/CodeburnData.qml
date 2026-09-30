import QtQuick
import Quickshell
import Quickshell.Io

// What the AI coding tools cost, as numbers and short labels.
//
// Where this comes from, and why not from the plugin next door
// ------------------------------------------------------------
// `t1nk33r.codeburn` is installed here and it is not a backend, for exactly
// the reason the weather, prayer and tailscale plugins were not (PORTING.md
// items 17 and 25): its manifest declares `kinds: ["bar-widget"]` only, so
// `shell.serviceFor("t1nk33r.codeburn")` is null and its parsed payload lives
// in private properties of its own Panel.qml. Nothing here depends on that
// plugin being installed, enabled or running.
//
// The source is the `codeburn` CLI's own cache under ~/.cache/codeburn:
//
//   status-snapshot.<queryhash>.json   the memoized menubar payload, ~25 KB.
//                                      Envelope {version, semanticKey,
//                                      corpusFingerprint, newestMtimeMs,
//                                      observedAtMs, queryKey, payload}.
//   daily-cache.v31.json               the canonical per-day rollup,
//                                      {version, tzKey, lastComputedDate,
//                                      days:[{date, cost, calls, sessions,
//                                      tokens, models{}, projects{},
//                                      providers{}}]}.
//
// Deliberately NOT read: session-cache.v9/ (20 MB of shards, and the session
// records are private - this component never touches conversation content,
// only money, counts, model names, project names and dates).
//
// Three traps, all of them hit while writing this:
//
//  1. The snapshot filename carries a hash of the QUERY, and old ones are
//     never pruned - there are 18 on this machine. Newest mtime wins, and
//     the envelope has to be checked for a `payload.current` before it is
//     trusted: some of those files are a different schema version.
//  2. A snapshot is not necessarily about today. `--period week` writes a
//     file of exactly the same shape, and rendering its total under the word
//     "today" is a lie. `payload.current.label` says which period it is, so
//     the walk prefers a snapshot labelled with today's date, then the daily
//     cache's newest day (a true daily figure, usually yesterday's, since it
//     is recomputed just after midnight), and only then any snapshot at all -
//     with `periodLabel` always saying what the number actually covers.
//  3. Nobody here refreshes those files. Whatever runs codeburn does - the
//     bar plugin polls every 300 s - so this component cannot pretend the
//     number is current. It carries the source's own timestamp and exposes
//     `ageSeconds`, `ageLabel` and `stale`, and a view is expected to SHOW
//     them. `recompute()` is the escape hatch: it runs the same read-only
//     command the bar plugin's status.sh runs, but it is on-demand only,
//     never on a timer, because it measures 1.26 s warm on this machine.
//
// Costs are money, so the raw value and its display form are kept apart:
// `cost` is never rounded, `costLabel` abbreviates above 1000, and
// `costExactLabel` always spells the cents out. The formatters match
// t1nk33r.codeburn's Panel.qml:100-113 on purpose - a figure in the bar and
// the same figure in a widget must not be worded differently.
//
// `active` is what a view binds to its own `visible`: false only while the
// monitor is switched off (DPMS) - the one "not being drawn" state the shell
// can see, since a widget sits on every workspace by design - and it stops
// both the mtime scan and the clock. Unknown reads as true.
QtObject {
  id: cb

  property bool active: true
  // The mtime scan only stats a handful of files; the re-read and the JSON
  // parse happen ONLY when a path or an mtime actually changed. Half the
  // upstream cadence (300 s), so a fresh snapshot is picked up promptly
  // without ever spawning codeburn ourselves.
  property int intervalMs: 150000
  // Three missed upstream refreshes. Below that, "stale" would flag the
  // normal gap between two polls.
  property int staleAfterSec: 900

  property bool loaded: false
  // "" when a source parsed, otherwise why nothing is on screen. Codeburn
  // simply never having run is one of those reasons, and it is a state, not
  // a crash.
  property string errorMessage: ""

  // ── What period the numbers describe ────────────────────────────────
  // Straight from the source: "Today (2026-09-09)" for a today snapshot,
  // "9 Sep" for a day out of the daily cache, "Last 7 days" if that is all
  // that was on disk. A view must show this next to the total.
  property string periodLabel: ""
  // Reads `_nowMs` on purpose: the clock below is what makes this flip at
  // midnight instead of holding yesterday's verdict until the next parse.
  readonly property bool isToday: cb.periodLabel.indexOf(
    Qt.formatDate(new Date(cb._nowMs), "yyyy-MM-dd")) >= 0

  // ── Money ───────────────────────────────────────────────────────────
  property string currency: "$"
  property string currencyCode: "USD"
  property real cost: 0

  // ── Volume ──────────────────────────────────────────────────────────
  property int calls: 0
  property int sessions: 0
  // Reals, not ints: cacheReadTokens is 4.1e8 for one day here and a wider
  // period runs past what an int can hold.
  property real inputTokens: 0
  property real outputTokens: 0
  property real cacheReadTokens: 0
  property real cacheWriteTokens: 0
  property real cacheHitPercent: 0

  readonly property real totalTokens:
    cb.inputTokens + cb.outputTokens + cb.cacheReadTokens + cb.cacheWriteTokens

  // ── Breakdowns, biggest first ───────────────────────────────────────
  // [{ name, cost, calls, costLabel, share }]  share is 0..1 of `cost`.
  property var topModels: []
  // [{ name, cost, sessions, costLabel, share }]
  property var topProjects: []
  // [{ id, label, cost, calls, costLabel, share }] - only providers that
  // actually spent something; a column of zeroes is noise.
  property var providers: []

  // The daily history, oldest first, newest LAST - which is the order a
  // chart draws left to right, and the order both source files already use.
  // [{ date, cost, calls, label, costLabel }]
  property var days: []

  // Scale and alarm for a history chart, computed once here so the two
  // presentations cannot disagree about what counts as a bad day.
  readonly property real peakDailyCost: {
    var m = 0
    for (var i = 0; i < cb.days.length; i++) m = Math.max(m, cb.days[i].cost)
    return Math.max(m, cb.cost)
  }
  // Median of the COMPLETED days - the newest entry is the period in
  // progress and would drag its own baseline down.
  readonly property real medianDailyCost: {
    var v = []
    for (var i = 0; i < cb.days.length - 1; i++)
      if (cb.days[i].cost > 0) v.push(cb.days[i].cost)
    if (v.length === 0) return 0
    v.sort(function (a, b) { return a - b })
    var mid = Math.floor(v.length / 2)
    return v.length % 2 ? v[mid] : (v[mid - 1] + v[mid]) / 2
  }
  // The one thing worth an accent: this period has already cost twice a
  // typical day. Nothing else in this component is an alarm.
  readonly property bool spike:
    cb.medianDailyCost > 0 && cb.cost >= cb.medianDailyCost * 2

  // ── Preformatted labels ─────────────────────────────────────────────
  readonly property string costLabel: cb.formatCost(cb.cost)
  // Always the full cents, never abbreviated - what a tile with room shows
  // so the compact form above it is never the only figure on screen.
  readonly property string costExactLabel: cb.currency + Number(cb.cost).toFixed(2)
  readonly property string tokenLabel: cb.formatTokens(cb.totalTokens)
  // Truncated to a tenth, never rounded up: 99.994% is not "100%", and a
  // hit rate printed as 100 claims the period spent no fresh input at all.
  readonly property string cacheLabel: {
    var p = Math.max(0, Math.min(100, Number(cb.cacheHitPercent)))
    var t = Math.floor(p * 10) / 10
    return (t % 1 === 0 ? String(t) : t.toFixed(1)) + "%"
  }

  // ── Freshness ───────────────────────────────────────────────────────
  property string sourcePath: ""
  // "snapshot" | "daily" | "live" | "" - which of the three paths produced
  // the numbers above.
  property string sourceKind: ""
  // The source's own observation time (the envelope's `observedAtMs` when it
  // has one, the file's mtime otherwise), never "when we read it".
  property real sourceMtimeMs: 0

  property real _nowMs: Date.now()

  readonly property int ageSeconds: cb.sourceMtimeMs > 0
    ? Math.max(0, Math.round((cb._nowMs - cb.sourceMtimeMs) / 1000)) : -1
  readonly property bool stale: cb.ageSeconds > cb.staleAfterSec

  // One string, so a widget cannot invent its own wording for it.
  readonly property string ageLabel: {
    var s = cb.ageSeconds
    if (s < 0) return ""
    if (s < 60) return "Just now"
    if (s < 3600) return Math.floor(s / 60) + " min old"
    if (s < 172800) return Math.floor(s / 3600) + " h old"
    return Math.floor(s / 86400) + " d old"
  }

  readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/codeburn"

  // ── Formatters ──────────────────────────────────────────────────────
  function formatCost(v) {
    var n = Number(v)
    if (!isFinite(n)) return cb.currency + "0.00"
    var a = Math.abs(n)
    var sign = n < 0 ? "-" : ""
    if (a === 0) return cb.currency + "0.00"
    // A fraction of a cent is not nothing: "$0.00" reads as free.
    if (a < 0.01) return "<" + cb.currency + "0.01"
    if (a >= 1000000) return sign + cb.currency + (a / 1000000).toFixed(1) + "M"
    if (a >= 1000) return sign + cb.currency + (a / 1000).toFixed(1) + "k"
    return sign + cb.currency + a.toFixed(2)
  }

  function formatTokens(v) {
    var n = Number(v)
    if (!isFinite(n) || n <= 0) return "0"
    if (n >= 1000000000) return (n / 1000000000).toFixed(1) + "B"
    if (n >= 1000000) return (n / 1000000).toFixed(1) + "M"
    if (n >= 1000) return (n / 1000).toFixed(1) + "k"
    return String(Math.round(n))
  }

  // "2026-09-09" -> "9 Sep". Built component-wise rather than through
  // `new Date(iso)`, which parses a bare date as UTC midnight and lands on
  // the previous day for anyone west of Greenwich.
  function formatDate(iso) {
    var p = String(iso || "").split("-")
    if (p.length !== 3) return String(iso || "")
    var d = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]))
    return Qt.formatDate(d, "d MMM")
  }

  // Re-stat the cache. Cheap, and re-reads nothing unless something moved.
  function refresh() { if (cb.active) scanProc.running = true }

  // ── Recompute, on demand only ───────────────────────────────────────
  // The same invocation t1nk33r.codeburn's status.sh execs: no network, no
  // optimizer, no timeline, no writes outside codeburn's own cache. Measured
  // 1.26 s warm here, which is far too slow to sit in a poll loop, so it is
  // never on a timer - a view calls it when someone asks for fresh numbers.
  property bool recomputing: false
  property bool _liveApplied: false

  function recompute() {
    if (!cb.active || cb.recomputing) return
    cb.recomputing = true
    cb._liveApplied = false
    syncProc.running = true
  }

  // ── Source selection ────────────────────────────────────────────────
  // [{ path, kind, mtimeMs }] in priority order: snapshots newest first,
  // then the daily cache.
  property var _candidates: []
  property int _try: 0
  property string _scanSig: ""
  // The best non-preferred source seen during a walk, kept so a machine with
  // no today snapshot still shows something true.
  property var _dailyFallback: null
  property var _anyFallback: null
  property string _readPath: ""

  function _todayIso() { return Qt.formatDate(new Date(), "yyyy-MM-dd") }

  property Process _scanProc: Process {
    id: scanProc
    running: false
    // QML cannot list a directory, so one short shell does it. Two loops on
    // purpose: the snapshots are ranked by mtime and capped (18 of them here,
    // and only the newest few can possibly be relevant), while the daily
    // cache is appended unconditionally as the last resort - ranking it by
    // mtime with the rest would drop it off the end of the list on any busy
    // day. `exit 0` because an unmatched glob is a normal state.
    command: ["sh", "-c",
      "d=\"$1\"; " +
      "for f in \"$d\"/status-snapshot.*.json; do [ -f \"$f\" ] && stat -c '%Y %n' \"$f\"; done " +
      "| sort -rn | head -n 4; " +
      "[ -f \"$d/daily-cache.v31.json\" ] && stat -c '%Y %n' \"$d/daily-cache.v31.json\"; " +
      "exit 0",
      "sh", cb.cacheDir]
    stdout: StdioCollector {
      onStreamFinished: cb._applyScan(String(this.text || ""))
    }
  }

  function _applyScan(text) {
    var out = []
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line === "") continue
      var sp = line.indexOf(" ")
      if (sp <= 0) continue
      var secs = Number(line.substring(0, sp))
      var path = line.substring(sp + 1)
      if (!isFinite(secs) || path === "") continue
      out.push({
        path: path,
        kind: path.indexOf("daily-cache") >= 0 ? "daily" : "snapshot",
        mtimeMs: secs * 1000
      })
    }

    if (out.length === 0) {
      cb._candidates = []
      cb._scanSig = ""
      cb.loaded = true
      // Short on purpose: this lands on a 192x192 tile. `cacheDir` is a
      // property, for a view with room to name the place.
      cb.errorMessage = "Codeburn has not run"
      return
    }

    // Nothing moved: the parse is the expensive half, so skip it.
    var sig = text
    if (sig === cb._scanSig && cb.loaded && cb.errorMessage === "") return
    cb._scanSig = sig
    cb._candidates = out
    cb._try = 0
    cb._dailyFallback = null
    cb._anyFallback = null
    cb._readOne()
  }

  property FileView _file: FileView {
    id: file
    path: cb._readPath
    printErrors: false
    onLoaded: cb._consider(text())
    onLoadFailed: cb._advance()
  }

  function _readOne() {
    if (cb._try >= cb._candidates.length) { cb._settleFallback(); return }
    var p = cb._candidates[cb._try].path
    // Same path, newer mtime: `path` did not change, so nothing would load.
    if (cb._readPath === p) file.reload()
    else cb._readPath = p
  }

  function _advance() { cb._try += 1; cb._readOne() }

  function _consider(text) {
    var c = cb._candidates[cb._try]
    if (!c) return
    var doc = null
    try {
      doc = JSON.parse(String(text || ""))
    } catch (e) {
      cb._advance()
      return
    }
    if (!doc || typeof doc !== "object") { cb._advance(); return }

    if (c.kind === "daily") {
      if (!Array.isArray(doc.days) || doc.days.length === 0) { cb._advance(); return }
      if (!cb._dailyFallback)
        cb._dailyFallback = { doc: doc, path: c.path, whenMs: c.mtimeMs }
      cb._advance()
      return
    }

    // A snapshot of a schema we do not know is not a snapshot.
    var p = doc.payload
    if (!p || !p.current) { cb._advance(); return }
    // The envelope times itself; the file mtime is only a backstop.
    var whenMs = isFinite(Number(doc.observedAtMs)) && Number(doc.observedAtMs) > 0
      ? Number(doc.observedAtMs) : c.mtimeMs

    if (String(p.current.label || "").indexOf(cb._todayIso()) >= 0) {
      cb._applyPayload(p, c.path, whenMs, "snapshot")
      return
    }
    if (!cb._anyFallback)
      cb._anyFallback = { payload: p, path: c.path, whenMs: whenMs }
    cb._advance()
  }

  // No snapshot was about today. A true daily total from the rollup beats a
  // week's or a month's sum shown as a day, so it goes first.
  function _settleFallback() {
    if (cb._dailyFallback) {
      cb._applyDaily(cb._dailyFallback.doc, cb._dailyFallback.path,
                     cb._dailyFallback.whenMs)
      return
    }
    if (cb._anyFallback) {
      cb._applyPayload(cb._anyFallback.payload, cb._anyFallback.path,
                       cb._anyFallback.whenMs, "snapshot")
      return
    }
    cb.loaded = true
    cb.errorMessage = "No readable codeburn cache"
  }

  // ── Shaping ─────────────────────────────────────────────────────────
  function _share(v, total) {
    var t = Number(total)
    return t > 0 ? Math.max(0, Math.min(1, Number(v) / t)) : 0
  }

  function _rank(rows, total, limit) {
    rows.sort(function (a, b) { return b.cost - a.cost })
    var out = rows.slice(0, limit)
    for (var i = 0; i < out.length; i++) {
      out[i].costLabel = cb.formatCost(out[i].cost)
      out[i].share = cb._share(out[i].cost, total)
    }
    return out
  }

  function _days(list) {
    var out = []
    if (!Array.isArray(list)) return out
    for (var i = 0; i < list.length; i++) {
      var d = list[i] || {}
      var date = String(d.date || "")
      if (date === "") continue
      out.push({
        date: date,
        cost: Number(d.cost || 0),
        calls: Math.round(Number(d.calls || 0)),
        label: cb.formatDate(date),
        costLabel: cb.formatCost(Number(d.cost || 0))
      })
    }
    // Both sources already emit oldest-first; sorting makes that a
    // guarantee a chart can rely on instead of an observation.
    out.sort(function (a, b) { return a.date < b.date ? -1 : (a.date > b.date ? 1 : 0) })
    return out
  }

  function _applyPayload(p, path, whenMs, kind) {
    var cur = p.current || {}
    var money = p.currency || {}
    var total = Number(cur.cost || 0)

    cb.currency = String(money.symbol || "$")
    cb.currencyCode = String(money.code || "USD")
    cb.periodLabel = String(cur.label || "")
    cb.cost = total
    cb.calls = Math.round(Number(cur.calls || 0))
    cb.sessions = Math.round(Number(cur.sessions || 0))
    cb.inputTokens = Number(cur.inputTokens || 0)
    cb.outputTokens = Number(cur.outputTokens || 0)
    cb.cacheReadTokens = Number(cur.cacheReadTokens || 0)
    cb.cacheWriteTokens = Number(cur.cacheWriteTokens || 0)
    cb.cacheHitPercent = Number(cur.cacheHitPercent || 0)

    var models = []
    var src = Array.isArray(cur.topModels) ? cur.topModels : []
    for (var i = 0; i < src.length; i++) {
      var m = src[i] || {}
      if (String(m.name || "") === "") continue
      models.push({
        name: String(m.name),
        cost: Number(m.cost || 0),
        calls: Math.round(Number(m.calls || 0))
      })
    }
    cb.topModels = cb._rank(models, total, 5)

    var projects = []
    var psrc = Array.isArray(cur.topProjects) ? cur.topProjects : []
    for (var j = 0; j < psrc.length; j++) {
      var pr = psrc[j] || {}
      if (String(pr.name || "") === "") continue
      projects.push({
        name: String(pr.name),
        cost: Number(pr.cost || 0),
        sessions: Math.round(Number(pr.sessions || 0))
      })
    }
    cb.topProjects = cb._rank(projects, total, 5)

    // providerDetails carries the label and the call count; the flat
    // `providers` map is only a cost per id, so it is the fallback.
    var provs = []
    var dsrc = Array.isArray(cur.providerDetails) ? cur.providerDetails : []
    for (var k = 0; k < dsrc.length; k++) {
      var pd = dsrc[k] || {}
      if (Number(pd.cost || 0) <= 0) continue
      provs.push({
        id: String(pd.id || ""),
        label: String(pd.label || pd.id || ""),
        cost: Number(pd.cost || 0),
        calls: Math.round(Number(pd.calls || 0))
      })
    }
    if (provs.length === 0 && cur.providers && typeof cur.providers === "object") {
      var ids = Object.keys(cur.providers)
      for (var n = 0; n < ids.length; n++) {
        var c = Number(cur.providers[ids[n]] || 0)
        if (c <= 0) continue
        provs.push({ id: ids[n], label: ids[n].toUpperCase(), cost: c, calls: 0 })
      }
    }
    cb.providers = cb._rank(provs, total, 5)

    cb.days = cb._days(p.history ? p.history.daily : null)

    cb.sourcePath = path
    cb.sourceKind = kind
    cb.sourceMtimeMs = whenMs
    cb._nowMs = Date.now()
    cb.errorMessage = ""
    cb.loaded = true
  }

  // The rollup carries no currency block and no precomputed cache-hit rate,
  // so both are derived: USD is codeburn's own default, and the hit rate is
  // reads over reads-plus-fresh-input, which reproduces the snapshot's
  // `cacheHitPercent` to five decimals on this machine's data.
  function _applyDaily(doc, path, whenMs) {
    // Called after the walk has ended, so a dead end here must fall through
    // to whatever snapshot was kept - never back into `_advance()`, which
    // would re-enter this same fallback forever.
    var days = cb._days(doc.days)
    var raw = null
    var newest = days.length > 0 ? days[days.length - 1].date : ""
    for (var i = 0; newest !== "" && i < doc.days.length; i++)
      if (String(doc.days[i].date || "") === newest) { raw = doc.days[i]; break }
    if (!raw) {
      cb._dailyFallback = null
      cb._settleFallback()
      return
    }

    var total = Number(raw.cost || 0)
    cb.currency = "$"
    cb.currencyCode = "USD"
    cb.periodLabel = cb.formatDate(newest)
    cb.cost = total
    cb.calls = Math.round(Number(raw.calls || 0))
    cb.sessions = Math.round(Number(raw.sessions || 0))
    cb.inputTokens = Number(raw.inputTokens || 0)
    cb.outputTokens = Number(raw.outputTokens || 0)
    cb.cacheReadTokens = Number(raw.cacheReadTokens || 0)
    cb.cacheWriteTokens = Number(raw.cacheWriteTokens || 0)
    var reads = cb.cacheReadTokens
    cb.cacheHitPercent = (reads + cb.inputTokens) > 0
      ? reads / (reads + cb.inputTokens) * 100 : 0

    cb.topModels = cb._rank(cb._mapToRows(raw.models, "calls"), total, 5)
    cb.topProjects = cb._rank(cb._mapToRows(raw.projects, "sessions"), total, 5)

    var provs = cb._mapToRows(raw.providers, "calls")
    for (var j = 0; j < provs.length; j++) {
      provs[j].id = provs[j].name
      provs[j].label = String(provs[j].name).toUpperCase()
    }
    cb.providers = cb._rank(provs, total, 5)

    cb.days = days
    cb.sourcePath = path
    cb.sourceKind = "daily"
    cb.sourceMtimeMs = whenMs
    cb._nowMs = Date.now()
    cb.errorMessage = ""
    cb.loaded = true
  }

  // The rollup keys its breakdowns by name ({ "anthropic/claude-opus-5":
  // { cost, calls, ... } }) where the snapshot uses arrays of objects.
  function _mapToRows(map, secondKey) {
    var out = []
    if (!map || typeof map !== "object") return out
    var keys = Object.keys(map)
    for (var i = 0; i < keys.length; i++) {
      var v = map[keys[i]] || {}
      var row = { name: keys[i], cost: Number(v.cost || 0) }
      row[secondKey] = Math.round(Number(v[secondKey] || 0))
      out.push(row)
    }
    return out
  }

  property Process _syncProc: Process {
    id: syncProc
    running: false
    // status.sh exports this PATH before exec'ing codeburn, because the
    // shell's own environment does not carry ~/.npm-global/bin and the CLI
    // is an npm global here. Its stdout is the BARE payload - the same shape
    // as a snapshot's `payload`, without the envelope.
    command: ["sh", "-c",
      "PATH=\"$HOME/.npm-global/bin:$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH\"; " +
      "exec codeburn status --format menubar-json --scope combined " +
      "--period today --no-optimize --no-timeline"]
    stdout: StdioCollector {
      onStreamFinished: {
        var doc = null
        try {
          doc = JSON.parse(String(this.text || ""))
        } catch (e) {
          return
        }
        if (doc && doc.current) {
          cb._applyPayload(doc, "codeburn status --period today", Date.now(), "live")
          cb._liveApplied = true
        }
      }
    }
    onExited: function (code) {
      cb.recomputing = false
      if (code !== 0 && !cb.loaded) {
        cb.loaded = true
        cb.errorMessage = "codeburn exited " + code
      }
      // Only when nothing came back on stdout. codeburn serves a MEMOIZED
      // snapshot when the corpus fingerprint is unchanged, keeping the old
      // `observedAtMs`, so re-reading the file here would age the reading
      // back to "5 min old" the instant someone asked for it fresh - which
      // reads as a failed refresh. The scan timer still adopts the file
      // later, and by then its own timestamp is the newer one.
      if (!cb._liveApplied) cb.refresh()
    }
  }

  property Timer _scan: Timer {
    interval: cb.intervalMs
    running: cb.active
    repeat: true
    triggeredOnStart: true
    onTriggered: cb.refresh()
  }

  // Age has to keep moving between scans, or a tile that went stale while
  // nothing changed would keep claiming the data is fresh. No process, no
  // parse - one Date.now().
  property Timer _clock: Timer {
    interval: 30000
    running: cb.active
    repeat: true
    onTriggered: cb._nowMs = Date.now()
  }
}
