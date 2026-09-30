# PROJECT_MAP — Liquid Glass

External memory for this plugin. Update on every change — this file is meant
to answer "what is this and how does it work" without reading every file.

## [TECH_STACK]

- Runtime: Quickshell 0.3.1 / Qt 6 QML, run inside `omarchy-shell`
  (`quickshell -n -p "$OMARCHY_PATH/shell"`)
- Plugin id: `t1nk33r.nothing-glass`
- Host: Omarchy 4.x
- Source tree: the repository root **is** the plugin. It was severed from its
  KDE Plasma upstream on 2026-09-10 — no `packages/`, no `1-common/`, no
  `.plasmoid` build, and no symlinks anywhere in the tree (`PORTING.md` item 31)

## [SYSTEM_FLOW]

```
shell startup → Service.qml (Item, shell/manifest injected)
  → Store {} (owns ~/.config/omarchy/nothing-glass.json)
  → WidgetRegistry {} (type -> QML file + min size)
  → GlassSurface { store; registry }
    → Variants over Quickshell.screens → one PanelWindow per screen
      (WlrLayer.Bottom, namespace "t1nk33r-liquidglass")
      → Wallpaper.qml (hidden Image, mirrors the compositor's current
        wallpaper file; readlink -f + FileView watch + 5s poll backstop;
        threaded to every WidgetHost as `injectedBackdrop` — see
        WidgetHost.qml's note below)
      → Repeater over store.widgets filtered to this screen
        → WidgetHost { entry; registry; store; pluginSettings;
            injectedBackdrop; ... }
          → Config { id: plugin } / QtObject { id: theme } / QtObject
            { id: backdrop } — exposed as document ids so a Loader-loaded
            widget file can reference them unqualified (see WidgetHost.qml's
            own comment and PORTING.md item 5)
          → Loader (asynchronous) → widgets/<type>/main.qml
          → Region { id: maskRegion; item: host } — one per instance
          → Placement {} — RIGHT-drag to move, left-drag the corner grip to resize,
            commits to Store on release (no modifiers: none ever reach this surface)
      → mask: Region { regions: <union of every live WidgetHost's maskRegion> }
        — empty when there are no instances on this screen ⇒ fully click-through
  → IpcHandler "t1nk33r.nothing-glass" (Service.qml): listTypes, listWidgets,
    add, remove, move, resize, set, launcher, option, reload — all mutations
    go through Store, and `set <id> style '"nothing"'` is how a widget's
    style is pinned from the shell. `launcher <screen>` toggles the widget
    browser: the argument names the DESKTOP the browser acts on ("" = the
    monitor the user is on, resolved when it opens), not which window to
    show — there is one.

widget browser (manifest kinds: "service" + "bar-widget" + "panel")
  → Panel.qml — the `panel` entry point, loaded by the shell's panel loader on
    summon and destroyed on hide (no `keepLoaded`). Nothing visual comes from
    the host: the FloatingWindow declared here IS the window, titled
    PluginId.browserTitle ("Nothing Glass"). A toplevel, not the Overlay
    layer surface it used to be, so Hyprland can float, size and centre it
    (rules.lua's `float_nothing_glass_browser`, matched on that title) and
    the desktop stays interactive behind it
  → NothingLauncher.qml — the content, unchanged: rail of sections (Desktop,
    one per catalogue group, Appearance), live tile grid, inspector, the
    knob pane. One instance, not one per screen, so the per-summon values it
    needs (the desktop new widgets land on, that monitor's reserved edges for
    "reset position") are resolved in Panel.open(), never injected at
    construction
  → the store, registry, merged settings, theme and the three style functions
    come from Service.qml over the shell's `service` injection
    (widgetStore/widgetRegistry/widgetSettings/widgetTheme/styleForEntry/
    styleForCategory/setCategoryStyle) — the same one Store and the same
    style precedence the desktop draws with, not a second copy
  → open(payloadJson)/close() are the loader's lifecycle; Escape, and a
    compositor-initiated close, call requestClose() → shell.hide(id) so the
    shell's openPanelIds and the window cannot disagree
  → payloads: `{"screen":"HDMI-A-1"}` picks the desktop, `{"widget":"<id>"}`
    opens on that widget with its settings beside it (the right-click sheet's
    cog), "" is the plain open-here
  → ways in: `omarchy-shell t1nk33r.nothing-glass launcher ''`, the bar
    icon, a keybind, or `shell summon t1nk33r.nothing-glass '<payload>'`

widgets/prayer/ + widgets/sunrise/ — two of the widgets written here rather
  than carried over from a Plasma applet. `prayer` renders
  components/PrayerCard.qml (small), the
  card plus the day's six rows (medium/large); `sunrise` draws the sun's arc
  from PrayerTimes' sunriseAt/sunsetAt/dayProgress and takes its coordinates
  from GeoLocation.

tests/run.sh — static checks plus four headless behavioural tests.
  Static: manifest defaults vs GlassSurface._fallbackDefaults, every
  plugin.settings key having a default, every registry path resolving in
  both style trees with no orphan widget directory and no type missing from
  a launcher group, PluginId.qml agreeing with manifest.json about the id,
  every QML type listed in its directory's qmldir, Store's legacy-store
  absorption being gated on the real store path, every WidgetFields key
  being a real setting. Behavioural: tests/prayer-rollover.qml driving
  PrayerTimes through six instants via its nowOverride seam (the instants are
  derived from a fixture location, not read off the clock), the Nothing
  primitives, the store round-trip and migration, and the settings merge -
  each fed the configuration it needs from a scratch HOME the harness builds,
  never the operator's.

components/PrayerCard.qml — the prayer card (ring, glyph, next time,
  countdown, names), rendered in TWO places that must match: the desktop
  widget and t1nk33r.lock's lock screen, which keeps a copy of this file next
  to copies of LiquidGlass/MacOSColors and a LiquidGlass sampling its own
  blurred lock wallpaper. Hand-written twice, they drifted apart in a day.

components/GeoLocation.qml + components/geo/geoclue-fix.sh — coordinates:
  GeoClue2 (via gdbus in a script, since Quickshell has no generic D-Bus
  client) -> the omaprayers entry's lat/lon -> Omarchy's weather.json ->
  the caller's fallback. `source` names the winner. geoclue is installed here
  but has no provider url configured, so it drops the connection and the
  configured coordinates win.

components/PrayerTimes.qml + components/prayers/ — prayer times. Engine.js
  and prayer-zone.sh are VENDORED from t1nk33r.omaprayers (MIT, Salem Sayed;
  LICENSE.omaprayers alongside) because that plugin is bar-widget-only: no
  service entry point, no getters on its IpcHandler, nothing cached on disk.
  The engine is fed the operator's own omaprayers settings, read live from
  ~/.config/omarchy/shell.json (plugins[] entry merged under the placed bar
  entry, bar wins). Offline: no network, no API key. Rows roll over to
  tomorrow once Isha has passed.

components/EventSource.qml + components/events/CalendarEvents.js — the
  calendar's only view of event data. Replaces Plasma's
  EventPluginsManager + three PlasmaCalendar.Calendar backends +
  daysModel.eventsForDate(). It reads ONE watched document,
  ~/.local/state/omarchy/calendar-events.json (the schema
  tmn73/omarchy-calendar publishes, adopted verbatim), and merges `khal list
  --json` when khal is installed; on this machine neither exists, so it
  returns [] and says so as `state: "no-backend"`. The field names match
  EventDataDecorator so a backend can be dropped in without touching the
  widget; the mapping, the day placement and the merge are pure ES5 in
  CalendarEvents.js (PORTING.md items 16 and 35).

ScreenInsets.qml — the bar's reserved edges per monitor, from
  HyprlandMonitor.lastIpcObject.reserved. The widget surface is
  exclusionMode: Ignore (a widget may sit anywhere), so nothing else keeps a
  drag - or "reset position" - out from behind the bar. Feeds Placement's
  snap origin and clamps, and both Reset actions. lastIpcObject is empty
  until refreshMonitors() is called, so this object primes it itself.

right-click on a widget → Placement.settingsRequested → WidgetHost →
  GlassSurface → WidgetSettingsWindow.openFor(entry, x, y) — the one-widget
  sheet, its own PanelWindow per screen (Top layer, namespace
  `<namespace>-settings`, keyboardFocus OnDemand while open, because the
  widget surface is Bottom + focus None and a surface without keyboard focus
  gets no key events, so its text fields would be untypeable)
  → the sheet: the Style row (Inherit + registry.stylesFor(type), hidden for
    a type with one drawing), the three size presets, the type's fields from
    WidgetFields.qml, Reset position, Remove — and a cog that closes the
    sheet and hands the same widget to the browser: GlassSurface.requestBrowser()
    → shell.summon(id, {"widget": …}) → Panel.open() → NothingLauncher.openForWidget(id)
  → the browser (a FloatingWindow toplevel, see the widget-browser block
    above) is the other way in: it opens on Desktop with that widget selected
    and WidgetInspector.qml
    beside the grid — the same size presets, the same Style row (Category /
    Liquid Glass / Nothing), the same per-type fields, Reset position and
    Remove (two taps, because a right-click can open the pane)
  → the two surfaces edit through the same Store and read the same
    WidgetFields table, which is what keeps them from disagreeing about a
    key's name, its type or what an empty value means
  → plain QtQuick plus this repo's Nothing primitives, not qs.Ui:
    GlassSurface is also instantiated by the standalone dev harness where
    `qs.Ui` does not resolve

shell startup → BarWidget.qml (second entry point, kinds: "bar-widget")
  → loaded by the bar, NOT by Service.qml/GlassSurface — no glass, no
    wallpaper, no `plugin`/`theme`/`backdrop` ids; the bar injects only
    bar/moduleName/settings
  → the CONTROL PANEL: a BarIconButton (squircle glyph drawn as shapes) that
    opens a KeyboardPanel (not PopupCard: it has text fields, and an
    xdg-popup never receives keys here) listing every desktop instance
  → and as of plan 055 the entry is the ICON ALONE: the workspace figure plan
    050 had drawn beside it is gone, so `implicitWidth` is exactly
    `button.implicitWidth` (`Style.bar.iconSlot`, 27). The figure, if wanted,
    is the first-party `omarchy.workspaces` widget's job
  → reaches the service's Store + WidgetRegistry via
    bar.shell.serviceFor(moduleName) → add / remove / reset instances through
    the same single writer the IPC uses; the Glass/Solid toggle writes
    styleMode through `setPluginSetting()` → `Service`'s `option` verb → the
    options file GlassSurface's merge applies LAST (the copy the widgets
    render). NOT `bar.shell.updateEntryInline` on the plugin's shell.json
    entry, which that merge overrides, so a write there moves nothing on screen
  → per-widget Edit, on EVERY row: three grid size buttons
    (WidgetRegistry.sizes(type) → Store.resize) and Position X,Y
    (NumberFields → Store.move, clamped to the screen), plus the type's own
    settings — whatever `WidgetFields.forType(type)` lists, never a copy of
    that table — → Store.set / Store.unset on THAT instance's sparse
    `settings` override, the object WidgetHost._mergedSettings merges
    over the plugin-wide value. Empty field + Save = unset. Settings fields
    pre-fill with the effective value the PANEL can see: override → bar
    entry → manifest default. The panel does not read `Options.qml`'s file,
    so a plugin-wide value set from the launcher shows here only once the
    shell.json entry carries it too
  → PanelKeyCatcher is blocked while any field holds focus, counted (not a
    bool): focus moving field-to-field delivers the loser's false after the
    winner's true
  → IpcHandler "t1nk33r.nothing-glass-panel": toggle, open, close
    (separate target: the service already owns "t1nk33r.nothing-glass")
  (the weather readout that plan 008 put here was replaced on the operator's
   request; the desktop `weather` type is unchanged)

widget types with their own external data source (all inside the Loader above):
  weather / bar widget → components/WeatherDataQs.qml  (Open-Meteo over XHR)
  city-*               → components/TzClock.qml        (`date` subprocess per zone)
  timer                → components/Notify.qml         (notify-send)
  now-playing          → Quickshell.Services.Mpris     (imported directly by
    widgets/now-playing/main.qml — the only widget that talks to a Quickshell
    service itself; no lyrics backend in the Quickshell port. Named `music`
    until the rename: MPRIS carries podcasts and video too)
```

