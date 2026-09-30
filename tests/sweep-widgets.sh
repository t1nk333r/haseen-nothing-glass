#!/usr/bin/env bash
# Runtime complement to run.sh.
#
# run.sh's sections 1-4 read the plugin's files: manifest/fallback drift,
# qmldir coverage, registry-vs-drawing agreement. All of that can pass while a
# tile still renders as an EMPTY SQUARE, which is this repo's signature
# failure and the reason PORTING.md items 20-21 exist: a QML type that fails
# to resolve draws nothing and logs nothing a static check can see, and a
# wrong `qmldir` line is invisible until something looks at pixels.
#
# So this loads every type the registry offers, in every style it claims,
# through the same injected shims a real host gives a widget, and then
# measures what came out:
#
#   * it loads   - registry.urlFor(type, style) resolves, the Loader reaches
#                  Ready, and no QML diagnostic names the tile's own files.
#   * it draws   - the tile's pixels are not blank and not one flat colour.
#
# Both halves are per tile, because "one of the tiles is blank" is the only
# useful answer; a suite that only knows the process exited zero has not
# tested the thing that breaks here.
#
# Three details are load-bearing, and all three were learned the hard way:
#
#   * The type list comes from WidgetRegistry.qml itself (listTypes /
#     stylesFor / urlFor), read by the driver at runtime. A hand-written list
#     cannot catch a type that was registered wrongly, which is half of what
#     regressed the last time. The registry is also where a silent SHRINK
#     would come from, though - a style that stops being offered renders fewer
#     tiles and every tile that is left still passes - so the rows are also
#     checked against the registry's own table (section 2b), and disagreeing
#     with it fails the run.
#   * The tiles are rendered against a private headless gamescope, never
#     QT_QPA_PLATFORM=offscreen. Offscreen selects Qt's software backend and
#     renders NO GLASS AT ALL, so a Liquid Glass tile would come out as bare
#     wallpaper - and a tile whose contents are drawn through a glass pipeline
#     that never ran is not a tile that was tested. The compositor gets its own
#     XDG_RUNTIME_DIR and no inherited WAYLAND_DISPLAY/DISPLAY, so it can
#     neither see nor disturb whatever session launched this.
#   * Tiles are 192x192 (the small grid preset - the size a tile actually
#     lives at). Grabs are compared on presence of ink and absence of error,
#     never on exact pixels: which numbers a live-data widget finds is not
#     reproducible, and a dpr of 2 would make a "same size" assertion a lie.
#
# Usage: tests/sweep-widgets.sh
# Exit: 0 when every tile passed, 1 when any did not, 0 with a SKIP line when a
# dependency is missing (the same rule run.sh applies to its behavioural half:
# a missing tool is not a defect in the plugin).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

have() { command -v "$1" >/dev/null 2>&1; }

# The driver and its tile, in this script's own directory: tests/ sits beside
# the runtime it drives, and the plugin root IS the repo root.
SWEEP_QML="$SCRIPT_DIR/widget-sweep.qml"
TILE_QML="$SCRIPT_DIR/WidgetSweepTile.qml"

for tool in qs gamescope magick; do
  have "$tool" || { echo "SKIP: widget sweep (needs $tool on PATH)"; exit 0; }
done
[[ -f $SWEEP_QML ]] || { echo "missing $SWEEP_QML" >&2; exit 1; }
[[ -f $TILE_QML ]] || { echo "missing $TILE_QML" >&2; exit 1; }
[[ -f $PLUGIN_DIR/WidgetRegistry.qml ]] || { echo "missing $PLUGIN_DIR/WidgetRegistry.qml" >&2; exit 1; }

# Ink thresholds, on the tile flattened onto black. A blank tile and a single
# flat colour both measure std 0 / one colour, and the two are what this is
# built to catch. The margin is real: across this repo's 53 type/style pairs
# the weakest drawing measures std 0.028 and 163 colours, an order of
# magnitude above both floors, so these are the "drew nothing" boundary
# rather than a tuned number.
INK_MIN_STD=0.01
INK_MIN_COLORS=3

# One EXIT trap for everything this makes, installed before the first thing is
# made (a fresh trap per section silently drops the previous one).
tmp=""
compositor_pid=""
cleanup() {
  # The compositor is started with setsid, so its pid is its process group and
  # nothing it forked can outlive the suite.
  if [[ -n $compositor_pid ]]; then
    kill -TERM -- "-$compositor_pid" 2>/dev/null || true
    kill -TERM "$compositor_pid" 2>/dev/null || true
  fi
  if [[ -n $tmp ]]; then rm -rf "$tmp"; fi
  # A trap that returns non-zero replaces the script's own exit status.
  return 0
}
trap cleanup EXIT

