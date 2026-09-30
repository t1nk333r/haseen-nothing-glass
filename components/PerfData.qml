import QtQuick
import Quickshell.Io

// What the machine is doing: processor load, memory in use, and the
// temperatures this host actually exposes. Read-only client of files the
// kernel publishes - no daemon, no lm_sensors, no `sensors` binary, no
// process spawned per reading.
//
// Every source here is a plain file:
//   /proc/stat                      the CPU counters, as a delta (see below)
//   /proc/meminfo                   MemTotal and MemAvailable
//   /sys/class/hwmon/*/temp*_input  one file per sensor, with the chip name
//                                   read once from ../name and the sensor's
//                                   own ../temp*_label
//
// Load is the one fact that cannot be read. A single sample of /proc/stat is
// a count since boot, not a rate: a percentage exists only as the difference
// between two samples, so this keeps the previous counters and measures over
// `intervalMs`. The first tick only primes the counters, which is why
// `cpuReady` is false until the second one - a widget showing 0% for two
// seconds would be reporting a reading it does not have yet.
//
// The temperature set is enumerated once, by one short-lived shell, because
// /sys/class/hwmon is a directory of symlinks and a directory cannot be read
// with a file view. After that every reading is a file read on a path already
// known - no process, no glob. A sensor that disappears takes itself out of
// the list and asks for one re-enumeration, so a dock unplugged or a module
// reloaded is picked up without polling the directory.
QtObject {
  id: perf

  // Bound to a view's own `visible`: a tile that is not being drawn runs no
  // timer and reads nothing. Same contract as StorageData's `active`.
  property bool active: true

  // The measurement window. Not a setting: /proc/stat accounts in 10 ms
  // ticks, so a shorter window is mostly quantisation noise, and a longer one
  // stops being "now". A view never sets this.
  property int intervalMs: 2000

  // How many sensors are read at all. Three is what a tile can show, and a
  // read of a temperature sensor is not free on every chip - an SMBus or EC
  // sensor is a bus transaction, not a memory read - so this reads the three
  // it may display and not the seventeen it may not.
  property int maxSensors: 3

  // ── Processor ────────────────────────────────────────────────────────
  // 0..100 across every core, over the interval above. One decimal: the
  // second is noise, and the tenth is what a meter can actually show.
  property bool cpuReady: false
  property real cpuPercent: 0

  // [busy, idle] totals of the previous sample, or null before the first one.
  property var _cpuPrev: null

  // ── Memory ───────────────────────────────────────────────────────────
  property bool memReady: false
  property real memTotalKb: 0
  property real memUsedKb: 0

  // Used is total minus MemAvailable, not minus MemFree: the kernel's own
  // estimate of what a new process could get counts reclaimable page cache
  // as available, and MemFree alone reports a healthy machine as 95% full.
  readonly property real memPercent: perf.memTotalKb > 0
    ? Math.max(0, Math.min(100, perf.memUsedKb / perf.memTotalKb * 100)) : 0

  // "37G" / "60.5G". Composed here, like BatteryData's stateLabel, so the two
  // drawings cannot disagree about the wording.
  readonly property string memUsedLabel: perf._human(perf.memUsedKb)
  readonly property string memTotalLabel: perf._human(perf.memTotalKb)
  readonly property string memText: perf.memReady
    ? perf.memUsedLabel + " / " + perf.memTotalLabel : ""

  // ── Temperatures ─────────────────────────────────────────────────────
  // Ranked, best-first, at most `maxSensors`: [{ chip, label, name, celsius,
  // text, path }]. Empty until the enumeration returns, and empty for good on
  // a machine with no hwmon sensors - the views show that as "--", never as a
  // plausible zero.
  property bool tempsEnumerated: false
  readonly property var temps: {
    var out = []
    for (var i = 0; i < perf._slots.length; i++) {
      var c = perf._values[i]
      if (c === null || c === undefined || !isFinite(c)) continue
      var s = perf._slots[i]
      out.push({
        chip: s.chip, label: s.label, name: s.name, path: s.path,
        celsius: c,
        // Whole degrees: the sensors report millidegrees, and a tenth of a
        // degree is below both the sensor's accuracy and anything a glance
        // needs. The degree sign is part of the reading, in one place.
        text: Math.round(c) + "\u00B0"
      })
    }
    return out
  }
  readonly property bool tempsReady: perf.temps.length > 0

  // The chosen sensors, and their readings, index for index. `_values` holds
  // null for a sensor that has not answered yet.
  property var _slots: []
  property var _values: []

  // ── Readings ─────────────────────────────────────────────────────────
  // One /proc/stat sample: user, nice, system, idle, iowait, irq, softirq,
  // steal. The guest counters that follow them are already inside user/nice,
  // so including them would double-count.
  function _applyStat(text) {
    var lines = String(text || "").split("\n")
    var line = ""
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].indexOf("cpu ") === 0) { line = lines[i]; break }
    }
    if (line === "") return
    var f = line.trim().split(/\s+/)
    if (f.length < 9) return
    var total = 0
    for (var j = 1; j <= 8; j++) total += Number(f[j])
    // Idle is idle + iowait: a disc waiting on itself is not load. This is
    // the same definition `top` and the kernel's own docs use.
    var idle = Number(f[4]) + Number(f[5])
    if (!isFinite(total) || !isFinite(idle)) return

    var prev = perf._cpuPrev
    if (prev !== null) {
      var dt = total - prev.total
      var di = idle - prev.idle
      // dt <= 0 means the counters did not move (a suspended machine, or a
      // wrapped read): keep the last reading rather than dividing by zero and
      // reporting a confident NaN.
      if (dt > 0) {
        var busy = Math.max(0, Math.min(1, (dt - Math.max(0, di)) / dt))
        perf.cpuPercent = Math.round(busy * 1000) / 10
      }
      perf.cpuReady = true
    }
    perf._cpuPrev = { total: total, idle: idle }
  }

  function _applyMeminfo(text) {
    var lines = String(text || "").split("\n")
    var total = 0
    var avail = 0
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].indexOf("MemTotal:") === 0) total = perf._kb(lines[i])
      else if (lines[i].indexOf("MemAvailable:") === 0) avail = perf._kb(lines[i])
    }
    if (!isFinite(total) || total <= 0) return
    if (!isFinite(avail) || avail < 0) avail = 0
    perf.memTotalKb = total
    perf.memUsedKb = Math.max(0, total - avail)
    perf.memReady = true
  }

  // "MemAvailable:   24632760 kB" -> 24632760
  function _kb(line) {
    var f = String(line).trim().split(/\s+/)
    return f.length >= 2 ? Number(f[1]) : NaN
  }

  // One sensor's file, in millidegrees. A read that lands after the list was
  // rebuilt carries an index the new list may not have - the value belongs to
  // a sensor that is no longer read, so it is dropped rather than written into
  // whatever slot now has that number.
  function _applyTemp(index, raw) {
    if (index < 0 || index >= perf._slots.length) return
    var v = parseFloat(String(raw || "").trim())
    var vals = perf._values.slice()
    vals[index] = isFinite(v) ? v / 1000 : null
    perf._values = vals
  }

  function _tempFailed(index) {
    if (index < 0 || index >= perf._slots.length) return
    var had = perf._values[index] !== null && perf._values[index] !== undefined
    var vals = perf._values.slice()
    vals[index] = null
    perf._values = vals
    // A sensor that stops reading is usually a chip that left the machine. The
    // re-enumeration is asked for on the transition only - a path that is gone
    // stays gone, so the next poll of that slot is silent and this cannot
    // become a process per tick.
    if (had) perf._enumerate()
  }

  // ── Sensor selection ─────────────────────────────────────────────────
  // The chips a glance cares about, in order. A machine with none of them
  // still gets its first `maxSensors` sensors: the rank is a preference, not
  // a filter.
  readonly property var _cpuChips: ["k10temp", "coretemp", "zenpower", "cpu_thermal",
                                    "soc_thermal", "acpitz"]
  readonly property var _gpuChips: ["amdgpu", "radeon", "nouveau", "i915", "xe"]
  readonly property var _storeChips: ["nvme", "drivetemp", "spd5118"]

  function _chipRank(chip) {
    var n = String(chip).toLowerCase()
    if (perf._cpuChips.indexOf(n) >= 0) return 0
    if (perf._gpuChips.indexOf(n) >= 0) return 1
    if (perf._storeChips.indexOf(n) >= 0) return 2
    return 3
  }

  // The one sensor per chip that means the chip: k10temp's Tctl over its
  // per-CCD probes, amdgpu's edge over its junction and memory, an NVMe
  // drive's Composite over its individual sensors. An unlabelled sensor (a
  // good few drivers ship none) ranks last and the lowest-numbered one wins,
  // which is the driver's own primary.
  readonly property var _primaryLabels: ["tctl", "tdie", "edge", "composite",
                                         "junction", "package", "cpu"]

  function _labelRank(label) {
    var i = perf._primaryLabels.indexOf(String(label).toLowerCase())
    return i < 0 ? perf._primaryLabels.length : i
  }

  // One sensor per chip, chips first by rank and then in the order the kernel
  // enumerated them - a stable order, so a row does not swap places between
  // two readings.
  function _pick(list) {
    var chips = []
    for (var i = 0; i < list.length; i++) {
      var s = list[i]
      var found = null
      for (var j = 0; j < chips.length; j++) {
        if (chips[j].chip === s.chip) { found = chips[j]; break }
      }
      if (found === null) {
        chips.push({ chip: s.chip, best: s, order: i })
      } else if (perf._labelRank(s.label) < perf._labelRank(found.best.label)) {
        found.best = s
      }
    }
    chips.sort(function (a, b) {
      var ra = perf._chipRank(a.chip)
      var rb = perf._chipRank(b.chip)
      return ra !== rb ? ra - rb : a.order - b.order
    })
    var out = []
    for (var k = 0; k < chips.length && k < perf.maxSensors; k++) {
      var b = chips[k].best
      out.push({
        chip: b.chip,
        label: b.label,
        // What the row is called. A driver that ships no label file still
        // names its chip.
        name: b.label !== "" ? b.label : b.chip,
        path: b.path
      })
    }
    return out
  }

  // "chip \t label \t path", one line per sensor, in enumeration order.
  function _applyEnumeration(text) {
    var lines = String(text || "").split("\n")
    var all = []
    for (var i = 0; i < lines.length; i++) {
      var f = lines[i].split("\t")
      if (f.length < 3 || String(f[2]).trim() === "") continue
      all.push({
        chip: String(f[0]).trim(),
        label: String(f[1]).trim(),
        path: String(f[2]).trim()
      })
    }
    var slots = perf._pick(all)
    var vals = []
    for (var k = 0; k < slots.length; k++) vals.push(null)
    perf._values = vals
    perf._slots = slots
    perf.tempsEnumerated = true
  }

  function _enumerate() {
    if (!perf._enumProc.running) perf._enumProc.running = true
  }

  function _human(kb) {
    var units = ["K", "M", "G", "T", "P"]
    var v = Number(kb)
    if (!isFinite(v) || v < 0) return "-"
    var i = 0
    while (v >= 1024 && i < units.length - 1) { v /= 1024; i++ }
    return (v >= 100 ? Math.round(v) : Math.round(v * 10) / 10) + units[i]
  }

  // ── The one timer ────────────────────────────────────────────────────
  // Re-reads the three sources. `triggeredOnStart` primes the CPU counters as
  // soon as the tile exists, so the first real percentage lands one interval
  // later rather than one interval after that.
  //
  // The sensor readers are not reloaded here: they are told to by `_revision`,
  // which each of them watches. Walking a created-object list by index would
  // work, but it is a QObject* as far as anyone can tell, and a delegate that
  // reloads when the reading it owns is due keeps the loop out of this file.
  property int _revision: 0

  function _read() {
    perf._statFile.reload()
    perf._memFile.reload()
    perf._revision++
  }

  property FileView _statFile: FileView {
    id: statFile
    path: "/proc/stat"
    printErrors: false
    onLoaded: perf._applyStat(text())
  }

  property FileView _memFile: FileView {
    id: memFile
    path: "/proc/meminfo"
    printErrors: false
    onLoaded: perf._applyMeminfo(text())
  }

  // One file view per chosen sensor. The model is the slot list, so a
  // re-enumeration rebuilds exactly the views the new list needs - no fixed
  // pool of readers pointed at paths that may not exist. Each reloads when the
  // tick above raises `_revision`, and reads its value out of its own file.
  property Instantiator _readers: Instantiator {
    id: readers
    model: perf._slots
    delegate: FileView {
      required property int index
      required property var modelData
      path: modelData.path
      printErrors: false
      property int revision: perf._revision
      onRevisionChanged: reload()
      onLoaded: perf._applyTemp(index, text())
      onLoadFailed: perf._tempFailed(index)
    }
  }

  // The enumeration. `sh` and not `bash`: a glob and a loop are POSIX, and the
  // lines of printf it prints are the whole interface. A chip with no readable
  // `name` is skipped, and a driver that ships no `_label` line reports an
  // empty label rather than a wrong one.
  //
  // `${b}_label`, never `$b_label`: the latter is the VARIABLE `b_label`, which
  // is unset - so `cat` got no argument, read the widget's own stdin, and the
  // enumeration never returned. Hence the `[ -e ]` guard as well: no branch
  // here can leave `cat` without a file.
  property Process _enumProc: Process {
    id: enumProc
    command: ["sh", "-c",
      "for d in /sys/class/hwmon/hwmon*; do n=$(cat $d/name 2>/dev/null); [ -n \"$n\" ] || continue; " +
      "for f in $d/temp*_input; do [ -e \"$f\" ] || continue; b=${f%_input}; l=\"\"; " +
      "if [ -e \"${b}_label\" ]; then l=$(cat \"${b}_label\" 2>/dev/null); fi; " +
      "printf '%s\\t%s\\t%s\\n' \"$n\" \"$l\" \"$f\"; done; done"]
    stdout: StdioCollector {
      onStreamFinished: perf._applyEnumeration(String(this.text || ""))
    }
  }

  property Timer _tick: Timer {
    interval: perf.intervalMs
    repeat: true
    running: perf.active
    triggeredOnStart: true
    onTriggered: perf._read()
  }

  Component.onCompleted: perf._enumerate()
}
