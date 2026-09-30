import QtQuick
import Quickshell
import Quickshell.Io
import "events/CalendarEvents.js" as CalendarEvents

// The calendar widget's only view of event data.
//
// Plasma supplied this through three `PlasmaCalendar.Calendar` backends, an
// `EventPluginsManager` and `daysModel.eventsForDate()`. That stack is
// Akonadi/KDE-PIM and does not exist off Plasma, so this is the seam where a
// replacement plugs in: whatever the backend, it returns objects with the
// same shape `EventCard.qml` and the grouping logic already render.
//
// ── This machine has no event source yet, and that is a finding ──
//
// Surveyed on 2026-09-06 (plan 011 phase A) and re-checked 2026-09-15:
//   * No calendar CLI installed - `khal`, `vdirsyncer`, `calcurse`, `gcalcli`
//     are all absent (`command -v` for each).
//   * No CalDAV or local-calendar configuration anywhere: no
//     ~/.config/vdirsyncer, ~/.local/share/vdirsyncer, ~/.config/khal,
//     ~/.local/share/calendars, ~/.calendars, no Evolution data server, no
//     Akonadi.
//   * The only `.ics` on disk is one downloaded invitation sitting in
//     ~/.local/share/Trash - not a calendar store.
//   * Quickshell 0.3.1 ships Greetd, Mpris, Notifications, Pam, Pipewire,
//     Polkit, SystemTray and UPower. There is no calendar service.
//   * `t1nk33r.todoist` is a bar-widget-only plugin whose state directory
//     holds nothing but `settings.json` (an API token); it caches no tasks
//     for anyone else to read.
//
// So `eventsForDate()` returning an empty array is still the truth here, not a
// placeholder - there is no data to return. What plan 020 changed is that the
// seam now has a real implementation behind it, so the day a writer appears the
// widget renders its events with no code change:
//
//   * `eventsFile` - `~/.local/state/omarchy/calendar-events.json`, the
//     document `tmn73/omarchy-calendar` (MIT) publishes and any sync writer can
//     produce. It is adopted VERBATIM (see `events/CalendarEvents.js` for the
//     schema and the two `dateKey` traps) and is watched, so an atomic
//     temp-file-plus-rename by the writer is picked up with no polling.
//   * `khal` - `khal list <from> <to> --json ...`, merged with the document,
//     and only if `command -v khal` says it is installed. Detection is one
//     probe per instance and is never repeated, so a machine without khal runs
//     no khal process at all.
//
// The rest of the interface is unchanged, and deliberately so: the root stays a
// `QtObject`, `eventsForDate(date)` keeps its signature and its returned field
// names (`title`, `startDateTime`, `endDateTime`, `isAllDay`, `eventColor`,
// `eventType` - Plasma's `EventDataDecorator` names), and `eventsChanged()` is
// still the one signal, emitted once per reload. This file reads no
// `plugin.settings.*`: the seam's configuration is its own properties, and
// `tests/run.sh` fails the build if a `plugin.settings` read appears
// here.
QtObject {
    id: source

    // ── Where the events come from ───────────────────────────────────────
    // The document's directory, derived exactly as `ClaudeUsageData` derives
    // its record: $XDG_STATE_HOME, else ~/.local/state. A sync writer owns the
    // file; this seam only ever reads it and never writes, migrates or repairs
    // it.
    readonly property string stateHome: {
        var env = Quickshell.env("XDG_STATE_HOME")
        if (env && String(env) !== "") return String(env)
        return Quickshell.env("HOME") + "/.local/state"
    }
    // Writable, so a dev harness can point the seam at a fixture - the property
    // is the seam's whole input path.
    property string eventsFile: source.stateHome + "/omarchy/calendar-events.json"

    // Never required: with no khal on PATH nothing is run, and the document
    // alone is a complete backend.
    property bool khalEnabled: true
    // khal hands us expanded instances, so its window has to cover what the
    // widget looks at. `widgets/calendar/main.qml`'s `_lookaheadPresets` tops
    // out at 60 days, and the seam may not read the setting that selects it.
    property int khalLookaheadDays: 60
    // 24 h, as a labelled guess: no published writer supplies its own refresh
    // interval yet, and the honest upgrade is `4 x intervalSeconds` once one
    // does. Past it the events are still returned - stale warns, it never
    // hides.
    property int staleAfterSeconds: 86400

    // ── What a widget reads ──────────────────────────────────────────────
    // "no-backend" | "empty" | "stale" | "ok" - exactly four, no fifth.
    //   no-backend  nothing can answer: no document and no khal, or a document
    //               that is not the published schema (`readError` says why)
    //   empty       a backend answered and nothing is scheduled
    //   stale       the document's `syncedAt` is older than the threshold
    //   ok          a backend answered with events
    // The widgets read this and `stateDetail` to word their empty state; they
    // never parse anything and they never branch their LAYOUT on it.
    readonly property string state: {
        if (source._fileError !== "") return "no-backend"
        if (!source._fileLoaded && !source._khalPresent) return "no-backend"
        if (source._stale) return "stale"
        return source._fileEvents.length + source._khalEvents.length === 0 ? "empty" : "ok"
    }

    // The one detail a widget may print under the state: the watched path when
    // there is no backend, the age of the last sync when the data is stale, and
    // nothing when the state speaks for itself.
    readonly property string stateDetail: {
        if (source._stale) return CalendarEvents.agePhrase(source._syncedAtMs, source._nowMs)
        if (source._fileLoaded || source._khalPresent) return ""
        return source.eventsFileLabel
    }

    // `eventsFile` as it may be DRAWN. The tile prints this onto the desktop,
    // and into every screenshot of it, so it must never carry an account name.
    // It is derived from where the path came from rather than by matching the
    // resolved string - matching is what broke on a trailing-slash HOME, a
    // symlinked HOME and an XDG_STATE_HOME outside HOME:
    //   XDG_STATE_HOME unset (or the standard ~/.local/state)
    //       -> "~/.local/state/omarchy/calendar-events.json"
    //   any other XDG_STATE_HOME -> "$XDG_STATE_HOME/omarchy/calendar-events.json"
    //   an overridden eventsFile (nothing in the plugin sets one; a harness
    //       may) -> a fixed phrase. Any piece of an arbitrary path - a suffix
    //       under HOME, a `..` walk, even the bare file name - can spell an
    //       account, so none of it is drawn.
    // `eventsFile` itself stays absolute: it is what the FileView reads.
    readonly property string eventsFileLabel: {
        var tail = "/omarchy/calendar-events.json"
        if (source.eventsFile === source.stateHome + tail) {
            var xdg = source._normPath(Quickshell.env("XDG_STATE_HOME"))
            var home = source._normPath(Quickshell.env("HOME"))
            if (xdg === "" || (home !== "" && home !== "/" && xdg === home + "/.local/state"))
                return "~/.local/state" + tail
            return "$XDG_STATE_HOME" + tail
        }
        return "a custom calendar-events.json"
    }

    // Collapse repeated slashes and drop a trailing one, so "/home/a/" and
    // "/home//a" compare equal to "/home/a". Lexical only - no filesystem call.
    function _normPath(path) {
        var p = String(path || "").replace(/\/{2,}/g, "/")
        return p.length > 1 ? p.replace(/\/$/, "") : p
    }

    // What is answering, in words - "calendar-events.json", "khal", or both.
    // Empty exactly when `state` is "no-backend".
    readonly property string backendLabel: {
        var file = source._fileLoaded ? "calendar-events.json" : ""
        var khal = source._khalPresent ? "khal" : ""
        if (file !== "" && khal !== "") return "khal + calendar-events.json"
        return file !== "" ? file : khal
    }

    // "" when fine. A document that is not the schema and a khal line that did
    // not parse both land here; only the first is a `no-backend` (see `state`),
    // because the second still has the document to fall back on.
    readonly property string readError: source._fileError !== "" ? source._fileError : source._khalError

    // A backend answered - "can this seam produce events", not "does it have
    // any". One definition of the four states read backwards.
    readonly property bool hasBackend: source.state !== "no-backend"

    // Fired when the event data behind `eventsForDate` has changed. The
    // widget coalesces bursts of these into one rebuild (80 ms), so a
    // file-watching or polling backend can emit freely.
    signal eventsChanged()

    // -> [ { title, startDateTime, endDateTime, isAllDay, eventColor,
    //        eventType } ]
    // Field names match Plasma's EventDataDecorator exactly so the widget
    // body ports unchanged.
    function eventsForDate(date) {
        return source._eventsFor(date)
    }

    // The one function a backend replaces. All-day rows first, then by start,
    // then by title; the document wins over khal on a shared id.
    function _eventsFor(date) {
        return CalendarEvents.forDay(source._fileEvents, source._khalEvents, date)
    }

    // ── The document ─────────────────────────────────────────────────────
    property bool _fileLoaded: false
    property string _fileError: ""
    property var _fileEvents: []
    // Epoch ms of the document's own `syncedAt`, or 0 when it has none - an
    // undated document is not a stale one, because nothing can be measured
    // against it.
    property double _syncedAtMs: 0
    // The file is re-read on a 60 s clock as well as on change, so identical
    // bytes must not become identical work downstream. `eventsChanged()` still
    // fires once per real reload.
    property string _lastSeenText: ""
    property bool _fileSettled: false

    // The watcher, held as a typed property rather than a bare child: a
    // `QtObject` has no children to reparent one into. `watchChanges` is the
    // whole mechanism the published contract expects a reader to use.
    property FileView _view: FileView {
        id: view
        path: source.eventsFile
        watchChanges: true
        printErrors: false
        onFileChanged: view.reload()
        onLoaded: source._applyFile(view.text())
        onLoadFailed: source._missingFile()
    }

    // The backstop the watcher cannot be. `watchChanges` needs an inode, so it
    // never fires for a file that does not exist yet - the normal state before
    // anyone syncs - and an atomic rename can land between two watches. This is
    // the seam's only poll: 60 s, four reads an hour, and it is also what lets
    // a document cross the staleness threshold with no file change at all.
    property Timer _backstop: Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: {
            source._nowMs = Date.now()
            view.reload()
        }
    }

    property double _nowMs: Date.now()

    readonly property bool _stale: source._fileLoaded && source._syncedAtMs > 0
        && (source._nowMs - source._syncedAtMs) > source.staleAfterSeconds * 1000

    function _applyFile(text) {
        if (source._fileSettled && text === source._lastSeenText) return
        source._lastSeenText = text
        source._fileSettled = true
        var parsed = CalendarEvents.parseDocument(text)
        source._fileLoaded = parsed.ok
        source._fileError = parsed.ok ? "" : parsed.error
        source._fileEvents = parsed.ok ? parsed.rows : []
        source._syncedAtMs = parsed.ok ? parsed.syncedAtMs : 0
        source.eventsChanged()
    }

    function _missingFile() {
        var wasSomething = source._fileLoaded || source._fileEvents.length > 0
        source._fileSettled = true
        source._lastSeenText = ""
        if (!wasSomething && source._fileError === "") return
        // A document that was there and is gone is the same state as one that
        // was never written: nothing can answer.
        source._fileLoaded = false
        source._fileError = ""
        source._fileEvents = []
        source._syncedAtMs = 0
        source.eventsChanged()
    }

    // ── khal, if it is installed ─────────────────────────────────────────
    property bool _khalPresent: false
    property bool _khalProbed: false
    property var _khalEvents: []
    property string _khalError: ""

    // One `command -v khal`, once per instance. A non-zero exit means absent,
    // and then nothing else is ever run - no timer, no retry, no second look.
    property Process _khalProbe: Process {
        command: ["sh", "-c", "command -v khal"]
        running: source.khalEnabled && !source._khalProbed
        onExited: function (exitCode) {
            source._khalProbed = true
            source._khalPresent = exitCode === 0
            if (source._khalPresent) source._runKhal()
        }
    }

    // Today to the widget's own lookahead bound, in the local calendar.
    readonly property var _khalWindow: {
        var now = new Date()
        var from = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        var to = new Date(from.getFullYear(), from.getMonth(), from.getDate() + source.khalLookaheadDays)
        return [CalendarEvents.localDateKey(from), CalendarEvents.localDateKey(to)]
    }

    // khal 0.14.1 prints one JSON array per calendar day, each on its own line,
    // and formats the datetimes with the locale's `datetimeformat` (`%c` by
    // default). The parser accepts that format's fixed replacement and counts
    // anything else as a failed line, so `[locale] datetimeformat =
    // %Y-%m-%d %H:%M` is a requirement of using khal here and a machine
    // without it gets a `readError` instead of wrong times.
    property Process _khalList: Process {
        id: khalList
        running: false
        command: ["khal", "list", source._khalWindow[0], source._khalWindow[1],
                  "--json", "uid", "--json", "title", "--json", "start",
                  "--json", "end", "--json", "all-day", "--json", "calendar"]
        stdout: StdioCollector {
            onStreamFinished: source._applyKhal(text)
        }
        onExited: function (exitCode) {
            if (exitCode === 0 || source._khalError !== "") return
            source._khalEvents = []
            source._khalError = "khal list exited " + exitCode
            source.eventsChanged()
        }
    }

    function _runKhal() {
        khalList.running = true
    }

    function _applyKhal(text) {
        var parsed = CalendarEvents.parseKhalOutput(text)
        source._khalEvents = parsed.rows
        if (parsed.errors === 0) source._khalError = ""
        else source._khalError = parsed.errors + (parsed.errors === 1
            ? " khal line did not parse" : " khal lines did not parse")
        source.eventsChanged()
    }

    // True once the document has been read (or found missing) and the khal
    // probe has answered: after this, `state` means something. The dev probe
    // waits on it; no widget reads it.
    readonly property bool _settled: source._fileSettled
        && (source._khalProbed || !source.khalEnabled)
}