tmp="$(mktemp -d)"
# `qs` refuses to load a QML module path outside the config folder, so the
# driver runs from its own scratch root: the runtime under test, the shared
# components and the fonts are reached through links beside it - the same
# links run.sh's test harness makes, and the fonts one for the same reason
# (NTheme resolves `../../fonts/...` from `components/nothing/`).
cp "$SWEEP_QML" "$tmp/widget-sweep.qml"
cp "$TILE_QML" "$tmp/WidgetSweepTile.qml"
ln -s "$PLUGIN_DIR" "$tmp/plugin"
ln -s "$PLUGIN_DIR/components" "$tmp/components"
ln -s "$PLUGIN_DIR/fonts" "$tmp/fonts"
# Store, Options and GlassSurface all derive their paths as
# $HOME/.config/omarchy/<name>; this is that directory inside the scratch
# tree, never the user's.
mkdir -p "$tmp/home/.config/omarchy" "$tmp/out"

# ── 1. a private headless compositor ──────────────────────────────────────
runtime="$tmp/runtime"
mkdir -p "$runtime"
# Bigger than the tile grid the driver lays out (see OUTPUT_* below), because a
# client window larger than the compositor's output gets resized to fit - which
# would quietly drop the tiles that fell off the edge, the one failure mode a
# sweep must not have. The driver checks the fit and says so if it stops
# holding.
OUTPUT_W=2048
OUTPUT_H=1536
# gamescope presents into whatever display it inherits, so inheriting one is
# exactly what must not happen: with neither WAYLAND_DISPLAY nor DISPLAY set
# it runs windowless, on its own socket, drawing nowhere.
env -u WAYLAND_DISPLAY -u DISPLAY XDG_RUNTIME_DIR="$runtime" setsid \
  gamescope --backend headless --expose-wayland -W "$OUTPUT_W" -H "$OUTPUT_H" -- sleep 300 \
  >"$runtime/compositor.log" 2>&1 &
compositor_pid=$!
waited=0
while [[ ! -S $runtime/gamescope-0 ]]; do
  if [[ $waited -ge 200 ]] || ! kill -0 "$compositor_pid" 2>/dev/null; then
    echo "SKIP: widget sweep (headless compositor did not come up)"
    exit 0
  fi
  sleep 0.1
  waited=$((waited + 1))
done

# ── 2. run the sweep ──────────────────────────────────────────────────────
# stdout and stderr into one file: the driver's protocol lines are prefixed
# SWEEP and everything else in there is a QML diagnostic, which is half of
# what this measures - Qt writes both "is not a type" for a widget that does
# not resolve and "Unable to assign [undefined] to int" for a settings key
# with no default to the same stream, and both are defects.
out="$tmp/sweep.log"
env HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" TMPDIR="$tmp" \
  OUT="$tmp/out" SWEEP_OUTPUT_W="$OUTPUT_W" SWEEP_OUTPUT_H="$OUTPUT_H" \
  QT_QPA_PLATFORM=wayland XDG_RUNTIME_DIR="$runtime" \
  WAYLAND_DISPLAY=gamescope-0 \
  timeout 180 qs -n -p "$tmp/widget-sweep.qml" >"$out" 2>&1 || true

if ! grep -q 'SWEEP done ' "$out"; then
  # Nothing else can show why: the scratch tree (and this log with it) is
  # removed by the trap on the way out.
  echo "FAIL: the sweep did not finish"
  tail -n 40 "$out" | sed 's/^/    /'
  exit 1
fi

# Every pair the registry offered, in registry order, as
# type|style|url|loadstate|png. The `SWEEP tile` lines are printed at
# instantiation, before anything loads, so a pair whose urlFor() yields
# nothing is still a row - and a row that fails.
#
# Quickshell prefixes console output with its own category, so the protocol is
# matched from wherever "SWEEP " starts rather than at the start of the line.
pairs_tsv="$tmp/pairs.tsv"
awk '
  {
    p = index($0, "SWEEP ")
    if (p == 0) next
    n = split(substr($0, p), f, " ")
    if (n < 3) next
    k = f[3] "|" f[4]
    if (f[2] == "tile") { url[k] = f[5]; order[++m] = k }
    else if (f[2] == "load") state[k] = f[5]
    else if (f[2] == "grab") png[k] = f[5]
  }
  END {
    for (i = 1; i <= m; i++) {
      k = order[i]
      print k "|" url[k] "|" state[k] "|" png[k]
    }
  }
' "$out" >"$pairs_tsv"

