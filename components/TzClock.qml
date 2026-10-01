import QtQuick
import Quickshell.Io

// Per-timezone wall clock. Replaces org.kde.plasma.clock's Clock (C++/
// QTimeZone-backed), which does not exist outside Plasma. The contract to
// preserve is: current time for an IANA zone, correct across DST
// transitions, with a change signal.
//
// See PORTING.md item 13 (plan 007 step 1) for which backend was chosen and
// why: this Qt build's QML JS engine has no `Intl` support at all, so
// `Date.prototype.toLocaleString`'s `timeZone` option silently no-ops rather
// than throwing -- it was verified to return the SAME (system-zone) string
// for every zone tested, including on both sides of a DST boundary. The only
// correct source of zone offsets here is the system's own tzdata, reached by
// shelling out to `date` under `TZ=<zone>` -- never a static offset table,
// which goes stale the next time a country changes its DST law.
Item {
    id: root

    property string timeZone: ""
    property bool trackSeconds: false

    // False when `date` did not recognise `timeZone`. glibc never errors on
    // an unknown TZ: `TZ=Foo/Bar date +%Z%z` prints `Foo+0000`, i.e. it
    // silently becomes UTC with the first path component as the
    // abbreviation. That is exactly what a typo in the `clocks` setting
    // produces, and without this flag it rendered as a plausible UTC clock.
    // Detected from that signature: offset 0 AND abbreviation == first
    // component of the zone string (UTC itself excepted).
    property bool zoneValid: true

    // Run the four-process DST self-test from this instance. Default off:
    // WorldClockQs enables it on its first clock only, so a widget costs
    // 4 extra `date` spawns at startup rather than 4 per configured city.
    property bool runSelfTest: false

    // Wall-clock time in `timeZone`, exposed the same way
    // org.kde.plasma.clock's Clock.dateTime did: a plain JS Date object whose
    // getHours()/getMinutes()/getDate()/etc (which JS can only ever evaluate
    // in the *system* timezone) report `timeZone`'s wall-clock values. This
    // works by shifting the true instant by (zone offset - system offset)
    // before constructing the Date -- see _recompute().
    readonly property date dateTime: _dateTime
    property date _dateTime: new Date()

    // "UTC+HH:MM" / "UTC-HH:MM" -- the format WorldClock.qml's
    // _offsetHoursFromStringFractional() parses via regex, matching what
    // org.kde.plasma.clock's Clock.timeZoneOffset produced.
    readonly property string timeZoneOffset: _offsetKnown ? _offsetLabel(_offsetMinutes) : ""

    signal timeChanged()

    // Offset of `timeZone` from UTC, in minutes (fractional-hour zones like
    // India are +330, not a whole hour). Refreshed hourly and on `timeZone`
    // change; a `date`/tzdata subprocess is the only correct source (see file
    // header) -- never hard-code this.
    property int _offsetMinutes: 0
    property bool _offsetKnown: false

    function _offsetLabel(minutes) {
        const sign = minutes < 0 ? "-" : "+";
        const abs  = Math.abs(minutes);
        const hh   = Math.floor(abs / 60);
        const mm   = abs % 60;
        return "UTC" + sign + (hh < 10 ? "0" + hh : String(hh)) + ":" + (mm < 10 ? "0" + mm : String(mm));
    }

    // Rebuild `_dateTime` from Date.now() plus the cached zone offset. Called
    // on every tick (see the tick Timers below) and whenever the offset
    // itself refreshes. Emits timeChanged() so WorldClockQs's Instantiator
    // delegate (onTimeChanged: root._rebuild()) rebuilds.
    function _recompute() {
        if (!root._offsetKnown) return;
        // Build a Date whose SYSTEM-zone fields equal the target zone's wall
        // clock. `wall` is the zone's wall time expressed as if it were UTC;
        // we then need d such that d + sysOffset(d) == wall. The system
        // offset must be taken at the SHIFTED instant, not at now: the
        // earlier `now + (zoneOff - sysOff(now))` form was one hour wrong
        // for |zoneOff - sysOff| hours around every system-zone DST switch
        // (probe under TZ=Europe/London: Tokyo read 06:00 for a true 05:00).
        // Invisible in a no-DST system zone such as this machine's Riyadh,
        // which is exactly why it survived plan 007. Two fixpoint passes
        // settle the boundary case.
        const wall = Date.now() + root._offsetMinutes * 60000;
        let d = new Date(wall + new Date(wall).getTimezoneOffset() * 60000);
        d = new Date(wall + d.getTimezoneOffset() * 60000);
        root._dateTime = d;
        root.timeChanged();
    }

    // --- Offset resolution (Quickshell.Io.Process) ----------------------------
    // One short-lived `date` process per configured zone per hour -- see
    // PORTING.md item 13 for why this is judged acceptable for a handful of
    // cities, and the STOP condition that applies if it ever isn't.

    Process {
        id: offsetProc
        running: false
        command: ["env", "TZ=" + root.timeZone, "date", "+%Z %z"]
        // A timeZone change while `date` is still running must re-run, or
        // the OLD zone's answer is stored under the new zone until the next
        // hourly refresh.
        onRunningChanged: if (!running && root._refetch) { root._refetch = false; running = true }
        stdout: StdioCollector {
            onStreamFinished: {
                const s = String(text || "").trim();
                // A run started for an earlier zone that has since been
                // replaced by an invalid one has nothing to say about it.
                if (!root._zoneNameValid(root.timeZone)) return;
                const m = /^(\S+)\s+([+-])(\d{2})(\d{2})$/.exec(s);
                if (m) {
                    const abbrev = m[1];
                    const minutes = (m[2] === "-" ? -1 : 1) * (parseInt(m[3], 10) * 60 + parseInt(m[4], 10));
                    const firstComponent = String(root.timeZone).split("/")[0];
                    const unknown = minutes === 0 && abbrev === firstComponent
                        && root.timeZone !== "UTC" && root.timeZone !== "Etc/UTC";
                    if (unknown && root.zoneValid)
                        console.warn("TzClock: zone", JSON.stringify(root.timeZone), "is not in tzdata (date reported", JSON.stringify(s) + "); showing UTC. Check the `clocks` setting.");
                    root.zoneValid = unknown ? false : true;
                    root._offsetMinutes = minutes;
                    const wasKnown = root._offsetKnown;
                    root._offsetKnown = true;
                    root._recompute();
                    if (!wasKnown) root._scheduleNextMinuteTick();
                } else {
                    console.warn("TzClock: could not parse `date +%Z %z` output for zone", root.timeZone, "->", JSON.stringify(s));
                }
            }
        }
    }

    property bool _refetch: false

    // An IANA name, as prayer-zone.sh accepts one: relative components of
    // letters, digits and `._+-`, no `..`. `timeZone` comes from the `clocks`
    // setting and becomes `TZ` for `date`, and glibc reads a TZ that starts
    // with `/` or `:` as a FILE to load - so anything else never reaches the
    // environment and is shown as the unknown zone it is.
    function _zoneNameValid(zone) {
        const z = String(zone);
        return /^[A-Za-z0-9][A-Za-z0-9._+-]*(\/[A-Za-z0-9._+-]+)*$/.test(z) && z.indexOf("..") === -1;
    }

    function _refreshOffset() {
        if (!root.timeZone) { root._offsetKnown = false; return; }
        if (!root._zoneNameValid(root.timeZone)) {
            if (root.zoneValid)
                console.warn("TzClock: zone", JSON.stringify(root.timeZone), "is not an IANA zone name; showing UTC. Check the `clocks` setting.");
            // The same state `date` produces for a name tzdata does not know.
            root._refetch = false;
            root.zoneValid = false;
            root._offsetMinutes = 0;
            const wasKnown = root._offsetKnown;
            root._offsetKnown = true;
            root._recompute();
            if (!wasKnown) root._scheduleNextMinuteTick();
            return;
        }
        if (offsetProc.running) root._refetch = true;
        else offsetProc.running = true;
    }

    onTimeZoneChanged: root._refreshOffset()

    // Hourly refresh. DST offsets change at a fixed moment (not gradually),
    // so an hourly poll catches every real-world transition within an hour;
    // a live desktop also wants this to survive suspend/resume, which an
    // hourly wall-clock Timer already does once the system timer fires again.
    // Every real-world DST switch lands on a :00 or :30 UTC boundary, so a
    // one-shot re-armed to 2 s past the next half hour picks a transition up
    // within seconds instead of anywhere up to 59 minutes late (a repeating
    // 3600000 ms Timer started at instantiation time). Two `date` spawns per
    // zone per hour instead of one — still nothing.
    Timer {
        id: offsetRefresh
        repeat: false
        running: true
        interval: 1800000 - (Date.now() % 1800000) + 2000
        onTriggered: {
            root._refreshOffset();
            offsetRefresh.interval = 1800000 - (Date.now() % 1800000) + 2000;
            offsetRefresh.running = true;
        }
    }

    // Tick discipline (AGENTS.md): 1 Hz only when trackSeconds is set;
    // otherwise once a minute, aligned to the true wall-clock boundary rather
    // than drifting off a fixed 60000ms interval (see calendar/main.qml's
    // midnightTimer + scheduleNextMidnight() for the same pattern).
    // 1 Hz, re-armed to the next wall-clock second boundary so every TzClock
    // on the desktop ticks in the same event-loop pass (all real zones share
    // the same seconds). A free-running 1000 ms repeat timer started at
    // instantiation gave each clock its own phase: grid second hands stepped
    // visibly out of sync, and WorldClockQs rebuilt N times a second.
    Timer {
        id: secondTicker
        repeat: false
        running: root.trackSeconds && root._offsetKnown
        interval: 1000 - (Date.now() % 1000)
        onTriggered: {
            root._recompute();
            secondTicker.interval = 1000 - (Date.now() % 1000);
            secondTicker.running = root.trackSeconds && root._offsetKnown;
        }
    }

    Timer {
        id: minuteTicker
        repeat: false
        running: false
        onTriggered: {
            root._recompute();
            root._scheduleNextMinuteTick();
        }
    }

    function _scheduleNextMinuteTick() {
        if (root.trackSeconds || !root._offsetKnown) return;
        const msIntoMinute = Date.now() % 60000;
        minuteTicker.interval = Math.max(50, 60000 - msIntoMinute);
        minuteTicker.running = true;
    }

    onTrackSecondsChanged: if (!root.trackSeconds) root._scheduleNextMinuteTick()

    // --- DST correctness self-test (plan 007 step 5) --------------------------
    // The live system clock cannot be moved to observe a real DST transition
    // (AGENTS.md's live-desktop rules), so this checks the same Process-based
    // offset resolution above against two hard-coded, independently-verified
    // instants for two zones -- one inside DST, one outside -- and warns
    // (never throws) on a mismatch. Ground truth for these four pairs is
    // recorded in PORTING.md item 13 (`TZ=<zone> date -d '<date> UTC' ...`).
    // Gated on `runSelfTest` (see the property): four short-lived `date`
    // subprocesses per *widget*, not per city. It used to run in every
    // TzClock — with four cities per widget and several city widgets on a
    // desktop, dozens of identical spawns at every shell start for one
    // canary's worth of information.
    Process {
        running: root.runSelfTest
        command: ["env", "TZ=America/New_York", "date", "-d", "@1768478400", "+%z"]
        stdout: StdioCollector {
            onStreamFinished: root._dstAssert("America/New_York", "2026-01-15 12:00 UTC (EST, no DST)", "-0500", String(text || "").trim())
        }
    }
    Process {
        running: root.runSelfTest
        command: ["env", "TZ=America/New_York", "date", "-d", "@1784116800", "+%z"]
        stdout: StdioCollector {
            onStreamFinished: root._dstAssert("America/New_York", "2026-07-15 12:00 UTC (EDT, DST)", "-0400", String(text || "").trim())
        }
    }
    Process {
        running: root.runSelfTest
        command: ["env", "TZ=Australia/Adelaide", "date", "-d", "@1768478400", "+%z"]
        stdout: StdioCollector {
            onStreamFinished: root._dstAssert("Australia/Adelaide", "2026-01-15 12:00 UTC (ACDT, southern-summer DST)", "+1030", String(text || "").trim())
        }
    }
    Process {
        running: root.runSelfTest
        command: ["env", "TZ=Australia/Adelaide", "date", "-d", "@1784116800", "+%z"]
        stdout: StdioCollector {
            onStreamFinished: root._dstAssert("Australia/Adelaide", "2026-07-15 12:00 UTC (ACST, southern-winter no DST)", "+0930", String(text || "").trim())
        }
    }

    function _dstAssert(zone, whenLabel, expected, actual) {
        if (actual !== expected) {
            console.warn("TzClock DST self-test FAILED:", zone, whenLabel, "expected", expected, "got", actual,
                "-- offset resolution may be wrong; see PORTING.md item 13");
        }
    }

    Component.onCompleted: root._refreshOffset()
}
