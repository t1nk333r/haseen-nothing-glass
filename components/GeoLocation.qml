import QtQuick
import Quickshell
import Quickshell.Io
import "JsonRead.js" as JsonRead

// Where this machine is, for widgets that need coordinates rather than a city
// name (the sunrise tile computes sun times from lat/lon).
//
// Precedence, best first:
//   1. GeoClue2, via `geo/geoclue-fix.sh` - ONLY when `useGeoclue` is on,
//      which it is not by default; re-queried hourly at most, since a sunrise
//      time does not move fast enough to justify more.
//   2. The user's own prayer coordinates: the `t1nk33r.omaprayers` entry in
//      shell.json. Exact, hand-set, already there.
//   3. Omarchy's shared weather location
//      (`~/.local/state/omarchy/settings/weather.json`, written by
//      `omarchy-weather-location`) when it carries coordinates.
//   4. `fallbackLatitude` / `fallbackLongitude` from the caller (the plugin's
//      own latitude/longitude settings).
//
// `source` names the winner so a tile can say where its numbers came from,
// and nothing ever renders empty.
//
// GeoClue is opt-in because asking it is not free of consequence: the helper
// asks under Firefox's desktop id (Omarchy runs no GeoClue agent to vouch for
// any other), and a network provider in /etc/geoclue/geoclue.conf is sent
// nearby Wi-Fi BSSIDs. With no provider configured - Omarchy's default - it
// accepts the D-Bus connection and drops it ("Remote peer disconnected"),
// and this object reports why and falls through to the local coordinates.
QtObject {
  id: geo

  property double fallbackLatitude: 0
  property double fallbackLongitude: 0
  // Opt-in. GeoClue is asked under another app's identity (geo/geoclue-fix.sh)
  // and may reach a network location provider, so nothing asks it unless the
  // user turned `useGeoclue` on. Turning it off drops any fix already held, so
  // the tile falls back at once rather than after a restart.
  property bool useGeoclue: false
  onUseGeoclueChanged: {
    if (geo.useGeoclue) { geo.refresh(); return }
    fixProc.running = false
    geo._geoclue.ok = false
    geo._geoclue.error = ""
  }

  readonly property double latitude: _geoclue.ok ? _geoclue.latitude
    : (_prayer.ok ? _prayer.latitude
    : (_weather.ok ? _weather.latitude : geo.fallbackLatitude))
  readonly property double longitude: _geoclue.ok ? _geoclue.longitude
    : (_prayer.ok ? _prayer.longitude
    : (_weather.ok ? _weather.longitude : geo.fallbackLongitude))
  readonly property string label: _prayer.label !== "" ? _prayer.label : _weather.label

  readonly property string source: _geoclue.ok ? "geoclue"
    : (_prayer.ok ? "prayer settings"
    : (_weather.ok ? "omarchy weather" : "manual"))
  // True when nothing resolved and these coordinates are just the caller's
  // own fallback coming back out - a consumer that wants to know whether the
  // position was actually discovered has to be able to tell.
  readonly property bool usesFallback: !_geoclue.ok && !_prayer.ok && !_weather.ok
  readonly property real accuracyM: _geoclue.ok ? _geoclue.accuracy : 0
  readonly property string geoclueError: _geoclue.error
  readonly property bool valid: latitude !== 0 || longitude !== 0

  // --- geoclue ------------------------------------------------------------

  property QtObject _geoclue: QtObject {
    property bool ok: false
    property double latitude: 0
    property double longitude: 0
    property real accuracy: 0
    property string error: ""
  }

  function refresh() {
    if (!geo.useGeoclue) return
    fixProc.running = false
    fixProc.running = true
  }

  property Process _fixProc: Process {
    id: fixProc
    running: false
    command: ["bash", Qt.resolvedUrl("geo/geoclue-fix.sh").toString().replace("file://", "")]
    stdout: StdioCollector {
      onStreamFinished: {
        // A lookup in flight when the user opts out is killed, but its output
        // may already be buffered: never let it land after the opt-out.
        if (!geo.useGeoclue) return
        var out = null
        var raw = String(text || "")
        try {
          // One JSON line is all the helper prints; 64 KiB is far past it.
          if (JsonRead.tooLarge(raw, 64 * 1024)) throw new Error("too large")
          out = JSON.parse(raw.trim().split("\n").pop())
        } catch (e) {
          geo._geoclue.error = "fix helper produced no JSON"
          geo._geoclue.ok = false
          return
        }
        if (!out || out.ok !== true) {
          geo._geoclue.error = out && out.error ? String(out.error) : "unknown geoclue failure"
          geo._geoclue.ok = false
          return
        }
        geo._geoclue.latitude = Number(out.latitude)
        geo._geoclue.longitude = Number(out.longitude)
        geo._geoclue.accuracy = Number(out.accuracy) || 0
        geo._geoclue.error = ""
        geo._geoclue.ok = true
      }
    }
  }

  property Timer _hourly: Timer {
    interval: 3600000
    repeat: true
    running: geo.useGeoclue
    onTriggered: geo.refresh()
  }

  // --- configured coordinates --------------------------------------------

  property QtObject _prayer: QtObject {
    property bool ok: false
    property double latitude: 0
    property double longitude: 0
    property string label: ""
  }

  // shell.json is ~10 KB on a real desktop and weather.json a few hundred
  // bytes; a file over these caps is refused unparsed and treated exactly
  // like an unreadable one (JsonRead.js).
  readonly property int _maxShellBytes: 4 * JsonRead.MiB
  readonly property int _maxWeatherBytes: JsonRead.MiB

  function _applyShell(text) {
    var cfg = null
    if (JsonRead.tooLarge(text, geo._maxShellBytes)) { geo._prayer.ok = false; return }
    try { cfg = JSON.parse(String(text || "")) } catch (e) { return }
    var id = "t1nk33r.omaprayers"
    var entry = {}
    function pick(list) {
      if (!Array.isArray(list)) return false
      for (var i = 0; i < list.length; i++)
        if (list[i] && String(list[i].id || "") === id) {
          for (var k in list[i]) entry[k] = list[i][k]
          return true
        }
      return false
    }
    pick(cfg ? cfg.plugins : null)
    if (cfg && cfg.bar && cfg.bar.layout) {
      var sections = ["left", "center", "right"]
      for (var s = 0; s < sections.length; s++) if (pick(cfg.bar.layout[sections[s]])) break
    }
    var lat = Number(entry.latitude)
    var lon = Number(entry.longitude)
    if (!isFinite(lat) || !isFinite(lon) || (lat === 0 && lon === 0)) {
      geo._prayer.ok = false
      return
    }
    geo._prayer.latitude = lat
    geo._prayer.longitude = lon
    geo._prayer.label = String(entry.locationLabel || "")
    geo._prayer.ok = true
  }

  property FileView _shellFile: FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: geo._applyShell(text())
    onLoadFailed: geo._prayer.ok = false
  }

  // --- Omarchy's shared weather location ----------------------------------

  property QtObject _weather: QtObject {
    property bool ok: false
    property double latitude: 0
    property double longitude: 0
    property string label: ""
  }

  property FileView _weatherFile: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var d = null
      var raw = String(text() || "")
      if (JsonRead.tooLarge(raw, geo._maxWeatherBytes)) { geo._weather.ok = false; return }
      try { d = JSON.parse(raw) } catch (e) { geo._weather.ok = false; return }
      var lat = Number(d ? d.latitude : NaN)
      var lon = Number(d ? d.longitude : NaN)
      geo._weather.label = String((d && d.name) || "")
      geo._weather.latitude = isFinite(lat) ? lat : 0
      geo._weather.longitude = isFinite(lon) ? lon : 0
      geo._weather.ok = isFinite(lat) && isFinite(lon) && !(lat === 0 && lon === 0)
    }
    onLoadFailed: geo._weather.ok = false
  }

  Component.onCompleted: geo.refresh()
}
