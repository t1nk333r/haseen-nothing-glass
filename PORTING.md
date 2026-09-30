# Engineering notes — the Liquid Glass Quickshell plugin

**This tree was severed from its KDE Plasma upstream on 2026-09-10.** There is
no `packages/`, no `1-common/` and no `.plasmoid` build any more: the
repository root is the whole project — the runtime QML, `components/` (with
`components/shaders/`), `widgets/`, `widgets-nothing/`, `fonts/` and `icons/`
all sit in it, all real files, and the tree carries **no symlink at all**.
Item 31 records the cut and what it renamed.

What is left here is the record of what this codebase learned, in the order
it learned it. Other documents and commit messages cite these items **by
number**, so numbers are never reused and never reassigned — append at the
end.

Items marked **[HISTORICAL]** are the mechanical recipe that turned a Plasma
applet into a widget of this tree. Their input no longer exists, so nothing
new will ever go through them; they are kept because they explain why the
widget bodies look the way they do — 4-space indent, `anchors.fill: parent`
on the root element, a bare `backdrop.item`, `../fonts/X.ttf`. Everything
else on this page still binds what you write today.

## 1. Where files go

```
widgets/<type>/main.qml         # the widget body
widgets/<type>/widget/...       # its own subcomponents
```

`<type>` is the string that goes in `nothing-glass.json`'s `"type"` field and
in `WidgetRegistry.qml`'s `_entries` map (`clock-digital`, `calendar`,
`timer`, ...). `widgets-nothing/<type>/` is the same layout for the Nothing
drawing of the same type (item 20).

**A file reaches the shared tree with a relative directory import, by depth:**

| the file | what it writes |
|---|---|
| a root-level runtime file (`GlassSurface.qml`, `Service.qml`, …) | `import "components"` |
| `widgets/<type>/main.qml`, `widgets-nothing/<type>/main.qml` | `import "../../components"` |
| `widgets-nothing/weather/widget/WeatherHeader.qml` (the one depth-3 importer) | `import "../../../components/nothing"` |

`import "widget"` for a type's own subdirectory never changes.
`Qt.resolvedUrl` paths follow the same rule — a file that loads a face writes
`Qt.resolvedUrl("../../fonts/X.ttf")` — and a `Loader`'s `source:` string is a
**path, not an import**: it needs the same dots. A missed one is silent by
construction, because a widget that fails to load renders as an empty tile
with no error (items 20-21).

**Never add a symlink.** This tree used to hold itself together with a symlink
farm — `plugin/components -> ../components`, a `components -> ../../components`
in every widget type directory, per-widget font and icon links — because the
standalone `qs -p` harness treats the entry file's own directory as a sandboxed
config root and rejects any import string that textually contains `..`. The
flat root replaced the mechanism: the harness now runs at the root
(`qs -n -p glass-dev.qml`), where `import "components"` resolves as a real
sibling directory, and the widget trees use the dotted form above.
`omarchy-plugin-validate` refuses **any** symlink inside a plugin folder, so a
re-added one breaks `omarchy plugin add` as well.

There is no installer and nothing to copy: the repository root **is** the
plugin, and `omarchy plugin add` installs the checkout as it stands. Adding a
type is one directory — it is copied by definition, because it is already
there.

## 2. Imports

[HISTORICAL] Ported bodies dropped `org.kde.plasma.plasmoid`,
`org.kde.plasma.core` and `org.kde.kirigami`, and kept `QtQuick`,
`QtQuick.Layouts`, `QtQuick.Effects`. Nothing in this tree imports Plasma.

Order imports per house style, exactly:
`QtQuick` / `Qt.labs.*` / `QtQuick.Controls` / `QtQuick.Layouts` /
`Quickshell` / `Quickshell.Io` / `qs.Commons` / `qs.Ui` / then local
(`"components"`, `"widget"`).

**Indent**: widget bodies under `widgets/` and `widgets-nothing/` carry a
**4-space** indent, inherited from the Plasma files they were copied from.
Keep it. Plugin-side QML (anything under ``) uses
the plugins' **2-space** style. Do not mix the two within one file.

## 3. Root element [HISTORICAL, one live rule]

A widget body's root element is a plain `Item` with `anchors.fill: parent`.
**That anchor line is load-bearing and applies to anything written today**:
`WidgetHost.qml`'s `Loader` has an explicit size (it fills the host Item,
which is sized from the store entry's `w`/`h`), and per Qt's `Loader`
semantics a `Loader` with an explicit size does **not** auto-resize the item
it loads — the loaded root must fill itself, or it renders at its implicit
(usually 0×0) size.

The rest of this item is the record of how the Plasma originals got there:

```qml
PlasmoidItem {
    id: root
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation
    ...
    fullRepresentation: Item {
        id: full
        Layout.preferredWidth: ...
        Layout.minimumWidth: 160
        Layout.minimumHeight: 160
        ...
    }
}
```

became

```qml
Item {
    id: full
    anchors.fill: parent
    ...
}
```

Three things happened at once, not just a rename:

- The outer `PlasmoidItem` wrapper disappeared — everything inside
  `fullRepresentation: Item { id: full ... }` became the file's only root
  element, still `id: full`.
- `anchors.fill: parent` was **added**; it was never in the original, because
  Plasma's containment sized `fullRepresentation` through the `Layout.*`
  attached properties instead. See the live rule above.
- `preferredRepresentation` / `fullRepresentation` went away entirely — the
  host (`WidgetHost.qml`) owns sizing, and there is no compact/full
  representation switch anywhere in this tree.

## 4. Delete, do not shim [HISTORICAL]

Two Plasma attached properties were deleted outright rather than emulated,
and no Quickshell equivalent was invented for either:

- **`Plasmoid.backgroundHints`** (16 uses across the fleet) — meaningless
  without a Plasma applet background.
- **`Plasmoid.formFactor`** (11 uses) — only the weather panel genuinely
  needed a form-factor branch, and that one became the bar widget's
  `vertical` / `barSize` (item 14).

## 5. The three ids a widget body reads

A widget body reads settings as `plugin.settings.<key>` — bare, no `host.`
qualifier. `WidgetHost.qml` supplies it by declaring `Config { id: plugin }`
as a QML **id**, not merely a property: the widget is a separate document
loaded through `Loader.source`, and only ids (and true context properties)
fall through a Loader's parent-context chain for unqualified lookups. A
plain property would only be reachable as `host.plugin`, which no widget
body writes. There are 413 such reads across the 47 `.qml` files of the tree
(400 of them across the 41 files of the two widget trees, which is the figure
`AGENTS.md`'s settings section quotes — count each with
`grep -rIo --include='*.qml' 'plugin\.settings\.'`); they were spelled
`plasmoid.configuration.<key>` until the severance (item 31).

The same trick carries two more ids, and a widget may use all three without
declaring anything:

- **`theme`** — `systemBackground` and the Omarchy `palette`, forwarded from
  `GlassSurface.qml`/`Service.qml`. It stands in for the
  `Kirigami.Theme.backgroundColor` a Plasma body used to read (item 10).
- **`backdrop`** — a `QtObject` whose `item` is the screen's shared
  `Wallpaper.qml` Image, injected as `injectedBackdrop`. A body writes
  `wallpaperItem: backdrop.item` on its `LiquidGlass` and
  declares no backdrop of its own. (On Plasma each body declared its own
  `PlasmaBackdrop { id: backdrop }`; that component imported Plasma and did
  not come across, so the host supplies the same name instead — which is why
  the line itself never had to change.)

`WidgetHost.qml`'s `_refreshBackdrop()` nulls and re-sets that `item`
whenever `injectedBackdrop.status` becomes `Image.Ready`, once per instance,
because a `ShaderEffectSource` re-captures only on a sourceItem *identity*
change — not when the Image it already points at finishes loading or swaps
pixels. That covers both the first paint and every later wallpaper switch.

The same host also supplies that Image *blurred*, once per screen, for the
Nothing style's frosted card: `GlassSurface.qml`'s `FrostLayer` blurs the
same wallpaper beside it and hands its output to every host as
`injectedFrost`, which `NTheme.frostSource` exposes. Nothing owns that pass —
see item 20 — and a Nothing card reads neither `backdrop.item` nor
`frostSource` itself: `NCard` does, through the injected `nothing` object.

A Nothing body gets a fourth id, `nothing` (NTheme), and must not touch
`MacOSColors` or `LiquidGlass` — see item 20.

## 6. `Layout.*` → plain sizing

- `Layout.minimumWidth` / `Layout.minimumHeight` live in
  `WidgetRegistry.qml`'s entry for the type (`minWidth`/`minHeight`), where
  `Placement.qml`'s resize clamp reads them:
  ```qml
  clock-digital: { path: "widgets/clock-digital/main.qml", minWidth: 160, minHeight: 160 }
  ```
- `Layout.preferredWidth` / `Layout.preferredHeight` are dropped entirely —
  the host sets `width`/`height` on the `WidgetHost` Item from the store
  entry's `w`/`h`, and the body's root `anchors.fill: parent` (item 3)
  follows that.
- Wide-mode side-panel logic (`readonly property bool isWide: full.width >=
  full.height * 2` and its kin) needs no change — it reads
  `full.width`/`full.height`, which the store entry drives instead of a
  Plasma containment. The comparison is the same.

## 7. `Kirigami.Units.*` [HISTORICAL]

84 uses fleet-wide, almost all in Plasma config UIs, which did not come
across at all. In widget **bodies** each was replaced with the literal value
it resolves to at the default scale, or with `Style.space(n)` from `qs.Ui`
where that module was already imported:

| Kirigami unit | Literal value |
|---|---|
| `Kirigami.Units.smallSpacing` | `4` |
| `Kirigami.Units.largeSpacing` | `8` |

## 8. `i18n("...")` [HISTORICAL]

There is no Plasma i18n here, so every `i18n("Some string")` became the bare
string `"Some string"`. Nothing in this tree is translated; the strings are
literals in the QML.

## 9. Fonts

```qml
FontLoader {
    id: barlowSemiBold
    source: Qt.resolvedUrl("../../fonts/barlow_semibold.ttf")
}
```

resolves against **`fonts/`** at the repo root. The dotted path is the whole
mechanism: a widget body at `widgets/<type>/main.qml` writes `../../fonts/X.ttf`,
and `components/nothing/NTheme.qml` writes the same, because both sit two
levels below the root. There is no per-widget font directory and no symlink any
more (item 1); `fonts/` is a real directory beside the widget trees, and the
installed plugin has the same bytes because the checkout *is* the plugin.

Three files load the Barlow faces, all of them with that `../../fonts/` form:
`components/nothing/NTheme.qml` (both cuts) and the two digital clocks
(`widgets/clock-digital/main.qml`, `widgets/city-digital/main.qml`).

`icons/` works the same way: `icons/weather/` holds the three condition sets
that the weather widgets name with `../../../icons/…` from
`widgets/weather/widget/`, and `widgets/now-playing/icons/` holds that
widget's own SVGs directly.

**Name the face through the token, never through a loader.** A body reads
`colors.uiFont` (Liquid Glass) or `theme.sans` / `theme.sansBold` / `theme.mono`
(Nothing). Naming a `FontLoader`'s `.name` at a call site is the pattern the
system-font mode replaced, and since the four Apple faces were removed
(`fonts/LICENSES.md`) it is not even available to a glass widget: there is no
glass `FontLoader` left, and `colors.uiFont` is the fontconfig alias `omarchy
font set` writes, with no second face under it to switch to. A body that keeps
a loader for a deliberate face of its own is the two digital clocks, whose
digit face is Barlow. That alias resolves to `sans-serif` for words and
`monospace` for readouts; the Nothing style's `theme.sans` / `theme.sansBold`
still choose between Barlow and the same alias.

