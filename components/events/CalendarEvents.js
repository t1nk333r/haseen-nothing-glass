// The pure half of the calendar seam: the published document in, the widget's
// event objects out.
//
// `EventSource.qml` owns every input/output - the watched file, the `khal`
// probe and process, the four states and their wording. Everything that can be
// decided from bytes alone lives here instead, so it can be exercised without a
// filesystem, a shell or a widget: a `node` test can `require` this file (the
// trailing `typeof module` guard, exactly as `prayers/Engine.js` does) and hand
// it a document. Nothing in this file mentions QML, Quickshell or a path.
//
// ── The schema is not ours ──
//
// `tmn73/omarchy-calendar` (MIT) publishes `~/.local/state/omarchy/
// calendar-events.json` and a sync writer owns it. It is adopted VERBATIM, not
// "similar": a writer that already produces it can feed this widget unchanged.
// Nothing here rewrites or migrates it - the plugin only ever reads.
//
//   {"version":1,"syncedAt":"...","source":"whatever","events":[
//     {"id":"stable","calendarId":"work@example.com","calendarName":"Work",
//      "color":"#f83a22","dateKey":"2026-08-10","start":"2026-08-10T19:15:00-05:00",
//      "end":"2026-08-10T20:15:00-05:00","allDay":false,"title":"Tax filing"}]}
//
// A multi-day event is emitted once per day it covers, each row with its own
// `dateKey` and all rows sharing one `id`, so a row's key is `id + dateKey`.
// Unknown fields are ignored.

// "YYYY-MM-DD" and the two local datetime spellings this accepts.
var DATE_KEY_RE = /^(\d{4})-(\d{2})-(\d{2})$/
var LOCAL_DATETIME_RE = /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?$/
// `#rrggbb` only. `#RGB`, `#rrggbbaa`, "red" and "0x123456" are all refused
// rather than passed through to a colour that would silently be transparent.
var RGB_RE = /^#[0-9a-fA-F]{6}$/

function pad2(n) {
  return (n < 10 ? "0" : "") + n
}

function trimmed(value) {
  if (value === undefined || value === null) return ""
  return String(value).replace(/^\s+|\s+$/g, "")
}

// "YYYY-MM-DD" for the LOCAL day `date` falls on.
//
// `toISOString().slice(0, 10)` is the trap this exists to avoid, in both
// directions: on a local-midnight `Date` it names the PREVIOUS day at positive
// offsets (verified here: `TZ=Europe/Berlin new Date("2026-09-11T00:00:00")
// .toISOString().slice(0,10)` is `"2026-09-10"`), and a bare
// `new Date("2026-09-11")` is UTC midnight, which renders the previous day at
// negative ones (`TZ=America/New_York` puts `getDate()` at 10). `dateKey` is
// the grid's key, so it has to be the local date, read off the local fields.
function localDateKey(date) {
  return date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate())
}

// A `Date` in local time, or null when the text is not a datetime this can
// place.
//
// The two explicit spellings come first because `new Date()` mishandles them:
// an offset-less ISO datetime is local by the ES spec (`2026-09-11T00:00:00`,
// the all-day shape tmn73 writes) but a bare `2026-09-11` is UTC midnight - the
// previous day for anyone west of Greenwich. `khal` prints the same two shapes
// with a space instead of the `T`. Anything else is handed to the platform's
// own parser, which is what places an offset-bearing ISO datetime.
function parseDateTime(value) {
  var text = trimmed(value)
  if (text === "") return null
  var m = LOCAL_DATETIME_RE.exec(text)
  if (m) {
    return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]),
                    Number(m[4]), Number(m[5]), m[6] ? Number(m[6]) : 0)
  }
  m = DATE_KEY_RE.exec(text)
  if (m) return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]))
  var date = new Date(text)
  return isFinite(date.getTime()) ? date : null
}

// `#rrggbb`, or `""`.
//
// Empty is a VALUE, not a failure: the widget's `_pillColorFor` treats an empty
// `eventColor` as "no colour given" and falls back to its `eventType` table. A
// string that is present but not a colour has to become that same empty string
// - handing `"0x123456"` to a QML `color` property draws transparent black.
function colour(value) {
  var text = trimmed(value)
  return (typeof value === "string" && RGB_RE.test(text)) ? text : ""
}

