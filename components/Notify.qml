import QtQuick
import Quickshell.Io

// Outbound desktop notifications for the ported widgets.
//
// Plasma's `org.kde.notification` does not exist here, and Quickshell's
// `Quickshell.Services.Notifications` is the wrong direction entirely — it is
// a *server* for receiving notifications, not a client for sending them. So
// this shells out to `notify-send`, which hands the notification to whatever
// daemon is running (mako on Omarchy) and therefore inherits the user's own
// notification styling.
//
// This is the port's ONLY outbound-notification path. Anything else that needs
// to notify should reuse it rather than spawning `notify-send` inline, so the
// argv discipline below stays in exactly one place.
QtObject {
  id: notify

  // Set false to make send() a no-op (nothing needs it yet; it exists so a
  // widget can offer a "silent" mode without every call site learning how
  // notifications are delivered).
  property bool enabled: true

  // Title and body go in as SEPARATE argv entries — never interpolated into a
  // shell string, and never through a shell at all. Today every caller passes
  // fixed literals, but the moment a widget notifies with user-supplied text
  // (a timer label, a track title) a shell-string wrapper would be a command
  // injection. Process.command takes a list<string> and execs directly, so
  // there is no shell to inject into. Plan 009 gates on this with a literal
  // grep for shell invocations in this file — keep it satisfiable.
  function send(title, body, urgency) {
    if (!notify.enabled) return
    var u = (urgency === undefined || urgency === null) ? "normal" : String(urgency)
    if (u !== "low" && u !== "normal" && u !== "critical") u = "normal"
    // `--` ends the options: a title or body starting with `-` (a timer
    // label, a track title) is then text, never a notify-send flag.
    var argv = ["notify-send", "-u", u, "-a", "Liquid Glass", "--",
                String(title === undefined ? "" : title),
                String(body === undefined ? "" : body)]
    var q = notify._queue.slice()
    q.push(argv)
    notify._queue = q
    notify._drain()
  }

  // One Process, fed from a queue. Quickshell ignores `running = true` on a
  // Process that is already running, so a second send() inside the few
  // milliseconds notify-send takes to exit used to be dropped on the floor.
  // Every accepted send now runs, in order.
  property var _queue: []

  function _drain() {
    if (notify._proc.running || notify._queue.length === 0) return
    var q = notify._queue.slice()
    var next = q.shift()
    notify._queue = q
    notify._proc.command = next
    notify._proc.running = true
  }

  property Process _proc: Process {
    running: false
    onExited: function (exitCode) {
      if (exitCode !== 0)
        console.warn("Notify: notify-send exited " + exitCode
                     + " — is a notification daemon running? (busctl --user list | grep Notifications)")
      notify._drain()
    }
  }
}
