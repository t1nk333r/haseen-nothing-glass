import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import "components"

// The per-screen containment that replaces Plasma's containment. One
// PanelWindow per monitor, wallpaper + N widget instances living in the same
// window so each instance's own LiquidGlass can sample the wallpaper via
// ShaderEffectSource (see Wallpaper.qml's header comment for why that
// constraint exists).
//
// Plan 003 scoped this to *one* hard-coded demo tile — no widgets, no config,
// no placement. Plan 004 wired that tile's *appearance* (every LiquidGlass
// knob + MacOSColors) through the `plasmoid`/`colors` bridge below. Plan 005
// replaces the demo tile with a Repeater over Store.widgets and makes `mask`
// a union over the live instances.
Variants {
  id: root

  // Injected by Service.qml — only when this plugin is actually running
  // inside the shell. All stay at their defaults under the standalone dev
  // harness (glass-dev.qml instantiates GlassSurface
  // directly, bypassing Service.qml entirely), in which case
  // `plugin.settings` falls back to `_fallbackDefaults` below
  // (mirroring manifest.json's `settings.defaults`), `theme` falls back to
  // its own #1c1c1e default, and `store`/`registry` are real (both are
  // dependency-free — see their own files) so instances still render and
  // persist under the dev harness too.
  property var shell: null
  property var manifest: null
  property Theme theme: Theme {}
  property Store store: Store {}
  property WidgetRegistry registry: WidgetRegistry {}
  property PluginId identity: PluginId {}

  // Settings that survive the shell's housekeeping - see Options.qml. Merged
  // LAST, so a value the user set through our own UI wins over a stale one
  // left on the shell.json entry.
  property Options options: Options { identity: root.identity }

  // Stands in for Plasma's `plasmoid` context property — see Config.qml.
  // `configuration` merges manifest.json's `settings.defaults`, this plugin's
  // own entry in shell.json (read from disk - see the note on `_shellConfig`
  // below) and the options file on top of both (Options.qml), so
  // every read below re-evaluates the moment a setting changes in the
  // settings UI, with no restart. This is the *plugin-wide* configuration;
  // each WidgetHost layers its own instance `settings` on top of it (plan
  // 005 step 3) — instance overrides win.
  property Config plugin: Config {
    settings: root._mergedSettings()
  }

  // Mirrors manifest.json's `settings.defaults`. Needed for two cases where
  // `root.manifest` reads as null: (1) permanently, under the standalone dev
  // harness, which instantiates GlassSurface directly and never sets
  // `manifest` at all; (2) transiently, on real shell startup — shell.qml's
  // `ensureService()` calls `comp.createObject(serviceHost)` (running this
  // file's own property bindings, `plasmoid` included, with `manifest` still
  // at its `null` default) and only *afterwards* does `inst.manifest =
  // manifest` on the Service instance, one property-assignment step later.
  // Without this fallback, that first `_mergedSettings()` pass returns
  // `{}`, every `plugin.settings.*` read below is `undefined`, and
  // QML logs "Unable to assign [undefined] to int/double" on every one of
  // them — a real, observed warning (`journalctl -t omarchy-shell`), not a
  // hypothetical. A fourth place to update alongside the "three places" a
  // new knob otherwise touches (plan 004's maintenance notes) — worth it to
  // keep shell startup and the dev harness log clean. `tests/run.sh` checks
  // this literal against manifest.json's `settings.defaults` and fails if
  // they drift, so this is enforced, not just hoped for.
  readonly property var _fallbackDefaults: ({
    styleMode: 0, appearance: 0, cornerRadius: 100, roundness: 7.5,
    refractThickness: 35, refractIOR: 1.7, refractScale: 65,
    tintAlpha: 0.1, chromaStrength: 0.3, specStrength: 0.7,
    blurRadiusPx: 6, realtimeRefraction: false, opaqueBackground: true,
    clocks: "America/Los_Angeles|,Europe/London|,Asia/Tokyo|,Australia/Sydney|",
    widgetStyle: "liquid-glass", categoryStyles: ({}),
    accentColor: "#D71921", uiScale: 100, followTheme: false,
    systemFont: false, surfaceAlpha: 1.0, frost: 0.0,
    photoFolder: "", photoIntervalSec: 30, photoShuffle: true,
    storageMounts: "", networkInterface: "",
    useGeoclue: false,
    firstDayOfWeek: 0, eventLookaheadDays: 2,
    location: "", unit: "", refreshMinutes: 15,
    latitude: 40.7128, longitude: -74.006,
    playerFilter: "", filterMode: 0, artRefreshEnabled: false,
    autoHideEnabled: false, autoHideTimeout: 30,
    analogSecondSweep: false
  })

  // Plan 008 made this plugin dual-kind (`service` + `bar-widget`), and the
  // shell keeps exactly ONE shell.json entry per plugin id: either in
  // `plugins[]` or — once the id is placed on the bar — in
  // `bar.layout.<section>[]`. Every shell lookup checks the bar layout first
  // and `plugins[]` second (services/PluginRegistry.qml:206-223
  // findEntryLocation), and the settings UI edits whichever one it finds
  // (t1nk33r.settings/SettingsPanel.qml:645-648 configuredPluginEntry). So
  // reading only `plugins[]` here would silently strand every desktop widget
  // on manifest defaults the moment the bar widget is placed. Same precedence
  // as the shell: defaults < plugins[] entry < bar entry.
  // `omarchy bar set <id> <key> <value>` stores the value as a STRING unless
  // the caller remembers `--json` (the bar CLI's documented behaviour), and
  // now that this plugin's entry lives in the bar layout that is the natural
  // CLI for it. A string "1" survives `radius: "100"` (QML coerces) but
  // breaks every strict comparison the widgets make —
  // `plugin.settings.appearance === 1` is false for "1", so Light mode
  // silently never engages. Coerce each override to the TYPE of its manifest
  // default: numeric strings become numbers, "true"/"false" become booleans,
  // everything else passes through. Keys with no default are left alone.
  function _coerceLike(value, sample) {
    if (typeof value !== "string") return value
    if (typeof sample === "number") {
      var n = Number(value)
      return (value.trim() !== "" && !isNaN(n)) ? n : value
    }
    if (typeof sample === "boolean") {
      if (value === "true") return true
      if (value === "false") return false
    }
    return value
  }

  function _entryOverrides(entry, out, defaults) {
    if (!entry) return
    for (var ek in entry) {
      if (ek === "id") continue
      out[ek] = (defaults && ek in defaults) ? root._coerceLike(entry[ek], defaults[ek]) : entry[ek]
    }
  }

  function _findEntry(list, id) {
    if (!Array.isArray(list)) return null
    for (var i = 0; i < list.length; i++) {
      if (list[i] && String(list[i].id || "") === id) return list[i]
    }
    return null
  }

  // ── Which style draws a widget ──────────────────────────────────────
  // Three levels, most specific first:
  //
  //   1. the widget's own `style`, set from its right-click sheet;
  //   2. its CATEGORY's style, set once for e.g. every Time widget;
  //   3. `widgetStyle`, the plugin default.
  //
  // Categories are the registry's groups, which is also how the browser
  // organises its rail - so "make all my clocks Nothing" is one control, not
  // one per clock, and there is no single global switch flipping widgets the
  // user never asked about.
  function styleForEntry(entry) {
    if (!entry) return root.styleForCategory("")
    var own = String(entry.style || "")
    if (own !== "") return own
    return root.styleForCategory(root.registry ? root.registry.group(entry.type) : "")
  }

  function styleForCategory(group) {
    var g = String(group || "")
    var map = root.plugin.settings.categoryStyles
    if (g !== "" && map && typeof map === "object" && map[g]) return String(map[g])
    return String(root.plugin.settings.widgetStyle || "liquid-glass")
  }

  // Set (or clear, with "") the style for a whole category.
  function setCategoryStyle(group, style) {
    var g = String(group || "")
    if (g === "") return false
    var next = {}
    var map = root.plugin.settings.categoryStyles
    for (var k in (map || {})) next[k] = map[k]
    if (String(style || "") === "") delete next[g]
    else next[g] = String(style)
    return root.setPluginSetting("categoryStyles", next)
  }

  // ── The widget browser ─────────────────────────────────────────────
  // The browser is a toplevel the shell summons (Panel.qml), not a window in
  // this per-screen surface, so there is no instance here to toggle or to
  // open on a widget: the surface asks the shell for the panel and passes the
  // widget in the payload. The bar icon and the IPC verb go through
  // Service.toggleLauncher, which is the same door for the plain summon.
  function requestBrowser(widgetId) {
    if (!root.shell || typeof root.shell.summon !== "function") return
    root.shell.summon(root.identity.id,
                      JSON.stringify({ widget: String(widgetId || "") }))
  }

  // ── The other half of the pair ─────────────────────────────────────
  // Writes one plugin-wide setting back into this plugin's single shell.json
  // entry - the same path the settings UI and the bar panel take. Absent
  // shell (dev harness) makes this a no-op rather than an error.
  // The plugin has exactly ONE shell.json entry, and it lives in EITHER
  // `bar.layout.<section>` (placed - the bar icon renders) OR `plugins[]`
  // (un-placed). Both carry its settings. `_mergedSettings()` above
  // reads both; anything that WRITES has to look in both too.
  //
  // An earlier version of this function looked only in `plugins[]`. On a host
  // whose entry sat in `bar.layout.right`, the first launcher write therefore
  // found nothing, pushed a fresh `plugins[]` row, and the shell was left
  // with the id in two places: the bar icon went un-placed and the settings
  // that had been on the bar entry (styleMode among them) stopped being read.
  // Observed on this machine, 2026-09-09.
  function _findEntryAnywhere(cfg, id) {
    if (!cfg) return null
    var hit = root._findEntry(cfg.plugins, id)
    if (hit) return hit
    var layout = cfg.bar && cfg.bar.layout ? cfg.bar.layout : null
    if (!layout) return null
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      hit = root._findEntry(layout[sections[s]], id)
      if (hit) return hit
    }
    return null
  }

  function setPluginSetting(key, value) {
    if (!root.shell) return false
    var id = root.identity.id
    var cfg = root._shellConfig
    var entry = root._findEntryAnywhere(cfg, id)
    var next = {}
    for (var k in (entry || {})) if (k !== "id") next[k] = entry[k]
    next[key] = value

    // `updateEntryInline` edits the entry WHEREVER it is - bar layout first,
    // then plugins[] - and returns false when the id appears in neither.
    //
    // There is no second path, and this used to pretend there was.
    // `shell.mutateShellConfig()` is wired only for a manifest declaring the
    // `bar` kind (shell.qml:654); this plugin declares service / bar-widget /
    // panel, so the promotion the fallback performed - inventing a plugins[]
    // row for an id that appears nowhere - returned false on every call and
    // the mutation never ran. Upstream reached the same conclusion on its own
    // fork (nearby-share's Service.qml: "not an option and no longer
    // attempted", for this exact reason).
    //
    // Nothing is lost by dropping it: the point of the mirror is to make the
    // value visible to the Omarchy settings UI, and an id with no entry
    // anywhere has no row there to show it in. The durable copy below is the
    // source of truth - it survives a restart and GlassSurface's merge applies
    // it last - so success is whether that write happened, not whether an entry
    // existed to mirror into. Reporting failure when the value was in fact
    // persisted (the IPC `option` reply is built from this) is the bug the old
    // fallback masked from the other side.
    var durable = false
    if (root.options) { root.options.set(key, value); durable = true }

    // And through the shell as well, when the entry exists, so the settings UI
    // shows the same value while its entry lasts. Its own false return (the id
    // is in neither the bar layout nor plugins[]) is a display miss, not a
    // write failure, so it does not override the durable result.
    if (entry && typeof root.shell.updateEntryInline === "function")
      root.shell.updateEntryInline(id, next)

    return durable
  }

  // ── Where the plugin's own settings come from ───────────────────────
  //
  // NOT from `shell`. A service-kind plugin is injected `omarchyPath`,
  // `shell`, `manifest`, `barWidgetRegistry` and `pluginRegistry` and nothing
  // else (shell.qml:929-932); the scoped facade it gets has no `shellConfig`
  // and no `settings` - only the bar-widget entry point is handed a live
  // `settings` object. Reading `shell.shellConfig` therefore returned null on
  // every evaluation, `_mergedSettings()` fell back to pure defaults,
  // and NO user setting has ever reached a widget: styleMode stayed Glass no
  // matter what the panel wrote. Instrumented and confirmed on this machine
  // (`shell=yes cfgObj=no`, every time), which is also why the settings
  // writer could not find its own entry and un-placed the bar icon instead.
  //
  // So the surface reads the file the shell writes. Read-only, watched, and
  // parsed exactly the way the shell parses it. Writes still go through
  // `shell.updateEntryInline()`, which IS in the facade - one writer, still
  // the shell.
  readonly property string _shellConfigPath:
    (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"))
    + "/omarchy/shell.json"

  property var _shellConfig: null

  // A typed property, NOT a bare child: this file's root is `Variants`, whose
  // default property takes the per-screen delegate, so a loose FileView here
  // is swallowed and never loads (observed: `cfgLoaded=no`, forever). Same
  // shape Store.qml uses for its own Process/Timer children.
  property FileView _shellConfigFile: FileView {
    id: shellConfigFile
    path: root._shellConfigPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        root._shellConfig = JSON.parse(text())
      } catch (e) {
        // A half-written file during someone else's save: keep the last good
        // copy rather than dropping every setting for a frame.
        console.warn("nothing-glass: shell.json unreadable, keeping last known settings")
      }
    }
    onLoadFailed: root._shellConfig = null
    onFileChanged: reload()
  }

  function _mergedSettings() {
    var out = {}
    var defaults = (root.manifest && root.manifest.settings && root.manifest.settings.defaults) || root._fallbackDefaults
    for (var k in defaults) out[k] = defaults[k]

    var cfg = root._shellConfig
    var id = root.identity.id
    if (!cfg || !id) return out

    root._entryOverrides(root._findEntry(cfg.plugins, id), out, defaults)

    var layout = (cfg.bar && cfg.bar.layout) ? cfg.bar.layout : null
    if (layout) {
      var sections = ["left", "center", "right"]
      for (var s = 0; s < sections.length; s++) {
        var hit = root._findEntry(layout[sections[s]], id)
        if (hit) { root._entryOverrides(hit, out, defaults); break }
      }
    }

    // Ours last: the shell may relocate its own entry and drop what was on
    // it (measured), so this copy is the one that has to win.
    var own = root.options ? root.options.values : null
    for (var ok in (own || {}))
      out[ok] = (ok in defaults) ? root._coerceLike(own[ok], defaults[ok]) : own[ok]

    root._adoptLegacyScaledKeys(out)
    return out
  }

  // Five settings used to be stored as integers scaled by 10 or 100, because
  // Plasma's kcfg could only hold Int. Nothing about Omarchy needs that -
  // its schema takes `number`, which is what these are now. A config written
  // by an older build still carries the old key, so convert it here, at the
  // single point every source is merged, rather than making each of the 96
  // read sites cope with two spellings. Harmless once no old config is left.
  readonly property var _legacyScaled: ({
    roundnessX10: { key: "roundness", div: 10 },
    refractIORx100: { key: "refractIOR", div: 100 },
    tintAlphaPct: { key: "tintAlpha", div: 100 },
    chromaStrengthPct: { key: "chromaStrength", div: 100 },
    specStrengthPct: { key: "specStrength", div: 100 }
  })

  function _adoptLegacyScaledKeys(out) {
    for (var old in root._legacyScaled) {
      if (!(old in out)) continue
      var spec = root._legacyScaled[old]
      var n = Number(out[old])
      if (isFinite(n)) out[spec.key] = n / spec.div
      delete out[old]
    }
  }

  model: Quickshell.screens

  // Two windows per screen, not one: the widget surface below (Bottom layer,
  // no keyboard focus, behind every application window) and the settings
  // sheet a right-click opens (Top layer, focusable - a surface with no
  // keyboard focus receives no key events, so its text fields would be
  // untypeable). A Scope groups them; it is not a visual item and adds
  // nothing to either window.
  Scope {
    id: screenScope
    required property var modelData

    // The bar's reserved edges on this screen. The widget surface ignores
    // exclusive zones on purpose (a widget may sit anywhere), so nothing
    // else keeps a drag - or "reset position" - out from behind the bar.
    ScreenInsets {
      id: screenInsets
      screen: screenScope.modelData
    }

    // ── Is this screen actually being drawn? ─────────────────────────────
    // The one "not on screen" state a Bottom-layer surface can really see: a
    // monitor switched off (DPMS). Widgets are mapped on every workspace by
    // design - that is the product - so "another workspace" and "a full-screen
    // window on top" are not states anything here can detect, and the data
    // components' own comments now say so instead of promising otherwise.
    //
    // `dpmsStatus` sits in the same `hyprctl monitors -j` object ScreenInsets
    // reads, with the same catch: `lastIpcObject` is EMPTY until a refresh
    // reply has landed. UNKNOWN - no monitor, an empty object, a compositor
    // that is not Hyprland - must read as DRAWN. The failure mode has to be a
    // visible widget, never a blank desktop.
    property var _monitor: null

    function _resolveMonitor() {
      var name = String(screenScope.modelData ? screenScope.modelData.name : "")
      var list = Hyprland.monitors ? Hyprland.monitors.values : []
      for (var i = 0; i < list.length; i++) {
        if (list[i] && String(list[i].name) === name) { screenScope._monitor = list[i]; return }
      }
      screenScope._monitor = null
    }

    // Resolved imperatively and read from a binding, like ScreenInsets'
    // `current`: monitorFor() can create the monitor object it returns, which
    // notifies the monitor list, which would re-evaluate a binding that called
    // it - an actual binding loop. The monitor object itself survives a
    // refresh (measured: the same object across 18 consecutive
    // refreshMonitors() calls), so a binding on its `lastIpcObject` is what
    // keeps this value current, not the poll.
    readonly property bool screenDrawn: {
      var monitor = screenScope._monitor
      var ipc = monitor ? monitor.lastIpcObject : null
      if (!ipc || ipc.dpmsStatus === undefined) return true
      return !!ipc.dpmsStatus
    }

    // Hyprland reports no event for a DPMS change - its event list is
    // monitoradded/removed, focusedmon and the workspace family, and nothing
    // for dpms - so asking again is the only way to see one. One `j/monitors`
    // round trip per screen every 5 s, the same request ScreenInsets already
    // makes: it bounds both how long a switched-off monitor goes on being
    // polled and how long the desktop can stay blank once the screen is back.
    // Running only where there is a Hyprland socket to ask.
    property Timer _dpmsPoll: Timer {
      interval: 5000
      repeat: true
      running: Hyprland.requestSocketPath !== ""
      onTriggered: {
        Hyprland.refreshMonitors()
        screenScope._resolveMonitor()
      }
    }

    Component.onCompleted: screenScope._resolveMonitor()
    onModelDataChanged: screenScope._resolveMonitor()

  PanelWindow {
    id: surface
    readonly property var modelData: screenScope.modelData

    screen: modelData
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }

    WlrLayershell.namespace: root.identity.namespace
    // Bottom, not Background and not Overlay. Omarchy's wallpaper owns the
    // Background layer and ordering two surfaces within one layer is not
    // guaranteed, so Background risks rendering the widgets *under* the
    // wallpaper. Bottom sits directly above it and below every application
    // window: desktop widgets stay behind running windows, which is what the
    // operator asked for. Do not raise this to Top/Overlay.
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // Widgets on THIS screen only, as a keyed list. An instance whose
    // `screen` matches no connected monitor (unplugged cable) is filtered
    // out here — it stays in Store.widgets (see Store.qml / plan 005 step 1)
    // and simply never gets a WidgetHost anywhere, rather than being deleted.
    //
    // `_hostModel` is the Repeater's model and is reassigned ONLY when the
    // set of ids on this screen changes. Geometry/settings changes are pushed
    // into the existing WidgetHost's `entry` instead (see _syncHosts), so a
    // drag-release, resize or `set` no longer destroys and re-creates every
    // widget on the screen — which re-ran every clock's `date` spawns,
    // re-logged every QML warning, dropped every in-flight network request
    // and flickered, on every store write.
    property var _hostModel: []

    function _screenEntries() {
      var out = []
      var all = root.store ? root.store.widgets : []
      for (var i = 0; i < (all ? all.length : 0); i++) {
        if (all[i] && all[i].screen === surface.modelData.name) out.push(all[i])
      }
      return out
    }

    function _sameIds(a, b) {
      if (a.length !== b.length) return false
      for (var i = 0; i < a.length; i++) if (a[i].id !== b[i].id) return false
      return true
    }

    function _syncHosts() {
      var next = surface._screenEntries()
      if (!surface._sameIds(surface._hostModel, next)) {
        surface._hostModel = next
        return
      }
      var hosts = surface._maskItems
      for (var i = 0; i < next.length; i++) {
        for (var h = 0; h < hosts.length; h++) {
          if (hosts[h].entry && hosts[h].entry.id === next[i].id) {
            if (hosts[h].entry !== next[i]) hosts[h].entry = next[i]
            break
          }
        }
      }
    }

    Connections {
      target: root.store
      function onWidgetsChanged() { surface._syncHosts() }
    }
    Component.onCompleted: surface._syncHosts()

    // The union input mask. Empty by construction when there are no
    // instances on this screen (regions: [] and no item/shape of its own),
    // which is what keeps the surface fully click-through with zero
    // widgets — the rule a decoration plugin exists to follow: it draws no
    // interactive surface of its own, so an empty mask lets every click
    // through. Populated by hostRepeater's
    // itemAdded/itemRemoved below rather than an Instantiator, since the
    // Region for each instance is something WidgetHost.qml already owns
    // (`maskRegion`) — no need to build a second, parallel non-visual
    // repeater over the same model.
    property var _maskItems: []

    // While any instance is being dragged or resized the mask becomes the
    // WHOLE surface. Hyprland stops delivering pointer motion to a layer
    // surface the moment the pointer leaves its input region, implicit grab
    // or not — measured in the lab: a 75 px grip drag resized by 12 px and
    // stalled exactly where the pointer crossed the mask edge. Widening the
    // mask for the duration of the gesture is the only way the drag can
    // outrun the widget it is enlarging. Restored to the union the moment
    // the button is released.
    readonly property bool _interacting: surface._maskItems.some(function (it) { return it.interacting })

    Item { id: fullMask; anchors.fill: parent }

    mask: Region {
      item: surface._interacting ? fullMask : null
      regions: surface._interacting ? [] : surface._maskItems.map(function (it) { return it.maskRegion })
    }

    // Invariant: Wallpaper must be a child of the same PanelWindow as every
    // LiquidGlass instance that samples it. See Wallpaper.qml's header.
    //
    // Plan 005's placeholder widget type deliberately left
    // LiquidGlass.wallpaperItem at its null default and rendered the flat
    // fallback rect — see widgets/placeholder/main.qml. Plan
    // 006 (the first real port) threads this `backdrop` instance down to
    // every WidgetHost as `injectedBackdrop`, the same way `theme` already
    // is; WidgetHost.qml provides the `backdrop` id + recapture-on-load/
    // on-switch fix (see its own comments) at the per-instance level, since
    // there is no longer one single glass to patch.
    Wallpaper { id: backdrop; anchors.fill: parent }

    // One blur per screen, beside the wallpaper it blurs and for the same
    // reason Wallpaper is here: the blurrable backdrop is this window's own
    // Image, not the compositor's. `active` is the plugin-wide `frost` key -
    // off (the default) means no layer holds a source, no FBO is allocated and
    // no pass runs, so a matte installation pays nothing for the feature. Every
    // Nothing host on this screen is handed the output as `injectedFrost`; see
    // NTheme.qml and PORTING.md item 20.
    FrostLayer {
      id: frostLayer
      anchors.fill: parent
      wallpaper: backdrop
      active: Number(root.plugin.settings.frost) > 0
    }

    MacOSColors {
      id: colors
      styleMode: plugin.settings.styleMode
      appearance: plugin.settings.appearance
      systemBackground: theme.systemBackground
      themePalette: root.theme ? root.theme.palette : null
    }

    Repeater {
      id: hostRepeater
      model: surface._hostModel

      // The model is a plain JS array, so a reassignment still re-creates
      // every delegate — which is why _syncHosts only reassigns when an id
      // is added or removed, and otherwise updates `entry` in place.
      delegate: WidgetHost {
        id: widgetHost
        required property var modelData
        entry: modelData
        registry: root.registry
        store: root.store
        pluginSettings: root.plugin.settings
        // Bound to `widgetHost.entry`, NOT to `modelData`. _syncHosts swaps
        // `entry` in place and only reassigns the model when an id is added
        // or removed, so a style change on an existing widget never touches
        // `modelData` - binding to it left the tile drawn in the old style
        // until the next restart, with the store already showing the new one.
        style: root.styleForEntry(widgetHost.entry)
        injectedTheme: root.theme
        injectedBackdrop: backdrop
        // This screen's half-res blurred wallpaper, or null while `frost` is 0
        // (nothing was built) - the Nothing style's material source. See
        // FrostLayer.qml and NTheme's frost comment.
        injectedFrost: frostLayer.output
        // False only while THIS screen is switched off (DPMS). The host turns
        // it into its own `visible`, which Qt propagates to every child, so
        // each widget body's existing `active: root.visible` starts telling
        // the truth without a single widget file changing. See screenScope's
        // `screenDrawn` for what it can and cannot see.
        screenDrawn: screenScope.screenDrawn
        screenWidth: surface.width
        screenHeight: surface.height
        insetLeft: screenInsets.left
        insetTop: screenInsets.top
        insetRight: screenInsets.right
        insetBottom: screenInsets.bottom

        // Right-click on a widget opens ITS settings sheet, beside it: one
        // widget's style, its own per-type fields, size and position. The
        // browser - every widget, the catalogue, the plugin-wide appearance -
        // is one cog away inside the sheet, so the two do not compete.
        onSettingsRequested: function (entry, screenX, screenY) {
          settingsSheet.openFor(entry, screenX, screenY)
        }
      }

      onItemAdded: function (index, item) {
        var arr = surface._maskItems.slice()
        arr.push(item)
        surface._maskItems = arr
      }
      onItemRemoved: function (index, item) {
        var arr = surface._maskItems.slice()
        var idx = arr.indexOf(item)
        if (idx !== -1) arr.splice(idx, 1)
        surface._maskItems = arr
      }
    }
  }

  // The widget browser is NOT here: it is a toplevel the shell summons on its
  // own (Panel.qml), because a layer surface is not a window Hyprland can
  // float, size or centre. The settings sheet below hands a widget over to it
  // through the shell - see requestBrowser().

  // The single-widget settings sheet. Its own window because the widget
  // surface above has no keyboard focus and its text fields would be
  // untypeable - see WidgetSettingsWindow.qml's header.
  WidgetSettingsWindow {
    id: settingsSheet
    screen: screenScope.modelData
    store: root.store
    registry: root.registry
    pluginSettings: root.plugin.settings
    themePalette: root.theme ? root.theme.palette : null
    insetLeft: screenInsets.left
    insetTop: screenInsets.top
    refreshInsets: screenInsets.refresh
    styleForCategory: root.styleForCategory
    openBrowser: function (id) { root.requestBrowser(id) }
  }

  }
}