// A document row, as the widget's event object, or null when it cannot be
// placed on a timeline.
//
// `title` is `title`; `start` is `startDateTime`; an absent `end` is `start`
// (a zero-length event, which is what a writer means by omitting it); `allDay`
// is `isAllDay`, strictly boolean; `color` is `eventColor`; `eventType` is
// `eventType`; every other field of the published schema - `calendarId`,
// `calendarName`, `location`, `source`, `version` - is ignored, and `isMinor`/
// `description` are unread by every consumer.
//
// `endDateTime` is produced although no consumer reads it yet: the next-event
// tile (plan 011 step 5) needs it, and it costs nothing here. A row whose
// `start` does not parse is DROPPED - it has no place on the grid, and keeping
// it would render a card with `Invalid Date` in it.
function mapRow(row) {
  if (!row || typeof row !== "object") return null
  var start = parseDateTime(row.start)
  if (start === null) return null
  var end = parseDateTime(row.end)
  var key = trimmed(row.dateKey)
  return {
    id: typeof row.id === "string" ? row.id : "",
    title: typeof row.title === "string" ? row.title : "",
    startDateTime: start,
    endDateTime: end === null ? start : end,
    isAllDay: row.allDay === true,
    eventColor: colour(row.color),
    eventType: typeof row.eventType === "string" ? row.eventType : "",
    // null, not "": "this row is on every day it spans" is a different fact
    // from "this row is on the empty day".
    dateKey: DATE_KEY_RE.test(key) ? key : null
  }
}

// The published document, parsed and mapped.
//
// `{ ok, error, rows, syncedAtMs }` - `ok: false` carries a human `error` for
// the widget's `readError` and NO rows, because a truncated file is not
// half an answer. An empty file, a file that is not JSON, a JSON value that is
// not an object, and an object with no `events` array are all `ok: false`;
// the last one is a schema violation rather than an empty calendar, which is
// why `{"version":1}` does not read as "nothing scheduled".
function parseDocument(text) {
  var body = (text === undefined || text === null) ? "" : String(text)
  var empty = { ok: false, error: "the file is empty", rows: [], syncedAtMs: 0 }
  if (trimmed(body) === "") return empty
  var doc
  try {
    doc = JSON.parse(body)
  } catch (e) {
    return { ok: false, error: "not JSON: " + e.message, rows: [], syncedAtMs: 0 }
  }
  if (!doc || typeof doc !== "object" || Array.isArray(doc)) {
    return { ok: false, error: "the document is not an object", rows: [], syncedAtMs: 0 }
  }
  if (!Array.isArray(doc.events)) {
    return { ok: false, error: "the document has no events array", rows: [], syncedAtMs: 0 }
  }
  var rows = []
  for (var i = 0; i < doc.events.length; i++) {
    var mapped = mapRow(doc.events[i])
    if (mapped !== null) rows.push(mapped)
  }
  var synced = parseDateTime(doc.syncedAt)
  return { ok: true, error: "", rows: rows, syncedAtMs: synced === null ? 0 : synced.getTime() }
}

// One `khal list --json ...` row, or null when it cannot be placed.
//
// The khal shape differs from the published one in three ways, and each is
// handled here rather than in the widget: the id is `uid`, the all-day flag is
// a STRING (`khal/khalendar/event.py:765` prints Python's `str(True)`), and
// there is no colour at all - so `eventColor` is `""` and the widget's
// `eventType` fallback table decides the pill, exactly as for a colourless
// document row.
function mapKhalRow(row) {
  if (!row || typeof row !== "object") return null
  var start = parseDateTime(row.start)
  if (start === null) return null
  var end = parseDateTime(row.end)
  var flag = row["all-day"]
  return {
    id: typeof row.uid === "string" ? row.uid : "",
    title: typeof row.title === "string" ? row.title : "",
    startDateTime: start,
    endDateTime: end === null ? start : end,
    isAllDay: flag === true || flag === "True" || flag === "true",
    eventColor: "",
    eventType: "",
    // khal hands us expanded instances with no `dateKey`; they are placed by
    // their own `[start, end)` span below.
    dateKey: null
  }
}

