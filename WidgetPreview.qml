import QtQuick
import "components/nothing"

// A live widget, drawn small.
//
// The launcher's tiles are the REAL component - same file, same shims, same
// data - laid out at its true tile size and then scaled down as a whole. A
// mock-up drifts from the widget the moment either changes; this cannot, and
// a widget edit shows up in its own preview by construction.
//
// It is deliberately NOT a WidgetHost: no store row, no Placement, no drag,
// no mask Region, no persistence. Only the injection chain a widget body
// needs to resolve - `plasmoid`, `theme`, `backdrop`, `nothing`.
Item {
  id: preview

  required property var registry
  required property var pluginSettings
  required property var injectedTheme

  property string type: ""
  property string style: "liquid-glass"

  // The tile size this preview pretends to be, in desktop pixels. The
  // launcher passes one of the three grid presets.
  property real tileWidth: 192
  property real tileHeight: 192

  // Per-instance settings to preview with (the store row's `settings`, when
  // previewing something already on the desktop). Empty for a catalogue tile.
  property var settingsOverrides: ({})

  // Never larger than life. A widget blown up past 1:1 reads as a different
  // widget - the type looks heavier and the dot pitch coarser than it will be
  // on the desktop - and the whole point of a live preview is that what you
  // see is what you get.
  readonly property real fitScale: Math.min(1.0, Math.min(
    preview.width / Math.max(1, preview.tileWidth),
    preview.height / Math.max(1, preview.tileHeight)))

  clip: true

  Item {
    id: stage
    width: preview.tileWidth
    height: preview.tileHeight
    anchors.centerIn: parent
    scale: preview.fitScale
    transformOrigin: Item.Center

    // Same merge order as WidgetHost: manifest defaults + plugin-wide entry,
    // then this instance's overrides on top.
    QtObject {
      id: plugin
      readonly property var settings: {
        var out = {}
        var base = preview.pluginSettings || {}
        for (var k in base) out[k] = base[k]
        var ov = preview.settingsOverrides || {}
        for (var ok in ov) out[ok] = ov[ok]
        return out
      }
    }

    QtObject {
      id: theme
      readonly property color systemBackground: preview.injectedTheme
        ? preview.injectedTheme.systemBackground : "#1c1c1e"
      readonly property var palette: preview.injectedTheme ? preview.injectedTheme.palette : null
    }

    // A Liquid Glass widget asks the backdrop for the wallpaper item to
    // sample. There is no wallpaper behind a launcher tile, so it gets none
    // and falls back to its flat tinted rect - the same path the dev harness
    // and Plasma's plasmoidviewer take. Truthful about colour and layout,
    // and it costs no second ShaderEffectSource per tile.
    QtObject {
      id: backdrop
      readonly property var item: null
    }

    NTheme {
      id: nothing
      scale: {
        var v = Number(preview.pluginSettings ? preview.pluginSettings.uiScale : 100)
        return (isFinite(v) && v > 0) ? v / 100 : 1
      }
      accent: {
        var c = preview.pluginSettings ? preview.pluginSettings.accentColor : ""
        return (c && String(c) !== "") ? String(c) : "#D71921"
      }
      followTheme: !!(preview.pluginSettings && preview.pluginSettings.followTheme)
      // A preview must draw what the desktop draws, or the browser lies about
      // the material; it does not bind `systemFont`, which is the one axis
      // that stays a preview's own.
      surfaceAlpha: {
        var v = Number(preview.pluginSettings ? preview.pluginSettings.surfaceAlpha : 1)
        return (isFinite(v) && v >= 0 && v <= 1) ? v : 1
      }
      // The frost AMOUNT is bound, so a preview tells the truth about how much
      // of the card's backdrop the frost would fill - but `frostSource` is
      // deliberately not, and cannot be: there is no wallpaper behind a
      // launcher tile to blur (the `backdrop` above is null for the same
      // reason), and `LauncherTile` lays an opaque plate under the preview
      // besides. NCard reads a null source as the matte card, so the tile draws
      // exactly what the style drew before frost existed. Documented in
      // PORTING.md item 20, not a bug to fix here.
      frost: {
        var v = Number(preview.pluginSettings ? preview.pluginSettings.frost : 0)
        return (isFinite(v) && v >= 0 && v <= 1) ? v : 0
      }
      themePalette: preview.injectedTheme ? preview.injectedTheme.palette : null
    }

    Loader {
      id: body
      anchors.fill: parent
      asynchronous: true
      // The browser's content exists only while its toplevel is open (the
      // shell's panel loader creates and destroys it on summon/hide), so
      // `visible` is the whole story again - there is no closed sheet with
      // live previews behind it to gate against.
      active: preview.visible && preview.type !== ""
      source: (preview.registry && preview.registry.hasType(preview.type))
        ? preview.registry.urlFor(preview.type, preview.style) : ""
      onStatusChanged: {
        if (body.status === Loader.Error)
          console.warn("nothing-glass: preview of '" + preview.type + "' (" + preview.style + ") failed to load")
      }
    }
  }
}
