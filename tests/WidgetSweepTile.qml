import QtQuick
import "plugin"
import "components/nothing"

// One tile in the widget sweep: exactly the four injected ids WidgetHost.qml
// gives a widget body by hand (`plugin`, `theme`, `backdrop`, `nothing`), the
// registry's own URL for this type/style, and nothing else.
//
// This is deliberately NOT WidgetPreview.qml, the launcher's live preview,
// even though that file hosts a widget the same way. WidgetPreview injects
// `backdrop.item: null` on purpose - there is no wallpaper behind a launcher
// tile - and LiquidGlass answers a null wallpaperItem with its flat fallback
// rect, so the whole capture/blur/refract chain never runs. The sweep hands
// the tile the same kind of wallpaper Item a real screen does, because what
// it is checking is what a desktop draws.
//
// The tile is 192x192 - the small grid preset, the size a tile actually lives
// at - and clips, so a widget that overflows cannot paint outside its own
// grab and be measured as ink it does not have.
Item {
  id: tile

  // A widget that draws outside its own tile must not be measured as ink it
  // does not have: a real tile is cleaned to its own rounded shape, so the
  // grab is clipped to the same box.
  clip: true

  // --- set by the driver, one per registry type/style pair ---------------
  required property string type
  required property string style
  required property var registry
  required property var pluginSettings
  required property var injectedTheme
  required property var backdropSource

  // "ready" / "error" / "loading" / "null", the wording the sweep's report
  // uses. This is a FUNCTION, not a bound property, on purpose: Qt
  // re-evaluates a dependent binding lazily, so a binding read from inside
  // the Loader's own onStatusChanged still answers with the previous status -
  // every tile reported "loading" while the driver, reading a moment later,
  // quite correctly saw "ready". The status is the subject here; read it
  // directly.
  function stateName() {
    var s = widgetLoader.status
    if (s === Loader.Ready) return "ready"
    if (s === Loader.Error) return "error"
    if (s === Loader.Loading) return "loading"
    if (s === Loader.Null) return "null"
    return "unknown"
  }
  // The URL the registry resolved for this pair, as the Loader sees it.
  readonly property string url: String(widgetLoader.source)
  // True once the loader can no longer change status on its own.
  function settled() {
    return widgetLoader.status === Loader.Ready || widgetLoader.status === Loader.Error
  }

  // --- the injection chain, mirrored from WidgetHost.qml -----------------

  Config { id: plugin; settings: tile.pluginSettings }

  QtObject {
    id: theme
    readonly property color systemBackground: tile.injectedTheme ? tile.injectedTheme.systemBackground : "#1c1c1e"
    readonly property var palette: tile.injectedTheme ? tile.injectedTheme.palette : null
  }

  QtObject {
    id: backdrop
    readonly property Item item: tile.backdropSource
  }

  NTheme {
    id: nothing
    scale: {
      var v = Number(tile.pluginSettings ? tile.pluginSettings.uiScale : 100)
      return (isFinite(v) && v > 0) ? v / 100 : 1
    }
    accent: {
      var c = tile.pluginSettings ? tile.pluginSettings.accentColor : ""
      return (c && String(c) !== "") ? String(c) : "#D71921"
    }
    followTheme: !!(tile.pluginSettings && tile.pluginSettings.followTheme)
    systemFont: !!(tile.pluginSettings && tile.pluginSettings.systemFont)
    // The sweep measures what the desktop draws, so it reads the knob too -
    // at its default 1.0 that is the same pixels the style drew before it.
    surfaceAlpha: {
      var v = Number(tile.pluginSettings ? tile.pluginSettings.surfaceAlpha : 1)
      return (isFinite(v) && v >= 0 && v <= 1) ? v : 1
    }
    // Bound for the same reason surfaceAlpha is - the sweep reads the knob a
    // desktop reads - and deliberately without a `frostSource`: this tile is a
    // window with a flat backdrop, not a screen with a FrostLayer behind it, and
    // NCard reads that as the matte card. So a Nothing tile measures the same
    // drawing at any frost value, which is what the sweep's baseline is
    // (PORTING.md item 20).
    frost: {
      var v = Number(tile.pluginSettings ? tile.pluginSettings.frost : 0)
      return (isFinite(v) && v >= 0 && v <= 1) ? v : 0
    }
    themePalette: tile.injectedTheme ? tile.injectedTheme.palette : null
  }

  Loader {
    id: widgetLoader
    anchors.fill: parent
    asynchronous: true
    source: (tile.registry && tile.registry.hasType(tile.type))
      ? tile.registry.urlFor(tile.type, tile.style) : ""

    onStatusChanged: {
      if (tile.settled()) tile.report()
    }
  }

  Component.onCompleted: {
    // Printed for every pair the registry offers, before any of it is
    // loaded, so the report enumerates by the registry rather than by what
    // happened to load - a type whose urlFor() yields nothing is a row like
    // any other, and a row that must fail.
    console.log("SWEEP tile " + tile.type + " " + tile.style + " " + tile.url)
    if (tile.url === "") {
      console.log("SWEEP load " + tile.type + " " + tile.style + " nousource " + tile.url)
      tile.settledDone = true
    } else if (tile.settled()) {
      tile.report()
    }
  }

  function report() {
    if (tile._reported) return
    tile._reported = true
    tile.settledDone = true
    console.log("SWEEP load " + tile.type + " " + tile.style + " " + tile.stateName() + " " + tile.url)
  }
  property bool _reported: false
  // Set by report() and by the empty-URL case above; only the driver reads
  // it, and only to know when to stop waiting.
  property bool settledDone: false
}