**A text that elides or fits needs an explicit `width`.** Without one
`width == implicitWidth == contentWidth`, the item always "fits", and both
`elide` and `fontSizeMode: Text.HorizontalFit` are inert — measured: a
200.8 px string in a 150 px box still painted 200.8 px. Give the text a box
from its parent (or anchors), *then* the rule. `elide` on its own is not a
rule, it is a hope.

**Never size a layout from an estimate of a face's advance width.** The
"~0.55em per character" constants are right for the bundled face and wrong
by construction in system-font mode, where the desktop's own face is
1.54–1.69x wider: the tailscale node map boxed every hostname from that
constant and elided all nine. Measure with a `TextMetrics` on the face that
will draw it — `font.family: theme.sans`, the same `pixelSize`, and
`font.letterSpacing`, plus `.toUpperCase()` if the text is drawn with
`Font.AllUppercase`, since `TextMetrics` capitalises nothing itself — and
floor the result with `Math.max(estimate, advanceWidth)` so a measurement
can only widen a box, never re-solve a layout that already ships.
`advanceWidth` is readable in the same statement that sets `text` (0.0 for
`""`), so no change signal is needed.

**The dot-matrix displays have no font.** `components/nothing/dots.js` is a
5x7 table of `0`/`1` and `NDotMatrix` paints `Rectangle`s from it; `dot`/
`gap` come from `theme.px()` or `fitWidth`/`fitHeight`. No elide, no fit and
no family applies to one, in either mode.

## 10. The glass binding block

Every Liquid Glass widget carries this block, and they are all the same. Copy
it from a neighbour (`widgets/clock-digital/main.qml:48-66`):

```qml
LiquidGlass {
    id: glass
    anchors.fill: parent
    wallpaperItem: backdrop.item   // resolved by WidgetHost.qml's backdrop id, item 5
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
    fallbackOpacity: colors.glassFallbackOpacity
    solidMode: colors.isSolid
    solidColor: colors.solidBackground
}
```

Five of those reads used to divide by 10 or 100. They do not any more — item
31 says why, and what an old config does.

Likewise the `MacOSColors { id: colors; ... }` block stays local to the
widget file — `systemBackground: theme.systemBackground` reads the `theme`
id `WidgetHost.qml` provides (item 5).

