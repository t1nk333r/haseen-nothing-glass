This file provides guidance to Agents when working with code in this repository.

## What this repo is

The source tree of **`t1nk33r.nothing-glass`**, an Omarchy shell plugin for
Quickshell: macOS-Tahoe / iOS-style desktop widgets that refract the live
Hyprland wallpaper through a shader, plus a second, monochrome **Nothing OS**
drawing of most of the same widgets. One plugin, one runtime, two styles.

Requires Omarchy 4.x (Hyprland) and Quickshell 0.3.1. Nothing here needs a
build step: `tests/run.sh` uses `jq`, `tests/sweep-widgets.sh` uses `qs`,
`gamescope` and ImageMagick, `sync-lock-card.sh` uses `install`, and the
`omarchy` CLI is what installs and updates the plugin. Rebuilding the shaders
needs `qsb` from `qt6-base-dev-tools`.

*History, once:* this started as 16 KDE Plasma 6 applets under `packages/`
sharing a `1-common/` symlink tree. Those trees, their install/package
scripts and the translation catalogues were deleted when the port became the
product; `git log` still has them. Nothing in this repo targets Plasma any
more, and no doc here should be read as describing it.

## Repo layout

**The repo root is the plugin.** `omarchy plugin add` clones this repository,
validates it where it lands and installs the checkout unchanged — there is no
build step, no second repository and **no symlink anywhere in the tree**
(`omarchy-plugin-validate` refuses any symlink inside a plugin folder).

```
manifest.json            the plugin contract the shell reads
Service.qml              the runtime: IPC surface, store, registry, one
                         GlassSurface per screen
BarWidget.qml            the bar entry point (the control panel)
Panel.qml                the widget browser's toplevel
GlassSurface.qml         the two layer surfaces: widgets, and the sheet
WidgetHost.qml           one per widget instance
Store.qml Options.qml    the instance store, and plugin-wide settings
WidgetRegistry.qml       type -> QML file, group, default size
WidgetFields.qml         the per-instance field table
Placement.qml            drag/resize for one instance
WidgetSettingsWindow.qml the right-click sheet
WidgetInspector.qml WidgetPreview.qml LauncherTile.qml KnobRow.qml
NothingLauncher.qml      the widget browser's content
Theme.qml Wallpaper.qml FrostLayer.qml Config.qml PluginId.qml
ScreenInsets.qml
components/              shared QML: LiquidGlass.qml, MacOSColors.qml, the
                         data sources (WeatherDataQs, PrayerTimes,
                         GeoLocation, TailscaleData, NetworkData,
                         StorageData, BatteryData, PhotoData, CodeburnData,
                         EventSource, TzClock, WorldClockQs), shaders/,
                         nothing/ (the NTheme primitives), qmldir
widgets/<type>/          Liquid Glass drawing: main.qml (+ widget/ subtypes)
widgets-nothing/<type>/  Nothing drawing of the same type
fonts/                   the two Barlow faces + LICENSES.md, the inventory
icons/                   the shared icon sets
tests/                   run.sh, sweep-widgets.sh and the QML tests they drive
glass-dev.qml            runs the surface standalone, scratch store
build-shaders.sh         components/shaders/*.frag -> *.qsb
sync-lock-card.sh        mirrors the prayer card into the lock plugin, if one is installed
.github/                 CI workflow, issue templates, funding
nothing-glass-widgets.desktop   optional menu entry (see the README)
```

There is no symlink left to explain: a widget at `widgets/<type>/main.qml`
reaches the shared tree with `import "../../components"`, root-level files with
`import "components"`, and a widget's own `widget/` subdirectory with
`import "../../../components"`. **Never re-add a symlink** — validation refuses
it, and the relative directory import is the mechanism that replaced it
(PORTING.md items 1 and 21). Loader URL strings need the same treatment:
`source: "../../components/MotionWatch.qml"` from a widget directory, never
`"components/…"`.

Four things about the plugin its file names do not tell you:

