# A portable desktop layout for Nothing Glass

The layout is 18 hand-arranged widgets stored in
`~/.config/omarchy/nothing-glass.json`, and that file only means anything on
the machine that wrote it: it records an absolute screen name (`DP-2`) and
absolute logical-pixel coordinates, so sending it elsewhere lands rows
off-screen or on a monitor that does not exist. This is the format that
travels instead.

It is a specification, not an implementation. Writing it added no IPC verb, no
UI and no change to any `.qml`; the behaviour below was measured with the
plugin's existing surface (`listTypes`, `listWidgets`, `add`, `move`,
`resize`, `set`), and the rows the format needs and that surface lacks are
written down in `## Interface`. The throwaway prototype that produced the
evidence lives in `/tmp/layout-spike/` and is deliberately not in this repo.

Line numbers here are as of `c551b1a`, which is also the commit this document
was written at. `Store.qml` — the authority on the document — is unchanged
since the plan that asked for this was written; the files around it have
moved, and every citation below is the live tree's.

## The document format

```json
{
  "format": "nothing-glass.layout",
  "formatVersion": 1,
  "generator": { "plugin": "t1nk33r.nothing-glass", "version": "0.1.0" },
  "capturedAt": "2026-09-15T06:52:30Z",
  "source": {
    "screen": { "name": "DP-2", "width": 2560, "height": 1440 },
    "widgetStyle": "nothing",
    "styleMode": 2
  },
  "count": 18,
  "widgets": [
    {
      "id": "photos-1", "type": "photos", "style": "nothing",
      "x": 16, "y": 40, "w": 400, "h": 400,
      "settings": { "photoIntervalSec": 20 },
      "omitted": ["photoFolder"]
    }
  ]
}
```

Top level:

| field | type | required | meaning |
| --- | --- | --- | --- |
| `format` | string | yes | `"nothing-glass.layout"`. The document's identity: a reader that does not recognise it refuses the document rather than guessing. The shell's own precedent is `/usr/share/omarchy/shell/services/PluginRegistry.qml:48-49`, which refuses a `schemaVersion` it does not know. |
| `formatVersion` | integer | yes | `1`. Same rule: an unknown number is refused, not interpreted. |
| `generator` | object | yes | `{ "plugin": <manifest id>, "version": <manifest version> }`. Informational — it explains a suspicious document, it does not select behaviour. |
| `capturedAt` | string | yes | ISO 8601, UTC. Informational; a human reading a shared layout wants to know how old it is. |
| `source` | object | yes | The exporting desk. Its size drives the geometry transform, and nothing else in it is binding. |
| `count` | integer | yes | `widgets.length`. Advisory: a disagreement is reported, `widgets` is authoritative (see `## Import rules` 8). |
| `widgets` | array | yes | The rows, in the sender's visual order. |

`source`:

| field | type | required | meaning |
| --- | --- | --- | --- |
| `screen.name` | string | yes | The sender's monitor name (`DP-2`). **Information, never authority** — no row carries it, and the import never uses it. |
| `screen.width`, `screen.height` | number | yes | The sender's screen in **logical** pixels — the same quantity `WidgetHost.qml:22-23` receives as `screenWidth`/`screenHeight` (`GlassSurface.qml:579-580` passes `surface.width`/`surface.height`). This is the ratio the import scales by. |
| `widgetStyle` | string | no | The sender's plugin-wide default style. Informational: the import does not apply it, because the receiving desk's own default is the receiving desk's business. |
| `styleMode` | integer | no | The sender's appearance mode. Informational, same reason. |

A row in `widgets`:

| field | type | required | meaning |
| --- | --- | --- | --- |
| `id` | string | yes, may be empty | The sender's id. Carried so a human can diff two layouts and so an edited document keeps its shape; **never authoritative** — the import mints its own (rule 7), so a document cannot overwrite a widget by naming it. |
| `type` | string | yes | A widget type, e.g. `clock-digital`. Must be one of `WidgetRegistry.listTypes()`. |
| `style` | string | no | `"liquid-glass"` or `"nothing"` — the row's reserved `style` column (`Store.qml:488-489`), the per-instance override that beats category and plugin defaults. Absent means "inherit", which is exactly what the column means when it is missing. |
| `x`, `y` | number | yes | The sender's **logical** pixel origin. |
| `w`, `h` | number | yes | The sender's tile size. Canonical in a document this tooling wrote; a hand-written odd size is snapped on import, not trusted. |
| `settings` | object | yes, may be empty | The per-instance overrides that survived the export filter. Flat, keyed by widget setting name, values typed as `WidgetFields.qml` declares them (string, number, bool). |
| `omitted` | array | no | The keys the export removed, so a reader can see *that* something was dropped instead of silently getting a widget with stray defaults. Present only when non-empty. |

Three decisions worth stating outright:

- **No per-row `screen`.** Every row in the document is destined for one
  screen, the one the import is pointed at. A row-level screen would be the
  sender's machine leaking back into the format.
- **No plugin-wide settings block in version 1.** `widgetStyle`,
  `categoryStyles`, `systemFont`, `photoFolder`, `storageMounts`,
  `networkInterface` and the rest of `nothing-glass-options.json` describe
  the sender's desk, not the sender's layout. A later version may add one;
  that is a `formatVersion` bump, not a field appearing quietly.
- **`w`/`h` are pixels, not size names.** The store holds pixels and the
  canonical sizes are derivable (`WidgetRegistry.qml:206-208`), so a name
  would be a second vocabulary for the same thing. The import maps the pixels
  onto the canonical set.

## Import rules

In order. Each rule says what it must do and what happens if it is relaxed.

1. **Refuse what you do not understand.** A document whose `format` is not
   `nothing-glass.layout` or whose `formatVersion` is not `1` is refused
   whole — not partially imported, not best-effort. The prototype exits 2
   with the offending values named. *Relaxed, an unknown future version is
   read as version 1 and half its rows land wrong.*

2. **Never carry the sender's screen name.** No row gets
   `source.screen.name`; the target screen is named by the caller, defaulting
   to the monitor the user is on. The store's own IPC already refuses an
   empty screen (`Service.qml:101-104`, `"error: screen is required"`), which
   is why "unset" cannot mean "the sender's" here.
   *Evidence:* the phase-1 document mentions `DP-2` exactly once, in
   `source.screen.name`; every imported row carries `DP-2` because that was
   the **target** it was imported onto, not because the document said so.
   *Relaxed, a layout moved to a desk without a `DP-2` imports 18 rows that
   render nowhere (`GlassSurface.qml:463-470`) and are never deleted.*