# ── 2b. the rows must be the pairs the registry's own table implies ───────
#
# The rows above are what the driver asked stylesFor() for - the same function
# a shrink hides behind. Make stylesFor() stop offering a style and the sweep
# renders fewer tiles, every one of them still passes, and the run is green
# while half the drawings were never loaded. Measured, not assumed: with
# stylesFor() patched to return only "liquid-glass" this script printed
# `PASS 27 / FAIL 0`, with the Nothing drawings never instantiated and nothing
# in the output saying so.
#
# So the expectation is read from WidgetRegistry.qml's table - the literal the
# registry builds itself from, parsed the way tests/run.sh section 3 parses it -
# and the two lists must match exactly. `nothingOnly` offers one style,
# `nothing: true` offers both, anything else offers liquid-glass; that is
# stylesFor()'s rule, restated against the data rather than against the
# function. A style that stops being offered is a failure, not a smaller run.
registry_file="$PLUGIN_DIR/WidgetRegistry.qml"
[[ -f $registry_file ]] || { echo "missing $registry_file" >&2; exit 1; }

expected_tsv="$tmp/expected.tsv"
awk '
  /^[[:space:]]*"?[A-Za-z0-9-]+"?:[[:space:]]*\{/ {
    key = $1; sub(/:.*/, "", key); gsub(/"/, "", key); block = ""
  }
  { block = block " " $0 }
  /\}/ {
    if (key != "") {
      n = (block ~ /nothing:[[:space:]]*true/) ? 1 : 0
      o = (block ~ /nothingOnly:[[:space:]]*true/) ? 1 : 0
      if (o) print key "|nothing"
      else if (n) { print key "|liquid-glass"; print key "|nothing" }
      else print key "|liquid-glass"
    }
    key = ""; block = ""
  }
' "$registry_file" | sort >"$expected_tsv"

if [[ ! -s $expected_tsv ]]; then
  echo "parsed no types out of $registry_file - the table is gone or reshaped" >&2
  exit 1
fi

actual_tsv="$tmp/actual.tsv"
cut -d'|' -f1,2 "$pairs_tsv" | sort >"$actual_tsv"

if ! diff -q "$expected_tsv" "$actual_tsv" >/dev/null; then
  {
    echo
    echo "FAIL  the registry's table and the sweep disagree about the pairs."
    echo "      registry implies $(wc -l <"$expected_tsv") pairs, this run rendered $(wc -l <"$actual_tsv"):"
    diff "$expected_tsv" "$actual_tsv" | sed 's/^/      /'
    echo "      (- = offered by the registry and never rendered; + = rendered but not offered)"
  } >&2
  exit 1
fi

# A diagnostic is only attributed to a tile when it names that tile's own
# directory; anything else - a shared component, this harness - is reported
# globally below rather than guessed at, because guessing puts the failure on
# the wrong row. The type list for that global pass comes from the rows
# themselves, so it stays correct as types come and go.
tile_paths_re="$(cut -d'|' -f1 "$pairs_tsv" | sort -u | paste -sd'|')"

# What counts as a defect Qt reported. Two spellings, because the same
# message arrives in two shapes: Qt's own "path.qml:line:col: message", and
# Quickshell's scene-graph form "@path.qml[line:-1]: message", which is how a
# binding that threw shows up. Matching only the first silently drops the
# second, which is the shape a broken binding takes here. It travels to awk
# through the environment rather than `-v`, which would eat the backslashes
# and quietly match the wrong thing (awk warns, and the warning is easy to
# scroll past).
DIAG_RE='\.qml:[0-9]+:[0-9]+:|\.qml\[-?[0-9]+:-?[0-9]+\]:| is not a type|No such file or directory|failed to load|File not found'
export DIAG_RE

# ── 3. the verdict ────────────────────────────────────────────────────────
pass=0
fail=0
failed_names=""
report="$tmp/report.txt"
: >"$report"

while IFS='|' read -r type style url state png; do
  reasons=""

  # (a) it loads. `nousource` and any state but `ready` are exactly the
  # registry/drawing disagreement this half exists for.
  case "$state" in
  ready) ;;
  "") reasons+="no load report from the driver; " ;;
  *) reasons+="load $state; " ;;
  esac
  if [[ -z $url ]]; then reasons+="urlFor() returned no URL; "; fi

  # (a2) the row drew its OWN style. `urlFor()` is the one place that decides
  # which file a user's widget is drawn from, and a cross-wire - every
  # "nothing" row resolving to `widgets/<type>/main.qml`, or the reverse -
  # renders a perfectly good tile of the WRONG drawing: state is ready, the
  # pixels are full of ink, and neither half above can see it. Measured, not
  # assumed: with urlFor() patched to return the Liquid Glass file for both
  # styles, this script printed `PASS 51 / FAIL 0` before this check existed
  # (the row's URL is printed in the report for a failed row and nowhere else,
  # so nothing else in the run ever looked at it).
  #
  # The tree, not the exact file, is the comparison: a widget's own `widget/`
  # helper is free to move, but a style's entry point only ever lives in that
  # style's tree. A `nothingOnly` type is offered in the `nothing` style by
  # stylesFor(), so the same rule covers it.
  if [[ -n $url ]]; then
    case "$style" in
    nothing)
      [[ $url == */widgets-nothing/* ]] \
        || reasons+="nothing row loaded $url; "
      ;;
    *)
      [[ $url != */widgets-nothing/* ]] \
        || reasons+="liquid-glass row loaded $url; "
      ;;
    esac
  fi

  # (b) nothing Qt logged against this tile's own files. The directory to
  # match on comes from the URL this row actually resolved to, not from the
  # type: perf's two rows load `widgets/perf/main.qml` and
  # `widgets-nothing/perf/main.qml`, and matching on the type alone put a
  # missing-file warning from the Nothing drawing on the Liquid Glass row too.
  # The directory (not the file) is the unit, because a diagnostic in a
  # widget's own `widget/` helper still names that widget's directory.
  row_dir=""
  if [[ -n $url ]]; then
    row_dir="$(sed -E 's#.*/(widgets(-nothing)?/[^/]+/).*#\1#' <<<"$url")"
    [[ $row_dir == "$url" ]] && row_dir=""
  fi
  diag=""
  if [[ -n $row_dir ]]; then
    diag="$(awk -v d="$row_dir" '
      BEGIN { dre = ENVIRON["DIAG_RE"] }
      index($0, d) && $0 ~ dre { print }
    ' "$out")"
  fi
  if [[ -n $diag ]]; then reasons+="QML diagnostic; "; fi

  # (c) it draws. A tile that loaded and drew nothing is the silent failure:
  # its grab is blank or one flat colour. The size is the PNG's own, not the
  # driver's idea of it - it is the file the measurement is of.
  std="--"
  colors="--"
  size="--"
  if [[ -z $png || ! -f $png ]]; then
    reasons+="no tile grab; "
  else
    size="$(magick "$png" -format '%wx%h' info: 2>/dev/null || echo '?')"
    stats="$(magick "$png" -background black -flatten -colorspace Gray \
      -format '%[fx:standard_deviation] %k' info: 2>/dev/null || echo "0 0")"
    std="${stats%% *}"
    colors="${stats##* }"
    if awk -v s="$std" -v c="$colors" -v s0="$INK_MIN_STD" -v c0="$INK_MIN_COLORS" \
      'BEGIN { exit !(s < s0 || c < c0) }'; then
      reasons+="no ink (std $std, $colors colours); "
    fi
  fi

  if [[ -z ${reasons//[[:space:]]/} ]]; then
    pass=$((pass + 1))
    printf 'PASS  %-14s %-13s %-9s std %-9s colours %s\n' \
      "$type" "$style" "$size" "$std" "$colors" >>"$report"
  else
    fail=$((fail + 1))
    failed_names+="    $type ($style) - ${reasons%; }"$'\n'
    {
      printf 'FAIL  %-14s %-13s %-9s std %-9s colours %s\n' \
        "$type" "$style" "$size" "$std" "$colors"
      printf '        load %s  url %s\n' "${state:-none}" "${url:-none}"
      if [[ -n $diag ]]; then sed 's/^/        qml: /' <<<"$diag"; fi
    } >>"$report"
  fi
done <"$pairs_tsv"

cat "$report"

# Diagnostics that name no tile: a shared component (LiquidGlass, MacOSColors,
# NTheme, a widget's own `widget/` subdirectory) or this harness itself. They
# are not attributed to a row because the path does not say which widget
# pulled them in - but they cannot be ignored either, so they are printed and
# they fail the run.
global_diag="$(awk -v res="(${tile_paths_re})" '
  BEGIN { dre = ENVIRON["DIAG_RE"] }
  {
    line = $0
    if (line !~ dre) next
    if (match(line, /[^ ]*\.qml/)) file = substr(line, RSTART, RLENGTH); else file = ""
    if (file ~ ("(^|/)widgets(-nothing)?/" res "/")) next
    print line
  }
' "$out")"

if [[ -n ${global_diag//[[:space:]]/} ]]; then
  fail=$((fail + 1))
  echo
  echo "FAIL  shared QML diagnostic (not attributable to one tile):"
  sed 's/^/        /' <<<"$global_diag" | head -40
fi

echo
if [[ $fail -eq 0 ]]; then
  echo "PASS $pass / FAIL 0"
  exit 0
fi
echo "PASS $pass / FAIL $fail"
printf '%s' "$failed_names"
exit 1
