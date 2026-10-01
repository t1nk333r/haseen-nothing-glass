import QtQuick
import Quickshell.Io

// Two chores on the files this plugin owns - the widget store, its .bak and
// the options file - each one a short child process, run one at a time:
//
//   restrict(path)    `chmod 600` unless the file is 600 already. The store
//                     holds every widget's settings (folders, locations,
//                     player names) and a file created through FileView gets
//                     whatever the umask allows - 0644, readable by every
//                     account on the machine. FileView has no mode knob. An
//                     atomic save (QSaveFile) keeps the mode of the file it
//                     replaces, but a file deleted while the shell runs comes
//                     back with the umask's mode, so the check runs after
//                     every save and every load rather than once per path.
//                     Saves are coalesced and a request already queued for the
//                     path absorbs a second one, so this is at most one short
//                     child per write or load. The moment between a file's
//                     first creation and its chmod stays open: closing it
//                     would need control of the shell's umask.
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

  function restrict(path) {
    var p = String(path || "")
    if (p === "") return
    // Only when the mode is not 600 already. A chmod changes the file's ctime
    // even when the mode stays the same, and the store and options views
    // watch their files and reload on that and restrict again on load, so an
    // unconditional chmod would chase its own event forever. The path is a
    // positional parameter, never part of the script.
    chores._enqueue({ kind: "restrict", path: p,
                      argv: ["sh", "-c", 'test "$(stat -c %a -- "$1")" = 600 || chmod 600 -- "$1"', "sh", p] })
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
      if (!ok) console.warn("nothing-glass: could not make " + job.path + " private (chmod 600)")
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
