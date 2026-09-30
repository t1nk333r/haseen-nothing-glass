import QtQuick
import Quickshell.Services.UPower

// Battery, as numbers. No presentation: a Nothing view and (later) a Liquid
// Glass view read the same object, the same way both weather views read
// WeatherDataQs.
//
// UPower is a CLIENT of the system daemon - it claims no bus name and owns
// nothing, so several readers in one process are fine. Everything here is
// push-based; there is no timer in this file.
QtObject {
  id: bat

  readonly property var _dev: UPower.displayDevice

  // A desk machine has a display device that is simply not a battery. Say so
  // once, here, rather than letting every view invent its own empty state.
  readonly property bool present: !!(_dev && _dev.isPresent && _dev.isLaptopBattery)

  readonly property real percent: present ? Math.max(0, Math.min(100, _dev.percentage * 100)) : 0
  readonly property int state: present ? _dev.state : UPowerDeviceState.Unknown

  readonly property bool charging: state === UPowerDeviceState.Charging
                                   || state === UPowerDeviceState.PendingCharge
  readonly property bool full: state === UPowerDeviceState.FullyCharged
  readonly property bool discharging: state === UPowerDeviceState.Discharging

  // Watts. Positive whichever way the energy is going - the direction is
  // `charging`, and a view that prints a signed number can flip it itself.
  readonly property real ratePower: present ? Math.abs(_dev.changeRate) : 0

  // Seconds, 0 when UPower has not made up its mind yet (it reports 0 for
  // "unknown", and so do we - a view must not print "0 min left").
  readonly property int secondsLeft: {
    if (!present) return 0
    var s = bat.charging ? _dev.timeToFull : _dev.timeToEmpty
    return (isFinite(s) && s > 0) ? Math.round(s) : 0
  }

  readonly property string stateLabel: {
    if (!present) return "No battery"
    if (bat.full) return "Full"
    if (bat.charging) return "Charging"
    if (state === UPowerDeviceState.PendingDischarge) return "Pending"
    return UPower.onBattery ? "Discharging" : "On AC"
  }

  // "3h 40m", "48m", or "" when the estimate is not available. One place, so
  // the two styles cannot disagree about the wording.
  readonly property string timeLabel: {
    var s = bat.secondsLeft
    if (s <= 0) return ""
    var h = Math.floor(s / 3600)
    var m = Math.round((s % 3600) / 60)
    if (m === 60) { return (h + 1) + "h 0m" }
    return h > 0 ? (h + "h " + m + "m") : (m + "m")
  }

  readonly property real health: (present && _dev.healthSupported)
    ? Math.max(0, Math.min(100, _dev.healthPercentage)) : 0
  readonly property bool healthKnown: present && !!_dev.healthSupported
}
