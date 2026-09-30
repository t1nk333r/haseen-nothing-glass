import QtQuick
import Quickshell
import Quickshell.Io

// The weather location Omarchy itself uses, so the desktop weather tile and
// the bar's weather widget cannot disagree about where you are.
//
// Omarchy's weather widget (`/usr/share/omarchy/shell/plugins/panels/weather/`)
// is a bar-widget plugin, not a service: it declares `kinds: ["bar-widget"]`
// only, so `shell.serviceFor("omarchy.weather")` returns null, its IpcHandler
// exposes nothing but void open/close/toggle/refresh, and the parsed report
// lives in private properties of a per-monitor Panel.qml instance. There is
// no live weather data to borrow.
//
// What IS shared is this file: `~/.local/state/omarchy/settings/weather.json`,
// written by `/usr/bin/omarchy-weather-location` and watched live by that
// panel (Panel.qml:95-102). Reading the same file gives both widgets the same
// city with no coupling to the other plugin's internals, and a change made
// with `omarchy-weather-location <city>` moves both at once.
//
// Absent file = Omarchy is on wttr.in IP auto-detection, which Open-Meteo
// cannot reproduce; `valid` stays false and the caller keeps its own setting.
QtObject {
  id: loc

  readonly property string path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"

  property string name: ""
  property double latitude: 0
  property double longitude: 0

  // Coordinates are what makes this usable without a geocode round-trip; a
  // name-only file still counts, the consumer just geocodes it.
  readonly property bool hasCoordinates: latitude !== 0 || longitude !== 0
  readonly property bool valid: name !== "" || hasCoordinates

  function _apply(raw) {
    var name = ""
    var lat = 0
    var lon = 0
    try {
      var data = JSON.parse(String(raw || ""))
      if (data && typeof data === "object") {
        if (typeof data.name === "string") name = data.name.replace(/^\s+|\s+$/g, "")
        var la = parseFloat(data.latitude)
        var lo = parseFloat(data.longitude)
        if (!isNaN(la) && !isNaN(lo)) { lat = la; lon = lo }
      }
    } catch (e) {
      // Same posture as Omarchy's own parser: a malformed file is "unset",
      // not an error to show the user.
    }
    loc.name = name
    loc.latitude = lat
    loc.longitude = lon
  }

  property FileView _file: FileView {
    path: loc.path
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: loc._apply(text())
    onLoadFailed: loc._apply("")
  }

  // The first read races shell startup - Omarchy's own panel carries the
  // same one-shot correction (Panel.qml:104-110).
  property Timer _firstRead: Timer {
    interval: 1500
    running: true
    onTriggered: loc._file.reload()
  }

  // `watchChanges` on a path that does not exist yet never fires: a
  // watcher needs an inode. Until the user runs `omarchy-weather-location
  // --set`, that is the normal state, so poll slowly for the file's
  // appearance and stop the moment it is there (verified in the lab: the
  // tile stayed on its own city after the file was created without this).
  property Timer _awaitFile: Timer {
    interval: 15000
    repeat: true
    running: !loc.valid
    onTriggered: loc._file.reload()
  }
}
