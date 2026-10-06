#!/usr/bin/env bash
# Cross-checks manifest.json's `settings.defaults` against GlassSurface.qml's
# `_fallbackDefaults` literal. The two are supposed to be numerically
# identical (see GlassSurface.qml's comment on `_fallbackDefaults`, plan 004)
# — this is what actually enforces that, rather than leaving it to a comment
# that the next person adding a knob has to remember to also update.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$PLUGIN_DIR/manifest.json"
GLASS_SURFACE="$PLUGIN_DIR/GlassSurface.qml"

have() { command -v "$1" >/dev/null 2>&1; }
have jq || { echo "jq is required but not found on PATH" >&2; exit 1; }
[[ -f $MANIFEST ]] || { echo "missing $MANIFEST" >&2; exit 1; }
[[ -f $GLASS_SURFACE ]] || { echo "missing $GLASS_SURFACE" >&2; exit 1; }

# manifest.json's settings.defaults, as sorted "key=value" lines.
manifest_defaults="$(jq -r '
  .settings.defaults
  | to_entries
  | sort_by(.key)[]
  | "\(.key)=\(.value)"
' "$MANIFEST")"

if [[ -z $manifest_defaults ]]; then
  echo "manifest.json has no settings.defaults entries — nothing to compare" >&2
  exit 1
fi

# GlassSurface.qml's `_fallbackDefaults` is a flat `{ key: N, key: N, ... }`
# object literal by construction (its own comment says so), so a line-range
# extract between the property declaration and its closing `})`, followed by
# a plain `key: value` token scan, is enough — no QML parser needed.
fallback_block="$(sed -n '/_fallbackDefaults: ({/,/^  })/p' "$GLASS_SURFACE")"
if [[ -z $fallback_block ]]; then
  echo "could not find the _fallbackDefaults literal in $GLASS_SURFACE" >&2
  echo "(expected a 'property var _fallbackDefaults: ({ ... })' block)" >&2
  exit 1
fi

# Matches `key: N`, `key: N.M`, `key: true`/`false`, and `key: "string"`
# (quotes stripped). Every widening here came from a real hole: plan 006
# added the first string-typed default and plan 008 the first
# fractional one (latitude/longitude), and each time a too-narrow regex
# silently dropped that key from this side of the comparison — turning a real
# drift into a false match instead of a loud failure.
# An empty object default is written `key: ({})` in QML - the parens keep QML
# from reading the braces as a scope - and `"key": {}` in JSON. Both normalise
# to `key={}` so the two sides stay comparable.
fallback_defaults="$(grep -oE '[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*(\(\{\}\)|-?[0-9]+(\.[0-9]+)?|true|false|"[^"]*")' <<<"$fallback_block" \
  | sed -E 's/:[[:space:]]*/=/; s/^([^=]+)="([^"]*)"$/\1=\2/; s/^([^=]+)=\(\{\}\)$/\1={}/' | sort)"

if [[ -z $fallback_defaults ]]; then
  echo "extracted a _fallbackDefaults block but found no 'key: number' pairs in it" >&2
  exit 1
fi

if [[ $manifest_defaults != "$fallback_defaults" ]]; then
  {
    echo "manifest.json settings.defaults and GlassSurface.qml _fallbackDefaults have drifted:"
    echo
    diff --label "manifest.json (settings.defaults)" --label "GlassSurface.qml (_fallbackDefaults)" \
      <(echo "$manifest_defaults") <(echo "$fallback_defaults") || true
    echo
    echo "Update BOTH — manifest.json's settings.defaults and GlassSurface.qml's" \
         "_fallbackDefaults — to the same key/value set. See the maintenance note" \
         "on _fallbackDefaults for why the duplication exists."
  } >&2
  exit 1
fi

echo "OK: manifest.json settings.defaults matches GlassSurface.qml _fallbackDefaults (${manifest_defaults//$'\n'/, })"

# ── 2. Every configuration key a widget reads must have a default ──────────
#
# `plugin.settings.someKey` with no entry in settings.defaults yields
# `undefined`, which QML then assigns to whatever property it was bound to:
# an int property logs "Unable to assign [undefined] to int" once per frame,
# a bool silently reads false, and the widget quietly does the wrong thing.
# Both `followOmarchyLocation` and `useGeoclue` were added to a widget before
# the manifest and behaved exactly like that until the manifest caught up.
default_keys="$(jq -r '.settings.defaults | keys[]' "$MANIFEST" | sort -u)"

# One root covers both widget trees: the plugin root IS the repo root, and
# `widgets/` and `widgets-nothing/` are real directories inside it. Before the
# flatten they had to be named separately, because `grep -R` descends into a
# symlinked directory only when it is named on the command line and the repo
# reached them through `plugin/widgets` -> `../widgets`.
scan_roots=("$PLUGIN_DIR")

# Comment lines are stripped first: the porting notes talk about
# `plugin.settings.X` in prose, and a doc comment must not fail a build.
#
# `|| true`, because an empty scan is NOT this check failing to find a
# problem - it is the check having nothing to look at, and under `set -e` +
# `pipefail` the grep above would end the script right here with a bare
# non-zero exit and no message (measured: a scan root with no .qml in it stops
# the run dead after section 1's OK line). The guard below is what turns that
# into a named failure, so the pipelines are allowed to come back empty.
used_keys="$(grep -Rh --include='*.qml' -v -E '^[[:space:]]*//' \
  "${scan_roots[@]}" 2>/dev/null |
  grep -oE 'plugin\.settings\.[A-Za-z_][A-Za-z0-9_]*' |
  sed 's/.*\.//' | sort -u || true)"
if [[ -z $used_keys ]]; then
  {
    echo "no plugin.settings.<key> read found under: ${scan_roots[*]}"
    echo "An empty scan compares nothing against nothing and reports success,"
    echo "so this is a failure: check the scan root and the read pattern."
  } >&2
  exit 1
fi