**`realtimeRefraction: plugin.settings.realtimeRefraction` stays in every
Liquid Glass binding block, but does NOT get a `settings.schema` entry in
`manifest.json`.** It lives in `settings.defaults` only (`false`, see
`manifest.json`'s `settings.notes.realtimeRefraction`) — needed purely so
the read above isn't `undefined`. On Plasma it mattered because the backdrop
could be a live wallpaper item; here it toggles `wallpaperTex.live` against a
still `Image` loaded from a file, so `true` re-captures identical pixels
every frame — pure GPU cost, zero visual difference. Wallpaper *file*
switches are handled by `WidgetHost.qml`'s `_backdropItem` null-toggle on
`Image.Ready` (item 5), not by this flag. Do not "helpfully" add a
`settings.schema` entry for it.

## 11. The verification loop

```
omarchy plugin update t1nk33r.nothing-glass  # or: git -C ~/.config/omarchy/plugins/t1nk33r.nothing-glass pull --ff-only local master
omarchy-restart-shell
journalctl -t omarchy-shell -f      # watch for QML errors while the next command runs
omarchy-shell t1nk33r.nothing-glass add <type> <screen>
```

`<screen>` is a `ShellScreen.name` (e.g. `HDMI-A-1`) — `hyprctl monitors`
lists connected screens if unsure. Confirm the new instance renders, then
exercise its config overrides with `omarchy-shell t1nk33r.nothing-glass set
<id> <key> <valueJson>` and its geometry with `move`/`resize`.

**`omarchy-restart-shell` is not optional after an edit** (plan 009 finding).
The inotify watcher on `~/.config/omarchy/plugins/` reloads the plugin when
the checkout changes — a `pull` into it, or `omarchy plugin update` — and that
is enough to see *new* files; but the running shell can keep serving a
**cached compilation of a file you just changed**. Observed concretely: a
`Font.Regular` → `Font.Normal` fix was deployed (`sed -n '183p'` on the
installed file showed the new line, and the file contained zero occurrences of
the old value), yet every fresh instance kept logging `main.qml[183]: Unable to
assign [undefined] to int` until a full `omarchy-restart-shell`, after which it
was silent.

**Separately — and this one was a real bug, now fixed:** a widget removed via
IPC came back in `nothing-glass.json` with its pre-move geometry, twice. Cause:
`Store.qml` debounces writes by 250 ms, and the plugin hot-reload (or a shell
restart) destroys the `Store` — and its pending `Timer` — before the write
lands. The next `Store` instance then loads the stale file. `Store.qml` now
flushes synchronously in `Component.onDestruction` (`FileView.blockWrites`),
so a mutation issued right before a reload is no longer lost. The earlier
attribution of this to compile staleness was wrong.

Practical rule: hot-reload is fine for *looking* at a change; restart the
shell before you *conclude* anything from a log line.

## 12. Config entries

For a **desktop widget type**, a per-widget setting goes in
`manifest.json`'s top-level `settings.schema` (array) and `settings.defaults`
(object) — **not** anywhere per-widget-type; there is no per-type schema,
only the sparse per-instance `settings` override object in
`nothing-glass.json` (see Store.qml). For a **bar-widget** setting, declare
`barWidget.schema` / `barWidget.defaults` per item 14 — and, because this is
a dual-kind plugin with ONE `shell.json` entry where the non-empty general
schema wins the settings UI (CONVENTIONS.md, "A dual-kind plugin has exactly
ONE entry"), also expose any operator-editable bar key in the general schema
and keep the two defaults identical.

Schema types are `integer`, `number`, `boolean`, `string` and `enum`, and an
enum's `options` are **`{ "label", "value" }` objects with numeric values** —
plain-string options make the settings UI write the label back into a field
the widgets compare against a number. A fractional value is a `number` with
real `min`/`max`/`step`; it is not scaled to an integer (item 31). Note that
both the settings UI's Dropdown and `omarchy bar set` (without `--json`)
deliver **strings**; `GlassSurface._mergedSettings()` coerces each override
to the type of its manifest default, so widgets can keep their strict
`=== 1` comparisons. Only add a schema entry a widget actually reads.

`plugin/tests/run.sh` cross-checks `manifest.json`'s `settings.defaults`
against `GlassSurface.qml`'s `_fallbackDefaults` literal and fails on drift,
and separately fails if any `plugin.settings.<key>` a widget reads has no
default. Update both places together. `WidgetHost.qml` needs no per-key
change: it merges whatever `pluginSettings` it was handed with the
instance's own `settings` override.

## 13. Timezone-aware clocks (plan 007 finding)

**`Date.prototype.toLocaleString`'s `timeZone` option is unusable in this
Qt/QML JS engine — `Intl` is entirely undefined.** Do not build any
timezone-aware code on `toLocaleString`, `Intl.DateTimeFormat`, or anything
else under the `Intl` namespace; it will silently no-op rather than throw in
most call shapes.

Evidence, gathered via `qs -n -p <probe>.qml` (Quickshell 0.3.1, Qt 6.11.2)
against ground truth from `TZ=<zone> date`, with the operator's own zone
(`Asia/Riyadh`, UTC+3, no DST) as a control and `Asia/Kolkata` (half-hour),
`Australia/Adelaide` (half-hour + southern DST), `America/New_York` and
`Europe/London` (northern DST) as the zones a naive implementation would get
wrong:

- `new Date().toLocaleString("en-US", { timeZone: tz, ... })`, run once for
  "now" and once each for explicit `Date.UTC(2026, 0, 15, 12, 0, 0)` (Jan,
  northern winter / southern summer) and `Date.UTC(2026, 6, 15, 12, 0, 0)`
  (Jul, northern summer / southern winter), returned the **exact same local
  wall-clock string for every zone**, including the control — i.e. the
  `timeZone` option was silently ignored across the board, not just on the
  half-hour/DST zones:
  ```
  === NOW ===
  Asia/Riyadh -> 9/2/26 10:19 AM
  Asia/Kolkata -> 9/2/26 10:19 AM
  Australia/Adelaide -> 9/2/26 10:19 AM
  America/New_York -> 9/2/26 10:19 AM
  Europe/London -> 9/2/26 10:19 AM
  === JAN 15 2026 12:00 UTC ===
  (all five zones) -> 1/15/26 3:00 PM
  === JUL 15 2026 12:00 UTC ===
  (all five zones) -> 7/15/26 3:00 PM
  ```
  Ground truth (`date`, same instants) was, respectively: Riyadh 15:00/15:00
  (control, matches by coincidence), Kolkata 17:30 both, Adelaide 22:30 (Jan,
  ACDT +10:30) / 21:30 (Jul, ACST +09:30), New York 07:00 (Jan, EST) / 08:00
  (Jul, EDT), London 12:00 (Jan, GMT) / 13:00 (Jul, BST). Only the Riyadh
  control happened to line up, because the JS engine was quietly formatting
  everything in the *system* zone regardless of the `timeZone` argument — the
  exact "passes in Riyadh every day of the year, wrong everywhere else"
  failure mode called out in plan 007.
- A second probe confirmed the root cause directly: `typeof Intl` is
  `"undefined"`, and touching `Intl.DateTimeFormat` throws
  `ReferenceError: Intl is not defined`. This Qt build's QML JS engine was
  compiled/configured without ECMA-402 (`Intl`) support.

**Chosen backend: the `Quickshell.Io.Process` fallback**, exactly as plan 007
step 1 prescribes for this outcome — shell out to `date` under `TZ=<zone>`
and let the system tzdata do the DST/half-hour math; never a static offset
table. Verified working and DST-correct, one `Process` per zone in parallel,
matching ground truth exactly for all five zones (`env TZ=<zone> date
'+%Y-%m-%d %H:%M %Z %z'`):
```
PROC Asia/Riyadh -> 2026-09-02 10:20 +03 +0300
PROC Asia/Kolkata -> 2026-09-02 12:50 IST +0530
PROC Australia/Adelaide -> 2026-09-02 16:50 ACST +0930
PROC America/New_York -> 2026-09-02 03:20 EDT -0400
PROC Europe/London -> 2026-09-02 08:20 BST +0100
```

`TzClock.qml` uses this: a `Process` running `date "+%Z %z"` under
`TZ=<zone>` resolves the zone's current UTC offset (minutes), cached and
refreshed hourly (plus once on creation); the displayed `dateTime` is then
computed locally every second/minute from `Date.now()` plus the cached
offset delta versus the system's own offset — no per-tick subprocess. This
keeps subprocess cost to one short-lived process per configured city per
hour, which plan 007 judged acceptable for a handful of cities.

Whoever revisits this should re-run the
`Intl`/`toLocaleString` probe rather than trust this conclusion — it is a
property of the Qt build, and a future Qt/Quickshell upgrade could add
`Intl` support.

## 14. The bar widget (plan 008 finding)

The plugin's second entry point is `plugin/BarWidget.qml` — not a
`widgets/<type>/` desktop instance. It began as the port of the one Plasma
*panel* applet, `weather-panel`, and is now the control panel. Everything
below was verified live against Omarchy 4.x / Quickshell 0.3.1.

**Manifest.** Add `"bar-widget"` to `kinds`, `"barWidget": "BarWidget.qml"`
to `entryPoints`, and a `barWidget` object with `displayName`, `description`,
`category`, `allowMultiple`, `defaultSection` (`left|center|right` — anything
else makes `PluginRegistry` reject the whole manifest), plus `defaults` and
`schema`. One plugin may hold both `service` and `bar-widget`: the two loader
loops in `shell.qml` (:326-333 and :673-717) are independent.

**The widget file.** Root element is `BarWidget` from `qs.Ui`, in a file that
may itself be called `BarWidget.qml` (the explicit module import wins over the
implicit directory import; `t1nk33r.omarr` does the same). The bar injects
exactly three properties — `bar`, `moduleName`, `settings`
(`plugins/bar/Bar.qml:1770-1776`) — and nothing else: no `plugin`, `theme`
or `backdrop` id (item 5), so none of items 3-10 above apply.

**Form factor is the one Plasma branch that survived.** `Plasmoid.formFactor`
(item 4 deleted it everywhere else) maps onto the base class's `vertical`
/ `barSize`. Note the asymmetry: on a vertical bar the host slot **forces**
width to `barSize` and honours only `implicitHeight`
(`Bar.qml:1581-1584`), so lay out with `WidgetButton`'s `fixedWidth` on a
horizontal bar and `fixedHeight` on a vertical one. `WidgetButton` also hides
itself unless `hasVisualContent` is true — set it explicitly when the button
carries custom content instead of `text`.

**Settings** come from `setting(key, fallback)`, never from the desktop
widgets' `plugin.settings`, and land in the plugin's single `shell.json`
entry — a dual-kind plugin has exactly ONE entry. Because that entry moves
into `bar.layout.<section>` the
moment the widget is placed, `GlassSurface.qml`'s `_mergedSettings()` reads
both `plugins[]` and the bar layout; keep that if you add a second bar widget.

**Injection is late, and that breaks naive fetch-on-load code.** Plasma had
every config value final before `Component.onCompleted`.
The bar assigns `settings` one step *after* the item is constructed, so a
widget that starts a network request from a config-derived binding will fire
one request with fallback values and another with the real ones — and the
response that lands last wins. `WeatherDataQs.qml` solves this with a
monotonic `_reqSeq` guard (stale responses dropped) plus `Qt.callLater`
coalescing of the config-changed handlers; copy that shape for any future
widget that fetches. Symptom if you skip it: the bar widget shows the
fallback config after every shell restart, and only corrects itself when a
setting is touched.

**Popup.** A panel applet's `fullRepresentation` maps onto `PopupCard` from
`qs.Ui` (`anchorItem`/`bar`/`owner`/`open` + content children). Define
`open()`, `close()`, `toggle()` and an `opened` property on the widget root:
`PopupCard.close()` calls `owner.close()` on an outside click, and the bar's
popout coordinator (`Bar.qml:316-322`) closes whichever popout is open when
another widget opens one.

**Verification loop** (no `add`/`move` IPC here — that is the desktop side):
```
omarchy plugin disable t1nk33r.nothing-glass && omarchy plugin enable t1nk33r.nothing-glass right
omarchy bar set t1nk33r.nothing-glass <key> <value> [--json]
omarchy bar position left     # exercise the vertical path, then restore
```

## 15. Quickshell MPRIS (plan 010 finding)

`Quickshell.Services.Mpris` replaces Plasma's `Mpris2Model`. The mapping the
now-playing widget's port settled on (the type was called `music` until it was
renamed), all verified against live players:

| Plasma `Mpris2Model` player | Quickshell `MprisPlayer` |
|---|---|
| `track` / `artist` / `album` / `artUrl` | `trackTitle` / `trackArtist` / `trackAlbum` / `trackArtUrl` |
| `playbackStatus === Mpris.PlaybackStatus.Playing` | `isPlaying` (bool) |
| `PlayPause()` / `Next()` / `Previous()` / `Play()` / `Pause()` | `togglePlaying()` / `next()` / `previous()` / `play()` / `pause()` |
| `Seek(offsetUs)` | `seek(offsetSeconds)` — it exists (`quickshell-service-mpris.qmltypes:499`); guard on `canSeek`, **not** `positionSupported` |
| `position` / `length` in **microseconds** | **seconds** (measured: `1958.915` vs the bus's `1958915000`); convert once at the data layer |
| `currentPlayer` + rows from 1 | no current player: scan `Mpris.players.values` **from index 0** |

Two runtime facts: `Mpris.players` is empty for the first ~0.5–1 s of a
session while D-Bus discovery runs, so the selection must be a binding, never
a one-shot read; and the player's own `positionChanged` must override local
extrapolation (a `Connections` on the active player), or an external seek
leaves the slider wrong until the next state change.

## 15. Grid sizes, theme palette, and the tokens a new widget must use

Three things every newly ported widget has to honour; all three were added on
2026-09-06 and are enforced by nothing but review.

1. **It will only ever be given three sizes.** `WidgetRegistry.qml` owns the
   grid (88 px cell, 16 px gutter) and the presets small 2×2 = 192×192,
   medium 4×2 = 400×192, large 4×4 = 400×400. Both the resize drag and the
   control panel choose among those, so a widget must look right at exactly
   those three and nothing in between. Its `minWidth`/`minHeight` in the
   registry MUST fit inside 192×192, or the small size silently disappears
   for that type. Check the widget's own aspect-ratio branches against 1:1
   and 2.08:1 before assuming a layout applies.

2. **It must pass the theme palette.** Next to the usual
   `systemBackground: theme.systemBackground`, add
   `themePalette: theme.palette`. Without it `styleMode` 2/3 ("follow theme")
   silently fall back to the macOS palette for that widget alone, which looks
   like a half-themed desktop.

3. **No polarity literals.** Ported Plasma code carries `#1A1B1E`,
   `#343436`, `#ffffff` for opaque fills and clock plates plus a local
   `_realLight` to choose between them. Replace them with
   `colors.solidBackground` and the `dialPlate` / `dialPlateDay` /
   `dialPlateNight` / `dialMarkDay` / `dialMarkNight` tokens; they reproduce
   the old values exactly in modes 0/1 and are the only reason a theme mode
   works. Four widgets shipped with these literals and stayed dark under a
   light theme until they were converted.

## 16. There is no calendar event source on this machine (plan 011 phase A)

Surveyed 2026-09-06, with commands, so nobody has to guess again:

| Looked for | Result |
|---|---|
| `khal`, `vdirsyncer`, `calcurse`, `gcalcli` | none installed (`command -v` for each) |
| `~/.config/vdirsyncer`, `~/.local/share/vdirsyncer`, `~/.config/khal`, `~/.local/share/calendars`, `~/.calendars` | none exist |
| Evolution data server / Akonadi | not installed, no `~/.config/akonadi`, no `~/.local/share/evolution` |
| `.ics` on disk (`find ~ -maxdepth 5 -name '*.ics'`) | one downloaded invitation in `~/.local/share/Trash` - not a store |
| Quickshell 0.3.1 services (`/usr/lib/qt6/qml/Quickshell/Services/`) | Greetd, Mpris, Notifications, Pam, Pipewire, Polkit, SystemTray, UPower. No calendar. |
| Omarchy plugins with event/task data | `t1nk33r.todoist` is `kinds: ["bar-widget"]` and its state dir holds only `settings.json` (an API token) - nothing cached for others |

So the options were: **A** ship without events (S), **B** read local `.ics`
(M, needs an RRULE-capable parser, and there is no `.ics` store to read),
**C** shell out to a calendar CLI (M, but none is installed), **D** a CalDAV
client in QML (L+, a separate project).

**Option A shipped**, and item 35 (plan 020) is the seam it shipped as and the
one document that seam now reads. `components/EventSource.qml` exposes
`eventsForDate(date)` returning objects with `EventDataDecorator`'s field
names and an `eventsChanged()` signal. On this machine it still returns an
empty array - and now it says WHY, which the old form could not: no backend is
`state: "no-backend"`, not the same words as a quiet week. Item 35 has the
contract; this item is the survey behind it, and the survey still stands.
Re-checked 2026-09-15 (plan 020 step 1), with the commands:

| Looked for | Result |
|---|---|
| `khal`, `vdirsyncer`, `calcurse`, `remind`, `todoman`, `gcalcli`, `dcal` | none installed (`command -v` for each: no output, exit 1) |
| `~/.local/state/omarchy/calendar-events.json` | does not exist (`ls -l` fails with "No such file or directory") |
| `~/.local/share/calendars` | does not exist |
| `git status --porcelain` in the repo | empty |

## 17. The prayer widget is not a port - it borrows another plugin's engine

`widgets/prayer/` has no Plasma original. It reproduces the prayer card on
this machine's lock screen (`t1nk33r.lock/LockView.qml:144-233`): a progress
ring with the md-mosque glyph (U+F1827, past U+FFFF so
`String.fromCodePoint`, and only the Nerd Font families carry it - name the
family explicitly), the next athan's time, and the next prayer's name with
the following one under it. It adds a countdown and two larger layouts.

Data (`components/PrayerTimes.qml`):

- `t1nk33r.omaprayers` computes prayer times offline - `Engine.js` is an
  adhan-js port in plain ES5 and `prayer-zone.sh` builds a 70-day IANA
  offset table from `date`/`zdump`. No network, no API key.
- It cannot be *asked* for them: `kinds: ["bar-widget"]` only, so
  `shell.serviceFor()` is null, its IpcHandler exposes open/close/toggle/
  refresh plus a prose `status()`, and the schedule never leaves its
  Panel.qml. Nothing is cached on disk. Same shape as the weather finding.
- So `Engine.js` + `prayer-zone.sh` are vendored under
  `components/prayers/` (MIT, Salem Sayed - `LICENSE.omaprayers` sits with
  them) and fed the operator's own omaprayers entry from `shell.json`. One
  source of truth for location, method, language and time format.
- `Engine.buildSchedule(config, zone, nowMs)` wants the `expectedConfig`
  shape from `omaprayers/Panel.qml:74-87`; `timings[Name]` is
  `{ at: ISO-with-offset, time: "HH:MM" }`.
- The lock screen is a THIRD implementation: it shells out to
  `python3 ~/.config/waybar/scripts/prayer-times.py`, which does not exist on
  this machine, which is why that card shows `--:--`. Do not wire anything to
  it.

## 18. Coordinates, and why "GPS" is not a thing here

`components/GeoLocation.qml` is the one place a widget asks where it is:
GeoClue2 first, then the operator's prayer coordinates from `shell.json`,
then Omarchy's `weather.json`, then the caller's own setting. `source` names
the winner and nothing ever renders blank.

GeoClue2 is installed on this machine and still cannot produce a fix: every
`url=` provider in `/etc/geoclue/geoclue.conf` is commented out, so the
service accepts the D-Bus connection and immediately drops it (the stock
`where-am-i` demo reports "Remote peer disconnected"). Enabling it means a
root edit AND sending nearby Wi-Fi BSSIDs to a third party. The script
(`geo/geoclue-fix.sh`, gdbus - Quickshell 0.3.1 has no generic D-Bus client)
therefore treats failure as ordinary and prints
`{"ok":false,"error":"..."}`; uncomment a provider later and it starts
working with no code change.

Two traps found building the first consumer:
- A widget that feeds coordinates INTO `PrayerTimes` must expect them late:
  GeoLocation has to read shell.json and try geoclue first. The schedule
  built from the fallback never corrected itself, so the sunrise tile showed
  New York's sunrise rendered in Riyadh's timezone (1:29 PM) while its own
  footer said Riyadh. `PrayerTimes` now rebuilds on any override change,
  debounced.
- Sun times must describe the CURRENT civil day even after Isha, when the
  prayer rows roll over to tomorrow - otherwise "sunrise" after midnight
  points at tomorrow's while the clock says tonight.

## 19. The lock screen is a second consumer of these components

`t1nk33r.lock` renders `components/PrayerCard.qml` over its own
`LiquidGlass`, from copies under `t1nk33r.lock/glass/` (QML cannot import
across plugin directories). `sync-lock-card.sh` refreshes those copies, and
**it has no automatic caller any more** — the materialiser that used to invoke
it is gone with the flattening, so run it by hand when the card changes:

```
./sync-lock-card.sh
```

- changing `PrayerCard.qml`, `PrayerTimes.qml`, `MacOSColors.qml`,
  `LiquidGlass.qml` or the shaders reaches the lock screen on the next
  `sync-lock-card.sh` — not on `omarchy plugin update`, which knows nothing
  about that other plugin;
- editing `t1nk33r.lock/glass/*` by hand does NOT survive that;
- `PrayerTimes.qml` sits one directory deeper there, so the mirror rewrites
  its two relative paths to `prayers/` on the way in;
- the script no-ops when the lock plugin is not installed.

## 20. Two styles, one plugin, one runtime

Both presentations ship in ONE Omarchy plugin, `t1nk33r.nothing-glass`. The
style is a property of a WIDGET, not of a plugin. (It was briefly a second
plugin; item 30 records why that was undone.)

```
<root>/*.qml           the runtime, at the repo root
widgets/<t>/          Liquid Glass presentation of type <t>
widgets-nothing/<t>/  Nothing presentation of the same type
PluginId.qml          the identity, and the only place it is spelled
```

`PluginId.qml` carries `id`, `label`, `styles` and `styleLabel(style)`, plus
the derived `storeName` and layer `namespace`. **No other file may spell a
plugin id, a store filename or a namespace out.** It is checked:
`tests/run.sh` fails when `PluginId.qml` and `manifest.json` disagree about
the id.

Which file draws an instance is resolved in three steps, first hit wins:

1. the widget's own `style` field in the store - the Style row in the
   right-click sheet, or the same row in the browser's inspector; empty
   means "not pinned";
2. its CATEGORY's style - the `categoryStyles` map, keyed by the registry
   `group` name, set by the Categories rows in the browser's Appearance
   pane;
3. the plugin-wide `widgetStyle` default.

`GlassSurface.styleForEntry(entry)` IS that resolution and the only copy of
it; `WidgetHost` is handed the answer rather than working it out.
`registry.urlFor(type, style)` then picks the file and falls back to the
presentation the type does have - a style is a preference, not a contract,
and a desktop must not lose a widget because a second drawing has not been
made yet. `registry.stylesFor(type)` is what a UI offers, and it has three
arms: `["nothing"]` for an entry flagged `nothingOnly` - a flag no entry sets
today - `["liquid-glass", "nothing"]` for one flagged `nothing: true`, which is
every user-facing type in the table, and `["liquid-glass"]` for one carrying
neither flag, which is the three `Dev` tiles (`placeholder`, `test-glass`,
`test-timer`).

Consequences worth knowing before you touch this:

- **One store.** `~/.config/omarchy/nothing-glass.json`, one writer, and
  `style` is a reserved COLUMN on a widget row rather than a key inside its
  `settings{}`: `store.set(id, "style", "nothing")` writes it and `""`
  deletes it. A leftover `~/.config/omarchy/nothing.json` from the split is
  absorbed once as `style: "nothing"` rows and renamed `.migrated`.
- **The registry hides nothing.** `hasType`/`listTypes`/`typesInGroup` are
  style-blind, so every type can be added and named; the style is chosen
  afterwards. `stylesFor(type)` is the one a UI asks: it answers with the
  styles this type is actually drawn in, in menu order.
- **A widget file still knows nothing about any of this.** Same
  `plugin.settings` keys as its twin, same data component, same three
  tile sizes. See the rules below.

Rules for writing a Nothing presentation:

- Read the SAME `plugin.settings` keys as the Liquid Glass twin. There
  is one settings schema, so a key means the same thing in both drawings.
- Reuse the twin's data component. Two fetches or two timers for one number
  is the failure mode two drawings of one widget invite.
- Style from the injected `nothing` object (NTheme) only. Never import
  `MacOSColors` or `LiquidGlass` in a Nothing widget, and never
  `import qs.Ui` (see item 3).
- **The wallpaper is host-supplied, and a Nothing-owned pass may blur it.**
  The rule above bans the glass *style*, not GPU work: `backdrop.item` (item
  5) is the screen's own `Wallpaper` Image, so `plugin/FrostLayer.qml` blurs
  it once per screen and `components/nothing/NFrost.qml` +
  `components/shaders/nfrost.frag` crop that blur under each level-0 card.
  That is why a Nothing card can be frosted at all — the compositor's
  wallpaper is in another window and `ShaderEffectSource` cannot sample across
  windows, so "blur what is behind" is impossible. What the ban still means,
  and what must not drift: no `MacOSColors`, no `LiquidGlass`, no `qs.Ui`, no
  reading or reusing `liquidglass.frag` — no refraction, no chromatic
  dispersion, no specular pair, no `roundness` 7.5 squircle, and above all no
  `tint`/`tintAlpha` — `NFrost` carries the style's own `surface` (rgb =
  `surfaceSolid`, a = how much of the backdrop that colour covers, i.e.
  `surfaceAlpha`) and the pass's own `frost`, and the two COMPOSE into one
  material: `backdrop = mix(nothing, blurred wallpaper, frost)`, then
  `material = mix(backdrop, surface, surface.a)`. Neither knob can annihilate
  the other — the surface covers its share of the card at every frost, the
  wallpaper is behind it at every `surfaceAlpha`, and `frost` 0 is the matte
  card at any opacity (no shader is instantiated then). `NFrost`'s silhouette
  is the same plain rounded rect at `NTheme.rCard` that `NCard` draws. Deleting
  the glass style still cannot break a Nothing widget: the two share
  `Wallpaper`, `theme` and `Store` — host plumbing — and the Kawase kernels,
  which are pure GLSL with no glass semantics. `Dual Kawase`'s pyramid is also
  *copied* from `LiquidGlass.qml` as a pattern, not imported from it.
  It is a desktop material by construction: a launcher preview, the sweep
  harness and the launcher's own sheet have no wallpaper behind them, hand
  the card a null `frostSource`, and draw the matte card — documented, not a
  bug to fix.
- Handle 192x192, 400x192 and 400x400 explicitly.

`followTheme` (plugin-wide, default off) makes NTheme take surfaces, ink and
accent from the live Omarchy theme instead of the stock matte-black palette
and the red accent; `accentColor` and `uiScale` are the other two knobs. All
three are in the launcher's Appearance pane.

**A setting written for a plugin that has no `plugins[]` entry yet needs
`mutateShellConfig`, not `updateEntryInline`.** The shell's
`updateEntryInline` only edits an entry it can already find (shell.qml:366)
and returns false otherwise; enabling a plugin does not create one. The first
write from a freshly enabled plugin appeared to work and changed nothing on
disk until `GlassSurface.setPluginSetting` learned to create the row.

## 21. A directory of QML types needs a `qmldir`

`components/` and `components/nothing/` each carry a generated `qmldir` listing
every type. This is not decoration.

A directory with no `qmldir` is an *implicit* directory that Quickshell's QML
scanner registers lazily, and the first type looked up before the directory is
registered fails with `<T> is not a type` - which type varies from run to run.
Observed as `NBadge is not a type` in one run and `BatteryData` /
`WorldClockQs` / `EventSource` / `PrayerTimes` / `Notify` in the next, each in
a different widget, with a silent empty tile as the only symptom on the
desktop. (The blast radius used to be larger: the old rsync installer
dereferenced the symlink farm into one copy of `components/` per widget
directory - 53 copies of the same tree, each registered lazily on its own. The
flat root has exactly one, beside the files that import it; the registration
rule did not change.)

**Adding a component or a primitive means adding its line to that directory's
`qmldir`.** `tests/run.sh` fails if a `.qml` file in either directory is
missing from it.

## 22. The store writes on the leading edge, synchronously

`Store.qml` used to debounce writes on the trailing edge only (250 ms) and
rely on `Component.onDestruction` to flush a pending one. That net has a hole:
**a signalled process runs no QML destructor**, and `omarchy-restart-shell`
signals (`quickshell kill`), as does every hot-reload of the installed
checkout. Reproduced with a scratch store - add a widget, `SIGTERM` 150 ms
later, and the widget is simply not in the file. It ate two resizes during
deploys before it was found.

Now: the first mutation after a quiet moment writes **immediately and
blocking** (`FileView.blockWrites`), and mutations inside the next 250 ms
coalesce into one trailing write. A burst of ten mutations still costs two
writes; a single one is on disk before the call returns.

The second half of the same bug: a reload that lands mid-burst used to
overwrite newer in-memory state with the older document, and the next flush
persisted that. Our own write triggers the file watch, so the replayed reload
arrives exactly then - `add` followed immediately by `set`/`move`/`resize` kept
only the `add`. `_applyText` now ignores a reload while `_revision !==
_writtenRevision`; an external edit made while the store is idle is still
adopted, which is checked by a harness alongside the burst case.

If you add a mutation function, route it through `_scheduleWrite()` - it is
what bumps `_revision`. A write that bypasses it will be silently reverted by
the next reload.

## 23. The photos widget takes a folder

`photos` declares three per-instance settings - `photoFolder`,
`photoIntervalSec`, `photoShuffle` - in `manifest.json`, `_fallbackDefaults`
and `WidgetFields.forType("photos")`, which is the three-place rule every
setting follows.

`photoFolder` accepts an absolute path or `~/…`; empty means
`$XDG_PICTURES_DIR`, then `~/Pictures`. `PhotoData._expand()` does the tilde
and trailing-slash handling, because that is what people type, and
`folderLabel` is the short form a widget shows in its empty state. The rescan
is driven by `on_DirChanged`, not `onFolderChanged`, so `~/Pictures` and
`/home/you/Pictures/` do not rescan for nothing.

Ways to set it: right-click the widget (Folder field), the bar panel's
per-widget rows, or
`omarchy-shell t1nk33r.nothing-glass set <id> photoFolder '"~/Wallpapers"'` - the
value is JSON, hence the quotes inside quotes.

## 24. Storage picks its own filesystems; the photo follows the card

`storage` takes `storageMounts` - a comma-separated list of mount points, in
the order they should appear; empty means every real filesystem, biggest
first. That default is also the discovery mechanism: the unfiltered list names
the exact strings to type.

The filter is a **binding on the parsed rows**, not a condition inside the
parse. `StorageData.allEntries` holds everything `df` reported and `entries`
derives the chosen subset, so editing the field re-filters on the spot. When
it filtered at parse time the change appeared to do nothing until the next
`df` up to a minute later - two tiles configured seconds apart disagreed,
which is how it was caught. A named mount `df` never reports (a typo, or a
drive that is not mounted) shows as `No such mount: <name>` rather than an
empty tile.

`photos` masks its picture with a rounded rectangle whose radius is the
card's minus the inset - the concentric radius, so the two curves are
parallel. `clip: true` cannot do this (Item clipping is rectangular), so the
frame is a layer with a `MultiEffect` mask over a hidden `Rectangle`; the mask
covers the caption strip too, so its bottom corners follow the same curve.

## 25. Tailscale: the plugin next door is not a backend, and the socket is no longer ours

`t1nk33r.tailscale` is installed and enabled here, and it is useless to us for
the same reason the weather and prayer plugins were (item 17): its manifest
declares `kinds: ["bar-widget"]` only, so `shell.serviceFor("t1nk33r.tailscale")`
is null and its `Service.qml` is a private child of its own Panel. Nothing in
`components/TailscaleData.qml` depends on it being installed. Its `Model.js`
is not vendored either: its peer projection omits exactly the fields the
drawings read (`CurAddr`, `Relay`, `Active`, `RxBytes`, `TxBytes`), so a
vendored copy would be edited beyond recognition; its model filters and sorts
the way the next paragraph rejects; and it carries no per-file licence header,
so copying it into a GPL-3.0 tree means filing an MIT attribution for code we
would rewrite anyway. The first-party dependency is a data-path and cadence
decision, not a file dependency.

**The source is the `tailscale` CLI**, three one-shot reads:

| what it feeds | command |
|---|---|
| peers, self, exit nodes, `up`/`loaded` | `tailscale status --json` |
| serve / funnel state | `tailscale serve status --json` |
| `relayName` / `homeRelayName` | `tailscale debug derp-map` |

Those documents are byte-equivalent to the LocalAPI documents this file used to
read over `/run/tailscale/tailscaled.sock` — same top-level, `Self` and `Peer`
key sets and the same values on every field the drawings read; `serve status
--json` is the serve-config document modulo pretty-printing; `debug derp-map`
is the derp-map document after key sorting. The socket is no longer ours to
assume: the CLI is the interface `tailscale` supports, and it is the one a
machine without a world-readable socket still has. `debug derp-map` says "not a
stable interface" in its own help, which is why it is read **once**, only when
the region map is empty, with the raw region code as the fallback
(`_regionName` already returns the code when the map is empty).

**Polling, not a push stream.** `intervalMs` stays 30000 — the same 30 s the
official plugin uses — plus a 2 s startup ramp that stops after the first
status settles or ~30 s (15 ticks). Without the ramp a shell restart would
show "Checking" for up to 30 s, where the old doorbell stream answered
immediately; the ramp is what the stream was buying. All of
`watch-ipn-bus?mask=6`, `watchProc`, `_settle` and `_revive` is gone.

**Reads are bounded by a supervisor, not by `--max-time`.** A failing `tailscale`
invocation takes ~5.1 s to exit 1 (measured with `--socket=/tmp/nope.sock`
against all three commands), so a 4 s wrapper would truncate a legitimate slow
call. Instead a 1 s repeating supervisor — running while `active`, and checking
all five processes (`which`, `status`, `serve`, `derp`, `ping`) — holds every
read to 15 s counted from *its own* launch: a read launched inside another
read's window gets its own full bound instead of inheriting what is left of an
earlier deadline and being killed while it is still working. At the bound the
supervisor discards that run's result and sends SIGTERM (`running = false`);
3 s later the same read is escalated to SIGKILL, so a read that ignores SIGTERM
cannot live on as a process every later poll has to step around. The failure
strings it can leave: a hung read the supervisor reaped is
`errorMessage = "tailscale did not answer"`, a CLI that exited non-zero is
`"tailscaled not reachable"`, and a machine without the CLI gets `"tailscale
not installed"` behind a `which tailscale` probe. Both drawings test only
`errorMessage !== ""` and then draw it, and `stateLabel` maps any non-empty
message to "Unavailable", so the `which` string is safe and strictly more
informative.

**`Online` is not `Active`.** A peer is `Online` when it is up on the tailnet
and `Active` only when there is a live WireGuard session. Most peers are online
and idle; that is the resting state of a tailnet, and a view that paints it as
a fault is lying. `direct` only means anything while `active` — for an idle
peer `Relay` is merely its home DERP region, not a live path.

**The divergences from the first-party model are deliberate.** Its `Model.js`
filters to online peers, drops Mullvad peers and sorts alphabetically; this
file keeps every peer (online and offline), keeps `active` distinct from
`online`, and sorts `active desc, online desc, name asc`. The tiles' leading
nodes and the node map's first slots are chosen by that sort, and the drawings
read `online` and `active` independently — adopting the first-party model would
visibly reorder the tiles and silently hide offline peers. That is a product
decision, not an oversight.

Deliberately absent: `netcheck` (1.2-2 s) and per-peer `tailscale ping`
(side-effectful - it nudges path discovery). `ping()` is unchanged and already
the CLI path (`tailscale ping -c 1 --timeout 3s <ip>`, one at a time, refresh
after); `netcheck` stays on-demand only, never in a poll loop. The widget is
strictly read-only: no `up`/`down`/`set`/`switch`.

## 26. The plugin's ONE shell.json entry can live in two places

A plugin id appears in `shell.json` EITHER inside `bar.layout.<section>`
(placed - the bar icon renders and the `-panel` IPC target exists) OR in
`plugins[]` (un-placed). Never both. Its settings ride on whichever entry
exists, which is why `GlassSurface._mergedSettings()` reads both.

**Anything that writes a setting must look in both too.** An earlier
`setPluginSetting()` searched only `plugins[]`. On this machine the entry sat
in `bar.layout.right`, so the first write from the launcher found nothing,
pushed a fresh `plugins[]` row, and left the id in two places at once: the bar
icon went un-placed, the `-panel` target disappeared with it, and the settings
that had been on the bar entry - `styleMode: 2` among them - stopped being
read, so every glass widget silently fell back to plain Glass. Two symptoms,
one cause, and neither of them looks like a config writer at first glance.

`_findEntryAnywhere()` is the fix, and it re-checks inside the
`mutateShellConfig` callback as well, because the config a binding read may be
a frame old.

Corollary for the UI: a plugin-wide setting must be reachable from somewhere
that is NOT the bar panel, because the bar entry can be un-placed (item 34).
The Liquid Glass style axis now lives in the launcher's Appearance
pane as well as the panel.

## 27. An offscreen harness cannot judge solid mode

`LiquidGlass` renders solid mode through the same `.qsb` shader as glass mode
(the fallback Rectangle is glass-only, by design - see its comment). Under
`QT_QPA_PLATFORM=offscreen` that shader does not run, so a solid-mode widget
grabs as EMPTY while a glass-mode one still shows its fallback rect. That is a
harness artifact, not a bug: the same widget at `styleMode: 1/2` renders a
proper opaque card on the real desktop. Verify solid mode with `grim`, never
with `grabToImage` offscreen.

## 28. A PLACED bar widget cannot reach its own service

When this plugin's shell.json entry sits in `bar.layout.<section>`, the shell
hands `BarWidget.qml` the facade built by `pluginShellForBarEntry()`
(shell.qml:706-729). That facade carries `_summon`, `_hide`, `_toggle`,
`_isOpen` and `_updateSettings` - and **no `_serviceLookup`**, so
`bar.shell.serviceFor(moduleName)` returns null forever. Not a race, not a
startup ordering problem: by construction. Instrumented and confirmed on this
machine (`shell=yes fn=true got=null`, every retry, indefinitely).

Un-placed (entry in `plugins[]`) the widget gets `pluginShellFor()` instead,
with `allowOwnService: true`, and the same code finds the service - which is
why the panel's widget list worked for weeks and then "broke" the moment the
entry went back into the bar.

Consequences the panel now lives with:

- The widget list, Add, and the Browse button are shown only when the service
  is reachable; placed, the panel says so and gives the command instead.
- Any retry loop must be BOUNDED. A binding that re-asks twice a second for
  the life of the session is a heartbeat with no pulse; ten tries covers the
  un-placed startup race and then stops.
- **A plugin-wide setting must therefore be reachable somewhere other than the
  bar panel.** The style axis is in the launcher's Appearance pane for exactly
  this reason, and per-widget settings are a right-click away on the widget.

Writing settings still works while placed - `_updateSettings` is in the
facade - which is why the STYLE buttons in the panel keep working when the
list next to them cannot load.

## 29. A service cannot read its own settings, and shell.json will not keep them

Two separate facts, both measured on 2026-09-09, that between them broke every
plugin-wide setting this port has.

**Reading.** A service-kind plugin is injected `omarchyPath`, `shell`,
`manifest`, `barWidgetRegistry` and `pluginRegistry` (shell.qml:929-932) and
nothing else. The scoped facade it gets has no `shellConfig` and no `settings`
- only the BAR-WIDGET entry point is handed a live `settings` object. So
`root.shell.shellConfig` was null on every evaluation,
`_mergedSettings()` returned pure defaults, and no user setting had ever
reached a widget: `styleMode` stayed Glass whatever the panel wrote.
Instrumented (`shell=yes cfgObj=no`) rather than guessed. `GlassSurface` now
reads `~/.config/omarchy/shell.json` itself through a FileView.

Trap inside the trap: that FileView must be a TYPED PROPERTY, not a bare
child. This file's root is `Variants`, whose default property is the delegate,
so a loose `FileView { }` is swallowed and never loads (`cfgLoaded=no`,
forever). Same shape `Store.qml` uses for its own children.

**Keeping.** The shell relocates and STRIPS the entry. Observed: entry in
`bar.layout.right` carrying `styleMode: 2` -> shell restart -> entry back in
`plugins[]` as `{ id }` alone. The style the user picked was gone by the next
restart. `omarchy bar set <id> <key> <value>` also silently no-ops for a
plugin that is not placed (it prints success and writes nothing), and
`omarchy bar put` will not place a dual-kind plugin at all.

So plugin-wide settings live in `Options.qml` -> `~/.config/omarchy/
<name>-options.json`, a file this plugin owns, and the merge order is:

    manifest defaults  <  shell.json entry  <  our options file

shell.json is still read (so the Omarchy settings UI keeps working) and still
written when the entry exists (so it shows the same value), but ours is the
copy that survives. Verified: set Solid, restart the shell, still Solid.

**Use the plugin's own verb, not the bar CLI:**

    omarchy-shell t1nk33r.nothing-glass option styleMode 2
    omarchy-shell t1nk33r.nothing-glass option followTheme true
    omarchy-shell t1nk33r.nothing-glass option widgetStyle nothing


## 30. Why the two-plugin split was undone

The Nothing style shipped briefly as a SECOND plugin, `t1nk33r.nothing`,
generated from a copy of this runtime by `4-nothing/install.sh` (that
directory and that plugin are both gone). QML cannot import across plugin
directories, which is what made a copy look like the cheap answer. It was
not. What it cost:

- **Two bar entries and two panels.** Each plugin is its own `shell.json`
  entry with its own bar icon and its own control panel, so the desktop had
  two places to add a widget and two lists that each showed half of what was
  on screen.
- **Two stores.** `liquidglass.json` and `nothing.json`, with ids that
  collided across them (both held a `tailscale-2` on this machine), plus a
  cross-Service "Move to …" operation whose entire purpose was to change how
  one tile is drawn.
- **Two of every setting.** One schema, two copies on disk: `styleMode` set
  on one plugin said nothing about the other, and the knobs that are
  genuinely plugin-wide had to be edited twice to mean one thing.
- **The second plugin could not keep its bar icon.** Both plugins are
  dual-kind (`service` + `bar-widget`), and `omarchy bar put` refuses to
  place a dual-kind plugin at all; the shell also relocates and strips the
  entry on startup, so it came back un-placed (item 29's "Keeping", and item
  28 for what placed vs un-placed changes). Un-placed means no icon - the
  second plugin was reachable only by IPC or through the first one's
  launcher.

All of that to express ONE axis on ONE widget. So: one plugin, one bar entry,
one store, one options file, and the style resolved per instance - the
widget's own `style`, then its category's, then the plugin-wide
`widgetStyle` (item 20). Nothing about a widget FILE changed; only who
chooses which file runs.

## 31. The fork was cut from Plasma, 2026-09-10

`packages/` (16 Plasma applets), `1-common/`, the root `install.sh`,
`package.sh`, `test.reload.sh` and `translate/` were deleted. What used to be
symlinks into `1-common/` are real files: `components/`
(including `components/shaders/`), `fonts/` and
`icons/`. `build-shaders.sh` compiles
`components/shaders/*.frag`. `git log` still has the Plasma
tree; the working tree does not.

**Why anything changed beyond deleting files.** Two constructs existed only
to keep merges from an upstream clean, and paid for themselves as long as
that upstream was live:

- the **`plasmoid` shim** — the host declared its config object as
  `id: plasmoid` so a widget body's `plasmoid.configuration.X` reads could
  come across a Plasma file byte for byte;
- the **kcfg integer scaling** — five fractional values were stored as
  integers scaled by 10 or 100 and divided back at every read site, because
  Plasma's kcfg could only hold `Int`.

With the fork cut there is nothing to merge from. Both were cost with no
benefit: a name that lies about what runs, and arithmetic in 97 bindings
working around a constraint of a config system this tree does not use.

**New spellings.** A widget body reads `plugin.settings.<key>` — 288 reads
across 30 files. `plugin/Config.qml` exposes `settings`, not `configuration`.
`WidgetHost.qml`, `GlassSurface.qml` and `WidgetPreview.qml` declare
`id: plugin`, not `id: plasmoid`. `_mergedConfiguration()` is
`_mergedSettings()` and the property carrying the plugin-wide merge into a
host is `pluginSettings`.

**The five keys.** Each is now a schema `number` with a real `min`/`max`/`step`
and a real default:

| Was | Is | Default was | Default is |
|---|---|---|---|
| `roundnessX10` | `roundness` | `75` | `7.5` |
| `refractIORx100` | `refractIOR` | `170` | `1.7` |
| `tintAlphaPct` | `tintAlpha` | `10` | `0.1` |
| `chromaStrengthPct` | `chromaStrength` | `30` | `0.3` |
| `specStrengthPct` | `specStrength` | `70` | `0.7` |

The `/ 10` and `/ 100` at the read sites are gone with them.

**An old config still works.** `GlassSurface._adoptLegacyScaledKeys()` maps
each old key onto its new one, dividing by 10 or 100, at the single point
where manifest defaults, the `shell.json` entry and the options file are
merged — so the two spellings are reconciled once per merge rather than at
288 read sites. It is a no-op once no config carries an old key.

## 32. The panel's widget list, Remove and position editor go over the plugin's own IPC

Item 28 says a PLACED bar entry cannot reach its own service, and placed is
the state the entry is normally in. But the IPC target belongs to the
SERVICE, not to the bar entry: the target exists while the plugin is enabled
— placed, absorbed or un-placed (plan 021, measured). So the panel reads and
acts on the same list the CLI does, over `listWidgets` / `remove` / `move` —
the route `openLauncher()` already took for the browser, generalised to the
list. `setPluginSetting()` was already shaped this way ("the shell-out is the
COMMON branch"); the panel now has a list to go with it.

- **One Process, on demand.** `BarWidget.qml` holds a TYPED `property
  Process _listProc` — a bare child would be swallowed by this file's root,
  the trap in item 29 — with a `StdioCollector` as its `stdout` and
  `waitForEnd: true`, so the handler never parses half a document. It runs on
  panel open, on the Refresh button, and after `remove`/`move`. Never on an
  interval: a binding that re-asks is the heartbeat item 28 forbids. The
  un-placed case keeps the in-process store, which is live.
- **The CLI's failure contract.** `/usr/share/omarchy/bin/omarchy-shell`
  prints the handler's return string to stdout and exits 0; every IPC-level
  failure (`Target not found.`, `Function not found.`, a wrong argument count,
  `Not ready to accept queries yet`) goes to stderr with exit 1, as does a
  shell that does not answer inside `OMARCHY_SHELL_IPC_TIMEOUT` (2 s). Exit 0
  with parseable stdout is the only success case — so the parse keeps the
  LAST good list and sets an error string instead of throwing inside a signal
  handler, and a failed read never empties the panel.
- **The honest fallback stays.** When the IPC does not answer the panel
  prints the `omarchy-shell <id> launcher ''` command it used to print, rather
  than an empty list that would read as "there are no widgets".
- **What still needs the service.** Add needs `registry.listTypes()` and
  `defaultSize()`; the size presets need `registry.sizes()`; the per-widget
  field table needs `WidgetFields.save`, which writes through a `Store` — and
  clearing a field must REMOVE the override, which the `set` verb cannot
  express (there is no `unset`). All three are the same one-extra-verb-each
  change and stay un-placed-only for now; the panel simply does not draw
  them. `Reset` needs `registry.defaultSize()` and the screen insets for the
  same reason, so it stays a no-op while placed until it gets the same
  treatment.

## 33. Accessibility: what this platform exposes, and what it does not (plan 040)

The desktop can be driven without a mouse, and the parts that could not were
fixed rather than renamed. What was delivered:

- **Names on the icon-only controls.** The settings sheet's cog and close
  button, every launcher tile and the bar icon carry `Accessible.role`,
  `Accessible.name` and `Accessible.onPressAction`. The name is words, never
  the painted mark: the cog is "Open this widget in the browser", not `⚙`.
- **Keyboard reachability in the sheet.** A painted shape with a `MouseArea`
  cannot take focus, so the cog and the close button are `FocusScope`s with
  `activeFocusOnTab`; Tab walks onto them and Return/Enter/Space run what a
  click runs. The launcher needed nothing here: arrows move the tile
  selection, Tab cycles the rail's sections, Enter activates, Escape backs
  out one level, and the current tile and rail row are already marked in red.
- **A focus ring** on those two controls: 2 px of the style's own accent
  (`colors.accent` — never a literal), drawn around the mark, never on it.
- **Hit areas at WCAG 2.2's AA minimum (24×24).** The mark is painted 22×22
  and the *target* is not: the sheet's two controls are 28×44 and the
  browser's boolean switch is 44×44. Nothing about the painting moved, and
  the sheet's two targets tile exactly across the 6 px gap between them.
- **A contrast floor for quiet text.** Nothing's `onQuiet` — white at 0.48,
  `#808080` on `surface`, 5.0:1 — is the dimmest ink a `Text` may read;
  `onFaint` (1.93:1) is decoration and stays on the twenty dot grids, bars
  and marks that are meant to be unlit. Glass carries the same floor as
  `MacOSColors.textQuiet` (0.55), because glass text dims per site by
  opacity.

**Screen readers are unverified, and cannot be verified here.** Qt's bridge
has a bus to publish to — `at-spi2-core` is installed and
`at-spi-dbus-bus.service` is active — and the names above are attached and
reachable in the object tree, but no reader is installed (`command -v orca`
finds none), so what a layer-shell surface publishes through Quickshell is
unmeasured. Treat the names as declarations, not as an observed reader path.

**Reduced motion has a signal, and it is already used.** The compositor's
reduced motion preference is exposed by Hyprland's Qt Quick Controls style
as `HyprlandStyle.reduceMotion`; `components/MotionWatch.qml` reads it and the
analog clock consumes it behind a `Loader`, so a missing style module fails
open. There is no Wayland protocol and no Quickshell property for it (checked
against `quickshell-core.qmltypes`), which makes this the one path — a new
motion-heavy widget reads the same watch instead of inventing a second
mechanism. `NTheme`'s `fast`/`med`/`ease` are unconditional and still need a
per-widget gate.

**Two targets stay small by someone else's decision.** The bar icon is 27×26
because Omarchy's bar sets the slot it lives in (`Style.bar.iconSlot`);
raising it is a bar-wide change, not this plugin's. And in the browser Tab is
bound to section cycling — that is the launcher's keyboard model — so the
boolean switches there remain pointer-only even though their target is now
large enough for a thumb.

## 34. Reaching the widget browser when the bar icon is gone (plan 021, measured)

Item 26, item 32 and item 28 all describe the ONE `shell.json` entry
leaving the bar. Item 32 recorded that the IPC target survives it. This item
records the way IN when the icon is not there to click — measured on this host
2026-09-15, in all four states of that entry.

**The interface.** One verb, one required argument:

```
omarchy-shell t1nk33r.nothing-glass launcher <screen>   # "" = the monitor you are on
```

`<screen>` is a `ShellScreen.name`, `""` is resolved to the focused monitor when
the panel opens, and the SAME call closes the browser — a launcher you have to
reach for the mouse to close is half a launcher. `launcher()` is
`plugin/Service.qml:139`, reached through the `IpcHandler` at
`plugin/Service.qml:90-160` (`target: plugin.id`).

| the one entry | `launcher ''` | `listTypes` | `-panel` target | desktop widgets |
|---|---|---|---|---|
| placed — `bar.layout.right` | opens | 27 names | answers | drawn |
| un-placed — bare `plugins[]` row | opens | 27 names | `Target not found.` | drawn |
| absorbed — `t1nk33r.nook` | opens | 27 names | `Target not found.` | drawn |
| disabled — id nowhere | no target | `Target not found.` | `Target not found.` | gone |

Only "disabled" loses the verb, which is item 32's point: the target belongs to
the SERVICE, and a plugin is enabled by a bare `plugins[]` marker exactly as
much as by a `bar.layout` slot (`shell.qml:907` is the gate — `kinds` must
contain `service` and `entryPoints.service` must exist; nothing asks where the
entry sits). `omarchy plugin list` calls the first three states **disabled**,
because for a `bar-widget` kind `enabled` is `inBar(id)`
(`shell.qml:1665-1681`, `services/PluginRegistry.qml:189`) — that report is
about the ICON, never about whether the plugin is running. New since the plan
was written: the shell's OWN IPC reaches the same browser, gated the same way,
`omarchy-shell shell summon t1nk33r.nothing-glass '{"screen":""}'` → `ok`, and
it answers `unknown` for a disabled plugin. `listTypes` returns **27** names,
not the 24 the plan recorded.

**What the browser IS, when you check for it.** A `FloatingWindow` toplevel, not
a layer surface: `plugin/Panel.qml:109-111`, titled from
`PluginId.browserTitle` (`plugin/PluginId.qml:24`, "Nothing Glass" — also what
Hyprland's float/center/size rule matches on). So the check is `hyprctl clients
-j` for a client with that title (1100×800, floating, measured), and NEVER
`hyprctl layers` for a launcher namespace: that layer no longer exists, which is
why five of plan 021's seven verification gates could never pass. The only layer
this plugin owns is its desktop surface, `namespace: t1nk33r-nothing-glass`,
and that one is drawn in all three enabled states — it is not evidence of
anything about reachability.

**Why the icon leaves without the plugin stopping.** The mover is the drawer
next door, `t1nk33r.nook`, not the shell and not this plugin:
`bin/nook-offload:391-431` (its `absorb`) moves the entry into the drawer's
`items[]`, records the slot under `widgetOrigins`, and appends a BARE
`{"id": wid}` row to `plugins[]`. Nothing can opt out — `absorbableIds()`
(`~/.config/omarchy/plugins/t1nk33r.nook/LayoutModel.js:208-228`) excludes only
the drawer itself and the ids it already holds, and consults no manifest field,
no `kinds`, no callback. Measured with `--dry-run`, then for real.

**The two surfaces shipped, and what they cost.** Both end in the verb above, so
both outlive the icon. Neither is installed automatically any more — the
script that used to do it went with the flattening — so the README documents
them as two optional manual steps:

- **A desktop entry**, `nothing-glass-widgets.desktop` →
  `~/.local/share/applications/nothing-glass-widgets.desktop`. The menu reads
  that directory (Quickshell's `DesktopEntries.applications`,
  `shell/services/AppLibrary.qml`), so it is a row in the menu's app search
  (the entry is "Nothing Glass", sub-label *Apps*, beside the root row) and a
  `gtk-launch nothing-glass-widgets` away.
  `Exec=omarchy-shell t1nk33r.nothing-glass launcher ""`: the empty argument is
  REQUIRED (the verb takes one) and it does survive desktop-file quoting —
  measured, `gtk-launch` and `gio launch` both open the browser and neither
  prints "Too few arguments provided". No `Icon=`: the plugin ships no icon
  file, and a name the theme does not have is worse than none.
- **A keybind**, `SUPER + SHIFT + U` → "Nothing Glass widgets": a single
  `o.bind(...)` line the README tells the user to add to
  `~/.config/hypr/bindings.lua` by hand, then `hyprctl reload`; removing the
  line and reloading takes the key away.
  Measured with a real uinput press (`ydotool key 125:1 42:1 22:1 …`): the
  first press opened the browser, the second closed it, `hyprctl configerrors`
  stayed empty and `omarchy menu keybindings --print | grep -c '^SUPER SHIFT + U '`
  is 1. Note that `wtype -M logo -k u` does NOT fire it — virtual-keyboard
  events do not reach Hyprland's bind handling, which is a fact about the test
  tool, not the binding.

**Rejected, measured, and why.**

- **Notifications.** `omarchy-notification-send "Nothing Glass" "Click to open
  the widget browser" --exec omarchy-shell t1nk33r.nothing-glass launcher ""`
  exits 0 and shows nothing to click: `~/.local/state/omarchy/notifications.json`
  has `"dnd": true` on this host. A surface that is silent by the user's own
  setting is not a way in.
- **A row in the menu extension.** A row in
  `~/.config/omarchy/extensions/omarchy-menu.jsonc` is watched live
  (`plugins/menu/Menu.qml`): it appeared at the bottom of the root menu with no
  refresh, its aliases resolved (`omarchy menu summon widgets` and `… liquid`
  opened the browser just as `… nothing-glass` did), and activating it from the
  search opened the browser. It works, and it is still rejected: it edits a file
  the user owns to add one row, and buys nothing the desktop entry does not.
  Restored afterwards. Worth knowing if you test it: `omarchy menu summon
  <route>` answers `ok` for a route that does not exist, so its exit status
  checks nothing — the browser appearing is the whole signal.
- **A third `kind`.** Moot, and the reason is worth recording: the plan says do
  NOT add `menu`/`panel` to `kinds` because `shell.qml`'s
  `isBarWidgetPanelPlugin()` (`shell.qml:1138-1150`) routes a manifest that
  declares `panel` to the panel loader instead of the bar-widget one. That is
  exactly what shipped — `manifest.json` declares `kinds: [service, bar-widget,
  panel]` with `entryPoints.panel = Panel.qml` — and the panel route is the one
  the browser opens through. Both probes still discriminate: with the entry
  placed, `…-panel nosuchverb` → `Function not found.` (target there, verb
  unknown) where an absent target gives `Target not found.`

**The recommendation, as shipped.** The desktop entry (survives every bar state,
costs no key, findable by name) plus the opt-in keybind (one keystroke, at the
price of an edit to `bindings.lua`). The IPC verb is the thing that must never
break; both surfaces are only a way to type it. Nothing is pushed at the user
when the entry goes missing — DND is on here and the entry points cover it.

**Two things upstream and the drawer still get wrong, neither ours.**
`findEntryLocation` / `findBarLocation` (`services/PluginRegistry.qml:204-248`)
and `updateEntryInline` (`shell.qml:1078-1110`) never look inside a drawer
entry's `items[]`, so a hosted widget is reported "disabled", `omarchy bar put`
cannot move it (`PluginRegistry.qml:321-339`) and `omarchy bar set` fails
(`:342-383`) — the drawer's own `hostedSettings()` (`LayoutModel.js:112`)
exists to read around precisely that. And the drawer's absorb→eject round trip
is not positionally faithful: `eject` put the entry back at `bar.layout.right`
index 8 where it had been 5, because `untouched_index()`
(`bin/nook-offload:337-354`) records the index the widget held before ANY
absorption and `eject` applies it to the CURRENT array (`:470`), so a widget
restored out of a section that still holds other absorbed widgets lands shifted
right by their count. No key is lost — `styleMode`, `widgetStyle`, `followTheme`
and `systemFont` all survived a `jq -S` diff against the pre-absorb backup — but
the order moves, and that is the drawer's to fix.

**The documented repair is lossy, and that is the strongest argument for the
surfaces above.** item 28 tells the user to restore a lost icon with
`omarchy plugin disable && omarchy plugin enable`. Measured: `disable` splices
the entry out of `bar.layout` entirely (no `plugins[]` row, so the plugin really
does go down — `listTypes` → `Target not found.`, the desktop surface's layer is
gone), and `enable` puts back a BARE `{"id": …}` at the END of the section —
`styleMode: 2`, `widgetStyle: "nothing"`, `followTheme: true` and `systemFont`
were all silently dropped (`PluginRegistry.qml:526-537` builds `{ id: key }` and
splices it at `defaultBarWidgetSection`'s index). So the cure costs the user
their styling; `PORTING.md` item 26's writer fix and these two surfaces are what
make it unnecessary to reach for.

**Open questions, answered as the plan recommended.** The desktop entry belongs
in `~/.local/share/applications/`, where the menu actually looks. The keybind
is that same `o.bind(...)` line, added by hand from the README — nothing
installs it for the user any more; the script that did, with its marked block,
timestamped backup, printed removal line and `SKIP_KEYBIND=1`, went with the
flattening.
`SUPER + SHIFT + U` was free at plan time and is free now. The user is NOT told
when the entry is un-placed; the entry is NOT re-placed on startup (this plugin
cannot influence the drawer and would fight the user's choice); `GlassSurface`
is NOT taught to read a drawer's `items[]` (item 29 keeps the settings legible
without it); and no new `kind` is added.

**Maintenance.** A rename is NOT a two-spot edit. Beside `PluginId.qml` itself,
the id is spelled in code in `manifest.json` (`id` — the suite asserts
only that this one agrees with `PluginId.qml`), the shipped
`nothing-glass-widgets.desktop` (`Exec=`, above — and again in the README's
optional keybind block), and
`tests/run.sh`'s shell.json merge fixture (`GlassSurface.qml:135` matches
that entry by id, so a stale fixture fails the merge test rather than passing
quietly). Every one of those fails silently or confusingly: the `.desktop` and
the keybind cost the way IN with no error anywhere,
and `manifest.json` disagrees with `PluginId.qml` only where the suite happens
to look. The id also appears in prose — comments in `BarWidget.qml`,
`Service.qml`, `Store.qml` and `WidgetRegistry.qml`, this page, the READMEs and
the shell commands in them — where a missed rename costs nothing at runtime.
Deferred: a `.desktop` uninstall path, an `Icon=`, and drift detection.

## 35. The calendar seam, and the one document it reads (plan 020)

Item 16 is the survey: no calendar CLI, no CalDAV, no local store, nothing
cached by a neighbour plugin. This item is what plan 020 put behind
`components/EventSource.qml` once that was established - a SPIKE, so read it
as an interface and a probed seam, not as a promise that a calendar exists
here. It still does not: on this machine the state is `no-backend`, and that
is the truth rather than a placeholder.

### What the seam answers

`components/EventSource.qml`, root unchanged (`QtObject`):

- **`eventsForDate(date)`** -> `[{ title, startDateTime, endDateTime,
  isAllDay, eventColor, eventType }]`, the signature and the field names
  Plasma's `EventDataDecorator` had, so neither widget body learns a second
  shape. **`endDateTime` is produced although nothing reads it yet**: the
  next-event tile (plan 011 step 5) needs it, and producing it costs nothing
  here. `isMinor`/`description` are unread by every consumer.
- **`eventsChanged()`** - one signal, fired once per reload; the consumers
  debounce it by 80 ms, so a watching backend may emit freely.
- **`state`** - exactly four values, no fifth: `no-backend` | `empty` |
  `stale` | `ok`.
- **`stateDetail`** - the watched path when there is no backend, as
  `eventsFileLabel` spells it for drawing (`~/.local/state/…`, or
  `$XDG_STATE_HOME/…` when the state dir is elsewhere, or, for an overridden
  path, the fixed phrase "a custom calendar-events.json" and no part of the
  path itself - derived from where the path came from, never from matching
  the resolved string, so it cannot carry an account name); the age of the
  last sync when the data is stale ("3 days ago"); `""` otherwise.
  `eventsFile` itself stays absolute - it is what the
  reader opens. Only the Liquid Glass drawing prints it; the Nothing drawing
  shows its headline alone. `tests/eventsource-home-relative.sh` holds it.
- **`backendLabel`** - what is answering, in words: `"calendar-events.json"`,
  `"khal"`, or `"khal + calendar-events.json"`; empty exactly when `state` is
  `no-backend`.
- **`hasBackend`** - `state !== "no-backend"`, one definition of the four
  states read backwards. **`readError`** - `""` when fine.
- **Inputs, all plain properties**, so a dev harness can point the seam
  anywhere: `eventsFile`, `khalEnabled`, `khalLookaheadDays` (60 - the
  widget's own lookahead bound, hard-coded because the seam may not read the
  setting that selects it), `staleAfterSeconds` (86400).
- **It reads no `plugin.settings.*`**, ever: a seam that is also a settings
  reader cannot be tested without a plugin. `plugin/tests/run.sh` section 2
  fails the build if one appears.

The pure half is **`components/events/CalendarEvents.js`** - no QML, no paths,
no I/O, plain ES5 with `Engine.js`'s trailing `typeof module` guard so a
`node` test can `require` it. The seam owns every input and output; the
mapping, the day placement, the ordering, the merge and the age phrase live in
the .js, where they can be exercised without a shell.

### The document, adopted verbatim

`~/.local/state/omarchy/calendar-events.json`, published by
`tmn73/omarchy-calendar` (MIT):

```json
{"version":1,"syncedAt":"2026-08-10T16:42:00+00:00","source":"whatever",
 "events":[{"id":"any-stable-id","calendarId":"work@example.com",
   "calendarName":"Work","color":"#f83a22","dateKey":"2026-08-10",
   "start":"2026-08-10T19:15:00-05:00","end":"2026-08-10T20:15:00-05:00",
   "allDay":false,"title":"Tax filing","location":""}]}
```

**Verbatim, not "similar"** - that is the entire reason to take someone else's
schema: a writer that already produces this file feeds the widget with no code
change, and a writer that produces something "similar" is a second schema
nobody maintains. Nothing here rewrites, migrates or repairs the document; the
plugin only ever reads it. The next-event tile must read the same
`eventsForDate` object, never the file a second time.

Writer rules the seam relies on, each of them load-bearing:

- `dateKey` is `YYYY-MM-DD` in **local** time and is the grid's key.
- A multi-day event is emitted **once per day it covers**, each row with its
  own `dateKey` and all rows sharing one `id`, so a row's key is
  `id + dateKey`. Both consumers dedup on `title + "|" +
  startDateTime.getTime()`. Placement is by `dateKey` alone, so those three
  rows land on exactly three days - but the CONSUMERS' dedup only collapses
  them into the one card they describe if every row repeats the event's own
  `start`. A writer that stamps each row with that day's midnight draws the
  same event once per day, which is the failure this contract is easy to get
  wrong in: `dev/calendar-events-probe.qml`'s `multiday` case asserts both
  halves (one row per day, one dedup key across them).
- The writer writes **atomically** (temp file, then rename), and the widget
  watches the file. The watch is `FileView.watchChanges` plus a **60 s
  Timer backstop**, for the reason `OmarchyLocation.qml` records: a watcher
  needs an inode, so `watchChanges` never fires for a file that does not
  exist yet - the normal state before anyone syncs - and an atomic rename can
  land between two watches. The backstop also re-evaluates the staleness
  threshold, which no file change announces.
- Unknown fields are ignored, including `version` and `source`.

### The two `dateKey` traps

`dateKey` is built from the local date's own fields (`getFullYear()`,
`getMonth() + 1`, `getDate()`), never from `toISOString()`:

- On a local-midnight `Date`, `toISOString().slice(0, 10)` names the
  **previous** day at positive offsets - verified here at `TZ=Europe/Berlin`:
  `new Date("2026-09-11T00:00:00").toISOString().slice(0,10)` is `"2026-09-10"`.
- A bare `new Date("2026-09-11")` is UTC midnight, which renders the previous
  day at negative offsets (`TZ=America/New_York` puts `getDate()` at 10).

So `CalendarEvents.parseDateTime` spells the two local forms out
(`YYYY-MM-DDThh:mm[:ss]` and `YYYY-MM-DD`, plus `khal`'s space-separated
twins, because an offset-less ISO datetime is local by the ES spec but a bare
date is not) and hands everything else - an offset-bearing ISO datetime - to
the platform's own parser. A row whose `start` does not parse is **dropped**:
it has no place on a timeline, and keeping it would render `Invalid Date` in a
card.

A row with **no** `dateKey` is on every local day in `[start, end)` -
half-open, so an all-day event starting at tomorrow's midnight covers tomorrow
and not today. A row **with** a `dateKey` is on that day whatever its `start`
says, which is what makes the field the grid's key rather than a hint.

### The mapping

`title`->`title`; `start`->`startDateTime` (`new Date`); `end`->`endDateTime`
(absent -> `start`, a zero-length event); `allDay`->`isAllDay`, strictly
`=== true`; `color`->`eventColor`, `#rrggbb` or `""`; `eventType`->
`eventType`; everything else ignored.

The empty string is a **value** in `eventColor`, not a failure: the widget's
`_pillColorFor` reads an empty colour as "none given" and falls back to its
`eventType` table, which is why an invalid colour (`#RGB`, `#rrggbbaa`,
`"red"`, `"0x123456"`) must become `""` rather than reach a QML `color`
property as transparent black.

`eventsForDate` returns the day's rows ordered all-day first, then by start,
then by title. Both bodies already imposed that order; producing it in the
seam means the answer is stable on its own.

### `khal`, if it is installed

- **Detection is one `command -v khal`** through `Process { command: ["sh",
  "-c", "command -v khal"] }`. A non-zero exit means absent, and then no khal
  process runs again - ever. `khal` is never required.
- **The command** is `khal list <from> <to> --json uid --json title --json
  start --json end --json all-day --json calendar`, `<from>` today and
  `<to>` the widget's own lookahead bound (60 d), in the local calendar.
- **The output shape** (khal 0.14.1, `khal/controllers.py:328-332`): one JSON
  array per calendar day, each on its own line. `all-day` is a **string**
  (`khal/khalendar/event.py:765` prints Python's `str(True)`), the id field is
  `uid`, and there is no colour at all - so a khal row's `eventColor` is `""`
  and the fallback table decides its pill.
- **The datetimes** are formatted with the locale's `datetimeformat`
  (`event.py:648`), `%c` by default, which no fixed parser can read. The
  parser accepts `YYYY-MM-DD HH:MM` and `YYYY-MM-DD` and counts every other
  line into `readError`, so **khal's config needs `[locale] datetimeformat =
  %Y-%m-%d %H:%M`** and a machine without it says so instead of rendering
  wrong times.
- **The document wins** on a conflict: a khal row whose `uid` is an `id` the
  document also carries ON THAT DAY is dropped, because the document is the
  richer record and the operator's sync owns it. The comparison is per day,
  which is what keeps it from collapsing a recurring event's instances - khal
  gives every instance the same `uid`.
- Unverified against a real khal: it is not installed here and installing it
  is out of scope, so the merge was proved against a stub that prints exactly
  the two lines above (`dev/calendar-events-probe.qml`, `CAL_KHAL=1`). If a
  real khal is ever put in front of this, the pager is the first thing to
  check - `khal list` writing through a pager would not hand the process its
  stdout.

### The four states, and the exact words

| `state` | when | Glass wide panel | Nothing (both captions) |
|---|---|---|---|
| `no-backend` | no document and no khal, or a document that is not the schema | "No calendar connected" + the watched path + "install \`khal\`, or point any sync script at this file" | "No calendar connected" |
| `empty` | a backend answered, nothing scheduled | "Nothing scheduled" | "NOTHING SCHEDULED" |
| `stale` | the document's `syncedAt` is older than `staleAfterSeconds` | "Calendar may be out of date" + "last sync 3 days ago" | "CALENDAR MAY BE STALE" |
| `ok` | a backend answered with events | the cards, as always | the schedule, as always |

Two rules the wording follows:

- **Stale warns, it never hides.** The events are still returned and still
  drawn; the words are the only difference. Hiding them would make an old
  document look like an empty week.
- **A malformed document is `no-backend` with `readError` set**, and the glass
  panel appends " · unreadable" to the path - the one thing the state cannot
  say by itself. `readError` is where a khal line that failed to parse also
  lands, which is why it is a diagnostic and only the DOCUMENT's failure moves
  the state.
- Both surfaces say the same words for the same state (Nothing uppercases
  them, as its `NLabel` does for every caption), so the two styles differ in
  drawing, not in what they tell the operator.
- The second glass line is **smaller, not fainter**: item 33 measured
  `textQuiet` as the dimmest ink a `Text` may read on that surface (5.0:1), so
  the hierarchy is carried by size. Nothing's captions stay words-only - the
  path belongs to the panel with room for it (open question 2).

### The `+` affordance: the contract, and no code

There is no `+` in either calendar today (`grep -c '"+"'` is 0 in both
files), and this spike does not add one. When one exists:

- **May** be `createEvent(title, start, end) -> { ok, error }` on
  `EventSource`. With `khal` active: `khal new <start> <end> <title>`. With
  the document only: append ONE non-recurring `VEVENT` under
  `~/.local/share/calendars/nothing-glass/`, on the first write only.
- **May not** write `~/.local/state/omarchy/calendar-events.json`: a sync
  daemon owns that file, the next sync clobbers the write, and writing
  mid-sync races its temp-file-plus-rename. **May not** write into a vdir this
  plugin did not create - `vdirsyncer` would push a phantom event or a
  conflict. **May not** appear in `no-backend` or `stale` (there is nothing to
  add to). **May not** offer a modal editor (`keyboardFocus: None`).
- **Ownership is the invariant**: one writer per store, and for the document
  that writer is never this plugin.

### How the seam was proved

`dev/calendar-events-probe.qml` is the spike's throwaway (ShellRoot +
`check()` + `Qt.exit`, modelled on `tests/prayer-rollover.qml`, so it is COPIED
next to a dereferenced `components/` and run from there - `qs -p` refuses an
import that textually leaves the entry file's directory). It drives the real
`EventSource` through six published-shape fixtures and two `khal`-stub runs,
and each run prints one `OK:` line naming the case and the state it saw:

| fixture | state | what it proves |
|---|---|---|
| `ok.json` | `ok` | epochs, not `getHours()`: `startDateTime.getTime()` equals `Date.parse` of the document's own `start` string; colours kept; all-day sorts first |
| `empty.json` | `empty` | an empty document is still a live backend |
| `stale.json` | `stale` | `stateDetail` is "3 days ago" and the events are STILL returned |
| `nocolor.json` | `ok` | a missing `color` maps to `""`, which is what engages the fallback table |
| `malformed.json` | `no-backend` | `readError` set, no event invented |
| a path never written | `no-backend` | `stateDetail` is the path and `hasBackend` is false |
| `ok.json` + khal stub | `ok` | the stub's row is merged, `backendLabel` names khal, and the document wins the `uid`/`id` they share |
| `ok.json`, stub removed | `ok` | no marker file appears - no khal process ran - and the state falls back to the document's own |

The three surfaces were then LOOKED AT, because a widget's failure here is
silent: each state was rendered headlessly (the sweep's own shim chain,
`tests/WidgetSweepTile.qml`, against a private gamescope) at the real preset
sizes and the grabs read back. The live session was tried first and its own
launcher covered the bottom-layer panels a dev harness opens - which is worth
knowing next time: **render widget bodies headlessly, not over the operator's
desktop.**

### Open questions (each with the recommendation taken)

1. **Staleness threshold default?** 24 h (`staleAfterSeconds: 86400`), as a
   labelled guess. Upgrade to `4 x intervalSeconds` when a writer supplies an
   interval - none does.
2. **Should `no-backend` print the watched path?** Yes in the glass wide
   panel, no in the Nothing captions. Done.
3. **Should this machine get a writer (tmn73's Google sync, or `khal` +
   `vdirsyncer`)?** No. Both routes write the same document, and the seam is
   now proved without one.
4. **Per-calendar colours, or the `eventType` fallback table?** `color` first,
   fallback only when it is missing or black. tmn73's `eventType` values are
   Google-specific, so anything unrecognised uses the default blue.
5. **Both sources carry the same event - which wins?** The document (the
   richer record), deduped on `uid` vs `id`, per day.
6. **Filter `declined` and `workingLocation` rows by default, like tmn73?**
   Show everything in v1 - the seam has no policy about a row's meaning.
7. **Build the next-event tile now?** No, as its own plan. It needs nothing
   new from this seam: `endDateTime` is already produced.
8. **Plain JSON enough, or the vdir/`.ics` route in v1?** JSON only. `.ics`
   needs RRULE, EXDATE and VTIMEZONE - the trap item 16 names - and buys
   nothing while khal hands us expanded instances for free.

## 36. How this plugin is published, and why the source tree can never be (plan 022)

> **Superseded 2026-09-30.** The flattening deleted the symlink farm, so the
> first two paragraphs below no longer describe this repository: the clone root
> **is** the plugin, `omarchy plugin validate .` exits 0 on this tree, and there
> is no second release repo. Everything else in the item — the three shell
> behaviours, the size lesson, the licence paperwork — is what the current
> release doc (`RELEASING.md`) and CI rest on.

Measured 2026-09-15, Omarchy 4.0.3-1. The decision record is `RELEASING.md` at
the repo root; this item is the part the next porter needs.

**The source tree is not installable** *(historical: it is now)*. `omarchy plugin add <url>` clones the
default branch into `$PLUGINS_DIR/.add.tmp.$$`, validates *that directory*,
reads the id from its `manifest.json`, refuses an id another plugin claims, and
moves it to `~/.config/omarchy/plugins/<id>/`. There is no subdirectory and no
branch option — a `release` branch nobody checks out is invisible to it.
`omarchy-plugin-validate` fails with `missing manifest.json in <dir>` when the
root has none (ours is at the root now, `manifest.json`) and refuses **any
symlink inside the folder** (`.git` is exempt). The symlink farm — three
`plugin/` symlinks and one `components` link per widget directory — was
therefore what stood between this tree and `add`; the relative directory import
is what replaced it (item 1), and the flat root validates.

**The artifact was build output, published as its own repo** *(historical: the
checkout is the artifact now)*. A generated release repo — root `manifest.json`, `LICENSE`, end-user `README.md`, `CHANGELOG.md`,
and the four materialised trees, built by the retired installer's copy rules
(`rsync -aL --delete`; `plugin/` first with `--exclude components --exclude
widgets --exclude widgets-nothing`) — was the only shape `add` accepts under
shape B, and the only one where what is cloned and what runs were the same
bytes. Proved end to
end with a throwaway id (`t1nk33r.nothing-glass-spikeproof`, never enabled:
`PluginId.qml` hard-codes the real one and derives the store file from it):
validate 0, add 0, remove 0, no leftover folder, row or staging dir.

**Three shell behaviours to know before scripting any of it.**

- `omarchy plugin add` returns when the folder has moved; the shell loads the
  plugin asynchronously (`Local plugin changed, reloading` in
  `journalctl --user -t omarchy-shell`, about 4 s here), so a catalogue query
  right after can show the old world and any IPC call in that window answers
  `omarchy-shell is not responding`.
- `omarchy plugin remove` knocks on the shell twice — `listPlugins` first,
  `rescanPlugins` last — so a busy shell fails it *before* it has touched the
  folder or *after* the folder is gone. Gate on the folder's existence, not on
  the exit code.
- `remove` moves a **non-git** folder to `$PLUGINS_DIR/.<id>.bak.<UTC stamp>`
  instead of deleting it, because a git checkout is upstream's and an rsync
  output is the user's. That is what an `install.sh` user has, and why their
  migration is `remove` then `add` — the dot-prefixed backup is invisible to the
  catalogue, so the id is free immediately.

**The artifact's size is a porting problem, not a packaging one.** 55.6 MB of
files at `e8d4b5c`, 28.1 MiB of it font bytes carrying six distinct faces
(8.9 MiB): the 9 MB face set is materialised twice — `widgets/fonts` and the
dereferenced `widgets/tailscale/fonts` — and the two Barlow faces once per
Nothing widget's `components/nothing/fonts`. Removing the duplication means
changing QML resource paths, so it belongs to whoever plans the release.

**The licence paperwork is settled; one decision is not.** The code is GPL-3.0
wherever a reader looks — root `LICENSE`, `plugin/LICENSE`, the manifest's
`"license": "GPL-3.0-only"`, and the README — and every bundled face is
inventoried in `fonts/LICENSES.md` with its source and its
redistribution answer, which for the four Apple faces is **not
redistributable**: the licence embedded in them permits Apple-platform design
mock-ups only and forbids embedding the file in a product. What is left
undecided is what the owner does with those four files — delete them from the
working tree or replace them with a face that may be redistributed; no release
ships them either way. Recorded with its evidence in `RELEASING.md`
(`## Licence`, open question 4).