3. **Scale the origin, snap the origin, clamp the origin — and do not scale
   the size.** In order:
   - scale `x`/`y` by `target / source` (width ratio for `x`, height for `y`);
   - snap to the registry lattice, `WidgetRegistry.snapCoord`
     (`WidgetRegistry.qml:265-269`): `16 + inset + n × 104`, the grid whose
     cell is 88 and whose gutter is 16;
   - clamp exactly as the drag gesture does — `Placement.qml:82-90`'s
     `_clampX`/`_clampY` against the target's `left/top/right/bottom` insets
     (`ScreenInsets.qml:60-67`, from `hyprctl monitors -j`'s `reserved`), with
     the same `max(inset, screen − inset − size)` guard for a tile too big
     for its screen;
   - take `w`/`h` from the canonical set — `WidgetRegistry.nearestSize`
     (`WidgetRegistry.qml:242-258`) over the three tiles in
     `WidgetRegistry.qml:206-208`, 192×192 / 400×192 / 400×400. All three are
     legal for every registered type: the largest `minWidth` and `minHeight`
     in the registry table is 160.

   *Why the size must not scale, measured:* the phase-2 document scaled 1.6×
   produced 640×640 tiles sitting at `16 + 640 = 656`, which is not a
   multiple of the 104 pitch. Neighbours stop being one gutter apart — the
   grid stops being a grid. With the size held canonical, every added row
   measured `192x192`, `400x192` or `400x400` and the origins stayed on the
   lattice. Scaling the *origin* is what preserves the arrangement; the
   origin is also where the sender's intent lives.

   *Insets:* read them, do not assume them. They are `0` on this desk today
   (`reserved: [0,0,0,0]`), so an implementation that approximated them as 0
   would have been indistinguishable from a correct one here — which is
   exactly why the approximation must not ship.

4. **Skip a type this build does not have.** A row whose `type` is not in
   `listTypes()` is counted in the report and the rest of the document
   imports. *Relaxed, a layout shared with an older build fails whole instead
   of delivering the widgets that do exist.*

5. **Accept only the styles that exist:** `liquid-glass` and `nothing`. Any
   other value is reported and the row keeps its inherited style rather than
   being written a style nothing reads.

6. **Filter the settings through the widget's own field list.** The keys are
   the ones `WidgetFields.forType()` declares (`WidgetFields.qml:21-76`); a key
   no field declares never had a reader. Four classes are dropped whatever the
   type allows, and land in `omitted`:
   - `photoFolder` — a path into the sender's filesystem;
   - `storageMounts` — mount points, i.e. the sender's disks;
   - `networkInterface` — a device name from the sender's machine;
   - `latitude` / `longitude` (the `sunrise` widget's fields,
     `WidgetFields.qml:33-40`) — the sender's location. Dropped for two
     reasons, either sufficient: it is personal, and a coordinate from
     another city is *wrong* design content — the receiving desk's sunrise
     and prayer times would silently be the sender's. (The plan named three
     drops; `sunrise` and its coordinates came afterwards, and the plan's own
     rule — "anything identifying the sender's machine" — reads the same way.)

   Design content stays: `location`, `clocks`, `unit`, `playerFilter`,
   `firstDayOfWeek`, `analogSecondSweep` and the rest travel, because they
   are what the layout *says*.

   **Enforce the list at both ends.** Filtering at export protects the person
   exporting; filtering at import protects everyone downstream of a document
   that was assembled by hand or edited before forwarding. Measured: the
   prototype's export strips `photoFolder` (sender-path grep 0), while its
   import writes the keys the document carries — so a hand-written document
   put `photoFolder` onto two imported rows. The real implementation must
   re-check the allowlist and the drop list on arrival, and report what it
   refused.

7. **Mint fresh ids; never overwrite.** The import sends no id at all and
   lets the store name the row exactly as a fresh `add` would
   (`Store._genId`, `Store.qml:394-404`: `<type>-<n>` for the lowest free
   `n`). Colliding, renaming, never removing — the additive policy the legacy
   migration already proves (`Store.qml:182-226`: incoming ids that are taken
   are renamed, nothing is deleted, the source file is kept as the undo).
   *Evidence:* the document carries ids `calendar-1`, `calendar-2`,
   `clock-digital-2`; the import produced `calendar-3`, `calendar-4` and a
   fresh `clock-digital-1`, and `comm -23` showed 0 originals touched.
   *Relaxed — an import that honours the carried id — a shared layout
   overwrites the recipient's widgets, which is the one failure this format
   must not have.*

8. **Failure is per row and is reported, never fatal to the document.** A
   `widgets` entry that is not an object; a row with no `type`; a non-numeric
   `x`/`y`/`w`/`h`; a non-object `settings`; a `count` that disagrees with
   `widgets.length` (reported at index `-1`; the array wins). Each of the
   first five skips that row alone, and the report says which index and why.
   *Evidence:* all six fired at once in phase 2 and the other 19 rows
   imported. *Relaxed, one stale key in a forwarded document means nothing
   imports,* which is how a share feature gets a reputation for losing
   layouts.

9. **A document must be safe to paste in public.** No path, no device name,
   no coordinate, no plugin-wide setting — enforced at export (rule 6) and
   checked as a gate: `grep -cE '/(home|Users|mnt|media)/|~/|tailscaled\.sock'`
   on the document must be 0.

## Interface

What a real implementation adds. Nothing here exists yet.

**Two IPC verbs**, beside the existing `listTypes` / `listWidgets` / `add` /
`remove` / `move` / `resize` / `set` / `launcher` / `option` / `reload` on
`Service.qml:90-184`'s `IpcHandler` (target `t1nk33r.nothing-glass`):

