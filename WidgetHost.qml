import QtQuick
import Quickshell
import "components/nothing"

// One widget instance: geometry from the store, a merged plugin.settings
// shim, and the Loader that instantiates the widget's own main.qml. The
// loaded file must not know it is hosted — see PORTING.md items 3/5 — which
// is what keeps a port mechanical: every `plugin.settings.X` read
// stays exactly as it was in the Plasma package.
Item {
  id: host

  // --- injected by GlassSurface.qml -------------------------------------
  required property var entry               // one row from Store.widgets: {id,type,screen,x,y,w,h,settings}
  required property WidgetRegistry registry
  required property Store store              // for Placement.qml's commit-on-release
  // Which drawing this instance gets. Resolved by GlassSurface from the
  // widget's own `style`, its category, then the plugin default - the host
  // is handed the answer, it does not work it out.
  property string style: "liquid-glass"
  required property var pluginSettings // the plugin-wide merged config (manifest defaults + shell.json entry + options file); this instance's `settings` override it, not the other way round
  required property real screenWidth        // this screen's PanelWindow size, for Placement.qml's clamp
  required property real screenHeight
  // False while this host's screen is switched off (DPMS); true whenever that
  // state is unknown - no monitor object, no Hyprland, the refresh reply not
  // in yet. Defaults to true for the same reason: the failure mode must be a
  // widget on screen, never a blank tile. See GlassSurface.screenScope.
  property bool screenDrawn: true

  // Reserved edges of this screen (the bar), forwarded to Placement so a
  // drag cannot park a widget behind it. See ScreenInsets.qml.
  property int insetLeft: 0
  property int insetTop: 0
  property int insetRight: 0
  property int insetBottom: 0
  property Theme injectedTheme: Theme {}
  property var injectedBackdrop: null       // GlassSurface.qml's shared per-screen Wallpaper Image
  // GlassSurface.qml's shared per-screen blurred copy of that wallpaper
  // (FrostLayer.output), or null while the plugin-wide `frost` key is 0. The
  // Nothing style's card material; a Liquid Glass widget never reads it.
  property Item injectedFrost: null

  x: entry.x
  y: entry.y
  width: entry.w
  height: entry.h

  // The other half of the data components' `active` gate: a host is visible
  // except while its screen is switched off. Qt propagates a parent's
  // `visible: false` to every child - and reads back as false on the child's
  // own `visible`, which is exactly what a widget body's `active:
  // root.visible` binds - so hiding this one Item is what makes those gates
  // tell the truth, with no widget file touched.
  //
  // Nothing else sets `visible`, here or on the surface: a widget must stay on
  // every workspace, so there is no second mechanism to add.
  visible: screenDrawn

  // Placement.qml writes x/y/width/height directly during a drag, which
  // breaks the four bindings above. Hosts now survive store writes
  // (GlassSurface._syncHosts swaps `entry` in place instead of re-creating
  // the host), so an IPC move/resize arriving after a drag must re-apply
  // the entry's geometry explicitly or it would silently not land.
  onEntryChanged: {
    if (!entry) return
    x = entry.x; y = entry.y; width = entry.w; height = entry.h
  }

  // Bumped from this host's own geometry, because that is the only way a card
  // inside it can move: Placement.qml writes x/y/width/height here, and a
  // widget body's own layout only follows. Nothing's frost crops a screen-sized
  // blurred wallpaper by the card's position, and that crop is a mapToItem()
  // call - a function, which notifies nothing when an ancestor moves. This
  // counter is the notification, so a drag or a resize re-crops exactly when it
  // must and no per-frame timer is needed (LiquidGlass.qml's 16 ms one tracks
  // the specular highlight, not the wallpaper). See NFrost.qml.
  property int _frostEpoch: 0
  onXChanged: host._frostEpoch++
  onYChanged: host._frostEpoch++
  onWidthChanged: host._frostEpoch++
  onHeightChanged: host._frostEpoch++

  // For the surface's union input mask (GlassSurface.qml) and for
  // Placement.qml's resize clamp.
  //
  // Region only knows circular corners, but LiquidGlass draws a superellipse
  // with exponent `roundness` (2 = circle, 7.5 by default): squarer than a
  // circle of the same radius, so a circular mask at `cornerRadius` excludes
  // visible glass — and Placement's resize grip lives exactly in that
  // excluded corner. Scale the radius so the circle cuts the 45° diagonal at
  // the same depth the superellipse does: a superellipse of exponent p
  // reaches the diagonal at r·(1 − 2^(−1/p)) from the corner, a circle at
  // r·(1 − 1/√2). For p = 7.5 that is 0.30·r. Slight over-inclusion along
  // the edges next to the corner is harmless; exclusion of visible pixels is
  // the bug.
  //
  // `roundness` IS that exponent — it is a real number here (default 7.5,
  // schema range 2.0..10.0), not Plasma's `roundnessX10` integer: the scaled
  // legacy key is converted once, at the merge point, by
  // GlassSurface._adoptLegacyScaledKeys, so nothing on this side divides it
  // again. Dividing by ten clamped this to its floor and drew a circle.
  // `Math.max(2, ...)` is only that floor — 2 is a circle.
  readonly property int maskRadius: {
    var cfg = host._mergedSettings()
    var r = Number(cfg.cornerRadius)
    if (isNaN(r) || r <= 0) return 0
    var p = Math.max(2, Number(cfg.roundness))
    if (isNaN(p)) return Math.round(r)
    var squircleCut = 1 - Math.pow(2, -1 / p)
    var circleCut = 1 - Math.SQRT1_2
    return Math.round(r * squircleCut / circleCut)
  }
  readonly property alias maskRegion: maskRegion
  // True while Placement is mid-drag/resize. GlassSurface widens the input
  // mask to the whole surface for the duration — see its mask comment.
  readonly property bool interacting: placement.dragging || placement.resizing

  // Stands in for Plasma's `plasmoid` context property, for the widget file
  // loaded below. This has to be a QML *id*, not merely a property: the
  // loaded file is a separate document, and only ids (and true context
  // properties) fall through a Loader's parent-context chain for
  // unqualified lookups from within it — a plain property named `plasmoid`
  // on `host` would only be reachable as `host.plugin`, which the ported
  // widget bodies never write (they read the bare `plasmoid` identifier,
  // unchanged from the Plasma package). See Config.qml and PORTING.md item 5.
  Config {
    id: plugin
    settings: host._mergedSettings()
  }

  // Same trick, for the Plasma-side `Kirigami.Theme.backgroundColor` a
  // ported widget's own `MacOSColors { systemBackground: ... }` binding
  // used to read (see AGENTS.md's MacOSColors token reference). Forwards
  // the theme injected from GlassSurface/Service.qml through an id so it
  // is reachable the same way `plasmoid` is.
  QtObject {
    id: theme
    property color systemBackground: host.injectedTheme ? host.injectedTheme.systemBackground : "#1c1c1e"
    // The full Omarchy palette for the two "follow theme" style modes. Null
    // when no theme was injected, which is exactly what MacOSColors treats
    // as "no palette, use the macOS one".
    property var palette: host.injectedTheme ? host.injectedTheme.palette : null
  }

  // Stands in for the ported widget's own local `PlasmaBackdrop { id: backdrop }`
  // declaration (PORTING.md item 5). PlasmaBackdrop.qml imports Plasma and
  // cannot be symlinked into this tree, so the loaded widget no longer
  // instantiates it itself — it keeps reading the unchanged `backdrop.item`
  // expression on its `LiquidGlass`, and this id supplies it from
  // the screen's shared Wallpaper Image (GlassSurface.qml's `backdrop`,
  // injected above as `injectedBackdrop`), through the Loader's parent
  // context chain the same way `plasmoid`/`theme` do.
  QtObject {
    id: backdrop
    readonly property Item item: host._backdropItem
  }

  // LiquidGlass's ShaderEffectSource only re-captures on a
  // sourceItem *identity* change — never merely because the wallpaper Image
  // it already points at finished loading or swapped pixels. Plan 004 solved
  // this for the old single demo tile with a Connections block in
  // GlassSurface.qml that nulled and re-set the tile's own wallpaperItem
  // binding on `backdrop.status` becoming Ready. There is no longer one
  // single glass to patch — every ported widget owns its own LiquidGlass —
  // so the equivalent lives here instead: toggling `_backdropItem`
  // null-then-back forces every widget's `wallpaperItem: backdrop.item`
  // binding (bound to this property via the `backdrop` id above) to
  // re-evaluate and re-capture, on both the very first paint (the wallpaper
  // file loads asynchronously) and every later wallpaper switch.
  property Item _backdropItem: null
  function _refreshBackdrop() {
    if (host.injectedBackdrop && host.injectedBackdrop.status === Image.Ready) {
      host._backdropItem = null
      host._backdropItem = host.injectedBackdrop
    }
  }

  Connections {
    target: host.injectedBackdrop
    function onStatusChanged() { host._refreshBackdrop() }
  }

  function _mergedSettings() {
    var out = {}
    var base = host.pluginSettings || {}
    for (var k in base) out[k] = base[k]
    var overrides = (host.entry && host.entry.settings) || {}
    for (var ok in overrides) out[ok] = overrides[ok]
    return out
  }

  // Not part of the visual tree (Region is a plain QObject, not an Item) —
  // just a child of `host`, the same way Timer/FileView live as children of
  // an Item elsewhere in this plugin. GlassSurface.qml collects these into
  // its union mask.
  Region {
    id: maskRegion
    item: host
    radius: host.maskRadius
  }

  // The Nothing style's tokens, reachable from a Nothing widget's body as
  // `nothing` through the same Loader parent-context chain that gives it
  // `plasmoid`, `theme` and `backdrop`. A Liquid Glass widget never touches
  // it; a Nothing widget never touches MacOSColors.
  NTheme {
    id: nothing
    scale: {
      var v = Number(host.pluginSettings ? host.pluginSettings.uiScale : 100)
      return (isFinite(v) && v > 0) ? v / 100 : 1
    }
    accent: {
      var c = host.pluginSettings ? host.pluginSettings.accentColor : ""
      return (c && String(c) !== "") ? String(c) : "#D71921"
    }
    followTheme: !!(host.pluginSettings && host.pluginSettings.followTheme)
    systemFont: !!(host.pluginSettings && host.pluginSettings.systemFont)
    // Plugin-wide, like the four above it - the style's material is one
    // setting, not one per instance. A value outside 0..1 (an `omarchy bar
    // set` typo) falls back to the opaque default rather than to whatever
    // alpha it parsed to.
    surfaceAlpha: {
      var v = Number(host.pluginSettings ? host.pluginSettings.surfaceAlpha : 1)
      return (isFinite(v) && v >= 0 && v <= 1) ? v : 1
    }
    // Plugin-wide like the four above it, and independent of `surfaceAlpha`
    // rather than an alternative to it: the two compose into one material in
    // nfrost.frag, which NTheme's own comment spells out. Same out-of-range
    // guard: an `omarchy bar set` typo falls back to the matte default rather
    // than to whatever it parsed to.
    frost: {
      var v = Number(host.pluginSettings ? host.pluginSettings.frost : 0)
      return (isFinite(v) && v >= 0 && v <= 1) ? v : 0
    }
    // This screen's half-res blurred wallpaper, or null while `frost` is 0.
    frostSource: host.injectedFrost
    // Re-runs a card's crop when this host moves.
    frostEpoch: host._frostEpoch
    themePalette: host.injectedTheme ? host.injectedTheme.palette : null
  }

  Loader {
    id: widgetLoader
    anchors.fill: parent
    asynchronous: true
    source: (host.registry && host.registry.hasType(host.entry.type))
      ? host.registry.urlFor(host.entry.type, host.style) : ""

    onStatusChanged: {
      if (widgetLoader.status === Loader.Error) {
        console.warn("nothing-glass: widget '" + host.entry.id + "' (type '" + host.entry.type + "') failed to load")
      }
    }
  }

  // An unknown type must render nothing and log once, not throw and not
  // crash the surface — one bad entry would otherwise take down every
  // widget on the desktop.
  Component.onCompleted: {
    if (!host.registry || !host.registry.hasType(host.entry.type)) {
      console.warn("nothing-glass: unknown widget type '" + host.entry.type + "' for instance '" + host.entry.id + "' — rendering nothing.")
    }
    host._refreshBackdrop()
  }

  // Right-drag to move, grip to resize. Nothing installed by Placement accepts
  // a left click except the grip itself — see Placement.qml's own header
  // comment.
  // Relayed from Placement's right-click up to GlassSurface, which owns the
  // settings window (one per screen, not one per widget).
  signal settingsRequested(var entry, real screenX, real screenY)

  Placement {
    id: placement
    anchors.fill: parent
    entry: host.entry
    store: host.store
    registry: host.registry
    screenWidth: host.screenWidth
    screenHeight: host.screenHeight
    insetLeft: host.insetLeft
    insetTop: host.insetTop
    insetRight: host.insetRight
    insetBottom: host.insetBottom

    onSettingsRequested: function (entry, screenX, screenY) {
      host.settingsRequested(entry, screenX, screenY)
    }
  }
}
