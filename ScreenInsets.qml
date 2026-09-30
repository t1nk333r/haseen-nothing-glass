import QtQuick
import Quickshell
import Quickshell.Hyprland

// How much of a screen the bar (and any other exclusive-zone surface) has
// taken, so widgets can be placed on the part of the desktop the user can
// actually see.
//
// The widget surface is deliberately `exclusionMode: Ignore` and anchored to
// all four edges (GlassSurface.qml), which is what lets a widget sit anywhere
// - but it also means y = 0 is UNDER the bar, and "reset position" parked
// tiles there. Hyprland already computes the answer per monitor:
// `HyprlandMonitor.lastIpcObject.reserved` is the same `[left, top, right,
// bottom]` array `hyprctl monitors -j` prints.
//
// `lastIpcObject` is EMPTY until something asks Hyprland for the monitor
// list - measured: a fresh `qs` probe reported `reserved: undefined` on the
// first tick and the real value one `refreshMonitors()` later - so this
// object kicks that off itself rather than trusting whatever else in the
// shell might have done it first.
//
// Everything degrades to 0 for an unknown monitor: an unplugged screen, or a
// compositor that is not Hyprland.
QtObject {
  id: insets

  // Bind either one. `screen` (a ShellScreen) is exact; `screenName` is for
  // callers that only have the store row's screen string - the bar's control
  // panel resets widgets on screens it is not itself on.
  property var screen: null
  property string screenName: ""

  // Resolved imperatively, NOT in a binding: `Hyprland.monitorFor()` can
  // create the monitor object it returns, which notifies the monitor list,
  // which re-evaluates the binding that called it - an actual binding loop,
  // logged as one on the first run of this file.
  property var _monitor: null

  function _resolve() {
    if (insets.screen) { insets._monitor = Hyprland.monitorFor(insets.screen); return }
    var wanted = String(insets.screenName || "")
    var list = Hyprland.monitors ? Hyprland.monitors.values : []
    for (var i = 0; i < list.length; i++) {
      if (list[i] && String(list[i].name) === wanted) { insets._monitor = list[i]; return }
    }
    insets._monitor = null
  }

  function refresh() {
    Hyprland.refreshMonitors()
    resolveTimer.restart()
  }

  property Timer _resolveTimer: Timer {
    id: resolveTimer
    interval: 150
    onTriggered: insets._resolve()
  }

  function _reservedOf(monitor) {
    var zero = { left: 0, top: 0, right: 0, bottom: 0 }
    if (!monitor) return zero
    var obj = monitor.lastIpcObject
    var r = obj ? obj.reserved : null
    if (!r || r.length < 4) return zero
    return { left: Number(r[0]) || 0, top: Number(r[1]) || 0,
             right: Number(r[2]) || 0, bottom: Number(r[3]) || 0 }
  }

  // For a screen this object is not bound to (the bar's control panel resets
  // widgets on other screens). One-shot, no caching.
  function forScreen(name) {
    var wanted = String(name || "")
    var list = Hyprland.monitors ? Hyprland.monitors.values : []
    for (var i = 0; i < list.length; i++) {
      if (list[i] && String(list[i].name) === wanted) return insets._reservedOf(list[i])
    }
    return insets._reservedOf(null)
  }

  // Depends on `_monitor.lastIpcObject`, which updates on its own when the
  // refresh reply lands.
  readonly property var current: insets._reservedOf(insets._monitor)

  readonly property int left: insets.current.left
  readonly property int top: insets.current.top
  readonly property int right: insets.current.right
  readonly property int bottom: insets.current.bottom

  onScreenChanged: insets._resolve()
  onScreenNameChanged: insets._resolve()

  // One fetch at startup, then a couple of retries: `refreshMonitors()` is
  // asynchronous and the first shell frame routinely lands before the reply.
  // Stops as soon as an edge is non-zero, and gives up after the third try so
  // a genuinely edge-to-edge desktop does not poll forever.
  property Timer _prime: Timer {
    interval: 1200
    repeat: true
    running: true
    property int tries: 0
    onTriggered: {
      insets.refresh()
      tries++
      if (tries >= 3 || insets.top !== 0 || insets.left !== 0
          || insets.right !== 0 || insets.bottom !== 0) running = false
    }
  }

  Component.onCompleted: {
    insets._resolve()
    insets.refresh()
  }
}