## [ARCHITECTURE]

- `manifest.json` — plugin contract: `kinds` (`service` **and**
  `bar-widget` since plan 008), `entryPoints`, **plugin-wide** settings
  schema (glass defaults, the style axis and the per-type keys — see "Where
  state lives" below), and the `barWidget` block the bar registry reads.
- `BarWidget.qml` — the second entry point, the control panel (it replaced
  the plan-008 weather readout on 2026-09-06). Loaded by the bar, so none of
  the desktop machinery below applies to it directly: no `WidgetHost`, no
  glass. It reaches the desktop through `bar.shell.serviceFor(moduleName)`
  → `Service.widgetStore` / `Service.widgetRegistry`, and reads plugin-wide
  values with `setting(key, fallback)` off the injected `settings` object.
  Note the shell keeps ONE `shell.json` entry per plugin id and moves it into
  `bar.layout.<section>` once the widget is placed, which is why
  `GlassSurface._mergedSettings()` reads the bar layout too.
- `Service.qml` — entry point (`shell`/`manifest` injected by the shell
  loader per `shell.qml`'s `ensureService()`). Owns the single `Store` and
  `WidgetRegistry` instances (shared by every screen's `GlassSurface`
  `PanelWindow` and by the `IpcHandler`), instantiates `GlassSurface`, and
  declares the `t1nk33r.nothing-glass` `IpcHandler` (8 methods — see
  `[SYSTEM_FLOW]`). It is also the widget browser's data door: the browser is
  a toplevel the shell loads on its own (`Panel.qml`), so it cannot be handed
  the surface's bindings at construction; `widgetStore`, `widgetRegistry`,
  `widgetSettings`, `widgetTheme`, `styleForEntry()`, `styleForCategory()`
  and `setCategoryStyle()` forward the same objects and functions from the
  one surface, and `toggleLauncher(screen)` is the door both the bar icon
  and the `launcher` verb use.
- `GlassSurface.qml` — the per-screen containment: `Variants` over
  `Quickshell.screens`, one `PanelWindow` each. Plan 003 hard-coded one demo
  tile; plan 004 wired its *appearance* through the config/`colors` bridge;
  **plan 005 replaced the demo tile with a `Repeater` over `Store.widgets`
  filtered to that screen, and made `mask` a union over the live
  instances**, built from each `WidgetHost`'s own `maskRegion` via the
  `Repeater`'s `itemAdded`/`itemRemoved` signals (not a second parallel
  `Instantiator` — see the file's own comment on `_maskItems`). Also owns
  plugin-wide settings merging: `_mergedSettings()` = manifest defaults +
  this plugin's `shell.json` entry + its own options file, handed down as
  `pluginSettings`, and each `WidgetHost` layers the instance's own
  `settings` on top. `_adoptLegacyScaledKeys()` runs at the end of that
  merge and is the only place the pre-fork scaled keys are understood
  (PORTING.md item 31). It no longer instantiates the widget browser — that
  is `Panel.qml`, one toplevel for the whole desktop — and only asks the
  shell to summon it with a widget in the payload (`requestBrowser()`, the
  right-click sheet's cog).
- `Store.qml` (plan 005) — the single on-disk instance store,
  `~/.config/omarchy/nothing-glass.json`: `FileView { watchChanges: true;
  atomicWrites: true }` with manual `JSON.parse`/`JSON.stringify` (not
  `JsonAdapter` — see "Deviation from the plan" below), debounced writes
  (250ms), a `_selfWrite` guard against reacting to its own atomic writes,
  and corrupt-file handling that logs once, backs the bad file up to
  `nothing-glass.json.bak`, and never overwrites the original. **One writer**:
  every mutation (`add`/`remove`/`move`/`resize`/`set`) goes through this
  file — `IpcHandler` and `Placement.qml` both call into it rather than
  touching the file themselves. It also normalises ROWS on the way in:
  `_adoptLegacyTypes()` maps a retired widget `type` onto the living one
  (`_legacyTypes`) for both readers, because a type is also the directory its
  QML is loaded from and a stale name draws nothing.
- `WidgetRegistry.qml` (plan 005) — maps a `type` string to the QML entry
  point for a given STYLE (`urlFor(type, style)` →
  `widgets/<type>/main.qml` or `widgets-nothing/<type>/main.qml`), plus its
  minimum size, label, catalogue group and hint. `stylesFor(type)` is the
  styles that type can actually be drawn in. Twenty-seven entries: the three
  `Dev` ones (`placeholder`, `test-glass`, `test-timer`) plus the twenty-four
  user-facing types — `clock-digital`, `clock-analog`, `clock-analog-2`,
  `clock-analog-3`, `city-1`, `city-2`, `city-3`, `city-digital`, `weather`,
  `sunrise`, `calendar`, `prayer`, `timer`, `now-playing`, `tailscale`,
  `codeburn`, `perf`, `deepseek`, `claude-usage`, `omarr`, `battery`, `network`,
  `storage`, `photos` — and every one of the twenty-four carries a drawing in
  BOTH trees (`nothing: true`), so no type is single-style.
- `WidgetHost.qml` (plan 005; wallpaper threading added plan 006) — one
  widget instance: geometry from its store entry, the merged settings
  (`pluginSettings` + this instance's `settings` override, via
  `_mergedSettings()`), the `plugin`/`theme`/`backdrop` ids (declared as QML
  **ids**, not properties, so a `Loader`-loaded widget file's unqualified
  reads resolve through the Loader's parent-context chain — see the file's
  own comment), the `Loader` that instantiates the widget, and the
  `maskRegion` the surface's union mask collects. An unknown `type` logs once
  and renders nothing (does not throw, does not affect other instances).
  `backdrop` supplies the name a widget body's `wallpaperItem: backdrop.item`
  line expects (on Plasma each body declared its own `PlasmaBackdrop`, which
  imported Plasma and did not come across); its `item` property mirrors
  `injectedBackdrop` (GlassSurface.qml's shared per-screen `Wallpaper`) and
  is toggled null-then-back on `injectedBackdrop.status === Image.Ready`
  (`_refreshBackdrop()`) — the per-instance equivalent of plan 004's
  demo-tile recapture fix, needed once per `WidgetHost` since each widget
  owns its own `LiquidGlass`.
- `Placement.qml` (plan 005) — drag/resize, one instance per `WidgetHost`:
  **right**-button drag anywhere to move, plain left drag on the bottom-right
  grip to resize, and a right-click that does not travel opens the browser's
  inspector (`settingsRequested`). No modifier gate — this surface has
  `keyboardFocus: None`, so Wayland never delivers modifiers to it and the
  original SUPER gate could not have worked; see the file's header. Snapped
  to the registry's 88+16 grid, clamped to screen bounds and to the type's
  minimum size, and committed to `Store` on release only.
- `widgets/` and `widgets-nothing/` — one subdirectory per `type` string per
  style, in the repo root (the source tree and the installed plugin are the
  same bytes). A widget body reaches the shared tree with
  `import "../../components"`; there is no per-widget `components` symlink —
  see `PORTING.md` item 1.
- `fonts/` — the two Barlow faces and their inventory, at the repo root.
  `components/nothing/NTheme.qml` and the two digital clocks load them with
  `Qt.resolvedUrl("../../fonts/X.ttf")`. `icons/` works the same way, shared
  by the widget that needs it. See `PORTING.md` item 9.
- `Wallpaper.qml` — hidden (`visible: false`) `Image` that mirrors
  `~/.local/state/omarchy/current/background`'s resolved target, the same way
  `/usr/share/omarchy/shell/plugins/background/Background.qml` does. Must
  live in the same `PanelWindow` as every `LiquidGlass` that samples it —
  `ShaderEffectSource.sourceItem` does not work across windows. Plan 004's
  per-tile recapture-on-load/on-switch fix (nulling and re-setting
  `wallpaperItem` on `backdrop.status === Image.Ready`) was removed with the
  single demo tile it patched; plan 006 re-solved it per-instance in
  `WidgetHost.qml` (`_refreshBackdrop()` — see that file's note above).
- `FrostLayer.qml` — the Nothing style's producer half: the screen's
  wallpaper blurred once per wallpaper change (Dual Kawase, 4 down + 3 up,
  half-resolution output) and handed to every host as `injectedFrost` →
  `NTheme.frostSource`. Same window as the `Wallpaper` it blurs, for the same
  reason. Off (no layer holds a source, so nothing is allocated and no pass
  runs) while the plugin-wide `frost` key is 0, which is its default. The
  consumer is `components/nothing/NFrost.qml` + `shaders/nfrost.frag`; the
  rule this is written under is PORTING.md item 20, and the control story is
  `NTheme.frost`'s comment.
- `components/` — a real directory at the repo root, imported by the runtime
  and by every widget body (`import "components"` at depth 0,
  `import "../../components"` from a widget). One copy, in the source tree and
  in the installed plugin alike.
- `components/`, `fonts/` and `icons/` hold real files. They were symlinks
  into a shared `1-common/` tree until the fork was cut from Plasma on
  2026-09-10 (`PORTING.md` item 31), and the flat root carries **no symlink at
  all** — the relative directory import is what replaced them.
- The repo root **is** the plugin: `omarchy plugin add` clones this repository
  straight into `~/.config/omarchy/plugins/t1nk33r.nothing-glass/`, so the
  installed folder is a git checkout of this tree and there is no build step.
  Never hand-edit the installed copy — the next `omarchy plugin update`
  fast-forwards it.

### Where state lives: three files, on purpose

Plugin-wide defaults are declared in `manifest.settings` and ride on the
plugin's `shell.json` entry (house convention, plan 004) — but the shell
relocates and strips that entry, so the copy that survives a restart is
`~/.config/omarchy/nothing-glass-options.json`, owned by `Options.qml`. Merge
order: manifest defaults < `shell.json` entry < options file (PORTING.md
item 29). `shell.json` is still read, and still written when the entry
exists, so the Omarchy settings UI keeps showing the same value.

The widget instance array cannot be expressed in that flat typed-scalar
schema (`DynamicSettingsForm.qml` has no array-of-objects field type), and
`shell.json` is rewritten by the shell itself, so a hand-maintained array in
it would race those writes — so instances live in a third file,
`~/.config/omarchy/nothing-glass.json`, owned entirely by `Store.qml`. Each
row carries `id`, `type`, `screen`, `x/y/w/h`, an optional `style` column
and a sparse `settings{}` override. See `Store.qml`'s own header for the full
reasoning; anyone tempted to consolidate must first solve that representation
problem.

### Tailscale, and the interactive node web

| File | Role |
|---|---|
| `components/TailscaleData.qml` | the tailnet as numbers: three polled `tailscale` CLI reads - `status --json`, `serve status --json`, `debug derp-map` - on a 30 s timer with a 2 s startup ramp, every read bounded by a 1 s supervisor at 15 s counted from its own launch and escalated to SIGKILL 3 s later. The LocalAPI socket and the long-lived `watch-ipn-bus` push stream this file used to hold open are gone (the direct-vs-relay facts a doorbell could not carry forced a status read behind it anyway), so `active` - bound to the drawing's `visible` - is what stops the polls. Also `ping(peerId)` - the only source of latency, on demand only, because it is side-effectful. The `t1nk33r.tailscale` plugin is bar-widget-only and cannot serve as a backend; see PORTING.md item 25 |
| `widgets/tailscale/main.qml` | Liquid Glass presentation |
| `widgets-nothing/tailscale/main.qml` | Nothing presentation |

Both draw a node web at 400x400 with THIS machine at the centre - every fact
the data layer has (direct, endpoint, rx/tx) is measured from here, so a mesh
would be inventing edges. Link style carries the path: solid direct, dashed
via DERP, faint idle, fainter offline.

The web is interactive under one rule - **wakes on touch, sleeps otherwise**:
hover to inspect, left-drag to pull a node with a spring home, double-click to
pin (session-only, never stored), click to ping, wheel to spread. There is no
idle timer, no physics and no repaint at rest; the settle clock starts on
release and stops itself. Geometry lives in a `_nodes` array the painter only
draws - if you touch the map, keep that split or the cost model goes with it.

### Store writes: leading edge, synchronous, reload-guarded

Two data-loss paths were closed on 2026-09-07 (PORTING.md item 22): a
trailing-only debounce lost the last mutation whenever the shell was signalled
(no QML destructor runs then), and a reload triggered by our own write could
overwrite newer in-memory state mid-burst. Writes now happen on the leading
edge with `blockWrites`, coalesce for 250 ms, and `_applyText` refuses to apply
a reload while `_revision !== _writtenRevision`. Any new mutation must go
through `_scheduleWrite()`, which is what bumps `_revision`.

### Deviation from the plan: `Store.qml` does not use `JsonAdapter`

Plan 005 suggested `FileView` + `JsonAdapter`. `Store.qml` instead uses plain
`FileView` with manual `JSON.parse`/`JSON.stringify` — the same pattern
`shell.qml` itself uses for `shell.json` (`userConfigFile`, around
`shell.qml:130-139`), which is the one place in this whole system already
proven to handle exactly this class of problem (missing file, malformed
file, atomic writes, watched reloads) correctly. `JsonAdapter`'s automatic
bidirectional property sync is harder to reason about for the corrupt-file
contract this plan requires (log once, back up, never overwrite the
original) — deliberately avoided in favour of the one pattern already
proven correct in this codebase. Behaviourally equivalent to what the plan
asked for; implemented differently.

### Two styles, one plugin

Both presentations ship in ONE plugin, `t1nk33r.nothing-glass`, from one
runtime and one store. The style is chosen per WIDGET, resolved in
`GlassSurface.styleForEntry()`: the widget's own `style` column → its
category's entry in `categoryStyles` (keyed by the registry `group`) → the
plugin-wide `widgetStyle` default. `WidgetHost` is handed the resolved
string and `registry.urlFor(type, style)` picks the file, falling back to
whichever drawing the type does have. Full rules: PORTING.md item 20; why
this is not two plugins any more: item 30.

| File | Role |
|---|---|
| `plugin/PluginId.qml` | the identity: id, label, `browserTitle` (the browser toplevel's window title, and the string Hyprland's rule matches), `styles`, `styleLabel()`, store filename, layer namespace. The only file that spells any of them |
| `components/nothing/NTheme.qml` | the Nothing tokens (colours, geometry, type, motion) and `px()`; injected into every widget by `WidgetHost` as `nothing`. `followTheme` swaps the stock matte-black palette for the live Omarchy theme; `surfaceAlpha` (0..1) multiplies the alpha of the three surface fills, each of which is a `*Solid` opaque base plus that multiplier - `surfaceSolid` is the token for the call sites that must stay opaque at every value, the six dial hub discs being the ones that exist. `frost` (0..1) is how much of a level-0 card's backdrop is the blurred wallpaper, and it composes with `surfaceAlpha` rather than replacing it: `NFrost` draws `material = mix(backdrop, surface, surface.a)` over `backdrop = mix(nothing, blurred wallpaper, frost)`, so each knob still moves the card at any value of the other, and `frost` 0 is the matte card at any `surfaceAlpha`. `frostSource` (the screen's blurred wallpaper, null wherever there is no screen behind the widget) and `frostEpoch` (bumped by the host on geometry changes, so a card's `mapToItem` crop re-runs) are its other two inputs |
| `components/nothing/N*.qml` | the primitives: `NCard NText NLabel NMono NDivider NBadge NButton NProgress NDotMatrix NDotField NDial NFrost` (`NFrost` is the frosted card material: one visible `ShaderEffect` cropping the screen's blurred wallpaper under the card's rounded rect — see PORTING.md item 20) |
| `components/nothing/dots.js` | dot-matrix glyph patterns used by `NDotMatrix` |
| `components/{Battery,Network,Storage,Photo}Data.qml` | data components behind the `battery`, `network`, `storage` and `photos` types; presentation-free |
| `plugin/Panel.qml` | the widget browser's WINDOW: the manifest's `panel` entry point. A FloatingWindow titled `PluginId.browserTitle`, `open(payloadJson)`/`close()` for the shell's panel loader, `requestClose()` (what Escape calls) so the shell's open state agrees with the window. One instance for the whole desktop; resolves the target screen and its insets at open time |
| `plugin/NothingLauncher.qml` | the widget browser's CONTENT, inside Panel.qml's window: rail of sections — Desktop, one per catalogue group, then Appearance — beside a grid of live tiles. One browser, the whole catalogue; the Appearance pane carries the plugin-wide `widgetStyle`, a Categories row per group, and the knobs of both drawings — `glassKnobs` and, for the Nothing style, a `nothingKnobs` table (`surfaceAlpha`, `frost`, displayed as percents through `mult: 100`) whose ranges come from the manifest schema. Its own `NTheme` binds none of the appearance knobs, on purpose: the sheet and its tiles stay opaque and matte |
| `plugin/KnobRow.qml` | one Appearance knob row — name, value in the knob's own units, drag track. Both knob tables (`glassKnobs`, the Nothing `nothingKnobs`) draw through it, and it is the pane's one write site: it holds the pending value while the handle is dragged and writes once on release, dividing by the row's `mult` |
| `plugin/LauncherTile.qml` | one tile: preview, name, hint, style chip, click to add/remove, right-click a desktop tile to open the inspector |
| `plugin/WidgetInspector.qml` | everything about ONE instance, inside the browser: size, style, the per-type fields, reset, remove |
| `plugin/WidgetSettingsWindow.qml` | the same one-widget surface as a right-click sheet next to the tile (its own Top-layer PanelWindow, OnDemand focus), with a cog that hands the widget to the browser |
| `plugin/WidgetPreview.qml` | the preview host: the REAL widget with the same `plugin`/`theme`/`backdrop`/`nothing` ids, at true tile size, never upscaled |
| `components/qmldir`, `components/nothing/qmldir` | explicit type registration; required, see PORTING.md item 21 |

A widget file never learns which of the two it is: same
`plugin.settings` keys, same data component, same three tile sizes.
A Nothing drawing styles itself from the injected `nothing` (NTheme) object
and must not import `MacOSColors` or `LiquidGlass`.

The Nothing knobs (`followTheme`, `accentColor`, `uiScale`, `systemFont`,
`surfaceAlpha`, `frost`) are **plugin-wide**, exactly like the glass ones — no
per-instance override reaches them. A new one touches, in order:
`manifest.json` `settings.defaults` + a `settings.schema` entry (ranged, or
the browser pane drops the control and `tests/run.sh` section 4b fails), the
`_fallbackDefaults` literal in `GlassSurface.qml` (section 1 fails if it
drifts), a declared property in `NTheme.qml`, a binding at the three sites
that render a widget — `WidgetHost.qml` (the desktop), `WidgetPreview.qml`
(the browser's tiles) and `tests/WidgetSweepTile.qml` (the sweep) — and a row
in `NothingLauncher.qml`'s knob table (`glassKnobs` / `nothingKnobs`, both drawn
by `KnobRow.qml`). `NothingLauncher`'s own `NTheme` binds
none of the appearance knobs on purpose: the browser's frame and its tiles sit
in the launcher's own opaque material rather than over the wallpaper (the
sheet's comment says so), so they stay opaque. One wart to keep: a `0..1` knob
whose label says "(%)"
prints `0.50`, not 50, in the Omarchy settings panel — its readout is
`toFixed(2)` on the stored value, exactly as `tintAlpha` already does.

Ways in: `omarchy-shell t1nk33r.nothing-glass launcher ''` (empty = the focused
monitor, the desktop new widgets land on), the bar icon's left click (the same
verb, in-process when the service resolves), the bar panel's **Browse widgets…**,
or a keybind. All of them end at the one toplevel: `omarchy-shell shell toggle
t1nk33r.nothing-glass '{"screen":"…"}'`.

## [ORPHANS & PENDING]

- There is no install script any more. `omarchy plugin add <url>` clones this
  repo into `~/.config/omarchy/plugins/t1nk33r.nothing-glass/` and that
  checkout is the plugin; `omarchy plugin update` fast-forwards it and
  `omarchy plugin remove` deletes it. The two surfaces the old installer added
  (a desktop entry and a `SUPER + SHIFT + U` keybinding) are documented in the
  README as optional manual steps.
- `Repeater` in `GlassSurface.qml` is bound to a plain JS array
  (`Store.widgets`, filtered), not an incrementally-updatable model, so any
  store change re-creates every `WidgetHost` on that screen rather than
  reusing instances by `entry.id`. Correct, not optimal — see the file's own
  comment on `hostRepeater`. Worth a proper `DelegateModel` if instance churn
  ever becomes visible as flicker.
- A minor race exists in `Store.qml`'s "log once" corruption guard: a
  filesystem-watch-triggered reload landing very close to an explicit
  `reload()` IPC call can log the warning twice instead of once (observed
  directly during plan 005's testing). The critical guarantees — the
  original file is never overwritten, nothing crashes, no widgets render —
  held in every observed case; only the "log once" wording is imperfect
  under that specific race.
- **Load with six instances (plan 006)**: with `test-glass`, `clock-digital`,
  `clock-analog`, `clock-analog-2`, `clock-analog-3`, and `clock-glass-text` (since removed)
  all added to one screen (six live Kawase pyramids + one SDF/JFA chain),
  `omarchy-shell`'s own CPU usage (`ps -o pcpu`) held steady at ~6% over a
  5-second sample — no growth, no busy-loop signature. A clean per-instance
  GPU cost could **not** be isolated on this run: the live desktop's dGPU
  (`/sys/class/drm/card1/device/gpu_busy_percent`) was already reading
  96-99% busy from unrelated foreground activity (browser tabs, likely video
  playback) both before and after the widgets were added, so the six
  instances' own contribution is not visible above that noise floor. Revisit
  this measurement on an otherwise-idle GPU before trusting a real number
  here.
