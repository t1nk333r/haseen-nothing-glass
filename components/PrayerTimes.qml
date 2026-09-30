import QtQuick
import Quickshell
import Quickshell.Io
import "prayers/Engine.js" as Engine

// Prayer times for the desktop widget.
//
// ── Where the numbers come from ───────────────────────────────────────────
//
// `t1nk33r.omaprayers` already computes them, entirely offline: `Engine.js`
// is an adhan-js port in plain ES5 and `prayer-zone.sh` builds a 70-day IANA
// offset table with `date`/`zdump`, so no network and no API key. But that
// plugin declares `kinds: ["bar-widget"]` only - no service entry point, so
// `shell.serviceFor("t1nk33r.omaprayers")` is null - and its IpcHandler
// exposes nothing but open/close/toggle/refresh and a prose `status()`. The
// computed schedule never leaves that plugin's Panel.qml, and nothing is
// cached on disk. Same shape as the weather finding in OmarchyLocation.qml.
//
// So the engine is VENDORED (`components/prayers/`, MIT, Salem Sayed - see
// LICENSE.omaprayers) and fed the user's OWN omaprayers settings, read live
// out of `~/.config/omarchy/shell.json`. One source of truth for location,
// method and language: change it in the prayers plugin and this follows.
//
// (The lock screen's prayer card is a third implementation again - it shells
// out to `python3 ~/.config/waybar/scripts/prayer-times.py`, a path that no
// longer exists on this machine, which is why that card shows `--:--`. This
// widget does not depend on it.)
QtObject {
  id: prayers

  // --- inputs ------------------------------------------------------------
  // All optional: anything left empty falls back to the omaprayers entry.
  property string overrideTimezone: ""
  property double overrideLatitude: 0
  property double overrideLongitude: 0

  // The overrides arrive AFTER the first schedule is built (GeoLocation has
  // to read shell.json and try geoclue first), and a schedule computed from
  // the fallback coordinates never corrected itself: the sunrise tile showed
  // New York's sunrise rendered in Riyadh's timezone - 1:29 PM - while its
  // own footer said Riyadh. Any override change now re-reads the config and
  // rebuilds, coalesced so a burst of three changes costs one rebuild.
  onOverrideLatitudeChanged: overrideDebounce.restart()
  onOverrideLongitudeChanged: overrideDebounce.restart()
  onOverrideTimezoneChanged: overrideDebounce.restart()
  onNowOverrideChanged: prayers._recompute()

  property Timer _overrideDebounce: Timer {
    id: overrideDebounce
    interval: 120
    onTriggered: prayers._shellFile.reload()
  }

  // Test seam: the instant everything is computed against. Null means "now".
  // The rollover rules here - next prayer wrapping past midnight, rows
  // switching to tomorrow after Isha, the daylight fraction - are the part of
  // this file most likely to be subtly wrong, and they cannot be exercised
  // without pretending it is a different time of day. Moving the machine's
  // clock to test it is forbidden, so the seam is here.
  property var nowOverride: null

  // --- outputs -----------------------------------------------------------
  property bool ok: false
  property string error: "loading"

  // [{ key, en, ar, timeText, at (Date), isPrayer, isNext, isPast }]
  property var rows: []
  property var next: null      // the next of the five prayers (never Sunrise)
  property var after: null     // the one after that
  property real progress: 0    // 0..1 through the window between them
  property int remainingMinutes: 0
  property string remainingText: ""

  property string locationLabel: ""

  // Sun times for today, straight out of the same offline engine (the
  // schedule already carries Sunrise and Sunset per day). The sunrise tile
  // uses these so nothing on this desktop needs a network call to know when
  // the sun comes up.
  property var sunriseAt: null
  property var sunsetAt: null
  property string sunriseText: ""
  property string sunsetText: ""
  // 0 before sunrise, 1 after sunset, the fraction of daylight elapsed in
  // between - what the tile's arc marker rides on.
  property real dayProgress: 0
  property bool isDaylight: false
  property string hijriDisplay: ""
  // True once Isha has passed and the rows describe tomorrow.
  property bool showsTomorrow: false
  property string language: "English"
  property string timeFormat: "12-hour"

  readonly property bool isArabic: prayers.language === "Arabic"

  // Names. Sunrise is listed but is not a prayer: it never becomes `next`,
  // matching both the omaprayers panels and the lock card.
  readonly property var _names: [
    { key: "Fajr",    en: "Fajr",    ar: "الفجر",   isPrayer: true },
    { key: "Sunrise", en: "Sunrise", ar: "الشروق",  isPrayer: false },
    { key: "Dhuhr",   en: "Dhuhr",   ar: "الظهر",   isPrayer: true },
    { key: "Asr",     en: "Asr",     ar: "العصر",   isPrayer: true },
    { key: "Maghrib", en: "Maghrib", ar: "المغرب",  isPrayer: true },
    { key: "Isha",    en: "Isha",    ar: "العشاء",  isPrayer: true }
  ]

  // --- config, read from the omaprayers entry ------------------------------

  property var _config: null

  function _findEntry(list, id) {
    if (!Array.isArray(list)) return null
    for (var i = 0; i < list.length; i++)
      if (list[i] && String(list[i].id || "") === id) return list[i]
    return null
  }

  function _applyShellConfig(text) {
    var cfg = null
    try {
      cfg = JSON.parse(String(text || ""))
    } catch (e) {
      prayers.error = "shell.json is not valid JSON"
      return
    }
    var id = "t1nk33r.omaprayers"
    // The shell keeps ONE entry per plugin and moves it into the bar layout
    // once the widget is placed, but a stale copy can remain in `plugins[]` -
    // measured: the `plugins[]` copy here has no `language` while the placed
    // bar entry says Arabic. So both are read and the bar entry wins, the
    // same precedence GlassSurface._mergedSettings applies.
    var entry = {}
    var found = false
    var base = prayers._findEntry(cfg ? cfg.plugins : null, id)
    if (base) { found = true; for (var bk in base) entry[bk] = base[bk] }
    if (cfg && cfg.bar && cfg.bar.layout) {
      var sections = ["left", "center", "right"]
      for (var s = 0; s < sections.length; s++) {
        var hit = prayers._findEntry(cfg.bar.layout[sections[s]], id)
        if (!hit) continue
        found = true
        for (var hk in hit) entry[hk] = hit[hk]
        break
      }
    }
    if (!found) {
      prayers.error = "no t1nk33r.omaprayers settings found in shell.json"
      prayers.ok = false
      return
    }

    // `omarchy bar set` stores everything as a string, so coerce here.
    prayers._config = {
      locationLabel: String(entry.locationLabel || ""),
      latitude: prayers.overrideLatitude || Number(entry.latitude),
      longitude: prayers.overrideLongitude || Number(entry.longitude),
      timezone: prayers.overrideTimezone || String(entry.timezone || ""),
      method: Number(entry.calculationMethod),
      school: entry.school,
      latitudeAdjustmentMethod: entry.latitudeAdjustmentMethod,
      midnightMode: entry.midnightMode,
      hijriAdjustment: entry.hijriAdjustment,
      tune: entry.tune,
      shafaq: entry.shafaq,
      methodSettings: entry.methodSettings
    }
    prayers.locationLabel = prayers._config.locationLabel
    prayers.language = String(entry.language || "English")
    prayers.timeFormat = String(entry.timeFormat || "12-hour")
    prayers._loadZone()
  }

  property FileView _shellFile: FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: prayers._applyShellConfig(text())
    onLoadFailed: {
      prayers.error = "could not read shell.json"
      prayers.ok = false
    }
  }

  // --- timezone window + schedule -----------------------------------------

  property var _zone: null
  property var _schedule: null

  function _loadZone() {
    if (!prayers._config || !prayers._config.timezone) return
    zoneProc.running = false
    zoneProc.running = true
  }

  property Process _zoneProc: Process {
    id: zoneProc
    running: false
    command: ["bash", Qt.resolvedUrl("prayers/prayer-zone.sh").toString().replace("file://", ""),
              "--timezone", prayers._config ? prayers._config.timezone : "UTC"]
    stdout: StdioCollector {
      onStreamFinished: {
        var zone = null
        try {
          zone = JSON.parse(String(text || ""))
        } catch (e) {
          prayers.error = "timezone window did not parse"
          prayers.ok = false
          return
        }
        prayers._zone = zone
        prayers._rebuild()
      }
    }
  }

  function _rebuild() {
    if (!prayers._config || !prayers._zone) return
    var schedule = Engine.buildSchedule(prayers._config, prayers._zone, Date.now())
    if (!schedule || schedule.ok !== true) {
      prayers.error = (schedule && schedule.error) ? schedule.error : "schedule failed"
      prayers.ok = false
      return
    }
    prayers._schedule = schedule
    prayers.error = ""
    prayers.ok = true
    prayers._recompute()
  }

  // --- per-minute derived state -------------------------------------------

  function _dayFor(dateText) {
    var days = prayers._schedule ? prayers._schedule.days : []
    for (var i = 0; i < days.length; i++) if (days[i].date === dateText) return days[i]
    return null
  }

  function _fmtClock(hhmm) {
    var m = /^(\d{1,2}):(\d{2})/.exec(String(hhmm || ""))
    if (!m) return String(hhmm || "")
    var hour = parseInt(m[1], 10)
    if (prayers.timeFormat !== "12-hour") return (hour < 10 ? "0" : "") + hour + ":" + m[2]
    var suffix = hour >= 12 ? "PM" : "AM"
    var display = hour % 12
    if (display === 0) display = 12
    return display + ":" + m[2] + " " + suffix
  }

  function _fmtDuration(minutes) {
    var v = Math.max(0, Math.round(Number(minutes) || 0))
    var h = Math.floor(v / 60)
    var rest = v % 60
    var hUnit = prayers.isArabic ? " س" : "h"
    var mUnit = prayers.isArabic ? " د" : "m"
    if (v <= 0) return prayers.isArabic ? "الآن" : "now"
    if (h <= 0) return rest + mUnit
    if (rest === 0) return h + hUnit
    return h + hUnit + " " + rest + mUnit
  }

  function _recompute() {
    if (!prayers._schedule || !prayers._zone) return
    var nowMs = prayers.nowOverride ? Number(prayers.nowOverride) : Date.now()
    var todayText = Engine.localDate(prayers._zone, nowMs)
    var today = prayers._dayFor(todayText)
    if (!today) { prayers.ok = false; prayers.error = "no schedule for today"; return }

    prayers.hijriDisplay = prayers.isArabic ? today.hijri.displayAr : today.hijri.display

    // Sun times always describe the CURRENT civil day, even after Isha when
    // the prayer rows below roll over to tomorrow: "sunrise" after midnight
    // means this morning's, and the arc has to agree with the clock.
    var sunriseT = today.timings.Sunrise
    var sunsetT = today.timings.Sunset || today.timings.Maghrib
    prayers.sunriseAt = (sunriseT && sunriseT.at) ? new Date(sunriseT.at) : null
    prayers.sunsetAt = (sunsetT && sunsetT.at) ? new Date(sunsetT.at) : null
    prayers.sunriseText = sunriseT ? prayers._fmtClock(sunriseT.time) : ""
    prayers.sunsetText = sunsetT ? prayers._fmtClock(sunsetT.time) : ""
    if (prayers.sunriseAt && prayers.sunsetAt) {
      var riseMs = prayers.sunriseAt.getTime()
      var setMs = prayers.sunsetAt.getTime()
      var span = setMs - riseMs
      prayers.isDaylight = nowMs >= riseMs && nowMs <= setMs
      prayers.dayProgress = span > 0
        ? Math.max(0, Math.min(1, (nowMs - riseMs) / span))
        : 0
    } else {
      prayers.isDaylight = false
      prayers.dayProgress = 0
    }

    var tomorrow = prayers._dayFor(prayers._nextDateText(todayText))

    // Which day the six rows describe. Once Isha has passed, "today's
    // times" are all in the past and useless - every panel in omaprayers
    // and every glance at this widget then means tomorrow, so the list
    // rolls over with the next prayer rather than showing six greyed rows.
    var lastPrayer = today.timings.Isha
    var ishaPassed = lastPrayer && lastPrayer.at
      && new Date(lastPrayer.at).getTime() <= nowMs
    var rolled = (ishaPassed && tomorrow) ? true : false
    var sourceDay = rolled ? tomorrow : today
    prayers.showsTomorrow = rolled

    var rows = []
    for (var i = 0; i < prayers._names.length; i++) {
      var n = prayers._names[i]
      var t = sourceDay.timings[n.key]
      if (!t || !t.at) continue
      var at = new Date(t.at)
      rows.push({ key: n.key, en: n.en, ar: n.ar, isPrayer: n.isPrayer,
                  timeText: prayers._fmtClock(t.time), at: at,
                  isPast: at.getTime() <= nowMs, isNext: false })
    }

    var upcoming = null
    var following = null
    for (var r = 0; r < rows.length; r++) {
      if (!rows[r].isPrayer || rows[r].at.getTime() <= nowMs) continue
      if (!upcoming) { upcoming = rows[r]; continue }
      if (!following) { following = rows[r]; break }
    }

    if (!upcoming && tomorrow && tomorrow.timings.Fajr && tomorrow.timings.Fajr.at) {
      upcoming = { key: "Fajr", en: "Fajr", ar: "الفجر", isPrayer: true,
                   timeText: prayers._fmtClock(tomorrow.timings.Fajr.time),
                   at: new Date(tomorrow.timings.Fajr.at), isPast: false, isNext: true }
    }
    if (!following && tomorrow) {
      var order = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
      var wantIndex = upcoming ? order.indexOf(upcoming.key) + 1 : 0
      var wantKey = order[wantIndex % order.length]
      // After Isha the next prayer is tomorrow's Fajr, so the one AFTER that
      // is tomorrow's Dhuhr - today's row would carry a time already past.
      var fromTomorrow = upcoming && upcoming.at.getTime() > new Date(tomorrow.date + "T00:00:00").getTime()
      var src = fromTomorrow ? tomorrow : today
      var tt = src.timings[wantKey]
      if (tt && tt.at) {
        var meta = null
        for (var mi = 0; mi < prayers._names.length; mi++)
          if (prayers._names[mi].key === wantKey) meta = prayers._names[mi]
        following = { key: wantKey, en: meta ? meta.en : wantKey, ar: meta ? meta.ar : wantKey,
                      isPrayer: true, timeText: prayers._fmtClock(tt.time),
                      at: new Date(tt.at), isPast: false, isNext: false }
      }
    }

    if (upcoming) {
      for (var k = 0; k < rows.length; k++) rows[k].isNext = (rows[k].key === upcoming.key && !rows[k].isPast)
    }

    // Progress through the window: from the previous prayer of the day (or
    // yesterday's Isha) to the next one.
    var previousMs = 0
    for (var p = rows.length - 1; p >= 0; p--) {
      if (rows[p].isPrayer && rows[p].at.getTime() <= nowMs) { previousMs = rows[p].at.getTime(); break }
    }
    if (!previousMs) {
      var yesterday = prayers._dayFor(prayers._prevDateText(todayText))
      if (yesterday && yesterday.timings.Isha && yesterday.timings.Isha.at)
        previousMs = new Date(yesterday.timings.Isha.at).getTime()
    }
    var span = upcoming ? (upcoming.at.getTime() - previousMs) : 0
    prayers.progress = (span > 0 && previousMs > 0)
      ? Math.max(0, Math.min(1, (nowMs - previousMs) / span))
      : 0

    prayers.remainingMinutes = upcoming ? Math.max(0, Math.floor((upcoming.at.getTime() - nowMs) / 60000)) : 0
    prayers.remainingText = upcoming ? prayers._fmtDuration(prayers.remainingMinutes) : ""
    prayers.next = upcoming
    prayers.after = following
    prayers.rows = rows
  }

  function _shiftDateText(dateText, days) {
    var parts = String(dateText || "").split("-")
    if (parts.length !== 3) return ""
    var d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]) + days)
    var mm = d.getMonth() + 1
    var dd = d.getDate()
    return d.getFullYear() + "-" + (mm < 10 ? "0" : "") + mm + "-" + (dd < 10 ? "0" : "") + dd
  }
  function _nextDateText(dateText) { return prayers._shiftDateText(dateText, 1) }
  function _prevDateText(dateText) { return prayers._shiftDateText(dateText, -1) }

  // A minute is the finest granularity anything here displays (the countdown
  // is "1h 23m"), so tick on the wall-clock minute boundary rather than
  // drifting off a fixed 60 s interval - AGENTS.md's tick discipline.
  property Timer _tick: Timer {
    interval: 60000 - (Date.now() % 60000)
    running: true
    repeat: true
    onTriggered: {
      interval = Math.max(1000, 60000 - (Date.now() % 60000))
      prayers._recompute()
    }
  }

  // The schedule covers ~70 days, so a day rollover needs no re-fetch - but
  // the zone window does age out. Rebuild it daily.
  property Timer _daily: Timer {
    interval: 86400000
    running: true
    repeat: true
    onTriggered: prayers._loadZone()
  }
}
