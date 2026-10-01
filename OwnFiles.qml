import QtQuick
import Quickshell.Io

// Two chores on the files this plugin owns - the widget store, its .bak and
// the options file - each one a short child process, run one at a time:
//
//   restrict(path)    `chmod 600`. The store holds every widget's settings
//                     (folders, locations, player names) and a file created
//                     through FileView gets whatever the umask allows - 0644,
//                     readable by every account on the machine. FileView has
//                     no mode knob, but an atomic save (QSaveFile) keeps the
//                     mode of the file it replaces, so the chmod only has to
//                     land once per file: a path is remembered as done once a
//                     chmod has succeeded with no second request queued
//                     behind it (a write that landed while the chmod was
//                     running may have replaced the inode it changed).
//   retire(from, to)  `mv -n` of a retired file to its `.migrated` name, and
//                     the CHECK that it actually went: `mv -n` exits 0 when
//                     the target already exists and the source stays where it
//                     was. A source left in place is reported; nothing may
//                     depend on the rename having happened (Store.qml keeps
//                     its own durable "absorbed" record for exactly that
//                     reason).
//
// Both are bounded the way every other child of this plugin is: a run that
// has not exited after `_boundMs` is sent SIGTERM, then SIGKILL after a grace
// (components/TailscaleData.qml's `_supervise`), and one that cannot be
// exec'd at all - Quickshell 0.3.1 drops `running` without an `exited` - is
// settled from `onRunningChanged`, so the queue can never stall.
Item {
  id: chores

  readonly property int _boundMs: 5000
  readonly property int _killGraceMs: 2000

  // Pending jobs, oldest first: { kind, path, argv, to }.
  property var _queue: []
  // The job `proc` is running, or null.
  property var _job: null
  // path -> true once `chmod 600` has landed for it.
  property var _restricted: ({})

  function restrict(path) {
    var p = String(path || "")
    if (p === "" || chores._restricted[p] === true) return
    chores._enqueue({ kind: "restrict", path: p, argv: ["chmod", "600", "--", p] })
  }

  function retire(from, to) {
    var f = String(from || "")
    var t = String(to || "")
    if (f === "" || t === "") return
    // Paths travel as positional parameters, never spliced into the script.
    chores._enqueue({ kind: "retire", path: f, to: t,
                      argv: ["sh", "-c", 'mv -n -- "$1" "$2" && test ! -e "$1"', "sh", f, t] })
  }

  function _queued(kind, path) {
    for (var i = 0; i < chores._queue.length; i++)
      if (chores._queue[i].kind === kind && chores._queue[i].path === path) return true
    return false
  }

  function _enqueue(job) {
    if (chores._queued(job.kind, job.path)) return
    chores._queue = chores._queue.concat([job])
    chores._next()
  }

  function _next() {
    if (chores._job !== null || proc.running || chores._queue.length === 0) return
    var job = chores._queue[0]
    chores._queue = chores._queue.slice(1)
    chores._job = job
    proc.started = false
    proc.abandoned = false
    proc.launchedAt = Date.now()
    proc.command = job.argv
    proc.running = true
  }

  function _finish(ok) {
    var job = chores._job
    if (job === null) return
    chores._job = null
    if (job.kind === "restrict") {
      if (ok && !chores._queued("restrict", job.path)) {
        var done = {}
        for (var k in chores._restricted) done[k] = chores._restricted[k]
        done[job.path] = true
        chores._restricted = done
      } else if (!ok) {
        console.warn("nothing-glass: could not make " + job.path + " private (chmod 600)")
      }
    } else if (!ok) {
      console.warn("nothing-glass: " + job.path + " was not renamed to " + job.to +
                   " (the target exists, or the move failed); it stays where it is")
    }
    // Not from inside the Process's own signal handler.
    Qt.callLater(chores._next)
  }

  Process {
    id: proc
    property bool started: false
    property bool abandoned: false
    property double launchedAt: 0
    onStarted: proc.started = true
    onExited: function (code) {
      if (proc.abandoned) { Qt.callLater(chores._next); return }
      chores._finish(code === 0)
    }
    onRunningChanged: {
      if (proc.running || proc.started || proc.abandoned) return
      // The exec itself failed: no `exited` is coming.
      chores._finish(false)
    }
  }

  Timer {
    interval: 500
    repeat: true
    running: proc.running
    onTriggered: {
      var age = Date.now() - proc.launchedAt
      if (age < chores._boundMs) return
      if (!proc.abandoned) {
        proc.abandoned = true
        chores._finish(false)
        proc.running = false        // SIGTERM
        return
      }
      if (age >= chores._boundMs + chores._killGraceMs) chores._kill()
    }
  }

  // Guarded: a pid of 0 handed to kill(2) is the shell's own process group.
  function _kill() {
    var pid = proc.processId
    if (pid === null || pid === undefined || Number(pid) <= 0) return
    proc.signal(9)
  }

  Component.onDestruction: {
    if (!proc.running) return
    proc.abandoned = true
    chores._kill()
  }
}