// `khal list <from> <to> --json ...` output, parsed and mapped.
//
// khal 0.14.1 prints ONE JSON ARRAY PER CALENDAR DAY, each on its own line
// (`khal/controllers.py:328-332`). A bare object on a line is accepted too, so
// a version that drops the per-day grouping still parses. The datetimes are
// formatted with the locale's `datetimeformat` (`event.py:648`), `%c` by
// default - which no fixed parser can read - so this accepts exactly
// `YYYY-MM-DD HH:MM` (and `YYYY-MM-DD` for an all-day row) and counts every
// other line as a failure: khal's config needs `[locale] datetimeformat =
// %Y-%m-%d %H:%M`, and a machine without it says so through `readError`
// instead of rendering wrong times silently.
//
// `{ rows, errors }` - `errors` is the count of lines and rows that did not
// parse, which the caller folds into `readError`. Empty output is zero errors:
// "khal answered, nothing is scheduled" is not a failure.
function parseKhalOutput(text) {
  var body = (text === undefined || text === null) ? "" : String(text)
  var lines = body.split("\n")
  var rows = []
  var errors = 0
  for (var i = 0; i < lines.length; i++) {
    var line = trimmed(lines[i])
    if (line === "") continue
    var parsed
    try {
      parsed = JSON.parse(line)
    } catch (e) {
      errors++
      continue
    }
    var list = Array.isArray(parsed) ? parsed : [parsed]
    for (var j = 0; j < list.length; j++) {
      var mapped = mapKhalRow(list[j])
      if (mapped === null) errors++
      else rows.push(mapped)
    }
  }
  return { rows: rows, errors: errors }
}

// Is `row` on the local day `date` falls on?
//
// A row with a `dateKey` answers it directly - that is what the field is for.
// A row without one (khal, or a writer that omits the field) is on every local
// day its `[start, end)` span touches: a half-open interval, so an all-day
// event starting at tomorrow's midnight covers tomorrow and not today.
function coversDay(row, date) {
  if (row.dateKey !== null) return row.dateKey === localDateKey(date)
  var dayStart = new Date(date.getFullYear(), date.getMonth(), date.getDate())
  var dayEnd = new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1)
  return row.startDateTime.getTime() < dayEnd.getTime()
      && row.endDateTime.getTime() > dayStart.getTime()
}

// All-day rows first, then by start, then by title.
//
// Both widget bodies already impose this order themselves; producing it here
// means the seam's answer is stable on its own, and it is the order a reader
// expects (a banner above the day's clock times).
function compare(a, b) {
  if (a.isAllDay !== b.isAllDay) return a.isAllDay ? -1 : 1
  var delta = a.startDateTime.getTime() - b.startDateTime.getTime()
  if (delta !== 0) return delta
  if (a.title === b.title) return 0
  return a.title < b.title ? -1 : 1
}

// One local day's events, out of both sources.
//
// THE DOCUMENT WINS: when a `khal` row's `uid` is an `id` the document also
// carries on that day, the document's row is kept and khal's is dropped - it is
// the richer record (colour, calendar name, the writer's own `dateKey`) and it
// is the one the operator's sync owns. The comparison is per day, which is what
// keeps it from collapsing a recurring event's instances: khal gives every
// instance the same `uid`, and only the same DAY is ever compared.
function forDay(fileRows, khalRows, date) {
  var file = fileRows || []
  var khal = khalRows || []
  var out = []
  var ids = {}
  var i
  var row
  for (i = 0; i < file.length; i++) {
    row = file[i]
    if (!coversDay(row, date)) continue
    out.push(row)
    if (row.id !== "") ids[row.id] = true
  }
  for (i = 0; i < khal.length; i++) {
    row = khal[i]
    if (row.id !== "" && ids[row.id] === true) continue
    if (coversDay(row, date)) out.push(row)
  }
  out.sort(compare)
  return out
}

// "3 days ago" - the age of the last sync, for the widget's `stateDetail`.
//
// Coarse on purpose: the number is a warning about freshness, not a log line,
// and an operator reading "3 days ago" knows what to do with it.
function agePhrase(thenMs, nowMs) {
  var seconds = Math.floor((nowMs - thenMs) / 1000)
  if (!isFinite(seconds) || seconds < 60) return "just now"
  var minutes = Math.floor(seconds / 60)
  if (minutes < 60) return minutes === 1 ? "a minute ago" : minutes + " minutes ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours === 1 ? "an hour ago" : hours + " hours ago"
  var days = Math.floor(hours / 24)
  return days === 1 ? "a day ago" : days + " days ago"
}

// `Engine.js`'s guard, for the same reason: the file is plain ES5 that a
// `node` test can `require`, and QML never defines `module`.
if (typeof module !== "undefined") {
  module.exports = {
    localDateKey: localDateKey,
    parseDateTime: parseDateTime,
    colour: colour,
    mapRow: mapRow,
    parseDocument: parseDocument,
    mapKhalRow: mapKhalRow,
    parseKhalOutput: parseKhalOutput,
    coversDay: coversDay,
    compare: compare,
    forDay: forDay,
    agePhrase: agePhrase
  }
}
