import QtQuick
import Quickshell
import Quickshell.Io
import "JsonRead.js" as JsonRead

// Claude Code's rate-limit windows, from this machine's own usage record.
//
// There is no webhook and no token here. `omarchy-agent-usage-claude` (the
// collector shipped with Omarchy, run by `omarchy-agent-usage-update`) already
// reads Claude Code's OAuth login on this host, asks Anthropic's usage
// endpoint for the authoritative limits, and writes one display-ready JSON
// record; `t1nk33r.agents` runs it and draws it in the bar. This component is
// a second reader of that same record, the way the agents panel's own
// `Agent.qml` is: it watches the file and never talks to a disk format or an
// endpoint itself. Nothing here holds a credential, and no process is spawned
// to get the numbers - the record appears when the collector writes it.
//
//   ~/.local/state/omarchy/agents/usage/claude.json
//   {
//     "schemaVersion": 1, "id": "claude", "name": "Claude Code",
//     "updatedAt": "2026-09-13T19:58:41.321087+00:00",
//     "ready": true, "tierLabel": "Max 20x",
//     "usageStatusText": "", "authHelpText": "",
//     "limits": [
//       { "label": "Session (5-hour)", "percent": 0.0,  "resetsAt": "" },
//       { "label": "Weekly (7-day)",   "percent": 1.0,
//         "resetsAt": "2026-09-13T23:00:00.200565+00:00" },
//       { "label": "Fable Weekly", "title": "Fable Weekly", "percent": 1.0,
//         "resetsAt": "2026-09-13T23:00:00.200779+00:00" }
//     ],
//     ... local transcript stats this widget does not read ...
//   }
//
// The three windows the operator asked for are exactly `limits[]`: the 5-hour
// session, the 7-day week, and the per-model week ("Fable Weekly" on this
// plan; "Opus Weekly" or "Sonnet Weekly" on an older one). The array is what
// the collector's own README calls the panel's contract, so this widget
// renders whatever arrives rather than expecting three rows - a plan without a
// model-scoped window simply sends two.
//
// The record's own vocabulary, kept, not re-invented
// -------------------------------------------------
//  * `percent` is a FRACTION 0..1 in this record (the collector normalises
//    percent-scaled and fractional payloads to one scale). It is rendered as
//    a percentage; a value above 1 can only be a record written by something
//    else, and is read as an already-scaled percentage rather than as 4000%.
//  * `resetsAt` is ISO-8601 with an offset, and "" means the window reports
//    none (an unused session window has none). A reset already in the past
//    means the percentage belongs to the window BEFORE it: the row renders as
//    `—` with an empty bar, never the stale figure. (The collector drops such
//    a cached limit, so this is defence in depth; the same rule is what the
//    phone and menu-bar clients in ios-widget-backends/claude-usage use.)
//  * `updatedAt` is the record's own write time - the only freshness signal
//    the source has - so the age shown is the age of the RECORD, and the
//    component says so. `usageStatusText` / `authHelpText` are the collector's
//    own sentences for a probe that failed ("Sign-in expired", "Anthropic's
//    usage endpoint is rate limiting checks right now", ...): they are carried
//    through verbatim, and the windows the collector kept are still drawn
//    beside them, because a last-known-open window is a reading, not a
//    failure.
//  * there is no `severity` field, so the warning/critical bands are the
//    clients' own thresholds - 50% amber, 80% red - which is exactly the
//    fallback both of them apply when the API sends no severity.
//
// What this component does NOT do
// -------------------------------
// It does not run the collector, and it does not read
// `~/.claude/.credentials.json` or call the usage endpoint itself. The
// collector already does that once per refresh for the whole machine; a tile
// per screen re-probing a rate-limited endpoint would be a second, competing
// client. The cost of that choice is freshness: the record is as new as the
// last `omarchy-agent-usage-update` run (the agents widget asks every 900 s by
// default, and sooner after a transport failure). `ageSeconds` is that
// freshness, and a tile shows it.
QtObject {
  id: cu

  // The record `t1nk33r.agents` watches, derived exactly as its `Main.qml`
  // derives it: $XDG_STATE_HOME, else ~/.local/state.
  readonly property string stateHome: {
    var env = Quickshell.env("XDG_STATE_HOME")
    if (env && String(env) !== "") return String(env)
    return Quickshell.env("HOME") + "/.local/state"
  }
  readonly property string path: cu.stateHome + "/omarchy/agents/usage/claude.json"
  // The directory the tile names when there is no record at all: it is what to
  // look at, and it contains no secret.
  readonly property string dir: cu.stateHome + "/omarchy/agents/usage"

  // A tile on a screen that is off stops its clock (there is no network work
  // here to stop - the file watch is a handful of bytes on inotify).
  property bool active: true
  // Countdowns are minute-grained, and a window whose reset has passed must
  // flip to `—` promptly.
  property int clockSec: 30
  // Two of the agents widget's default 900 s refresh intervals. Past this the
  // record is worth flagging as old; it is this widget's threshold, not the
  // source's - the source's own signal is `updatedAt`, which is always shown.
  property int oldAfterSec: 1800

  // ── What a view draws ────────────────────────────────────────────────
  // "loading" | "ready" | "empty" | "missing" | "invalid"
  //   ready    the record carries at least one window
  //   empty    a record, but no windows in it (and possibly a reason)
  //   missing  no record: the collector has not written one for claude
  //   invalid  a record that does not parse
  property string state: "loading"
  property bool loaded: false
  // A sentence for the tile, "" when there is nothing wrong: the collector's
  // own words for a probe or a login it could not use, or - when it dropped
  // the probe on the floor without telling anyone in words (`retryAdvised`) -
  // this component's plain statement that the figures are the last known
  // ones. Built here so the two drawings cannot word the same state
  // differently.
  property string notice: ""
  // The two lines a tile with no numbers draws. `headline` names the state,
  // `detail` says what to look at or what to do about it.
  readonly property string headline: cu.state === "loading" ? "Reading the record"
    : cu.state === "missing" ? "No Claude record"
    : cu.state === "invalid" ? "Unreadable record"
    : (cu.statusText !== "" ? cu.statusText : "No limits in the record")
  readonly property string detail: cu.state === "missing"
      ? "claude.json is not in " + cu.dir
      : (cu.helpText !== "" ? cu.helpText
      : (cu.state === "invalid" ? "The record does not parse as JSON" : ""))

  // Straight from the record.
  property string sourceName: "Claude Code"
  property string tier: ""
  // The collector's two sentences. `usageStatusText` is set ONLY when the
  // probe or the login failed ("Waiting for auth", "Sign-in expired",
  // "Claude limits unavailable"); `authHelpText` is carried in every record -
  // a healthy one included - as the sentence to show when it did, so it is
  // never itself an alarm.
  property string statusText: ""
  property string helpText: ""
  // Set when a probe reached no server at all, so the shell retries sooner.
  // In that case the record keeps the last limits whose window is still open
  // and carries no sentence of its own, which is why the tile words it.
  property bool retryAdvised: false
  property bool recordReady: false
  property real updatedAtMs: 0

  // [{ key, label, percent, display, barValue, level, resetsEpoch, resetIn,
  //    resetsAt, expired }] in the record's own order. `percent` is -1 when
  // there is no live number (the window's reset has passed, or it carries no
  // percentage); `level` is 0 normal, 1 warning, 2 critical, and 0 for a
  // window with no live number, because the colour belongs to the number.
  property var windows: []

  // The raw limits of the last good read, so the clock can re-derive the rows
  // (countdowns, the expiry flip) without re-reading the file.
  property var _raw: []

  property real _nowMs: Date.now()

  // The record was read and says something. "Missing" and "invalid" are
  // states with a name, not blanks.
  readonly property bool ready: cu.state === "ready"
  // The collector said something about the probe or the login. The windows, if
  // any, are still drawn: the last known figures beside the reason they are
  // the last known ones.
  readonly property bool warned: cu.notice !== ""

  readonly property int ageSeconds: cu.updatedAtMs > 0
    ? Math.max(0, Math.round((cu._nowMs - cu.updatedAtMs) / 1000)) : -1
  readonly property string ageLabel: cu.ageSeconds < 0 ? "" : cu.formatAge(cu.ageSeconds)
  // Older than two of the collector's refresh intervals. Not the same thing as
  // "wrong": the record is still what the machine last knew.
  readonly property bool old: cu.ageSeconds > cu.oldAfterSec

  // The highest live percentage - what the small tile shows, the same window
  // the phone's small widget and the menu-bar item pick. Rows with no live
  // number lose, but a record whose every window has rolled still returns a
  // row so the tile can name the window it has nothing for.
  readonly property var tightest: {
    var best = null
    for (var i = 0; i < cu.windows.length; i++) {
      var w = cu.windows[i]
      if (w.percent < 0) continue
      if (best === null || w.percent > best.percent) best = w
    }
    if (best === null && cu.windows.length > 0) best = cu.windows[0]
    return best
  }

  // ── The sentences a tile draws ───────────────────────────────────────
  // Owned HERE rather than by each drawing. Two drawings keeping their own
  // byte-identical copy of a sentence is a copy, not a guarantee - nothing
  // makes the two agree tomorrow - and this component already owns the
  // record's own vocabulary (`notice`, `headline`, `detail`). The strings are
  // about the record, so they live with the record's reader and both styles
  // read them.

  // The window the header names: the tightest live one, exactly the window
  // the phone's own header and the menu-bar item pick.
  readonly property string resetLine: {
    var lead = cu.tightest
    if (!lead) return ""
    return lead.resetIn !== "" ? lead.label + " " + lead.resetIn : lead.label
  }

  // The freshness line - the phone's "stale · as of 23m ago", in this
  // source's own terms: the record's age, and the collector's sentence when
  // it had one.
  readonly property string freshnessText: {
    if (!cu.ready) return ""
    var parts = []
    if (cu.notice !== "") parts.push(cu.notice)
    // "stale" marks an old record and nothing else, and the "as of" falls
    // away when the collector's own sentence is already on the line: at
    // the 192 px preset "Sign-in expired  ·  as of 3h 7m ago" measures
    // 169 px against a 160 px box and elides, while the same line without
    // the two words fits (measured on the capture).
    if (cu.ageLabel !== "") {
      var prefix = cu.notice !== "" ? "" : (cu.old ? "stale · as of " : "as of ")
      parts.push(prefix + cu.ageLabel)
    }
    return parts.join("  ·  ")
  }

  // Provenance, for the presets with room for a line under the freshness
  // one: which record, and which plan's limits these are.
  readonly property string footerText: cu.sourceName
    + (cu.tier !== "" ? "  ·  " + cu.tier : "")

  // ── The record ───────────────────────────────────────────────────────
  // The same shape as t1nk33r.agents' own Agent.qml: a watched FileView, no
  // process, no timer on the file.
  property FileView _view: FileView {
    id: view
    path: cu.path
    watchChanges: true
    printErrors: false
    onFileChanged: view.reload()
    onLoaded: cu._apply(view.text())
    onLoadFailed: cu._missing()
  }

  // The clock: countdowns and the expiry flip. No file work happens here.
  property Timer _clock: Timer {
    interval: cu.clockSec * 1000
    running: cu.active
    repeat: true
    onTriggered: cu._tick()
  }

  function _tick() {
    cu._nowMs = Date.now()
    if (cu._raw.length > 0) cu.windows = cu._normalise(cu._raw)
  }

  function _missing() {
    // A record that was there and is gone is the same state as one that was
    // never written: the collector has not run for this agent.
    cu._raw = []
    cu.windows = []
    cu.loaded = false
    cu.state = "missing"
    cu.updatedAtMs = 0
    cu.sourceName = "Claude Code"
    cu.tier = ""
    cu.statusText = ""
    cu.helpText = ""
    cu.retryAdvised = false
    cu.recordReady = false
    cu.notice = ""
  }

  function _apply(text) {
    var record = JsonRead.parseOrNull(text)
    if (!record || typeof record !== "object") {
      cu._missing()
      cu.state = "invalid"
      return
    }
    cu.loaded = true
    cu.recordReady = record.ready === true
    cu.sourceName = JsonRead.str(record.name, "Claude Code")
    cu.tier = JsonRead.str(record.tierLabel, "")
    cu.statusText = JsonRead.str(record.usageStatusText, "")
    cu.helpText = JsonRead.str(record.authHelpText, "")
    cu.retryAdvised = record.retryAdvised === true
    cu.updatedAtMs = cu.parseIsoMs(JsonRead.str(record.updatedAt, ""))
    cu._nowMs = Date.now()

    cu._raw = Array.isArray(record.limits) ? record.limits : []
    cu.windows = cu._normalise(cu._raw)
    cu.state = cu.windows.length > 0 ? "ready" : "empty"

    // The status text is the collector's own alarm and the only one it sets;
    // with no status but a dropped probe, the figures that came through are
    // the last known ones and the tile says just that.
    cu.notice = cu.statusText !== "" ? cu.statusText
      : (cu.retryAdvised ? "Last known limits" : "")
  }

  // The record names a window the way its own panel wants it - "Session
  // (5-hour)", "Weekly (7-day)", "Fable Weekly" - and that panel has room for
  // all of it. A tile does not, and the phone's widget settled on the short
  // forms: Session, Week, and the model's name alone ("Fable" on a current Max
  // plan, "Opus" or "Sonnet" on an older one). So the parenthetical goes (it
  // is a duration, not a name: "Opus 5 (1M context) Weekly" is the Opus 5
  // window), and a trailing " Weekly" goes with it - the row is already under
  // a weekly reading and the model is what tells the rows apart.
  function shortLabel(label) {
    var s = String(label || "").trim()
    var cut = s.replace(/\s*\([^)]*\)\s*/g, " ").trim()
    if (cut !== "") s = cut
    var model = s.replace(/\s+Weekly$/i, "").trim()
    if (model !== "" && model.toLowerCase() !== "weekly") s = model
    return s.toLowerCase() === "weekly" ? "Week" : s
  }

  // ── Normalising one window ───────────────────────────────────────────
  function _normalise(list) {
    var out = []
    for (var i = 0; i < list.length; i++) {
      var w = list[i]
      if (!w || typeof w !== "object") continue
      var pct = cu._percent(w)
      var reset = cu.parseIsoSec(JsonRead.str(w.resetsAt, ""))
      var expired = reset > 0 && reset * 1000 <= cu._nowMs
      var live = expired ? -1 : pct
      var raw = JsonRead.str(w.title, "")
      if (raw === "") raw = JsonRead.str(w.label, "Window")
      var label = cu.shortLabel(raw)
      out.push({
        // The record gives a window no id; its label is what the collector
        // settled a scoped window to, and it is unique per record because the
        // collector dedupes on (model, window).
        key: label,
        label: label,
        labelRaw: raw,
        percent: live,
        display: live < 0 ? "\u2014" : Math.round(live) + "%",
        barValue: live < 0 ? 0 : live / 100,
        level: cu._level(live),
        resetsEpoch: reset,
        expired: expired,
        resetIn: expired ? "reset"
          : (reset > 0 ? "resets in " + cu.formatCountdown(reset - cu._nowMs / 1000) : ""),
        resetsAt: (reset > 0 && !expired) ? cu.formatWallClock(reset) : ""
      })
    }
    return out
  }

  // The record's `percent` is a fraction (the collector normalises both
  // scales to 0..1). A value above 1 is read as an already-scaled percentage
  // rather than as a 4000% window - the same guard the collector itself
  // applies when it sniffs a payload's scale.
  function _percent(window) {
    var raw = Number(window.percent)
    if (!isFinite(raw)) return -1
    var scaled = raw > 1 ? raw : raw * 100
    return Math.max(0, Math.min(100, scaled))
  }

  // 0 normal, 1 warning, 2 critical, by the clients' own bands (WARN 50,
  // CRIT 80) - the record carries no severity to defer to. A window with no
  // live number is neutral: a number we cannot vouch for must not be red.
  function _level(percent) {
    if (percent < 0) return 0
    if (percent >= 80) return 2
    if (percent >= 50) return 1
    return 0
  }

  // ── Times ────────────────────────────────────────────────────────────
  // The collector writes ISO-8601 with an explicit offset, and its
  // microseconds are six digits deep - one past what Date.parse is required to
  // take - so the stamp is parsed here, deliberately: seconds-resolution
  // fields for the epoch, the trailing offset applied by hand. A stamp with no
  // parsable head is 0, which reads as "no time", never as "now".
  function parseIsoSec(text) {
    var m = /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})/.exec(String(text || ""))
    if (!m) return 0
    var epoch = Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]),
      Number(m[4]), Number(m[5]), Number(m[6])) / 1000
    var off = /([+-])(\d{2}):(\d{2})$/.exec(String(text))
    if (off) {
      // `-05:00` means the wall clock is five hours behind UTC, so UTC is
      // that much later.
      var sign = off[1] === "-" ? 1 : -1
      epoch += sign * (Number(off[2]) * 3600 + Number(off[3]) * 60)
    }
    return epoch > 0 ? Math.floor(epoch) : 0
  }

  function parseIsoMs(text) {
    var sec = cu.parseIsoSec(text)
    return sec > 0 ? sec * 1000 : 0
  }

  // "2d 4h", "11h 2m", "41m", "now" - truncated, never rounded, so a
  // countdown can only ever understate what is left.
  function formatCountdown(seconds) {
    var s = Number(seconds)
    if (!isFinite(s) || s <= 0) return "now"
    var whole = Math.floor(s)
    var days = Math.floor(whole / 86400)
    var hours = Math.floor((whole % 86400) / 3600)
    var minutes = Math.floor((whole % 3600) / 60)
    if (days > 0) return days + "d " + hours + "h"
    if (hours > 0) return hours + "h " + minutes + "m"
    return minutes + "m"
  }

  // "just now", "41m ago", "2d 4h ago".
  function formatAge(seconds) {
    if (!isFinite(seconds) || seconds < 0) return ""
    if (seconds < 120) return "just now"
    return cu.formatCountdown(seconds) + " ago"
  }

  // "Mon 02:00" in this desktop's own zone. The C locale keeps the day name
  // English whatever the machine's locale is.
  function formatWallClock(epochSeconds) {
    return Qt.locale("C").toString(new Date(epochSeconds * 1000), "ddd HH:mm")
  }
}