```
exportLayout(): string
    -> the document, as JSON text. Returned, not written to a file:
       the caller decides whether it becomes a file, a clipboard entry
       or a pipe into ssh.

importLayout(json: string, screen: string): string
    -> {"added": N,
        "skipped": [ {"index": i, "reason": "…"}, … ],
        "screen": "DP-2"}
       index -1 marks a document-level note (today, only the count
       disagreement). screen has the same meaning as add's: "" is the
       monitor the user is on, resolved by the caller before the import
       starts, because a document imported onto a guessed screen is a
       document that may render nowhere.
```

That report shape is the prototype's, measured: the phase-1 run printed
`{"added":18,"skipped":[],"screen":"DP-2"}` and the phase-2 run printed the
six-entry version in `## Prototype evidence`.

**One store function**, `Store.importRows(rows, screen, opts)`, at
`Store.qml`'s mutation section (beside `add`/`remove`/`move`/`resize`/`set`/
`unset`, `Store.qml:420-541`). Not because it is tidier, but because
`Store.qml`'s header is explicit that there is **one writer**: "Adding a
second writer means adding it here too, or two writers race and lose the
user's layout." N separate `add`/`move`/`resize`/`set` calls do work — that
is exactly what the prototype proves — but each one is its own leading-edge
write with a 250 ms coalesce (`_scheduleWrite`, `_flush`), so an interrupted
import leaves half a layout on disk, and a large document writes the file
dozens of times. `importRows` should validate the whole document, build the
rows, commit them in one `widgets` assignment and schedule one write.

**One user-facing entry point**, and the verb comes first: it needs no
toplevel, works before the browser is open, and is what a script and a
keybind use. The widget browser (`Panel.qml`, the manifest's `panel` kind —
`manifest.json:8-12`) is the natural home for a button, and is now a real
option rather than a hypothetical one (open question 1).

`generator.version` comes from `manifest.json:5`.

## Prototype evidence

Two runs against the **live** store, both reverted. The file was snapshotted
first and restored from that snapshot — never by re-importing the export —
and the restore is proven by checksum: `c1d37b6fb9d47f5b51680f99c3cdd336`
immediately before the import and again after the restore, `cmp` exit 0, 18
rows back. Phase 1 is the honest round trip of this desk's own layout. Phase
2 points the same machinery at a document claiming a 1600×900 source — this
desk's own layout as it would have been at scale 1.6 — because with source
and target identical (2560×1440 at scale 1) the scale and clamp paths would
never execute; it also adds one row per failure mode in rule 8.

