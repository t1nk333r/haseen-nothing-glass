import QtQuick
import Quickshell
import Quickshell.Io
import "JsonRead.js" as JsonRead

// The omarr fleet and its queue, read out of the feed omarr publishes.
//
// Where this comes from, and why not from the plugin next door
// ------------------------------------------------------------
// `t1nk33r.omarr` is installed and running here. It declares a `service`, but
// a desktop widget cannot reach it: the shell scopes a third-party plugin to
// its own id, so `shell.serviceFor("t1nk33r.omarr")` is null for any other
// caller. The plugin solves that itself, in this tree's own idiom: its
// `Service.qml` projects the live snapshots and queue into
//
//   $HOME/.local/state/omarchy/omarr/feed.json
//
// through the atomic writer its credentials and seen documents already use --
// a same-directory temp file, `umask 077`, `chmod 600` and `mv -f -T` over the
// destination -- so a reader sees the old document or the new one and never
// half of either. That is the route every other widget on this machine reads
// its source by, and the reason this component needs no credentials, no API
// call and no network.
//
// The path is built from `HOME` and nothing else on purpose: the writer builds
// `stateDir` from `Quickshell.env("HOME")` too (`Service.qml:46`), and it does
// NOT consult `XDG_STATE_HOME`. An XDG-aware reader would look in a directory
// omarr never writes to on a machine that moved its state root, and would draw
// "omarr has not run" forever while the file sat one directory over.
//
// The contract is the `published feed` section of omarr's own `Model.js`
// (`FEED_VERSION`, the field whitelists, `FEED_LIST_LIMIT`, the write rule),
// and its tests assert the shape. What that means for this file:
//
//   version     1. A document of another version is REPORTED, never parsed on
//               a guess - a feed this widget mis-reads is worse than none.
//   updatedAt   the time of the write, in epoch ms. The freshness signal: the
//               writer moves it on every publish, and it publishes on a
//               material change (no closer than 10 s) or on its idle refresh
//               (120 s), so it never stalls while omarr runs.
//   statusText  the bar's own summary line (`Model.barStatusText`): "1
//               downloading", "Sonarr unreachable", "6 services". Shown in
//               its own words, so the tile and the bar cannot word one line
//               differently - EXCEPT when the line is the bare fleet count,
//               the one fact the tile already carries and therefore the one
//               line it drops. See `statusLineText`.
//   badgeCount / badgeUrgent / unreadCount
//               the bar item's own badge inputs (`Model.barBadge`) - the count
//               of unreachable services, else of active downloads, and whether
//               that is a state worth the accent.
//   snapshots   one row per configured service, whole: name, kind, group,
//               health ("up" | "down" | "unknown"), statusText, paused,
//               downloadingCount, queueTotal.
//   downloads   the merged active queue, already capped at 10 by the writer,
//               each row {title, serviceName, progress 0..1, status, timeleft,
//               speed}. NOT a second queue: it is the projection the plugin
//               already merged from every service's own queue.
//   onDeck / recent / calendar
//               media rows; read here only for their counts, which is all a
//               glance needs.
//
// `downCount` is the number of services DOWN, not a queue depth (its name is
// omarr's: `Model.mergeNow`'s downCount, which `barBadge` uses). `queueTotal`
// is the per-service queue depth, summed here into `queuedTotal`.
//
// The atomic-rename trap, and what was measured
// ---------------------------------------------
// The writer publishes by rename, which replaces the inode, and a watcher
// registered on an inode goes deaf the moment it is replaced. That is the
// defect class this tree has spent a week on, so it was measured before this
// file was written rather than assumed: two FileViews on two copies of a
// document rewritten by this writer's own recipe (`mktemp` in the same
// directory, `chmod 600`, `mv -f -T`), twice with the inodes changing
// underneath each time. BOTH loads answered twice - the path watcher survives
// the rename on Quickshell 0.3.1, with `watchChanges` alone and with
// `atomicWrites` as well. `atomicWrites` is kept anyway, because it is the
// documented spelling for exactly this writer and costs nothing.
//
// The slow re-read under it is the backstop for the one case a path watch
// cannot cover: `watchChanges` on a path that does not EXIST yet never fires,
// because a watcher needs an inode to hold (the same finding
// `OmarchyLocation.qml:75` records). A tile placed before omarr ever ran, or
// after the feed was deleted, would otherwise stay blank after the first
// write. One file read a minute, no process, and none at all while nothing is
// watching - the CodeburnData/DeepSeekData pattern.
QtObject {
  id: om

  // False only while the monitor is switched off (DPMS) - the one "not being
  // drawn" state the shell can see, since a widget sits on every workspace by
  // design. No re-read runs while it is false. Unknown reads as true, so the
  // failure mode is one read, never a blank tile.
  property bool active: true

  // Two and a half of the writer's idle refresh intervals (120 s). Past this,
  // omarr is not running or not authorised - the feed is still what the
  // machine last knew, and the tile says how old it is rather than passing it
  // off as current.
  property int staleAfterSec: 300
  // How often the feed is re-read while the tile is drawn. See the header:
  // this is what recovers a watch that had no inode to register on, and it is
  // the freshness clock besides.
  property int rereadMs: 60000

  // ── The source ──────────────────────────────────────────────────────
  readonly property string feedPath:
    (Quickshell.env("HOME") || "") + "/.local/state/omarchy/omarr/feed.json"

  property bool loaded: false
  property bool feedFound: false
  property int feedVersion: 0
  // "" only before the first read. One of "missing" (omarr has not written the
  // feed), "unreadable" (the file is there and is not a feed), "version" (a
  // document this widget does not know), "empty" (a readable feed with no
  // service in it) or "ready". Every one of those is a state with a name
  // rather than a blank tile.
  property string state: ""
  // The same reason as one sentence, for a view with room for one and for
  // anything reading the log.
  property string errorMessage: ""

  readonly property string noticeHeadline: om.state === "missing" ? "No omarr feed"
    : om.state === "unreadable" ? "Can't read the feed"
    : om.state === "version" ? "Feed version " + om.feedVersion
    : om.state === "empty" ? "No services"
    : ""
  readonly property string noticeDetail: om.state === "missing"
      ? "omarr has not written its feed yet."
    : om.state === "unreadable" ? "The omarr feed is unreadable."
    : om.state === "version" ? "This widget speaks version 1."
    : om.state === "empty" ? "No service is configured in omarr."
    : ""

  // ── Freshness ───────────────────────────────────────────────────────
  property real updatedAtMs: 0
  property real _nowMs: Date.now()

  readonly property int ageSeconds: om.updatedAtMs > 0
    ? Math.max(0, Math.round((om._nowMs - om.updatedAtMs) / 1000)) : -1
  // "just now" / "2m ago" / "3h ago" / "5d ago" - the Claude and DeepSeek
  // tiles' own wording, so one age reads the same on every tile here.
  readonly property string ageLabel: {
    var s = om.ageSeconds
    if (s < 0) return ""
    if (s < 120) return "just now"
    if (s < 3600) return Math.floor(s / 60) + "m ago"
    if (s < 86400) return Math.floor(s / 3600) + "h ago"
    return Math.floor(s / 86400) + "d ago"
  }
  // Older than the writer's own cadence: omarr is not running. Not the same
  // thing as wrong - the feed is still what the machine last knew - which is
  // why the tile shows it beside the age rather than throwing it away.
  readonly property bool stale: om.ageSeconds > om.staleAfterSec

  // The freshness line, worded once here so the two drawings cannot phrase it
  // differently - and so the "stale" mark is a property of the feed's age
  // rather than of one drawing. Same wording as the Claude tile's: "as of 2m
  // ago", and "stale · as of 2m ago" once the writer's cadence has been
  // missed twice over.
  readonly property string freshnessText: {
    if (!om.loaded || om.updatedAtMs <= 0 || om.ageLabel === "") return ""
    return (om.stale ? "stale · as of " : "as of ") + om.ageLabel
  }

  // Where the numbers came from, for the preset with room for a line under the
  // freshness one. The local source, named - never a service name or a URL.
  readonly property string sourceLabel: "omarr feed"

  // ── The bar's own summary line ──────────────────────────────────────
  property string statusText: ""

  // ── The bar's badge, by the bar's own rule ──────────────────────────
  // `BarWidget.qml:16-18` shows `unreadCount` when it has one and
  // `badgeCount` otherwise, and calls it urgent when `badgeUrgent` is set.
  // Mirrored here so the tile's badge and the bar's cannot disagree.
  property int badgeCount: 0
  property bool badgeUrgent: false
  property int unreadCount: 0

  readonly property int badgeNumber: om.unreadCount > 0 ? om.unreadCount : om.badgeCount
  readonly property bool badgeVisible: om.unreadCount > 0 || om.badgeCount > 0

  // ── The queue, as counts ────────────────────────────────────────────
  // Active downloads across the fleet, services unreachable, and the queued
  // depth the snapshots carry.
  property int downloadingCount: 0
  property int downCount: 0
  property int queuedTotal: 0
  // Bytes/s summed over the fleet, and its human form. `speed` is a number on
  // every snapshot row; 0 when nothing is moving.
  property real downloadSpeed: 0

  // ── The fleet ───────────────────────────────────────────────────────
  // One row per configured service, in the order omarr published them:
  // [{ id, name, kind, group, health, statusText, paused,
  //    downloadingCount, queueTotal, label, down, up, waiting }]
  //
  // `version` and `healthLabel` are deliberately not read into these rows
  // any more. No surface on this tile draws a version (see `boardRows`), and
  // every word the board's status column needs - "up", "down", "paused", and
  // the dash for a service with no reading - is resolved in one place there,
  // from `health` and `paused`, so a second spelling of the same state cannot
  // drift from the one the column draws.
  property var services: []

  readonly property int serviceCount: om.services.length
  // The one health state counted here, because it is the one the feed can
  // report and the tile can act on. `health` "unknown" is NOT counted and not
  // named anywhere: it is the absence of a reading - omarr's own starting
  // state, `Model.js:1381`, and exactly what the board's status column draws
  // as a dash - so a fleet of six unknowns is not six services in any third
  // state. omarr's per-service line words it "waiting" (`Model.js:1713`),
  // which is how that word came to be read as a state here; it is not one.
  readonly property int servicesDown: om._countHealth("down")

  // The names of the services that are not answering, in the fleet's own
  // order - what the tile names when the hero is a count.
  readonly property var downNames: {
    var out = []
    for (var i = 0; i < om.services.length; i++)
      if (om.services[i].down) out.push(om.services[i].label)
    return out
  }

  // ── The hero: what the tile is FOR ──────────────────────────────────
  //
  // The tile answers one question - "is anything wrong, and is anything
  // moving?" - so the largest type on it is the answer to that question, and
  // never a count of healthy services. That count is the least informative
  // fact the feed carries: it is the same on every reading while a six-deep
  // queue sits in the same document, unread.
  //
  // The order below is exception first, motion second, and every branch in it
  // is a state the FEED SENT. `health` "unknown" is not one - it is omarr
  // having no reading for the service yet, the same absence the board's
  // status column draws as a dash - so it drives nothing here and the chain
  // falls through to what IS known rather than speaking for the feed:
  //
  //   down         a service is not answering. Name it - "Sonarr down" - and
  //                put the names on the detail line when there is more than
  //                one ("2 down"). This is the first preset-independent
  //                answer to "which one";
  //   downloading  the fleet is moving bytes - the count, with the speed on
  //                the detail line;
  //   queued       there is work and none of it is moving - the depth;
  //   next         nothing is wrong and nothing is moving: what is on deck;
  //   fleet        nothing else is known: the fleet COUNTED, claiming nothing
  //                about the health of any service in it - "6 services". Not
  //                "6 up", which asserts a reading for services omarr has not
  //                reported on; the number that answered is not the number of
  //                services, and the tile draws the set it has.
  //
  // Both drawings read these three properties, so the two faces cannot
  // disagree about what the fleet is doing - the tree's existing rule.
  readonly property string heroKind: {
    if (om.serviceCount === 0) return "none"
    if (om.servicesDown > 0) return "down"
    if (om.downloadingCount > 0) return "downloading"
    if (om.queuedTotal > 0) return "queued"
    if (om._nextTitle !== "") return "next"
    return "fleet"
  }

  // What is on next, by the feed's own order: the calendar's first row, else
  // the on-deck list's. The title, or the subtitle when a row has none - a
  // row that names nothing is not "what is next" and does not get the hero.
  readonly property string _nextTitle: {
    var rows = om.calendar.length > 0 ? om.calendar : om.onDeck
    if (rows.length === 0) return ""
    var row = rows[0]
    return row.title !== "" ? row.title : row.subtitle
  }

  readonly property string heroLabel: {
    switch (om.heroKind) {
    case "down":
      return om.servicesDown === 1
        ? om.downNames[0] + " down" : om.servicesDown + " down"
    case "downloading": return om.downloadingCount + " downloading"
    case "queued": return om.queuedTotal + " queued"
    case "next": return "Next: " + om._nextTitle
    // The fleet, counted - the last answer that is a fact whatever the feed
    // has and has not said. "1 service" and "6 services" are the same words
    // omarr's own summary line uses for the same fact.
    case "fleet": return om.serviceCount === 1
        ? "1 service" : om.serviceCount + " services"
    default: return "No services"
    }
  }

  // The line that belongs to the hero and to nothing else: the names the
  // count alone cannot give, and the speed behind a download count. "" when
  // the hero already says everything - which is every other state, the fleet
  // count included: there is no line of names to put under a count of
  // services, and a service with no reading is not nameable as anything.
  readonly property string heroDetail: {
    switch (om.heroKind) {
    case "down":
      return om.servicesDown > 1 ? om.downNames.join(", ") : ""
    case "downloading":
      return om.formatSpeed(om.downloadSpeed)
    default: return ""
    }
  }

  // omarr's own summary line, drawn only when it is not a restatement of the
  // hero. Its commonest form is the bare fleet count ("6 services") - the
  // fact this redesign exists to stop drawing twice, and one the tile already
  // carries: in the hero when the fleet count is all there is to say, on the
  // board's own footer whenever the board is drawn, and in the strip's pips at
  // every preset. Everything else the line can say ("2 downloading", "Sonarr
  // unreachable") is news, and is drawn in omarr's own words because the bar
  // item shows the same string.
  readonly property string statusLineText: {
    if (!om.ready) return ""
    var text = om.statusText.trim()
    if (text === "") return ""
    if (/^[0-9]+ services?$/.test(text)) return ""
    return om.statusText
  }

  // ── The board's rows ────────────────────────────────────────────────
  //
  // The fleet, sorted exception-first, each row carrying its STATUS - and one
  // kind of datum only - in the value column. That is the whole point of the
  // column: it is read down, and a column whose cells are a queue depth on one
  // row, a version on the next and a health word on the third has no meaning
  // to read. The redesign before this one fell through exactly that chain
  // (`queueTotal`, else `downloadingCount`, else the version, else the health
  // word), and drew "6 queued" beside "6.4.4.10684" beside "up".
  //
  //   * STATUS, the column's one datum, in words the feed already speaks:
  //       down    the service is not answering;
  //       —       omarr has no reading for it yet (`health` "unknown", which
  //               is where every service starts). A dash, not a word: six
  //               services with no reading are not six statuses, and the
  //               column must not claim a state it does not know. The row
  //               carries `absent` so a drawing can ink it as the absence it
  //               is rather than as a value;
  //       paused  the service is up and deliberately stopped;
  //       up      answering. A service with work queued is STILL "up":
  //               being busy is a property of the service, not a status, and
  //               it is what made this column unreadable;
  //   * the QUEUE DEPTH rides with the name, in `activity`, drawn beside the
  //     label as a small count ("SONARR 6"). "0" is idle and draws nothing;
  //   * the VERSION is neither status nor activity, and is drawn nowhere on
  //     this tile: the feed still publishes it, and nothing here reads it.
  //
  // Sorting is not a second opinion here: the services are a SET that omarr
  // publishes in configuration order, unlike `downloads`, which is the
  // plugin's own merge order and is never re-sorted. Rank 4 is the healthy,
  // idle, empty service; the fleet's own order breaks every tie, so the list
  // is stable whatever the engine's sort does with equal keys.
  readonly property var boardRows: {
    var out = []
    for (var i = 0; i < om.services.length; i++) {
      var s = om.services[i]
      var busy = s.queueTotal > 0 || s.downloadingCount > 0
      out.push({
        rank: s.down ? 0 : s.waiting ? 1 : s.paused ? 2 : busy ? 3 : 4,
        order: i,
        label: s.label,
        // How much work the service is holding, as ONE number: `queueTotal`,
        // raised to `downloadingCount` when that is larger, because omarr
        // reports a torrent client's depth as 0 and counts its active rows
        // instead (`Service.qml:677`), while an arr's `queueTotal` is its own
        // `totalRecords` and already includes them (`Service.qml:587`).
        activity: Math.max(s.queueTotal, s.downloadingCount),
        // The column: one status, resolved here so the two drawings cannot
        // word it differently - and cannot put anything else in the cell.
        status: s.down ? "down" : s.waiting ? "—" : s.paused ? "paused" : "up",
        absent: s.waiting,
        alert: s.down
      })
    }
    out.sort(function (a, b) { return (a.rank - b.rank) || (a.order - b.order) })
    return out
  }

  // The accent applies to exactly one thing on this tile: a service that is
  // down, or a badge omarr itself calls urgent. A stale feed is NOT this -
  // it is the freshness line, in its own token (see the widget bodies).
  readonly property bool alert: om.servicesDown > 0 || om.badgeUrgent

  // ── The queue's rows ────────────────────────────────────────────────
  // The merged active queue, already capped at 10 by the writer:
  // [{ id, serviceName, title, progress, percent, percentLabel, status,
  //    timeleft, speed, speedLabel }]
  property var downloads: []
  // The media rows the feed carries. Counts are all the tile draws from them;
  // the rows themselves are kept so a preset with room can name what is next
  // without a second read.
  property var onDeck: []
  property var recent: []
  property var calendar: []

  // The leading download: the feed's own first row, which is the plugin's own
  // merge order (service by service, active rows first). Nothing here
  // re-sorts it - a tile that picked a different row than the plugin's toast
  // would be a second opinion about what is "leading".
  readonly property var lead: om.downloads.length > 0 ? om.downloads[0] : null

  // ── Is there anything to draw? ──────────────────────────────────────
  // A feed that parsed, is version 1, and carries a service row. An empty
  // fleet is a state with a name ("No services"), not a blank tile.
  readonly property bool ready: om.state === "ready"

  // ── Reading ─────────────────────────────────────────────────────────
  function refresh() { if (om.active) view.reload() }

  property FileView view: FileView {
    id: view
    path: om.feedPath
    watchChanges: true
    // The writer replaces the inode; this is the documented spelling for that
    // (see the header - measured to answer the second rename with and
    // without it).
    atomicWrites: true
    printErrors: false
    onLoaded: om._apply(text())
    onFileChanged: reload()
    onLoadFailed: {
      om.loaded = true
      om.feedFound = false
      om._clear()
      om.state = "missing"
      om.errorMessage = ""
    }
  }

  property Timer _reread: Timer {
    interval: om.rereadMs
    repeat: true
    triggeredOnStart: true
    running: om.active
    onTriggered: {
      om._nowMs = Date.now()
      om.refresh()
    }
  }

  // ── Parse ───────────────────────────────────────────────────────────
  function _clear() {
    om.feedVersion = 0
    om.updatedAtMs = 0
    om.statusText = ""
    om.badgeCount = 0
    om.badgeUrgent = false
    om.unreadCount = 0
    om.downloadingCount = 0
    om.downCount = 0
    om.queuedTotal = 0
    om.downloadSpeed = 0
    om.services = []
    om.downloads = []
    om.onDeck = []
    om.recent = []
    om.calendar = []
  }

  function _apply(raw) {
    om.loaded = true
    om._nowMs = Date.now()
    var text = String(raw === undefined || raw === null ? "" : raw).trim()
    if (text === "") {
      // The writer's file is gone (or was never written): omarr has not run,
      // or its state directory was cleared. Not an error - a state.
      om.feedFound = false
      om._clear()
      om.state = "missing"
      om.errorMessage = ""
      return
    }

    var parsed = JsonRead.parseOrNull(text)
    om.feedFound = true
    if (parsed === null || typeof parsed !== "object" || parsed instanceof Array) {
      om._clear()
      om.state = "unreadable"
      om.errorMessage = "The omarr feed is unreadable."
      return
    }

    // FEED_VERSION. Report a stranger's shape rather than read its fields on
    // a guess - a fleet drawn from a document this widget does not know is
    // exactly the silent mis-read the version exists to prevent.
    var version = JsonRead.int(parsed.version, 0)
    if (version !== 1) {
      om._clear()
      om.feedVersion = version
      om.state = "version"
      om.errorMessage = "The omarr feed is version " + version
        + ", which this widget does not know."
      return
    }

    om.feedVersion = version
    om.errorMessage = ""
    om.updatedAtMs = JsonRead.num(parsed.updatedAt, 0)
    om.statusText = JsonRead.str(parsed.statusText, "")
    om.badgeCount = JsonRead.int(parsed.badgeCount, 0)
    om.badgeUrgent = parsed.badgeUrgent === true
    om.unreadCount = JsonRead.int(parsed.unreadCount, 0)
    om.downloadingCount = JsonRead.int(parsed.downloadingCount, 0)
    om.downCount = JsonRead.int(parsed.downCount, 0)

    var rows = parsed.snapshots instanceof Array ? parsed.snapshots : []
    var services = []
    var queued = 0
    var speed = 0
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i] && typeof rows[i] === "object" ? rows[i] : {}
      var health = JsonRead.str(row.health, "")
      if (health !== "up" && health !== "down") health = "unknown"
      var name = JsonRead.str(row.name, "")
      var kind = JsonRead.str(row.kind, "")
      var queueTotal = JsonRead.int(row.queueTotal, 0)
      var rowSpeed = JsonRead.num(row.speed, 0)
      queued += queueTotal
      speed += rowSpeed
      services.push({
        id: JsonRead.str(row.id, ""),
        name: name,
        kind: kind,
        group: JsonRead.str(row.group, ""),
        health: health,
        statusText: JsonRead.str(row.statusText, ""),
        paused: row.paused === true,
        downloadingCount: JsonRead.int(row.downloadingCount, 0),
        queueTotal: queueTotal,
        // `name` is what the operator called the service; `kind` is its type.
        // A row with no name still gets a label, so a list can never draw a
        // blank line where a service is.
        label: name !== "" ? name : (kind !== "" ? kind : JsonRead.str(row.id, "")),
        up: health === "up",
        down: health === "down",
        waiting: health === "unknown"
      })
    }
    om.services = services
    om.queuedTotal = queued
    om.downloadSpeed = speed

    om.downloads = om._downloadRows(parsed.downloads)
    om.onDeck = om._mediaRows(parsed.onDeck)
    om.recent = om._mediaRows(parsed.recent)
    om.calendar = om._mediaRows(parsed.calendar)

    if (services.length === 0) {
      // Every field parsed, and there is no service configured. The counts
      // above are still true, and the tile says which state this is rather
      // than drawing an empty fleet as a healthy one.
      om.state = "empty"
      om.errorMessage = "No services"
      return
    }
    om.state = "ready"
  }

  // FEED_DOWNLOAD_FIELDS. `progress` is 0..1 in the feed
  // (`Model.formatProgress` is what omarr prints); the percent and its label
  // are derived once here so the two drawings cannot round it differently.
  function _downloadRows(list) {
    var rows = list instanceof Array ? list : []
    var out = []
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i] && typeof rows[i] === "object" ? rows[i] : {}
      var progress = JsonRead.num(row.progress, 0)
      var percent = Math.max(0, Math.min(100, Math.round(progress * 100)))
      var speed = JsonRead.num(row.speed, 0)
      var title = JsonRead.str(row.title, "")
      out.push({
        id: JsonRead.str(row.id, ""),
        serviceName: JsonRead.str(row.serviceName, ""),
        title: title !== "" ? title : "Untitled",
        progress: progress,
        percent: percent,
        percentLabel: percent + "%",
        status: JsonRead.str(row.status, ""),
        timeleft: JsonRead.str(row.timeleft, ""),
        speed: speed,
        speedLabel: om.formatSpeed(speed)
      })
    }
    return out
  }

  // FEED_MEDIA_FIELDS, for the counts and a title.
  function _mediaRows(list) {
    var rows = list instanceof Array ? list : []
    var out = []
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i] && typeof rows[i] === "object" ? rows[i] : {}
      out.push({
        id: JsonRead.str(row.id, ""),
        serviceName: JsonRead.str(row.serviceName, ""),
        title: JsonRead.str(row.title, ""),
        subtitle: JsonRead.str(row.subtitle, ""),
        airDate: JsonRead.str(row.airDate, ""),
        progress: JsonRead.num(row.progress, 0)
      })
    }
    return out
  }

  function _countHealth(health) {
    var n = 0
    for (var i = 0; i < om.services.length; i++)
      if (om.services[i].health === health) n++
    return n
  }

  // `Model.formatSpeed`, verbatim in shape - 1024-based, one decimal, and
  // omarr's own unit spellings - so a speed in the bar and the same speed here
  // are not worded differently. No speed at all is "" rather than "0 B/s":
  // nothing moving is not a transfer of zero bytes.
  function formatSpeed(bytes) {
    var n = Number(bytes)
    if (!isFinite(n) || n <= 0) return ""
    if (n < 1024) return Math.round(n) + " B/s"
    if (n < 1024 * 1024) return om._oneDecimal(n / 1024) + " KB/s"
    if (n < 1024 * 1024 * 1024) return om._oneDecimal(n / (1024 * 1024)) + " MB/s"
    return om._oneDecimal(n / (1024 * 1024 * 1024)) + " GB/s"
  }

  function _oneDecimal(n) {
    return (Math.round(Number(n) * 10) / 10).toFixed(1)
  }
}
