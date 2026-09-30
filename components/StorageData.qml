import QtQuick
import Quickshell
import Quickshell.Io

// Filesystem use. There is no service for this - `df` is the interface - so
// this is the one data component in the set that polls, and it is written to
// poll as little as it can get away with: one short-lived process every
// `intervalMs` (default 60 s), and none at all while nothing is watching.
//
// `active` is what a view binds to its own `visible`: false only while the
// monitor is switched off (DPMS) - the one "not being drawn" state the shell
// can see, since a widget sits on every workspace by design - and no process
// runs at all while it is false. Unknown reads as true, so the failure mode is
// a poll, never a blank tile. The signal is GlassSurface.qml's `screenDrawn`.
QtObject {
  id: store

  property bool active: true
  property int intervalMs: 60000

  // Mount points to report, in order. Empty means "every real filesystem",
  // which is what the widget shows until the user names one.
  property var mounts: []

  property bool loaded: false
  property string errorMessage: ""

  // Every filesystem `df` reported, biggest first. The parse writes this and
  // nothing else, so changing `mounts` re-filters instantly instead of
  // waiting up to a minute for the next `df` - a settings field that only
  // takes effect on the next poll reads as broken.
  property var allEntries: []

  // [{ mount, size, used, avail, usedPercent, sizeLabel, usedLabel, availLabel }]
  // The chosen subset, in the order the mounts were named.
  readonly property var entries: {
    if (store.mounts.length === 0) return store.allEntries
    var out = []
    for (var i = 0; i < store.mounts.length; i++) {
      for (var j = 0; j < store.allEntries.length; j++) {
        if (store.allEntries[j].mount === store.mounts[i]) { out.push(store.allEntries[j]); break }
      }
    }
    return out
  }

  readonly property var primary: store.entries.length > 0 ? store.entries[0] : null

  function refresh() { if (store.active) proc.running = true }

  function _human(kb) {
    var units = ["K", "M", "G", "T", "P"]
    var v = Number(kb)
    if (!isFinite(v) || v < 0) return "-"
    var i = 0
    while (v >= 1024 && i < units.length - 1) { v /= 1024; i++ }
    return (v >= 100 ? Math.round(v) : Math.round(v * 10) / 10) + units[i]
  }

  property Process _proc: Process {
    id: proc
    // -P forces the one-line-per-filesystem POSIX format (a long device name
    // wraps otherwise and every field shifts); -k fixes the unit at 1 KiB so
    // the parsing does not depend on the host's block size.
    command: ["df", "-Pk", "-x", "tmpfs", "-x", "devtmpfs", "-x", "efivarfs", "-x", "overlay"]
    stdout: StdioCollector {
      onStreamFinished: {
        var rows = []
        var lines = String(this.text || "").split("\n")
        for (var i = 1; i < lines.length; i++) {
          var f = lines[i].trim().split(/\s+/)
          if (f.length < 6) continue
          var mount = f[5]
          // No filtering here - `entries` does it, see its comment.
          var size = Number(f[1]), used = Number(f[2]), avail = Number(f[3])
          if (!isFinite(size) || size <= 0) continue
          rows.push({
            mount: mount,
            size: size, used: used, avail: avail,
            usedPercent: Math.max(0, Math.min(100, Math.round(used / size * 100))),
            sizeLabel: store._human(size),
            usedLabel: store._human(used),
            availLabel: store._human(avail)
          })
        }
        // Biggest filesystem first, which is the one people mean by "disk";
        // a named subset is reordered by `entries` to match what was asked
        // for.
        rows.sort(function (a, b) { return b.size - a.size })
        store.allEntries = rows
        store.loaded = true
        store.errorMessage = rows.length === 0 ? "No filesystems" : ""
      }
    }
  }

  property Timer _tick: Timer {
    interval: store.intervalMs
    running: store.active
    repeat: true
    triggeredOnStart: true
    onTriggered: store.refresh()
  }
}