missing="$(comm -23 <(echo "$used_keys") <(echo "$default_keys") || true)"
if [[ -n ${missing//[[:space:]]/} ]]; then
  {
    echo "widgets read configuration keys that manifest.json does not default:"
    echo "$missing" | sed 's/^/  - /'
    echo
    echo "Add each to BOTH manifest.json settings.defaults and GlassSurface.qml's"
    echo "_fallbackDefaults, or the binding resolves to undefined at runtime."
  } >&2
  exit 1
fi
echo "OK: every plugin.settings key used by a widget has a default"

# ── 3. The plugin must ship exactly the widget files it claims ────────────
# One plugin draws BOTH styles: `widgets/` is the Liquid Glass drawing and
# `widgets-nothing/` is the Nothing one, and WidgetRegistry.qml says which
# types have which. A type promising a drawing it does not ship renders as an
# empty tile with no error, so both trees are checked, not one.
registry="$PLUGIN_DIR/WidgetRegistry.qml"
identity="$PLUGIN_DIR/PluginId.qml"
[[ -f $identity ]] || { echo "missing $identity" >&2; exit 1; }

plugin_id=$(grep -oE 'property string id: "[^"]+"' "$identity" | head -1 | sed 's/.*"\(.*\)"/\1/')
manifest_id=$(jq -r '.id' "$MANIFEST")
[[ $plugin_id == "$manifest_id" ]] \
  || { echo "PluginId.qml id '$plugin_id' != manifest.json id '$manifest_id'" >&2; exit 1; }

# key|nothing|nothingOnly, one line per entry in the table.
entries=$(awk '
  /^[[:space:]]*"?[A-Za-z0-9-]+"?:[[:space:]]*\{/ {
    key = $1; sub(/:.*/, "", key); gsub(/"/, "", key); block = ""
  }
  { block = block " " $0 }
  /\}/ {
    if (key != "") {
      n = (block ~ /nothing:[[:space:]]*true/) ? 1 : 0
      o = (block ~ /nothingOnly:[[:space:]]*true/) ? 1 : 0
      print key "|" n "|" o
    }
    key = ""; block = ""
  }
' "$registry")

bad_paths=""
claimed_glass=""
claimed_nothing=""
while IFS='|' read -r key has_nothing only_nothing; do
  [[ -n $key ]] || continue
  # A nothingOnly type has no Liquid Glass drawing by design.
  if [[ $only_nothing != 1 ]]; then
    claimed_glass+="$key"$'\n'
    [[ -f "$PLUGIN_DIR/widgets/$key/main.qml" ]] \
      || bad_paths+="  - widgets/$key/main.qml"$'\n'
  fi
  if [[ $has_nothing == 1 || $only_nothing == 1 ]]; then
    claimed_nothing+="$key"$'\n'
    [[ -f "$PLUGIN_DIR/widgets-nothing/$key/main.qml" ]] \
      || bad_paths+="  - widgets-nothing/$key/main.qml"$'\n'
  fi
done <<< "$entries"
if [[ -n $bad_paths ]]; then
  { echo "$plugin_id is missing widget files its registry claims:"; printf '%s' "$bad_paths"; } >&2
  exit 1
fi
echo "OK: $plugin_id ships every widget file its registry offers, in both styles"

# And nothing more: a directory the registry does not name in that style is
# dead weight no launcher, IPC call or settings sheet can reach.
strays=""
for tree in widgets widgets-nothing; do
  claimed="$claimed_glass"; [[ $tree == "widgets-nothing" ]] && claimed="$claimed_nothing"
  for dir in "$PLUGIN_DIR/$tree"/*/; do
    [[ -d $dir ]] || continue
    name=$(basename "$dir")
    grep -qxF "$name" <<< "$claimed" || strays+="  - $tree/$name"$'\n'
  done
done
if [[ -n $strays ]]; then
  { echo "widget directories the registry does not offer in that style:"; printf '%s' "$strays"; } >&2
  exit 1
fi
echo "OK: no unreachable widget directories"

# ── 3b. The legacy-store migration must only run for the REAL store ────────
# Store._absorbLegacyStore() moves the retired t1nk33r.nothing plugin's
# widgets into this plugin's file and renames the source away. A Store
# pointed somewhere else - the dev harness passes a scratch path - would
# absorb the user's widgets into the scratch file and leave the desktop
# empty. That happened once, in a smoke test, on real data.
store_file="$PLUGIN_DIR/Store.qml"
grep -q '_mayAbsorb' "$store_file" \
  || { echo "Store.qml lost the _mayAbsorb guard: a scratch store would eat nothing.json" >&2; exit 1; }
grep -qE 'if \(!store\.loaded( \|\| [^)]*)? \|\| !store\._mayAbsorb\) return' "$store_file" \
  || { echo "Store._absorbLegacy() no longer checks _mayAbsorb before migrating" >&2; exit 1; }
for legacy in liquidglass.json nothing.json liquid-nothing.json; do
  grep -qE "path: store\._mayAbsorb \? \(store\._home \+ \"/\.config/omarchy/$legacy\"\) : \"\"" "$store_file" \
    || { echo "the $legacy reader is not gated on _mayAbsorb" >&2; exit 1; }
done
echo "OK: only the default-path store can absorb the retired plugin's widgets"

# Every non-dev type must sit in a group the launcher rail actually shows.
# A type in no group (or in a group missing from `groups`) still exists, still
# resolves, and is still invisible in the browser - which is exactly the kind
# of bug that only shows up when someone goes looking for a widget they know
# they wrote.
groups_line=$(grep -oE 'readonly property var groups: \[[^]]*\]' "$registry" | head -1)
[[ -n $groups_line ]] || { echo "WidgetRegistry.qml has no groups list" >&2; exit 1; }
orphans=""
while IFS='|' read -r key grp; do
  [[ -n $key ]] || continue
  case "$groups_line" in
    *"\"$grp\""*) ;;
    *) orphans+="  - $key (group '$grp')"$'\n' ;;
  esac
done < <(awk '
  /^[[:space:]]*"?[A-Za-z0-9-]+"?:[[:space:]]*\{/ {
    key = $1; sub(/:.*/, "", key); gsub(/"/, "", key); block = ""
  }
  { block = block " " $0 }
  /\}/ {
    if (key != "" && block !~ /dev:[[:space:]]*true/) {
      grp = ""
      if (match(block, /group:[[:space:]]*"[^"]+"/)) {
        grp = substr(block, RSTART, RLENGTH); sub(/group:[[:space:]]*"/, "", grp); sub(/"$/, "", grp)
      }
      print key "|" grp
    }
    key = ""; block = ""
  }
' "$registry")
if [[ -n $orphans ]]; then
  { echo "widget types that the launcher rail cannot reach:"; printf '%s' "$orphans"; } >&2
  exit 1
fi
echo "OK: every widget type is reachable from a launcher group"

# Every QML file in a component directory must be listed in that directory's
# qmldir. Without the listing the directory is implicit and Quickshell
# registers it lazily, so the first type looked up in a freshly-copied
# directory fails with "<T> is not a type" and the widget renders as an empty
# tile - see PORTING.md item 21.
# Every directory reached by an `import "<dir>"` needs one: the two component
# directories, plus each widget's own `widget/` subdirectory.
qmldir_dirs=("$PLUGIN_DIR/components" "$PLUGIN_DIR/components/nothing")
for tree in widgets widgets-nothing; do
  for wdir in "$PLUGIN_DIR/$tree"/*/widget; do
    [[ -d $wdir ]] && qmldir_dirs+=("$wdir")
  done
done
for dir in "${qmldir_dirs[@]}"; do
  [[ -d $dir ]] || continue
  qmldir="$dir/qmldir"
  [[ -f $qmldir ]] || { echo "$dir has QML types but no qmldir" >&2; exit 1; }
  missing=""
  for f in "$dir"/*.qml; do
    [[ -e $f ]] || continue
    tname=$(basename "$f" .qml)
    grep -qE "^$tname[[:space:]]+[0-9.]+[[:space:]]+$tname\.qml$" "$qmldir" \
      || missing+="  - $tname"$'\n'
  done
  if [[ -n $missing ]]; then
    { echo "types missing from $qmldir:"; printf '%s' "$missing"; } >&2
    exit 1
  fi
done
echo "OK: every component and primitive is registered in its qmldir"

# ── 4. The per-widget settings table may only name real keys ───────────────
#
# `|| true` for the same reason as section 2: with the table's rows renamed,
# the grep comes back empty and `set -e` + `pipefail` would end the script here
# with no message at all (measured: the run stops after section 3's last OK
# line). The guard names the file instead - and note that an empty table is not
# an empty problem: `comm` against no keys reports no unknown keys, which reads
# exactly like a pass.
fields_keys="$(grep -oE 'key: "[A-Za-z_][A-Za-z0-9_]*"' "$PLUGIN_DIR/WidgetFields.qml" |
  sed 's/key: "//; s/"$//' | sort -u || true)"
if [[ -z $fields_keys ]]; then
  {
    echo "no \`key: \"<setting>\"\` row found in $PLUGIN_DIR/WidgetFields.qml"
    echo "An empty table compares nothing against nothing and reports success,"
    echo "so this is a failure: check the file and the row pattern."
  } >&2
  exit 1
fi
unknown="$(comm -23 <(echo "$fields_keys") <(echo "$default_keys") || true)"
if [[ -n ${unknown//[[:space:]]/} ]]; then
  {
    echo "WidgetFields.qml offers keys that are not real settings:"
    echo "$unknown" | sed 's/^/  - /'
    echo "(editing one would write a store override nothing ever reads)"
  } >&2
  exit 1
fi
echo "OK: WidgetFields keys are all real settings"

# ── 4b. Every Appearance knob must have a range in the manifest ────────────
#
# The pane reads each knob's `min`/`max` from manifest.json's settings.schema
# rather than restating them, so a knob whose key is not ranged there is
# silently dropped instead of drawn - the safe failure, but an invisible one.
# This turns it into a build failure: the tables are the list of controls the
# pane offers, so every key in them must be ranged. A `step` is deliberately NOT
# required - four of the glass keys are integer-typed and declare none (the
# pane supplies its own drag granularity for those).
launcher_file="$PLUGIN_DIR/NothingLauncher.qml"
[[ -f $launcher_file ]] || { echo "missing $launcher_file" >&2; exit 1; }
# Both knob tables - `glassKnobs` and the Nothing style's `nothingKnobs` - and
# not every `key: "..."` in the file, so a delegate that names a key for another
# purpose cannot fail this. The range restarts at each `...Knobs: [` line, so a
# table added for a third group is covered the moment it lands rather than when
# someone remembers this check.
knob_tables="$(sed -n '/Knobs: \[/,/^  \]/p' "$launcher_file")"
if [[ -z $knob_tables ]]; then
  echo "could not find a knob table in $launcher_file" >&2
  exit 1
fi
knob_keys="$(grep -oE 'key: "[A-Za-z_][A-Za-z0-9_]*"' <<<"$knob_tables" |
  sed 's/key: "//; s/"$//' | sort -u)"
if [[ -z $knob_keys ]]; then
  echo "no knob table in $launcher_file names any key" >&2
  exit 1
fi
ranged_keys="$(jq -r '.settings.schema[]
  | select((.min != null) and (.max != null)) | .key' "$MANIFEST" | sort -u)"
unranged="$(comm -23 <(echo "$knob_keys") <(echo "$ranged_keys") || true)"
if [[ -n ${unranged//[[:space:]]/} ]]; then
  {
    echo "NothingLauncher.qml draws knobs that manifest.json does not range:"
    echo "$unranged" | sed 's/^/  - /'
    echo "(add min/max to the key in settings.schema, or the pane drops the control)"
  } >&2
  exit 1
fi
echo "OK: every Appearance knob key is ranged in the manifest schema"

# The Nothing style's knob, which the rest of this suite cannot see: the pane is
# a sheet in a running shell, and the sweep drives widget types, not the browser.
# Two things about its own row are still checkable, and both are silent defects:
#
#   * `mult` is the row's one display transform - the setting is stored `0..1`
#     and drawn as a percentage, so the entry carries 100. With `mult: 1` the
#     key is still written correctly, but a card at half opacity reads "0.5%";
#     the glass table's `tintAlpha` carries the same 100 for the same reason.
#   * `defaultValue` is what the Omarchy settings UI shows for a key that has no
#     stored value: `DynamicSettingsForm.currentValue()` falls back to `min`,
#     so without it the slider would open at 0.00 while the card is opaque.
#     That panel renders a `number` with a range as a drag slider, which is the
#     control this key is shaped for.
alpha_row="$(grep -F 'key: "surfaceAlpha"' <<<"$knob_tables" || true)"
if [[ -z $alpha_row ]]; then
  {
    echo "the Appearance pane draws no card-opacity knob:"
    echo "  - no surfaceAlpha entry in a knob table of $launcher_file"
    echo "(the Nothing table's one entry is that style's only user knob)"
  } >&2
  exit 1
fi
if [[ $alpha_row != *"mult: 100"* ]]; then
  {
    echo "the card-opacity knob does not display a percentage:"
    echo "  - $alpha_row"
    echo "(surfaceAlpha is stored 0..1, so the row needs the tintAlpha transform: mult: 100)"
  } >&2
  exit 1
fi
if ! jq -e '.settings.schema[] | select(.key == "surfaceAlpha") | .defaultValue == 1' \
     "$MANIFEST" >/dev/null; then
  {
    echo "manifest.json's surfaceAlpha schema entry has no defaultValue of 1:"
    echo "(the settings UI falls back to the entry's min for a key with no value,"
    echo " so its slider would open at 0.00 while the card is still opaque)"
  } >&2
  exit 1
fi

# ── 4c. Every compiled shader must have a QML consumer ─────────────────────
#
# build-shaders.sh globs `*.frag`, so every shader in the directory is
# recompiled on every shader edit, and the checkout is installed as-is, so
# every one of them ships. A shader nothing loads is
# therefore compiled and deployed forever while also reading as documentation
# of a pipeline that does not exist - which is exactly what `glyph_seed.frag`
# and `jfa.frag` were: producers for an SDF path whose only selector uniform was
# a hard-coded 1.0, so nothing ever ran it and nothing ever would. This is what
# caught them, and it is what refuses them if anyone re-adds the shaders without
# the QML that would drive them.
#
# The rule is deliberately the narrow one - "some QML loads this .qsb". A shader
# loaded only from a `.js` file or a settings string would trip it; widen the
# grep if that ever becomes real rather than dropping the check.
shader_dir="$PLUGIN_DIR/components/shaders"
[[ -d $shader_dir ]] || { echo "missing $shader_dir" >&2; exit 1; }
# One root, and for the same reason section 2 uses one: everything the run
# scans - the runtime, `components/` and both widget trees - lives under the
# plugin root now, as real directories `grep -R` descends into on its own.
shader_roots=("$PLUGIN_DIR")

shopt -s nullglob
shader_frags=("$shader_dir"/*.frag)
shopt -u nullglob
if [[ ${#shader_frags[@]} -eq 0 ]]; then
  echo "no .frag sources in $shader_dir" >&2
  exit 1
fi

orphan_shaders=""
for frag in "${shader_frags[@]}"; do
  base="$(basename "$frag")"
  grep -Rq --include='*.qml' -- "$base.qsb" "${shader_roots[@]}" \
    || orphan_shaders+="$base"$'\n'
done
if [[ -n ${orphan_shaders//[[:space:]]/} ]]; then
  {
    echo "these shaders are compiled and deployed but no QML loads them:"
    echo "$orphan_shaders" | sed '/^$/d; s/^/  - /'
    echo "(delete the shader, or add the QML that loads its .qsb)"
  } >&2
  exit 1
fi
echo "OK: every compiled shader has a QML consumer"

# ── 4d. A weather header is written once per style, not once per preset ────
#
# The header - city, temperature, condition, high/low - was written three
# times per body, once per grid preset, and the copies had already drifted:
# the city x1.1 in one and x1.15 in the other two, the hero temperature x4 in
# one and x3.5 in the others, the same high/low pair drawn two different
# ways. That is what three copies do, and it is why the four tiles read as
# four drawings instead of two styles. Each body now draws the header through
# one `widget/WeatherHeader.qml`; this is what refuses a fourth copy, which
# is exactly how the drift started.
#
# It does not duplicate the qmldir check above, which already covers both new
# files.
glass_weather="$PLUGIN_DIR/widgets/weather/main.qml"
nothing_weather="$PLUGIN_DIR/widgets-nothing/weather/main.qml"
for body in "$glass_weather" "$nothing_weather"; do
  [[ -f $body ]] || { echo "missing $body" >&2; exit 1; }
done

drift=""
for body in "$glass_weather" "$nothing_weather"; do
  headers=$(grep -cF "WeatherHeader {" "$body" || true)
  [[ $headers == 3 ]] \
    || drift+="  - $body: $headers WeatherHeader instances (want one per preset: 3)"$'\n'
done

# The glass body must not read what the header draws. `currentTemp` survives
# in exactly one line the header does not own - the spinner's no-data gate
# `isLoading && currentTemp === "--"`, a loading state rather than a reading -
# so that one is a count, not a presence: an inlined header adds more.
for field in cityName condition highTemp lowTemp; do
  grep -qF "weatherData.$field" "$glass_weather" \
    && drift+="  - $glass_weather: reads weatherData.$field, which the header draws"$'\n'
done
temp_reads=$(grep -cF "weatherData.currentTemp" "$glass_weather" || true)
[[ $temp_reads -le 1 ]] \
  || drift+="  - $glass_weather: reads weatherData.currentTemp $temp_reads times (only the spinner's loading gate may)"$'\n'

# The Nothing body passes `full.cityLabel` once per header instance and draws
# the city nowhere else, so its count is the header count too.
city_reads=$(grep -cF "full.cityLabel" "$nothing_weather" || true)
[[ $city_reads == 3 ]] \
  || drift+="  - $nothing_weather: full.cityLabel appears $city_reads times (want the 3 header bindings)"$'\n'

if [[ -n $drift ]]; then
  {
    echo "the weather header is being drawn outside its component:"
    printf '%s' "$drift"
    echo
    echo "Both weather bodies draw it through widgets/weather/widget/WeatherHeader.qml" \
         "and widgets-nothing/weather/widget/WeatherHeader.qml. A header written back" \
         "into a layout is how the two tiles drifted apart; change the component."
  } >&2
  exit 1
fi
echo "OK: the weather header is one component per style, not one per preset"

# ── 4e. Every Text draws plain text ────────────────────────────────────────
#
# A Text left on Qt's default AutoText obeys any markup in its string: an
# <img src="http://…"> in a calendar title, a track name, a peer's hostname
# or a city from a web service made the shell fetch that URL just by drawing
# it. Nothing in the plugin draws rich text on purpose, so every Text and
# Label says `textFormat: Text.PlainText` at its own level - a new one that
# forgets fails here, not in a security review.
autotext="$(cd "$PLUGIN_DIR" && find . -name '*.qml' -not -path './.git/*' -print0 |
  xargs -0 awk '
    FNR == 1 { open = 0 }
    open == 0 && /^[[:space:]]*([A-Za-z_.]+[[:space:]]*:[[:space:]]*)?(Text|Label)[[:space:]]*\{[[:space:]]*$/ {
      open = 1; depth = 1; ok = 0; at = FNR; next
    }
    open == 1 {
      if (depth == 1 && $0 ~ /^[[:space:]]*textFormat[[:space:]]*:[[:space:]]*Text\.PlainText/) ok = 1
      depth += gsub(/\{/, "{") - gsub(/\}/, "}")
      if (depth <= 0) { if (!ok) print FILENAME ":" at; open = 0 }
    }
  ' || true)"
if [[ -n $autotext ]]; then
  {
    echo "Text/Label elements without 'textFormat: Text.PlainText' (they obey markup in their string):"
    printf '  %s\n' $autotext
  } >&2
  exit 1
fi
echo "OK: every Text and Label draws plain text"

# ── 4f. A weather report is rolled back whole ──────────────────────────────
#
# WeatherDataQs._applyReport restores every property in `_renderOutputs` when
# a report throws half way through drawing. A property _render (or a helper
# it calls) writes but the list omits would silently survive that rollback,
# leaving half a rejected report on screen - so the two must name the same
# set. The render path is everything from `function _render()` to the end.
weather_qs="$PLUGIN_DIR/components/WeatherDataQs.qml"
render_writes="$(sed -n '/function _render()/,$p' "$weather_qs" |
  grep -oE 'wd\.[A-Za-z_][A-Za-z0-9_]* = ' | sed -E 's/^wd\.| = $//g' | sort -u || true)"
render_listed="$(sed -n '/_renderOutputs: \[/,/\]/p' "$weather_qs" |
  grep -oE '"[A-Za-z_][A-Za-z0-9_]*"' | tr -d '"' | sort -u || true)"
if [[ -z $render_writes || -z $render_listed ]]; then
  echo "could not read _render's writes or _renderOutputs from $weather_qs" >&2
  exit 1
fi
if [[ $render_writes != "$render_listed" ]]; then
  {
    echo "WeatherDataQs: _renderOutputs does not match what _render writes:"
    diff <(echo "$render_listed") <(echo "$render_writes") | sed -n 's/^</  listed, never written:/p; s/^>/  written, not rolled back:/p'
  } >&2
  exit 1
fi
echo "OK: a weather report that throws mid-render is rolled back whole"

# ── The behavioural-test harness ──────────────────────────────────────────
#
# Everything above reads the plugin's files; from here on the plugin is run.
# Each test is a ShellRoot that drives a real component and prints one
# "OK: <name>" line when every assertion held, and exits non-zero with a
# "FAIL <assertion>" line for each thing that did not.
#
# Four details make that possible, and most of them were learned the hard way:
#
#   * `qs` refuses to load a QML module path outside its config folder, so the
#     test file is copied into a scratch directory. The runtime under test, the
#     shared `components/` and `fonts/` are reached through links beside it -
#     the same trick glass-dev.qml documents - because the tests import
#     `plugin` and `components` directly.
#   * HOME and XDG_CONFIG_HOME point at that scratch directory. Store, Options
#     and PrayerTimes all derive their file paths from HOME, so without this a
#     behavioural test would read and write the user's real ~/.config/omarchy -
#     the one thing a test must never do. Whatever configuration a test needs
#     is written into that scratch tree by its own fixture (see
#     fixture_prayers, fixture_store and fixture_merge), which is also what
#     lets this suite run in a container with no omarchy config at all.
#   * A test that builds a PanelWindow needs a Wayland compositor, and there
#     is none on a build box. Those run against a private headless gamescope:
#     no window, no DRM output, its own socket in a scratch XDG_RUNTIME_DIR,
#     nothing drawn anywhere. Without gamescope the test is SKIPPED, never
#     failed - the same rule as a machine with no `qs`, because a missing
#     dependency is not a defect in the plugin.
#   * Cleanup is ONE EXIT trap for everything the harness made, installed on
#     first use. Arming a fresh trap per section, as the single-test version
#     did, silently drops the previous one and leaks its directory.
test_dirs=()
test_compositor_pid=""

cleanup_tests() {
  # The compositor is killed as a process group: it is started via setsid, so
  # its pid is its pgid and nothing of it can outlive the suite.
  if [[ -n $test_compositor_pid ]]; then
    kill -TERM -- "-$test_compositor_pid" 2>/dev/null || true
    kill -TERM "$test_compositor_pid" 2>/dev/null || true
  fi
  local dir
  for dir in ${test_dirs[@]+"${test_dirs[@]}"}; do rm -rf "$dir"; done
}

# run_qml_test <test file> <OK marker> [fixture function] [mode]
#
# mode is `wayland` for a test that builds a PanelWindow and empty for one
# that runs headless against the scratch HOME. Every test runs against that
# scratch HOME: the machine the suite runs on is never an input.
#
# The fixture function, if given, is handed the scratch HOME so it can write
# the files the test expects to find there.
run_qml_test() {
  local file="$1" marker="$2" fixture="${3:-}" mode="${4:-}"
  local name tmp home runtime="" out
  name="$(basename "$file")"

  # The caller passes the test's absolute path: the QML tests sit in this
  # script's own directory, tests/, beside the runtime they drive. A missing
  # file is a hard error, not a SKIP - a renamed or mis-pathed test used to
  # report as "qs not on PATH", which is how a silently shrinking suite looks.
  if ! have qs; then
    echo "SKIP: $name (qs not on PATH)"
    return 0
  fi
  if [[ ! -f $file ]]; then
    echo "missing test file: $file" >&2
    exit 1
  fi
  if [[ $mode == wayland ]] && ! have gamescope; then
    echo "SKIP: $name (needs a headless compositor: gamescope)"
    return 0
  fi

  tmp="$(mktemp -d)"
  test_dirs+=("$tmp")
  trap cleanup_tests EXIT
  home="$tmp/home"
  # Store, Options and GlassSurface all derive their paths as
  # $HOME/.config/omarchy/<name>; this is that directory inside the scratch
  # tree, not the user's.
  mkdir -p "$home/.config/omarchy" "$home/scratch"

  cp "$file" "$tmp/$name"
  # The scratch root carries the plugin's own layout through links beside the
  # copy of the test: `qs` refuses to load a QML module path outside its config
  # folder, and the test imports `plugin` (the runtime) and `components`
  # directly. The fonts link is not optional - NTheme resolves
  # `../../fonts/...` from `components/nothing/`, and without it the Nothing
  # face goes missing silently, which nothing in this suite asserts.
  ln -s "$PLUGIN_DIR" "$tmp/plugin"
  ln -s "$PLUGIN_DIR/components" "$tmp/components"
  ln -s "$PLUGIN_DIR/fonts" "$tmp/fonts"
  [[ -n $fixture ]] && "$fixture" "$home"

  # HOME and XDG_CONFIG_HOME are the scratch tree for every test, `wayland`
  # ones included: Store, Options and PrayerTimes all derive their file paths
  # from HOME, and a behavioural test must not read or write the user's real
  # ~/.config/omarchy. Whatever a test needs to find there - a store file, a
  # shell.json entry - its own fixture has just written.
  local -a env_vars=(TMPDIR="$tmp" HOME="$home" XDG_CONFIG_HOME="$home/.config")
  if [[ $mode == wayland ]]; then
    runtime="$(mktemp -d)"
    test_dirs+=("$runtime")
    # gamescope presents into whatever display it inherits, so inheriting one
    # is exactly what must not happen here: without them it runs windowless.
    env -u WAYLAND_DISPLAY -u DISPLAY XDG_RUNTIME_DIR="$runtime" setsid \
      gamescope --backend headless --expose-wayland -W 1280 -H 720 -- sleep 300 \
      >"$runtime/compositor.log" 2>&1 &
    test_compositor_pid=$!
    local waited=0
    while [[ ! -S $runtime/gamescope-0 ]]; do
      if [[ $waited -ge 200 ]] || ! kill -0 "$test_compositor_pid" 2>/dev/null; then
        echo "SKIP: $name (headless compositor did not come up)"
        return 0
      fi
      sleep 0.1
      waited=$((waited + 1))
    done
    env_vars+=(QT_QPA_PLATFORM=wayland XDG_RUNTIME_DIR="$runtime" WAYLAND_DISPLAY=gamescope-0)
  else
    env_vars+=(QT_QPA_PLATFORM=offscreen)
  fi

  out="$(env "${env_vars[@]}" timeout 120 qs -n -p "$tmp/$name" 2>&1 || true)"
  if grep -q "$marker" <<<"$out"; then
    grep -o "$marker.*" <<<"$out" | head -1
  else
    { echo "$name failed:"; grep -E 'FAIL|ERROR' <<<"$out" | head -20; } >&2
    exit 1
  fi
}

# ── 5. PrayerTimes' time-of-day rules ──────────────────────────────────────
#
# Headless, and only when `qs` is available (it is not on a build box). The
# component is driven through six instants via its `nowOverride` seam, since
# the rollover rules cannot be observed any other way and moving the machine's
# clock to test them is forbidden (it re-derives the whole schedule).
#
# Hermetic: the location is the fixture below, written into the scratch HOME,
# and the test derives its six instants from that fixture's own schedule
# instead of writing clock times. Karachi with the Karachi method (18 degrees,
# no DST) keeps every case on the day it was derived from in any season - the
# derivation was swept across a full year before it was pinned, because
# seeding a config under fixed times like 06:00 passes today and fails the
# month the sun rises later than that.
fixture_prayers() {
  local home="$1"
  cat >"$home/.config/omarchy/shell.json" <<'JSON'
{
  "plugins": [
    {
      "id": "t1nk33r.omaprayers",
      "locationLabel": "Karachi",
      "latitude": "24.8607",
      "longitude": "67.0011",
      "timezone": "Asia/Karachi",
      "calculationMethod": 1,
      "language": "English",
      "timeFormat": "24-hour"
    }
  ],
  "bar": { "layout": { "left": [], "center": [], "right": [] } }
}
JSON
}

ROLLOVER="$SCRIPT_DIR/prayer-rollover.qml"
run_qml_test "$ROLLOVER" "OK: PrayerTimes rollover" fixture_prayers

# ── 5b. The Nothing primitives: paint triggers, gating, the fit solver ─────
#
# Three defects that are all invisible in the source: NDial draws values it
# never observes, NDotField builds its whole dot grid while hidden, and
# NDotMatrix's gap floor can contradict its own fit solver. The repaint half
# is checked in pixels as well as in a counter - a trigger that fires without
# the painter drawing anything new passes the counter and fails the bytes.
#
# It has its own harness rather than run_qml_test because it needs OUT to
# name where the grabs land, and a real QtQuick Window to attach them to: an
# Item under ShellRoot alone never attaches to one, its Canvas never paints,
# and grabToImage() refuses. Everything it touches is under the scratch
# directory, OUT included.
if [[ ! -f "$SCRIPT_DIR/nothing-primitives.qml" ]]; then
  # A missing file is not a missing dependency: with `qs` on PATH this used to
  # print the SKIP that belongs to a box without `qs`, so a renamed or
  # mis-pathed test shrank the suite by 14 checks and the run stayed green -
  # the exact bug run_qml_test above no longer has.
  echo "missing test file: $SCRIPT_DIR/nothing-primitives.qml" >&2
  exit 1
fi
if have qs; then
  prim_tmp="$(mktemp -d)"
  test_dirs+=("$prim_tmp")
  trap cleanup_tests EXIT
  cp "$SCRIPT_DIR/nothing-primitives.qml" "$prim_tmp/nothing-primitives.qml"
  cp -rL "$PLUGIN_DIR/components" "$prim_tmp/components"
  # Its three NTheme instances resolve `../../fonts/...` from inside the
  # copied components directory, so the face has to be reachable there too.
  ln -s "$PLUGIN_DIR/fonts" "$prim_tmp/fonts"
  mkdir -p "$prim_tmp/home/.config"
  prim_out="$(env HOME="$prim_tmp/home" XDG_CONFIG_HOME="$prim_tmp/home/.config" \
    OUT="$prim_tmp" QT_QPA_PLATFORM=offscreen timeout 60 \
    qs -n -p "$prim_tmp/nothing-primitives.qml" 2>&1 || true)"
  if ! grep -q "OK: nothing primitives" <<<"$prim_out"; then
    { echo "nothing-primitives.qml failed:"
      grep -E 'FAIL|ERROR' <<<"$prim_out" | head -20; } >&2
    exit 1
  fi
  grep -o "OK: nothing primitives.*" <<<"$prim_out" | head -1

  # The grabs are the pixel half of the repaint check, and both directions
  # matter: an unchanged canvas must re-grab identically (or the comparison
  # is trivially "different" and proves nothing), and the first change must
  # really alter the bytes (or the trigger fired without a redraw).
  for stage in p0 p0b p1; do
    [[ -f "$prim_tmp/$stage.png" ]] \
      || { echo "NDial: the test wrote no $stage.png" >&2; exit 1; }
  done
  cmp -s "$prim_tmp/p0.png" "$prim_tmp/p0b.png" \
    || { echo "NDial: two grabs of an unchanged canvas differ, so the pixel check cannot discriminate" >&2; exit 1; }
  if cmp -s "$prim_tmp/p0.png" "$prim_tmp/p1.png"; then
    echo "NDial: changing ticks repainted nothing - p0.png and p1.png are identical" >&2
    exit 1
  fi
else
  echo "SKIP: nothing-primitives.qml (qs not on PATH)"
fi

# ── 6. The runtime: the store, the settings merge, the style chain ────────
#
# The three things every widget's state and configuration flows through, and
# the three that had no behavioural test at all - which is how two data-loss
# defects shipped: a settings migration that could re-arm and drop a value,
# and a style field written where nothing reads it. The fixtures are written
# into the scratch HOME, never into the user's own config.

# For runtime-store.qml: a store file that does not exist (a first run), a
# truncated one, and the three retired store files the migration reads.
fixture_store() {
  local home="$1"
  # An unparseable body: the store must render nothing and copy the bytes to
  # .bak beside it, not throw and not silently rewrite over them.
  printf '%s' '{"version":1,"widgets":[{"id":"broken-1"' >"$home/scratch/corrupt.json"
  # A document carrying a RETIRED widget type beside the living one and a name
  # the registry never had. Only the retired one may change; the other two must
  # come through untouched, which is what makes the table an exact-match
  # mapping rather than a guess. `type` is also the directory a widget is
  # loaded from, so a row left on the retired name draws nothing at all.
  cat >"$home/scratch/renamed-type.json" <<'JSON'
{
  "version": 1,
  "widgets": [
    { "id": "music-1", "type": "music", "screen": "TEST-1",
      "x": 16, "y": 16, "w": 192, "h": 192,
      "settings": { "playerFilter": "spotify" } },
    { "id": "now-playing-4", "type": "now-playing", "screen": "TEST-1",
      "x": 240, "y": 16, "w": 192, "h": 192, "settings": {} },
    { "id": "no-such-type-1", "type": "no-such-type", "screen": "TEST-1",
      "x": 464, "y": 16, "w": 192, "h": 192, "settings": {} }
  ]
}
JSON
  # This plugin's store under its current name, and the three retired files.
  # No retired row carries the style of the store it came from except the one
  # written that way, and the first collides with the id already in the store -
  # the case the rename exists for. Only a Store at its DEFAULT path may absorb
  # these, which is the one the test leaves unpointed (Store._mayAbsorb).
  cat >"$home/.config/omarchy/nothing-glass.json" <<'JSON'
{
  "version": 1,
  "widgets": [
    { "id": "clock-digital-1", "type": "clock-digital", "screen": "TEST-1",
      "x": 10, "y": 20, "w": 30, "h": 40, "settings": {} }
  ]
}
JSON
  # The second plugin this port briefly shipped as: every row is Nothing.
  cat >"$home/.config/omarchy/nothing.json" <<'JSON'
{
  "version": 1,
  "widgets": [
    { "id": "clock-digital-1", "type": "clock-digital", "screen": "TEST-1",
      "x": 1, "y": 2, "w": 3, "h": 4, "settings": {} },
    { "id": "weather-1", "type": "weather", "screen": "TEST-1",
      "x": 5, "y": 6, "w": 7, "h": 8, "settings": { "textColor": "#abcdef" } }
  ]
}
JSON
  # This plugin's own file before plan 053 renamed it. One row carries the
  # style it was drawn with, the other carries none - a row from THIS file
  # must not come out pinned to Nothing the way the rows above do.
  cat >"$home/.config/omarchy/liquid-nothing.json" <<'JSON'
{
  "version": 1,
  "widgets": [
    { "id": "timer-1", "type": "timer", "screen": "TEST-1",
      "x": 9, "y": 8, "w": 7, "h": 6, "style": "liquid-glass",
      "settings": { "durationSec": 300 } },
    { "id": "perf-1", "type": "perf", "screen": "TEST-1",
      "x": 11, "y": 12, "w": 13, "h": 14, "settings": {} }
  ]
}
JSON
  # A fourth retired file whose `.migrated` name is ALREADY taken - a restored
  # backup, a sync tool - so `mv -n` keeps the source where it is. Absorbing
  # it must still happen exactly once, however many times the store starts.
  cat >"$home/.config/omarchy/liquidglass.json" <<'JSON'
{
  "version": 1,
  "widgets": [
    { "id": "battery-1", "type": "battery", "screen": "TEST-1",
      "x": 21, "y": 22, "w": 192, "h": 192, "settings": {} }
  ]
}
JSON
  printf '%s\n' '{"version":1,"widgets":[]}' >"$home/.config/omarchy/liquidglass.json.migrated"
  # A layout shaped like a real desktop: 37 widgets of 22 types, three tile
  # sizes, two screens, both styles and none, and the per-instance settings
  # the field table offers (strings, numbers, reals, booleans, non-ASCII). The
  # load must hand every row back exactly as it is written here.
  cat >"$home/scratch/legit.json" <<'JSON'
{
  "version": 1,
  "widgets": [
    {"id": "tailscale-1", "type": "tailscale", "screen": "DP-1", "x": 16, "y": 40, "w": 192, "h": 192, "style": "nothing", "settings": {}},
    {"id": "network-1", "type": "network", "screen": "HDMI-A-1", "x": 224, "y": 144, "w": 400, "h": 192, "settings": {"networkInterface": "wlan0"}},
    {"id": "storage-1", "type": "storage", "screen": "DP-1", "x": 432, "y": 248, "w": 400, "h": 400, "style": "nothing", "settings": {"storageMounts": "/, /home"}},
    {"id": "photos-1", "type": "photos", "screen": "HDMI-A-1", "x": 640, "y": 352, "w": 192, "h": 192, "style": "nothing", "settings": {"photoFolder": "~/Pictures/Wallpapers", "photoIntervalSec": 45, "photoShuffle": false}},
    {"id": "clock-digital-1", "type": "clock-digital", "screen": "DP-1", "x": 848, "y": 456, "w": 192, "h": 192, "style": "nothing", "settings": {}},
    {"id": "calendar-1", "type": "calendar", "screen": "HDMI-A-1", "x": 1056, "y": 560, "w": 400, "h": 192, "style": "nothing", "settings": {"firstDayOfWeek": 1, "eventLookaheadDays": 2}},
    {"id": "timer-1", "type": "timer", "screen": "DP-1", "x": 1264, "y": 664, "w": 400, "h": 400, "style": "nothing", "settings": {}},
    {"id": "sunrise-1", "type": "sunrise", "screen": "HDMI-A-1", "x": 16, "y": 768, "w": 192, "h": 192, "style": "nothing", "settings": {"latitude": 40.7128, "longitude": -74.006, "useGeoclue": false}},
    {"id": "tailscale-2", "type": "tailscale", "screen": "DP-1", "x": 224, "y": 872, "w": 192, "h": 192, "style": "nothing", "settings": {}},
    {"id": "prayer-1", "type": "prayer", "screen": "HDMI-A-1", "x": 432, "y": 40, "w": 400, "h": 192, "style": "nothing", "settings": {}},
    {"id": "codeburn-1", "type": "codeburn", "screen": "DP-1", "x": 640, "y": 144, "w": 400, "h": 400, "style": "nothing", "settings": {}},
    {"id": "weather-1", "type": "weather", "screen": "HDMI-A-1", "x": 848, "y": 248, "w": 192, "h": 192, "style": "nothing", "settings": {"location": "Lisbon", "unit": "metric", "refreshMinutes": 30}},
    {"id": "clock-analog-1", "type": "clock-analog", "screen": "DP-1", "x": 1056, "y": 352, "w": 192, "h": 192, "style": "nothing", "settings": {"analogSecondSweep": true}},
    {"id": "calendar-2", "type": "calendar", "screen": "HDMI-A-1", "x": 1264, "y": 456, "w": 400, "h": 192, "settings": {}},
    {"id": "perf-1", "type": "perf", "screen": "DP-1", "x": 16, "y": 560, "w": 400, "h": 400, "settings": {}},
    {"id": "deepseek-1", "type": "deepseek", "screen": "HDMI-A-1", "x": 224, "y": 664, "w": 192, "h": 192, "settings": {}},
    {"id": "claude-usage-1", "type": "claude-usage", "screen": "DP-1", "x": 432, "y": 768, "w": 192, "h": 192, "style": "nothing", "settings": {}},
    {"id": "omarr-1", "type": "omarr", "screen": "HDMI-A-1", "x": 640, "y": 872, "w": 400, "h": 192, "style": "nothing", "settings": {}},
    {"id": "clock-digital-2", "type": "clock-digital", "screen": "DP-1", "x": 848, "y": 40, "w": 400, "h": 400, "settings": {}},
    {"id": "weather-2", "type": "weather", "screen": "HDMI-A-1", "x": 1056, "y": 144, "w": 192, "h": 192, "settings": {"location": "São Paulo"}},
    {"id": "calendar-3", "type": "calendar", "screen": "DP-1", "x": 1264, "y": 248, "w": 192, "h": 192, "settings": {}},
    {"id": "now-playing-1", "type": "now-playing", "screen": "HDMI-A-1", "x": 16, "y": 352, "w": 400, "h": 192, "settings": {"playerFilter": "spotify,mpv", "autoHideEnabled": true}},
    {"id": "codeburn-2", "type": "codeburn", "screen": "DP-1", "x": 224, "y": 456, "w": 400, "h": 400, "settings": {}},
    {"id": "claude-usage-2", "type": "claude-usage", "screen": "HDMI-A-1", "x": 432, "y": 560, "w": 192, "h": 192, "settings": {}},
    {"id": "deepseek-2", "type": "deepseek", "screen": "DP-1", "x": 640, "y": 664, "w": 192, "h": 192, "settings": {}},
    {"id": "perf-2", "type": "perf", "screen": "HDMI-A-1", "x": 848, "y": 768, "w": 400, "h": 192, "settings": {}},
    {"id": "tailscale-3", "type": "tailscale", "screen": "DP-1", "x": 1056, "y": 872, "w": 400, "h": 400, "settings": {}},
    {"id": "battery-1", "type": "battery", "screen": "HDMI-A-1", "x": 1264, "y": 40, "w": 192, "h": 192, "settings": {}},
    {"id": "network-2", "type": "network", "screen": "DP-1", "x": 16, "y": 144, "w": 192, "h": 192, "settings": {}},
    {"id": "storage-2", "type": "storage", "screen": "HDMI-A-1", "x": 224, "y": 248, "w": 400, "h": 192, "settings": {}},
    {"id": "perf-3", "type": "perf", "screen": "DP-1", "x": 432, "y": 352, "w": 400, "h": 400, "settings": {}},
    {"id": "codeburn-3", "type": "codeburn", "screen": "HDMI-A-1", "x": 640, "y": 456, "w": 192, "h": 192, "settings": {}},
    {"id": "claude-usage-3", "type": "claude-usage", "screen": "DP-1", "x": 848, "y": 560, "w": 192, "h": 192, "settings": {}},
    {"id": "deepseek-3", "type": "deepseek", "screen": "HDMI-A-1", "x": 1056, "y": 664, "w": 400, "h": 192, "settings": {}},
    {"id": "calendar-4", "type": "calendar", "screen": "DP-1", "x": 1264, "y": 768, "w": 400, "h": 400, "settings": {}},
    {"id": "city-2-1", "type": "city-2", "screen": "HDMI-A-1", "x": 16, "y": 872, "w": 192, "h": 192, "style": "liquid-glass", "settings": {"clocks": "America/Los_Angeles|LA,Europe/London|,Asia/Tokyo|Tokyo"}},
    {"id": "tailscale-4", "type": "tailscale", "screen": "DP-1", "x": 224, "y": 40, "w": 192, "h": 192, "style": "liquid-glass", "settings": {}}
  ]
}
JSON
  # Rows no writer of this plugin produces: non-finite geometry (spelled as
  # strings - Qt's JSON.parse refuses 1e999), absurd and negative numbers,
  # string sizes, `__proto__` and `constructor` keys, a style that is not a
  # string and settings far past the per-row cap. Every row must come
  # through - clamped, never dropped.
  local note
  note="$(head -c 20000 /dev/zero | tr '\0' x)"
  cat >"$home/scratch/hostile.json" <<JSON
{
  "version": 1,
  "widgets": [
    {"id": "inf-1", "type": "weather", "screen": "TEST-1", "x": "NaN", "y": -40, "w": "Infinity", "h": -10,
     "settings": {"__proto__": {"polluted": true}, "location": "Paris"}},
    {"id": "huge-1", "type": "perf", "screen": "TEST-1", "x": 1e308, "y": "12", "w": "192", "h": null,
     "settings": {"note": "$note"}},
    {"__proto__": {"polluted": true}, "id": "proto-1", "type": "timer", "screen": "TEST-1",
     "x": 16, "y": 16, "w": 192, "h": 192, "style": 12, "settings": {"constructor": 1, "durationSec": 300}}
  ]
}
JSON
  # A well-formed document past the 4 MiB parse cap: it must take the
  # corrupt-file path (not loaded, backed up, left on disk as it is).
  { printf '%s' '{"version":1,"widgets":[{"id":"big-1","type":"perf","screen":"TEST-1","x":16,"y":16,"w":192,"h":192,"settings":{}}],"pad":"'
    head -c 4500000 /dev/zero | tr '\0' a
    printf '%s\n' '"}'; } >"$home/scratch/huge.json"
  # 300 ordinary rows, more than the 256 a writer may add: all of them load.
  { printf '%s' '{"version":1,"widgets":['
    local i
    for ((i = 1; i <= 300; i++)); do
      ((i > 1)) && printf ','
      printf '{"id":"perf-%d","type":"perf","screen":"TEST-1","x":%d,"y":16,"w":192,"h":192,"settings":{}}' "$i" "$i"
    done
    printf '%s\n' ']}'; } >"$home/scratch/crowd.json"
}

# For runtime-settings-merge.qml: the plugin's shell.json entry and its own
# options file, each carrying a different value for the keys the precedence
# assertions use. The strings are the shape `omarchy bar set` writes unless
# told --json; the *X10/*Pct keys are the legacy spellings an older build
# stored.
fixture_merge() {
  local home="$1"
  cat >"$home/.config/omarchy/shell.json" <<'JSON'
{
  "plugins": [
    {
      "id": "t1nk33r.nothing-glass",
      "styleMode": 1,
      "appearance": 1,
      "cornerRadius": "42",
      "realtimeRefraction": "true",
      "roundnessX10": 75,
      "refractIORx100": 150,
      "tintAlphaPct": 25,
      "chromaStrengthPct": 75,
      "specStrengthPct": 50
    }
  ],
  "bar": { "layout": { "left": [], "center": [], "right": [] } }
}
JSON
  cat >"$home/.config/omarchy/nothing-glass-options.json" <<'JSON'
{
  "version": 1,
  "options": {
    "styleMode": 2,
    "refreshMinutes": "30",
    "widgetStyle": "nothing",
    "categoryStyles": { "Time": "liquid-glass" }
  }
}
JSON
}

run_qml_test "$SCRIPT_DIR/runtime-store.qml" \
  "OK: store round-trip and migration" fixture_store
run_qml_test "$SCRIPT_DIR/runtime-settings-merge.qml" \
  "OK: settings merge and style resolution" fixture_merge wayland

# ── 7. The calendar never draws an account path ────────────────────────────
#
# The no-backend empty state prints the watched events path onto the desktop.
# Its own runner varies HOME and XDG_STATE_HOME, which run_qml_test pins.
bash "$SCRIPT_DIR/eventsource-home-relative.sh"

# ── 8. GeoClue is an opt-in, and an opt-out holds ──────────────────────────
#
# Replaces the helper with a stub, so it needs its own scratch copy.
bash "$SCRIPT_DIR/geolocation-optin.sh"

# ── 9. Weather requests are bounded ────────────────────────────────────────
#
# Real curl against a local server: a deadline, a byte cap, one at a time.
bash "$SCRIPT_DIR/weather-http.sh"

# ── 10. Text from outside is drawn, never obeyed ───────────────────────────
#
# The real weather header and calendar event card given <img> markup: no
# fetch, against an AutoText control that must fetch.
bash "$SCRIPT_DIR/untrusted-text.sh"

# ── 13. Now Playing cover art is bounded before Qt sees it ─────────────────
#
# Real curl against local HTTPS/HTTP servers, through both real drawings.
bash "$SCRIPT_DIR/cover-art.sh"

# ── 14. Settings never become arguments, and children have deadlines ───────
bash "$SCRIPT_DIR/photo-folder.sh"
bash "$SCRIPT_DIR/argv-hardening.sh"
bash "$SCRIPT_DIR/child-deadlines.sh"
bash "$SCRIPT_DIR/prayer-zone-state.sh"

# ── 15. File-backed JSON is refused past its cap ───────────────────────────
bash "$SCRIPT_DIR/json-caps.sh"

# ── 16. Wallpaper paths, hidden clocks ─────────────────────────────────────
bash "$SCRIPT_DIR/wallpaper.sh"
bash "$SCRIPT_DIR/clock-visibility.sh"

# ── 16b. The DeepSeek tile with a full ledger ──────────────────────────────
bash "$SCRIPT_DIR/deepseek-layout.sh"

# ── 17. The IPC verbs only write real settings ─────────────────────────────
bash "$SCRIPT_DIR/settings-ipc.sh"

exit 0