```text

=== baseline
md5 before         : c1d37b6fb9d47f5b51680f99c3cdd336
PASS baseline row count: 18
PASS baseline snapshot is byte-identical

=== export
exported 18 row(s) from DP-2 (2560x1440 logical) -> /tmp/layout-spike/portable.json
PASS DP-2 mentions in the document: 1
PASS sender-path grep: 0

=== import
{"added":18,"skipped":[],"screen":"DP-2"}
PASS row count after import: 36

=== the originals survived, unchanged
rows in before.tsv missing from after.tsv:
PASS comm -23 lines: 0

=== every row is either an original or inside the screen
DP-2 logical: 2560x1440
PASS in-bounds predicate: true

=== restore from the snapshot taken first
PASS restored file is byte-identical to the snapshot
md5 before import  : c1d37b6fb9d47f5b51680f99c3cdd336
md5 after  restore : c1d37b6fb9d47f5b51680f99c3cdd336
PASS md5 before/after: c1d37b6fb9d47f5b51680f99c3cdd336
PASS row count after restore: 18

phase 1 failures: 0
md5 before         : c1d37b6fb9d47f5b51680f99c3cdd336

=== import of the foreign document (18 real rows + 6 edge rows, count says 99)
{"added":19,"skipped":[{"index":-1,"reason":"count 99 disagrees with widgets.length 24; the array is authoritative"},{"index":18,"reason":"entry is not an object"},{"index":19,"reason":"no type"},{"index":20,"reason":"non-numeric coordinate or size"},{"index":21,"reason":"settings is not an object"},{"index":22,"reason":"unknown type no-such-widget"}],"screen":"DP-2"}

=== what the import added, as geometry
calendar-3	calendar	328	1056	400	192
calendar-4	calendar	16	1056	192	192
claude-usage-2	claude-usage	1056	1248	400	192
clock-analog-1	clock-analog	1056	16	192	192
clock-digital-1	clock-digital	16	744	192	192
codeburn-2	codeburn	1680	16	400	400
deepseek-2	deepseek	328	1248	400	192
network-2	network	1056	432	192	192
omarr-2	omarr	1680	1248	400	192
perf-2	perf	328	744	400	192
photos-2	photos	16	16	400	400
prayer-2	prayer	640	16	192	192
storage-2	storage	640	432	192	192
sunrise-2	sunrise	1368	16	192	192
tailscale-1	tailscale	1368	432	192	192
tailscale-4	tailscale	1056	744	400	400
timer-2	timer	16	1248	192	192
weather-2	weather	1680	744	400	400
weather-3	weather	2160	1040	400	400

=== the scaled+clamped row (source 1600x900 -> target 2560x1440, x1.6)
clamped row: {"id":"weather-3","type":"weather","screen":"DP-2","x":2160,"y":1040,"w":400,"h":400,"settings":{"location":"London","photoFolder":"~/Pictures"}}
PASS clamped x: 2160
PASS clamped y: 1040
PASS canonical w: 400

=== grid invariant over everything the import added
rows added: 19
distinct sizes in the store: ["192x192","400x192","400x400"]
PASS every size canonical: 0

=== what the document settings become on the row
imported rows carrying photoFolder: 2
  finding: the EXPORT strips the path (phase 1, grep 0) but the IMPORT
  writes the keys the document carries, without re-checking the
  allowlist. A hand-written document can therefore put any key on a
  row. The spec must require the same allowlist on both sides.
PASS imported location survived (design content): 1
skipped entries:
{"index":-1,"reason":"count 99 disagrees with widgets.length 24; the array is authoritative"}
{"index":18,"reason":"entry is not an object"}
{"index":19,"reason":"no type"}
{"index":20,"reason":"non-numeric coordinate or size"}
{"index":21,"reason":"settings is not an object"}
{"index":22,"reason":"unknown type no-such-widget"}
PASS skipped count: 6
PASS added count: 19

=== restore from the snapshot taken first
PASS restored file is byte-identical to the snapshot
md5 before import  : c1d37b6fb9d47f5b51680f99c3cdd336
md5 after  restore : c1d37b6fb9d47f5b51680f99c3cdd336
PASS md5 before/after: c1d37b6fb9d47f5b51680f99c3cdd336
PASS row count after restore: 18

phase 2 failures: 0

```

## Why not just share the file

Every claim here carries today's number, measured on this desk
(`c551b1a`, monitor `DP-2 2560x1440 scale=1`, 18 rows all on `DP-2`).

- **The screen name is a binding, not a label.** 18 of 18 raw rows carry
  `"screen": "DP-2"`. A row whose screen matches no connected monitor is
  filtered out of every surface (`GlassSurface.qml:463-470`) and stays in the
  store, so it renders nowhere and says nothing — a silent no-render, not an
  error (`GlassSurface.qml:449-452`). In the document that name appears once,
  in `source.screen.name`, where it is information the importer reads for the
  size ratio and then discards.
- **Absolute coordinates assume the sender's screen.** The raw rows occupy one
  1456 × 1064 box in logical pixels, and nothing rescales them on load:
  `WidgetHost.qml:39-42` copies `x`/`y`/`w`/`h` straight out of the row, and
  the only clamp in the plugin is the drag gesture (`Placement.qml:82-90`).
  On a 1600 × 900 desk — this desk at scale 1.6, which is what the plan that
  asked for this document was written against — 4 of the 18 rows (`timer-1`,
  `deepseek-1`, `claude-usage-1`, `omarr-1`, all at `y=872` with `h=192`) have
  a bottom edge at 1064, i.e. 164 px past the bottom, and 0 rows pass the
  right edge. After an import, 0 rows are out of bounds (phase 1's in-bounds
  predicate is `true`).
  *The plan's motivating measurement — `music-1` 272 px past the right edge
  at 1600 logical — no longer reproduces:* that row is gone from the store and
  the monitor now reports `scale=1`, so the desk has room to spare and the bug
  is latent rather than visible. The claim is unchanged; only its witness
  moved.
