import QtQuick
import Quickshell
import "components"

// NOTE: `qs` refuses to load a QML module path outside the config folder,
// so run.sh copies this file next to a dereferenced `components/` in a temp
// directory and runs it there - hence the plain `import "components"`.
//
// Headless check of PrayerTimes' time-of-day rules, run by tests/run.sh when
// `qs` is on PATH.
//
// Hermetic: the location comes from a FIXTURE, not from the operator. run.sh's
// fixture_prayers() writes a t1nk33r.omaprayers entry (Karachi, method 1,
// Asia/Karachi) into the scratch HOME's shell.json, and the harness points
// HOME and XDG_CONFIG_HOME at that scratch tree - so this reads no part of the
// machine it runs on, and no part of the machine's timezone: every instant
// below is an epoch out of the fixture's own schedule, compared against
// epochs the component derives the same way.
//
// The six instants are DERIVED from that schedule instead of written as clock
// times: "before Fajr" is Fajr minus 30 minutes, "after sunset" is Maghrib
// plus 15, and so on. Fixed clock times cannot survive the year - sunrise in
// any city moves by hours between June and December, so a hard-coded 06:00 is
// daylight in one season and night in the other, and a fixed 21:00 is "after
// Isha" in winter and mid-evening in summer. The rules are about where an
// instant sits relative to that day's prayers, so each instant is built to sit
// there; that is what makes the 66 checks mean the same thing on every run,
// in every season, in any timezone.
//
// Moving the machine's clock is still forbidden (it re-derives the whole
// schedule), so PrayerTimes.nowOverride is the seam, as before.
ShellRoot {
  id: shell

  Item {
    id: host

    PrayerTimes { id: p }

    property int failures: 0
    property int checks: 0
    property var cases: null
    property int index: -1
    readonly property int minute: 60000

    function check(label, ok, detail) {
      host.checks++
      if (!ok) {
        host.failures++
        console.log("FAIL " + label + (detail ? "  (" + detail + ")" : ""))
      }
    }

    // The schedule day the component resolved for its own "now": `_zone.today`
    // is that zone's current date, and every instant has to come from that
    // same civil day or the rollover assertions would describe one day while
    // the instants described another.
    function dayTable() {
      var days = (p._schedule && p._schedule.days) ? p._schedule.days : []
      for (var i = 0; i < days.length; i++)
        if (days[i].date === p._zone.today) return days[i]
      return null
    }

    // A timing's `at` is an offset-carrying ISO string; the epoch it parses to
    // is what the component itself compares `nowOverride` against.
    function timing(day, key) {
      var t = day.timings[key]
      return (t && t.at) ? new Date(t.at).getTime() : NaN
    }

    // null after printing why, on a premise the fixture or the engine broke:
    // a case labelled "after sunset, before Isha" that is not before Isha
    // would assert the wrong rule, so it must fail loudly here rather than
    // half-run the 66 with mislabelled cases.
    function deriveCases() {
      var day = host.dayTable()
      if (!day) {
        console.log("FAIL PrayerTimes harness: no schedule day for "
                    + (p._zone ? p._zone.today : "?"))
        return null
      }
      var days = p._zone.days || []
      var start = NaN
      var end = NaN
      for (var i = 0; i < days.length - 1; i++) {
        if (days[i].date === p._zone.today) {
          start = days[i].start * 1000
          end = days[i + 1].start * 1000
        }
      }

      var m = host.minute
      var fajr = host.timing(day, "Fajr")
      var sunrise = host.timing(day, "Sunrise")
      var sunset = host.timing(day, "Sunset")
      var isha = host.timing(day, "Isha")
      var endOfDay = end - m

      var problems = []
      if (!(fajr < sunrise && sunrise < sunset && sunset < isha))
        problems.push("the day's Fajr < Sunrise < Sunset < Isha")
      if (!(sunrise + 30 * m < sunrise + (sunset - sunrise) / 2))
        problems.push("the day is longer than an hour, so sunrise+30 is before midday")
      if (!(fajr - 30 * m >= start))
        problems.push("Fajr-30 is inside the civil day")
      if (!(sunset + 15 * m < isha))
        problems.push("Sunset+15 is before Isha")
      if (!(isha + 15 * m < end))
        problems.push("Isha+15 is inside the civil day")
      if (!(endOfDay > isha))
        problems.push("the last minute of the day is after Isha")
      if (problems.length) {
        console.log("FAIL PrayerTimes harness: " + problems.join("; "))
        return null
      }

      // label, instant, isDaylight, rolled to tomorrow, where the day arc sits
      return [
        { label: "before Fajr",   at: fajr - 30 * m, daylight: false, tomorrow: false, arc: "start"  },
        { label: "after sunrise", at: sunrise + 30 * m, daylight: true, tomorrow: false, arc: "inside" },
        { label: "solar midday",  at: sunrise + (sunset - sunrise) / 2, daylight: true, tomorrow: false, arc: "inside" },
        { label: "after sunset",  at: sunset + 15 * m, daylight: false, tomorrow: false, arc: "end"    },
        { label: "after Isha",    at: isha + 15 * m, daylight: false, tomorrow: true,  arc: "end"    },
        { label: "day's last minute", at: endOfDay, daylight: false, tomorrow: true,  arc: "end"      }
      ]
    }

    function verify(c) {
      host.check(c.label + " has a next prayer", !!p.next)
      if (p.next) {
        host.check(c.label + " next prayer is in the future",
                   p.next.at.getTime() > c.at,
                   p.next.key + " at " + p.next.at)
        host.check(c.label + " countdown is shown", p.remainingText !== "")
      }
      host.check(c.label + " has the prayer after next", !!p.after)
      host.check(c.label + " lists six rows", p.rows.length === 6, "got " + p.rows.length)
      host.check(c.label + " marks exactly one row as next",
                 p.rows.filter(function (r) { return r.isNext }).length === 1)
      host.check(c.label + " rolls over to tomorrow only after Isha",
                 p.showsTomorrow === c.tomorrow, "showsTomorrow=" + p.showsTomorrow)
      host.check(c.label + " daylight flag", p.isDaylight === c.daylight, "isDaylight=" + p.isDaylight)
      host.check(c.label + " ring progress within 0..1",
                 p.progress >= 0 && p.progress <= 1, "progress=" + p.progress)
      if (c.arc === "inside") {
        host.check(c.label + " day progress strictly inside the day",
                   p.dayProgress > 0 && p.dayProgress < 1, "dayProgress=" + p.dayProgress)
      } else {
        host.check(c.label + " day progress parked at " + (c.arc === "start" ? "sunrise" : "sunset"),
                   p.dayProgress === (c.arc === "start" ? 0 : 1), "dayProgress=" + p.dayProgress)
      }
      host.check(c.label + " sun times are formatted",
                 p.sunriseText !== "" && p.sunsetText !== "")
    }

    Timer {
      id: driver
      interval: 250
      repeat: true
      running: true
      property int waited: 0

      onTriggered: {
        if (!p.ok) {
          driver.waited++
          if (driver.waited > 40) {
            console.log("FAIL PrayerTimes never became ready: " + p.error)
            Qt.exit(1)
          }
          return
        }

        // The fixture's schedule has to exist before the instants can be read
        // out of it; that is one tick, and the cases are then fixed for the run.
        if (host.cases === null) {
          host.cases = host.deriveCases()
          if (host.cases === null) Qt.exit(1)
          return
        }

        if (host.index >= 0) host.verify(host.cases[host.index])

        host.index++
        if (host.index >= host.cases.length) {
          console.log(host.failures === 0
            ? "OK: PrayerTimes rollover rules hold at " + host.checks + " checks across the day"
            : host.failures + " of " + host.checks + " prayer rollover checks FAILED")
          Qt.exit(host.failures === 0 ? 0 : 1)
          return
        }
        p.nowOverride = host.cases[host.index].at
      }
    }
  }
}