- **It draws TWO styles from ONE plugin.** Which one an instance gets is
  resolved per widget: its own `style` field, else its CATEGORY's style
  (`categoryStyles`, keyed by the registry's `group`), else the `widgetStyle`
  default. Set the first from the widget's right-click sheet, the other two in
  the browser's Appearance pane. A Nothing widget styles itself from the
  injected `nothing` (NTheme) object and must not import `MacOSColors`,
  `LiquidGlass` or `qs.Ui`. There was briefly a second plugin,
  `t1nk33r.nothing`; it is gone, and `Store._absorbLegacyStore()` migrates a
  leftover `nothing.json` into the one store on first load. Read `PORTING.md`
  item 30 before proposing a split again.
- **Never spell the plugin id, store filename or layer namespace anywhere but
  `PluginId.qml`** — ask it.
- **A component directory needs a `qmldir` entry for every `.qml` file in
  it.** Without it the directory is registered lazily and the first type
  looked up fails with "`<T>` is not a type", which renders as an empty tile
  and no error. `tests/run.sh` enforces this. `PORTING.md` items 20-21.
- **`sync-lock-card.sh` exists and has no automatic caller.** It mirrors
  `components/PrayerCard.qml` (+ `PrayerTimes`, `MacOSColors`, `LiquidGlass`,
  the shaders and `components/prayers/*`) into `t1nk33r.lock`'s `glass/`
  directory, and no-ops when that plugin is not installed. Run it by hand
  after touching any of those files; the materialiser that used to invoke it
  is gone with the flattening.

`~/.config/omarchy/plugins/t1nk33r.nothing-glass/` is a **git checkout** —
`omarchy plugin add` clones the repo straight into it, so the installed folder
and this tree hold the same bytes. Never hand-edit the installed copy: the
next `omarchy plugin update` fast-forwards it and overwrites the edit.

## Common commands

```bash
omarchy-restart-shell                         # re-register the plugin, the bar and the service
bash tests/run.sh                             # the drift/consistency tests (see below)
bash tests/sweep-widgets.sh                   # load-and-draw every type, both styles (see below)
./build-shaders.sh                            # components/shaders/*.frag -> *.qsb
./sync-lock-card.sh                           # mirror the prayer card into the lock plugin, if installed
qs -n -p glass-dev.qml                        # run GlassSurface standalone, no install, scratch store
omarchy plugin update t1nk33r.nothing-glass    # pull a new revision into the installed checkout
```

IPC — `omarchy-shell t1nk33r.nothing-glass <verb> [args]`, all of them declared
in `Service.qml`:

| Verb | Arguments |
|---|---|
| `listTypes` | — |
| `listWidgets` | — |
| `add` | `<type> <screen>` (empty screen = focused) |
| `remove` | `<id>` |
| `move` | `<id> <x> <y>` |
| `resize` | `<id> <w> <h>` |
| `set` | `<id> <key> <valueJson>` — per-instance override |
| `launcher` | `<screen>` (empty = focused monitor) |
| `option` | `<key> <value>` — plugin-wide; takes bare words and JSON |
| `reload` | — |

The bar control panel has its own handler, `BarWidget.qml`, on the
separate target `t1nk33r.nothing-glass-panel`: `toggle`, `open`, `close`. It
only exists while the bar entry is placed (`PORTING.md` item 28; item 34 is
the way in when the icon is gone).

Notes:
- `build-shaders.sh` prefers `qsb6` → `/usr/lib/qt6/bin/qsb` → `qsb`, working
  around a broken Qt5 `qtchooser` symlink at `/usr/bin/qsb` on some systems.
- The `glass-dev.qml` harness points `Store` at a **scratch** file, not
  `~/.config/omarchy/nothing-glass.json`; two writers on the real store lose
  each other's writes.

## Dev loop

Three loops, from cheapest to most real:

1. **Tests only** — `bash tests/run.sh` after touching the manifest, the
   registry, a settings key, a `qmldir` or a component directory;
   `bash tests/sweep-widgets.sh` after touching a widget body, a component or
   the registry. Both run against this tree; the sweep starts its own
   compositor and reports per tile.
2. **Commit + pull into the installed checkout** — edit here, `git commit`,
   then `git -C ~/.config/omarchy/plugins/t1nk33r.nothing-glass pull --ff-only
   local master` where `local` is a remote pointing at this clone. The shell's
   plugin watcher reloads on the file change (`Local plugin changed,
   reloading: <id>` in the journal), so edit→see is a few seconds with no
   restart. This is how the owner's own install is wired.
3. **A release** — `omarchy plugin update t1nk33r.nothing-glass` is what a
   user runs: it fetches the plugin's `origin`, fast-forwards, validates and
   rolls back on failure. It refuses to move past local changes, which is why
   the installed checkout must stay read-only. `omarchy-restart-shell` after
   either of the last two when something looks cached.

## The settings model

A widget body reads `plugin.settings.<key>` — 400 such reads across 41 files
in the two widget trees (count each with
`grep -rIo --include='*.qml' 'plugin\.settings\.' widgets widgets-nothing`).
`plugin` is an id, not a property: `WidgetHost.qml`
declares `Config { id: plugin }` so unqualified lookups from the loaded widget
document resolve through the Loader's parent-context chain.

Merge order, computed in `GlassSurface._mergedSettings()`:

1. `manifest.json` → `settings.defaults`
2. the plugin's `shell.json` entry — its `plugins[]` row, then whichever
   `bar.layout.<section>` holds it (normally only one of the two exists)
3. `~/.config/omarchy/nothing-glass-options.json` (`Options.qml`) — **last**,
   because the shell relocates its own entry and strips what was on it
   (`PORTING.md` item 29)

`WidgetHost._mergedSettings()` then lays that instance's own `settings`
override from the store on top, so two weather tiles can show two cities.
Values from sources 2 and 3 are coerced to the type of the matching default.

Instances live in `~/.config/omarchy/nothing-glass.json` (`Store.qml`), written
leading-edge and coalesced for 250 ms.

Five knobs used to be stored as integers scaled by 10 or 100 and are now plain
reals: `roundness` (7.5), `refractIOR` (1.7), `tintAlpha` (0.1),
`chromaStrength` (0.3), `specStrength` (0.7). Their schema type is `number`
with real `min`/`max`/`step`. `_adoptLegacyScaledKeys()` converts a config
written by an older build (`roundnessX10`, `refractIORx100`, `tintAlphaPct`,
`chromaStrengthPct`, `specStrengthPct`) at that single merge point — do not
teach read sites two spellings, and do not reintroduce scaled integers.

`realtimeRefraction` is in `settings.defaults` but deliberately not in
`settings.schema`: the backdrop is a still `Image` of the wallpaper file, so
re-capturing per frame costs GPU for no visual change.

### `bash tests/run.sh`

Run it after touching the manifest, the registry, a settings key or a
component directory. It is the only thing that catches these, and each check
came from a real bug:

1. `manifest.json`'s `settings.defaults` must match `GlassSurface.qml`'s
   `_fallbackDefaults` literal key-for-key and value-for-value. The
   duplication exists because the first `_mergedSettings()` pass runs before
   the manifest has loaded; the test is what keeps the two honest.
2. Every `plugin.settings.<key>` a widget reads must have a default —
   otherwise the binding is `undefined` at runtime.
3. `WidgetRegistry.qml` must not claim a drawing the tree does not ship, and
   no widget directory may be unreachable from a launcher group; `PluginId.qml`
   and the manifest must agree on the id; the legacy-store migration must stay
   guarded by `_mayAbsorb`.
4. Every `.qml` in `components/`, `components/nothing/` and each widget's
   `widget/` must be listed in that directory's `qmldir`.
5. Every key `WidgetFields.qml` offers must be a real setting.
6. `PrayerTimes`' rollover rules, headless through the `nowOverride` seam, if
   `qs` is on PATH (skipped otherwise). Never move the machine clock to test
   time-of-day code — it re-derives the whole schedule and the rollover rules
   are what is under test.
7. The calendar's no-backend state never draws an account path, across
   eight HOME / XDG_STATE_HOME / override spellings
   (`tests/eventsource-home-relative.sh`).
8. GeoClue stays off by default and an opt-out holds even mid-lookup
   (`tests/geolocation-optin.sh`, with the helper stubbed).
9. Weather requests are bounded and their answers cannot hang the shell:
   real `curl` against a local server must fail a stalled forecast at the
   deadline, cut an endless body off at the byte cap, reject a report whose
   "array" claims a trillion entries or whose fields are not numbers, apply
   a report that throws mid-render not at all (`_applyReport` restores every
   field `_render` writes - keep `_renderOutputs` in step with it), fail
   cleanly with no `curl` installed, treat a 0,0 geocode as not found, keep
   one request in flight across refreshes, and leave none behind a destroyed
   tile (`tests/weather-http.sh`).
10. Text from outside is drawn, never obeyed: the real weather header and
    calendar event card given `<img src="http://…">` in their strings must
    not fetch it, while an AutoText control in the same window must
    (`tests/untrusted-text.sh`).
11. Every `Text` and `Label` in the tree declares
    `textFormat: Text.PlainText` (static, section 4e). Qt's default,
    AutoText, obeys markup - and a calendar title, a track name, a peer's
    hostname or a city from a web service is markup someone else wrote. The
    Nothing primitives set it too.
12. `WeatherDataQs._renderOutputs` names exactly the properties the render
    path writes (static, section 4f), so a report that throws mid-render is
    rolled back whole.
13. Now Playing cover art never reaches Qt's loader raw. `components/CoverArt.qml`
    copies it first:
    - HTTPS only, including redirects, at most 3 redirects;
    - a 4 MiB cap and a 10 s deadline;
    - local files and `data:` URLs bounded too;
    - one fetch in flight;
    - copies in a 0700 directory under `$XDG_RUNTIME_DIR`, removed on teardown.

    Colour is sampled from a 64x64 grab, never from a `Canvas.loadImage` of the
    cover. `tests/cover-art.sh` covers these cases, against local HTTPS and
    HTTP servers and both real drawings:
    - an endless, stalled or oversize body;
    - `http` and a downgrade redirect;
    - `/dev/zero`, a FIFO and an oversize file;
    - superseding, destruction and no `curl`;
    - flip recovery;
    - flat RSS over 40 distinct covers.

    It needs `openssl`.
14. A setting never becomes an argument, and no child runs unbounded:
    - `tests/photo-folder.sh`: a `-delete` photo folder deletes nothing;
    - `tests/argv-hardening.sh`: Tailscale ping takes only a dotted quad,
      `notify-send` gets `--`, and a clock zone must be an IANA name;
    - `tests/child-deadlines.sh`: a hung `df`, `khal`, `codeburn` or `find`
      settles, recovers and leaves no child behind (`components/ChildBound.js`);
    - `tests/prayer-zone-state.sh`: the prayer helper writes nothing outside
      its own work directory.
15. File-backed JSON is refused past a per-source UTF-8 byte cap before
    `JSON.parse` (`components/JsonRead.js`, `tests/json-caps.sh`).
16. Wallpaper paths holding `#`, `?` or `%` load. The wallpaper poll pauses
    while the screen is not drawn, and the 16 ms second-hand sweep of every
    analog clock, in both drawings, stops while hidden (`tests/wallpaper.sh`,
    `tests/clock-visibility.sh`).
17. The IPC `option` and `set` verbs write only declared settings with finite,
    bounded values (`tests/settings-ipc.sh`). The store's own guards are in
    `tests/runtime-store.qml`:
    - clamped geometry, rows kept;
    - prototype keys dropped;
    - 16 KiB per-row settings and 256 rows;
    - a 4 MiB parse cap;
    - no writes while unreadable;
    - 0600 files, after a write and on load;
    - durable legacy absorption;
    - a 37-row layout loaded unchanged.

Checks 2 and 5 read a scan rather than a file, so both refuse an EMPTY one: a
`plugin.settings.<key>` grep or a `WidgetFields.qml` key table that comes back
with nothing fails the run and names the root or the file it looked in, because
an empty scan compares nothing against nothing and reports success. (Before
that guard the pipelines simply ended the script there under
`set -e`/`pipefail`, with no message at all — a stop a reader could mistake for
a crash rather than a finding.)

### `bash tests/sweep-widgets.sh`

The runtime half of the above. Everything run.sh checks is read off the files,
and all of it can pass while a tile renders as an empty square — which is what
a type that does not resolve does here (PORTING.md items 20-21). So this one
loads every type `WidgetRegistry.qml` offers, in every style `stylesFor()`
claims, at 192x192, through the same injected ids `WidgetHost.qml` gives a
widget (`plugin`, `theme`, `backdrop`, `nothing`), and then asserts **per
tile** that it loaded, that nothing Qt logged names its own files, and that its
pixels are neither blank nor one flat colour. The type list comes from the
registry itself, so a type registered wrongly is a row like any other — a row
that fails. The list does not come from `stylesFor()` unexamined, though: the
rows it produced are also compared against the pairs `WidgetRegistry.qml`'s own
table implies (`nothingOnly` → one style, `nothing: true` → both, else Liquid
Glass), because a style that quietly stops being offered renders fewer tiles
and every tile that is left still passes — a smaller green run, which is the
one answer this harness must not give. Disagreeing with the table fails the run
before the verdict is printed.

Run it after touching a widget body, a component, a `qmldir` or the registry.
It needs `qs`, `gamescope` and ImageMagick (`magick`), starts its own headless
compositor in its own `XDG_RUNTIME_DIR` and its own scratch `HOME`, and skips
rather than fails when a tool is missing. It finishes in well under a minute
and prints `PASS n / FAIL m` last, with each failure naming the tile, its size,
its measurements and the captured error.

## Per-widget QML conventions

Templates: `widgets/clock-digital/main.qml` (Liquid Glass) and
`widgets-nothing/clock-digital/main.qml` (Nothing).

- The root is a plain `Item { anchors.fill: parent }`. The host owns the
  window, the placement, the input mask and the backdrop; a widget draws.
- `WidgetHost.qml` injects four ids into the widget document: `plugin`
  (settings), `theme` (`systemBackground` + the Omarchy `palette`), `backdrop`
  (`backdrop.item`, the screen's wallpaper `Image`) and `nothing` (the NTheme,
  for the Nothing tree).
- Liquid Glass widget:
  `MacOSColors { styleMode: plugin.settings.styleMode; appearance: plugin.settings.appearance; systemBackground: theme.systemBackground; themePalette: theme.palette }`
  — semantic tokens only, never a hardcoded color, never an inline branch on
  `colors.isGlass` / `colors.isLight`. `themePalette` is required: without it
  style modes 2/3 silently fall back to the macOS palette.
- The standard glass block, values passed through unscaled:
  ```qml
  LiquidGlass {
      anchors.fill: parent
      wallpaperItem: backdrop.item
      radius: plugin.settings.cornerRadius
      roundness: plugin.settings.roundness
      refractThickness: plugin.settings.refractThickness
      refractIOR: plugin.settings.refractIOR
      refractScale: plugin.settings.refractScale
      tint: colors.glassTint
      tintAlpha: plugin.settings.tintAlpha
      chromaStrength: plugin.settings.chromaStrength
      specStrength: plugin.settings.specStrength
      blurRadius: plugin.settings.blurRadiusPx
      realtimeRefraction: plugin.settings.realtimeRefraction
  }
  ```
- Widget-specific components go in `widgets/<type>/widget/` with a `qmldir`
  (e.g. calendar's `TodayBadge.qml`, clock-digital's `TickRing.qml`).
- The shared tree is reached by a **relative directory import**, by depth,
  never by a symlink and never by a bare module name: `import "components"` in
  a root-level file, `import "../../components"` in `widgets/<type>/main.qml`,
  `import "../../../components"` in a widget's own `widget/` subdirectory.
  `Qt.resolvedUrl` paths follow the same rule — a widget that loads a face
  writes `Qt.resolvedUrl("../../fonts/barlow_semibold.ttf")`. A Loader's
  `source:` string is a path, not an import, and needs the dots too; a missed
  one is silent (PORTING.md item 1).
- A new setting is three edits, all required: `manifest.json`'s
  `settings.defaults`, its `settings.schema` entry, and `GlassSurface.qml`'s
  `_fallbackDefaults`. Add it to `WidgetFields.qml` if it should be editable
  per instance.

## LiquidGlass architecture (the key component)

`components/LiquidGlass.qml` + `components/shaders/liquidglass.frag` form the
backdrop of every Liquid Glass widget. Read both before touching either.

Pipeline:
1. `wallpaperItem` — supplied by the host, here `backdrop.item`: a hidden
   screen-sized `Image` of `~/.local/state/omarchy/current/background` living
   in the same layer surface as the widgets, so `mapToItem()` works. There is
   no compositor API for the live wallpaper and `ShaderEffectSource` cannot
   sample across windows, so each surface loads the same file the compositor
   does — see `Wallpaper.qml`'s header.
2. `crop.frag` maps wallpaper UV into widget-local UV.
3. Dual Kawase `kawase_down`/`kawase_up`, 1-6 levels driven by `blurRadius`
   (0 makes the chain inert and the glass shader samples the capture direct).
4. `liquidglass.frag` — Snell-on-a-dome edge refraction, chromatic dispersion,
   tint, corner specular, squircle silhouette mask.
5. Fallback `Rectangle` (flat tinted rounded rect) whenever `wallpaperItem` is
   null or zero-sized. `glass.active` switches between the two, so a flat
   uniform tile in a screenshot means the capture failed.

Important nuances:
- **`realtimeRefraction: false` by default.** `wallpaperTex.live` binds to it;
  a 16 ms `updateGeometry()` Timer and the width/height Connections
  `scheduleUpdate()` on move and resize, so a static wallpaper re-captures
  only on geometry change. `WidgetHost._refreshBackdrop()` additionally
  null-toggles `_backdropItem` when the wallpaper Image reaches `Ready`,
  because a `ShaderEffectSource` re-captures on `sourceItem` *identity*
  change only — that is what makes a wallpaper switch appear.
- **Mouse hover** is plumbed in as `mousePos` (widget UV) and `mouseFade`
  (0..1, 180 ms Behavior); only the corner specular reads it.
- **Uniforms mirror QML properties 1:1.** A new one means: property on
  `glass`, property on `glassShader`, entry in the shader's `uniform buf { }`,
  then `./build-shaders.sh`.
- **Solid mode** skips capture and refraction but keeps the silhouette and
  specular through the same shader, so the material still reads as macOS.

Shader specifics (`liquidglass.frag`):
- `sceneSDFAndNormal()` returns `vec3(d, nx, ny)` for the squircle. Fast paths
  for interior / straight edges skip `pow()`; only corner-wedge fragments pay
  the p-norm. `d` is normalized by the analytic gradient magnitude to stay
  unit-gradient at the 45° corner apex — otherwise the AA feather and the edge
  band visibly widen at the corners.
- Edge refraction uses `sinθI = (1-t)²` across the `refractThickness` band;
  the normal comes straight from `sceneSDFAndNormal`, no finite differences.
- Corner specular: a discrete-diagonal pick with a 2-way softmax over TL+BR
  vs TR+BL, so only one diagonal's two corners are ever lit. `restLight`
  parks the light at 1.2× the top-left corner offset and it blends toward the
  cursor on hover.

## MacOSColors token reference

`components/MacOSColors.qml` is the single source of truth for the Liquid
Glass palette. **Never hardcode a color or branch on `colors.isGlass` /
`colors.isLight` in widget code** — add a token here instead.

**Mode axes:**
- `styleMode`: 0 = Glass (shader), 1 = Solid (opaque), 2 = Solid following the
  Omarchy theme, 3 = Glass following the Omarchy theme
- `appearance`: 0 = Dark, 1 = Light, 2 = Follow system — ignored by the two
  theme modes, which take polarity from the theme
- `isGlass` (0 or 3) / `isSolid` (1 or 2) / `isThemed` (2 or 3) — derived
- `isLight` — in modes 0/1 always false in glass mode
  (`!isGlass && (appearance===1 || systemLight)`), so plain glass is always
  dark-on-dark. In a theme mode it is the luminance of
  `themePalette.background`, glass included.
- `themePalette` — `{ background, foreground, accent, urgent, surface }`, the
  Omarchy `Color` singleton passed through `plugin/Theme.qml` and injected as
  `theme.palette`. Null makes modes 2/3 fall back to the macOS palette.

**Core palette (solid mode, adapts light/dark):**
- `background`, `surface`, `surfaceAlt` — fill colors
- `labelPrimary/Secondary/Tertiary/Quaternary` — text hierarchy
- `separator` — divider lines
- `solidBackground`, `solidForeground` — opaque widget bg/fg

**Glass-aware tokens (use these in widgets):**
- `foreground` — white in glass, `solidForeground` in solid
- `glassTint`, `glassTintAlpha`, `glassFallbackOpacity` — passed to `LiquidGlass`
- `todayAccent` — white in glass, red in solid (calendar today badge)
- `punchOutText` — `true` in plain glass (destination-out canvas compositing
  for badge text)

**State ink** (an accent is a MEANING, not a shade — a metric tile reads one of
these instead of inventing a threshold colour of its own):
- `accentRed` — the fault ink, the one every threshold tile reaches for, and
  the colour `todayAccent` already resolves to in solid mode.
  `themePalette.urgent` in a theme mode, else Apple's red: `#FF3B30` dark,
  `#D70015` light.
- `accentAmber` — the warning step BETWEEN normal and fault: the Claude usage
  tiles' 50-79% band, the media-server tile's stale feed. Apple's systemOrange,
  `#FF9F0A` dark / `#FF9500` light, and deliberately not theme-aware — the
  Omarchy palette carries `urgent` and nothing between it and its accent, so
  there is no second key to read and a fixed amber is the honest form.
- `accentGreen` — the headroom ink: a live figure well clear of its limit (the
  Claude tiles' percentage under the warning band). Apple's systemGreen,
  `#30D158` dark, deepened to `#17803D` light, where the bright green measures
  under 3:1 on a pale panel and stops reading as a figure.

`actionGreen` / `actionOrange` below are NOT these — that pair is the timer's
button fills.

**Analog dial tokens** (never hardcode `#ffffff`/`#343436` for a clock plate):
- `dialPlate` — the disc the marks and hands sit on
- `dialPlateDay` / `dialPlateNight` — per-city day/night discs
- `dialMark` — the mark ink for a `dialPlate` disc, i.e. the end `dialPlate`
  took: the pick is made here, not in the widget
- `dialMarkDay` / `dialMarkNight` — text drawn on those discs
- `dialNumeralOpacity` / `dialHandOpacity` — how opaque a dial's numerals and
  its hands are drawn on that face: `0.85` / `0.92` in glass, `1.0` in solid

**Clock-face ink** (the faint static marks a face draws its content over, and
the big digits it draws them in):
- `dialTickOpacity` — an analog dial's perimeter ticks, flanking its hour marks
  and reading as part of the dial: `0.24` in glass, `0.30` in solid
- `tickRingOpacity` — a digital clock's sixty-tick ring, texture under the
  comet trail: `0.18` in glass, `0.30` in solid
- `readoutOpacity` — what a digital clock draws its OWN time in (`textQuiet`,
  0.55, in glass; full ink in solid) — its own token rather than
  `annotationOpacity`, because this is the tile's content and not a caption on it
- `rollingReadoutOpacity` — the rolling seconds cylinder (`test-timer`), one
  digit and nothing else on the face: `0.62` in glass, stopping at `0.92`
  rather than full ink in solid

**Annotation tokens:**
- `textQuiet` — the lowest opacity informative text may be drawn at (0.55)
- `annotationOpacity` — a secondary annotation's opacity on the widget's own
  face: `textQuiet` in glass, `1.0` in solid
- `citySecondaryOpacity` — the line under a city cell's primary (day word,
  DST diff): `0.85` in glass, `0.6` in solid, where it is a step down from its
  `1.0` primary rather than the glass face's softening

**Card tokens:**
- `cardBackground` — `#ffffff` dark modes, `#000000` light solid
- `cardBackgroundOpacity` — base opacity (0.10 dark, 0.08 light)
- `cardHoverOpacity` — hovered state (0.17 dark, 0.14 light)
- `cardPressOpacity` — pressed state (0.22 dark, 0.20 light)

**Timer action tokens:**
- `countdownText` — white in glass, orange `#FF8B00` in solid
- `actionGreen` / `actionOrange` — icon colors for solid mode buttons
- `actionGreenBg` / `actionOrangeBg` — button background (solid fill in glass,
  tinted in solid)
- `actionIconInk(stateColor)` — the ink for an icon on an action disc, i.e. on
  a fill of `actionGreenBg`/`actionOrangeBg`: `#ffffff` in glass, where the
  disc IS the action colour; the caller's own `actionGreen`-or-`actionOrange`
  in solid, where the disc is an 18% wash of it. A FUNCTION, not a property:
  the style arm is this file's and the state arm is the widget's, and a widget
  may not spell the style arm out itself
- `buttonIcon` — white in glass, `solidForeground` in solid (cancel/neutral)
- `cancelButtonBg` — semi-white in glass, semi-foreground in solid

**Weather / media tokens:** `weatherGradientTop/Bottom`, `weatherForeground`,
`weatherIconSet`, `weatherSeparator`, `weatherRangeBar*`, `musicSecondary`.

The Nothing style does not use this file at all: it reads the injected
`nothing` (`components/nothing/NTheme.qml`), whose surfaces, ink and accent
come from `accentColor`/`uiScale`, or from the live Omarchy theme when
`followTheme` is on.

## Timer / power conventions

- Do **not** gate a widget's Timers on `Qt.application.state === Qt.ApplicationActive`.
  These surfaces are never the focused application — `keyboardFocus: None` on
  a Bottom layer surface — so such a gate freezes the timer permanently. Gate
  on `visible` to sleep when hidden, or leave `running: true` for always-on
  clocks and tickers. The timer widget's countdown is driven off an absolute
  `targetTime` rather than a decrementing counter, which is what keeps it
  correct across dropped frames and suspend.
- For midnight rollovers, schedule a single-shot Timer at the next boundary
  instead of polling — `widgets/calendar/main.qml`'s `midnightTimer` +
  `scheduleNextMidnight()`.
- A face that only changes per minute gets a one-second watchdog that compares
  minute/hour/date and assigns only on change (`widgets/clock-digital/main.qml`),
  not a per-second property write.
- Heavy per-frame Canvas work precomputes geometry on property change — see
  `widgets/clock-digital/widget/TickRing.qml`'s `_rebuild()` tick-endpoint
  cache. Canvas does not repaint on a bound property change: mirror the value
  into a local property and call `requestPaint()` from its `onXxxChanged`.

## Adding a widget type

1. Create `widgets/<type>/main.qml` (and/or `widgets-nothing/<type>/main.qml`),
   copying the closest existing type. Start it with
   `import "../../components"` — a widget's own subcomponents beside it in
   `widget/` still use `import "widget"`.
2. Nothing else to link: there is no per-widget `components` symlink and no
   per-widget font/icon directory any more. A face is loaded with
   `Qt.resolvedUrl("../../fonts/<file>.ttf")`, an icon under `icons/` with
   `Qt.resolvedUrl("../../icons/…")`, and a Loader's `source:` needs the same
   `../../` prefix.
3. Register it in `WidgetRegistry.qml`: `label`, `hint`, a `group` that
   appears in `groups`, and `nothing: true` / `nothingOnly: true` for the
   styles it actually ships.
4. New settings: `manifest.json` (`settings.defaults` + `settings.schema`),
   `GlassSurface.qml`'s `_fallbackDefaults`, and `WidgetFields.qml` if the key
   is per-instance editable.
5. `widget/qmldir` must list every `.qml` beside it.
6. `bash tests/run.sh`, then `bash tests/sweep-widgets.sh` (it loads the new
   type in both styles and fails on an empty tile) — or iterate with
   `qs -n -p glass-dev.qml`.

## Wide-mode side panel layout

Calendar and timer switch to a side-panel layout when stretched wider than
2:1 (the Nothing drawings use their own 1.6:1 threshold against the three grid
presets). The pattern:

**Trigger condition:**
```qml
readonly property bool isWide: full.width >= full.height * 2
readonly property real wideGap: Math.round(full.height * 0.04)
```

**Structure:** `LiquidGlass` stays `anchors.fill: parent` (one backdrop for
the whole widget). The content splits into two sibling Items:

```
Item { id: leftPanel;  anchors { ...; right: rightPanel.left; rightMargin: wideGap } }
Item { id: rightPanel; width: isWide ? full.height : full.width; anchors.right: parent.right }
```

- `rightPanel` is always the original square content, sized `height × height`
  in wide mode.
- `leftPanel` is `visible: isWide`, fills the remaining width, and sets
  `clip: true`.
- Existing content is reparented via `parent: rightPanel` — its internal
  anchors keep working unchanged.

**Card component pattern (`widget/XxxCard.qml`):**
- Thin cards, compact padding. Height ≈ `fontSize * 2.8`, radius ≈ `height * 0.25`.
- Background: `colors.cardBackground` + `colors.cardBackgroundOpacity`, passed
  in as properties; never branch on `isGlass`/`isLight` inside a card.
- Hover/press: `colors.cardHoverOpacity`, `colors.cardPressOpacity`.
- A 3 px left vertical pill (`radius: 1.5`, full inner height, colored per
  entry) marks event/category cards; preset cards omit it.
- Font size derives from `full.height`, not width, to match the right panel.
- Scrollable lists use `ListView { clip: true }`; a `Column + Repeater` is
  only for very short fixed lists.

**Left panel sizing constants (scale from `full.height`):**
- `_margin`: `Math.round(full.height * 0.09)` — matches the right panel's grid margins
- `_cardSize`: `Math.round(full.height * 0.052)` — card text size
- `_cardSpacing`: `Math.round(full.height * 0.025)` — gap between cards

**Reference implementations:**
- `widgets/calendar/main.qml` + `widgets/calendar/widget/EventCard.qml`
- `widgets/timer/main.qml` + `widgets/timer/widget/PresetCard.qml`

## What the calendar widget does today

Month grid, today badge, midnight rollover, `firstDayOfWeek`, both layouts,
and the wide panel's three temporal groupings (today / this week / upcoming)
with their date formats and `eventType` pill colours — all intact.

`components/EventSource.qml` is the seam, and it has two backends, either of
them sufficient: `khal` when it is on `PATH`, and the watched document
`~/.local/state/omarchy/calendar-events.json` (the schema
`tmn73/omarchy-calendar` publishes; `events/CalendarEvents.js` adopts it
verbatim). Its `state` is exactly one of `no-backend` / `empty` / `stale` /
`ok`, and each drawing words its empty state from that without branching its
layout on it. The Liquid Glass drawing says "No calendar connected", "Calendar
may be out of date" or "Nothing scheduled" and adds `stateDetail` (the watched
path, or the sync age); the Nothing drawing says "No calendar connected",
"Calendar may be stale" or "Nothing scheduled" and prints no detail.
`stateDetail` is spelled from where the path came from (`~/.local/state/…` or
`$XDG_STATE_HOME/…`), never the resolved path, because it is drawn onto the
desktop — `tests/eventsource-home-relative.sh` holds that. Anything that returns
objects shaped like `EventCard.qml` renders — that is the whole contract.
Events are never shown in narrow mode.

## Plan numbers in comments

`PORTING.md` is the engineering record, and the code cites its items **by
number** — those numbers are frozen: never renumber an item, never reuse one,
append at the end. Plan numbers that appear in comments (e.g. "(plan 012)",
"plan 005 step 2") are **provenance from the private design record**: they date
a decision and have no public target, so do not try to resolve one. A comment
that needs the reader to go somewhere must point at a file in this repo.

## Agent skills

### Issue tracker

Issues live in GitHub Issues on `t1nk333r/t1nk33r.nothing-glass` — the only remote, so a plain `gh` resolves to it and no `-R` is needed.

### Triage labels

The five canonical roles, each label string equal to its name: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`.

### Domain docs

Single-context: one `CONTEXT.md` at the repo root, created lazily when terms or
decisions are actually resolved — do not scaffold one empty.