- **The raw file carries the sender's filesystem.** 2 of the 18 rows do:
  `storage-1` with `{"storageMounts":"/home, /mnt"}` and `photos-1` with
  `{"photoFolder":"~/Pictures"}`. Neither appears in the document
  (sender-path grep 0) — the export moves them to `omitted`.
- **Collisions are not the reason.** Sharing the raw file also doubles a
  layout without overwriting anything: the import added 18 rows, every one
  minted fresh, and `comm -23` between before and after is 0 lines — not one
  original touched. The gain is geometry and privacy, not collision safety.
- **Hand-editing is the failure the format removes.** `README.md:170`: both
  files "are written by the plugin; editing them by hand while the shell runs
  will lose the edit". A shared file invites exactly that edit; a document
  that is imported through a verb does not.

## Open questions

1. **Where does the feature live — a verb, a panel button, or both?** —
   Recommendation: the verb now; a button inside the widget browser when the
   browser is what people actually open. The browser is a real option as of
   `Panel.qml` and the manifest's `panel` kind, and a button there costs one
   call to the same code path the verb uses.
2. **Additive, or a replacing import?** — Recommendation: additive only in
   version 1. A replacing import is the one operation that can lose a layout
   outright, and the store's only net is the empty-over-non-empty `.bak`
   (`Store.qml:308-340`). If a replace mode is ever wanted, it should be a
   separate verb with its own confirmation, not a flag on this one.
3. **Coordinates: scaled absolute, or a grid?** — Recommendation: scaled
   origin, snapped to the registry lattice, with the size taken from the
   canonical set (rule 3). Measured: scaling the size too yields 640 × 640
   tiles at origins that are not on the 104 pitch — 16 + 640 = 656 — so
   neighbours stop being one gutter apart. A pure grid (ignore the sender's
   pixels, re-flow in reading order) is also defensible and would be a
   different, simpler format; it is not this one, because it throws away the
   arrangement the sender actually made.
4. **Do the plugin-wide settings travel?** — Recommendation: no in version 1.
   They describe a desk, not a layout, and the receiving desk already has its
   own. That is what keeps `photoFolder`, `storageMounts`,
   `networkInterface`, `systemFont` and `categoryStyles` out of the format
   entirely, rather than in it and filtered.
5. **Per-row `style` versus `categoryStyles`/`widgetStyle`?** —
   Recommendation: carry per-row styles, drop the global ones. A row style is
   an explicit choice about that widget; the globals are a desk's taste, and
   the receiving desk's taste should win.
6. **What about widgets on the sender's other screens?** — Recommendation:
   export every row and place them all on the chosen target screen. Today all
   18 already share one screen, so nothing is being decided by accident; but
   the format must not grow a per-row screen, and an import that dropped
   "rows not on the exporting screen" would lose widgets silently.
7. **A human-readable form — comments, size names, a YAML flavour?** —
   Recommendation: no. Keep `id` and `type` first in each row and the key
   order stable, so two documents diff to the lines that actually changed,
   which is the whole of the benefit with none of the parser.
8. **Is it worth building at all?** — Recommendation: yes. The alternative is
   the JSON file that silently breaks — rows that render nowhere, coordinates
   that point off the screen — and the same machinery (screen rewrite, ratio,
   lattice, clamp, filtered settings) is exactly what a monitor change on one
   machine needs too, which is where it will earn its keep even without
   sharing.
9. **Does the import re-check the settings allowlist, or trust the
   document?** — Recommendation: re-check, and report the refusals. The export
   has to filter; the import cannot assume the document was produced by the
   export. Measured: the prototype's import writes whatever keys the document
   carries, so a hand-written document put `photoFolder` onto two imported
   rows (see rule 6).
10. **What should a dropped `latitude`/`longitude` leave behind?** —
    Recommendation: nothing — leave the field unset, which is what an empty
    value already means (`WidgetFields.qml:33-40`: the coordinate is "used
    only when no other source resolves", so an unset field follows the
    receiving desk's own source). Do not substitute the sender's city or a
    zero; a wrong coordinate is worse than a fallback.
