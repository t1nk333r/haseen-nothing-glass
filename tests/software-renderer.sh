#!/usr/bin/env bash
# Under Qt's software scene graph - haseen's shell default - every tile still
# has a material. tests/software-renderer.qml checks the components' own
# verdicts; with ImageMagick present this also measures the grabbed tiles,
# because the defect was a tile that painted no pixels at all: a frosted
# Nothing card's coverage must be its surface (81% opaque here), both
# LiquidGlass modes must cover their squircle, and a solid tile's
# solidColor -> solidColorBottom blend must survive the fallback.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
command -v qs >/dev/null || { echo 'SKIP: software renderer (qs unavailable)'; exit 0; }
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/runtime" "$scratch/home" "$scratch/out"
chmod 700 "$scratch/runtime"
cp "$root/tests/software-renderer.qml" "$root/FrostLayer.qml" "$scratch/"
cp -r "$root/components" "$scratch/components"
ln -s "$root/fonts" "$scratch/fonts"
out=$(env -i PATH="$PATH" HOME="$scratch/home" XDG_RUNTIME_DIR="$scratch/runtime" OUT="$scratch/out" \
  QT_QPA_PLATFORM=offscreen timeout 30 qs -n -p "$scratch/software-renderer.qml" 2>&1 || true)
if ! grep -q 'OK: software renderer fallbacks' <<<"$out"; then
  { echo 'FAIL: software renderer fallbacks'; grep -E 'FAIL|ERROR|is not a type' <<<"$out" | head -20; } >&2
  exit 1
fi
echo 'OK: under the software renderer the frost and glass components fall back to a fill'
command -v magick >/dev/null || { echo 'SKIP: software renderer pixels (magick unavailable)'; exit 0; }
coverage() { magick "$scratch/out/$1.png" -alpha extract -format '%[fx:mean]' info:; }
# Mean alpha over the grabbed square, against a floor well under what each
# tile paints (measured: card 0.81 at surfaceAlpha 0.81, glass 0.52 for the
# 0.55 fallback, solid 0.96) and far above an empty tile, whose only pixels
# are the card's hairline (0.05).
failed=0
for row in card:0.6 glass:0.3 solid:0.8; do
  tile=${row%%:*} floor=${row#*:}
  [[ -f $scratch/out/$tile.png ]] || { echo "FAIL: no grab of the $tile tile" >&2; failed=1; continue; }
  c=$(coverage "$tile")
  awk -v c="$c" -v f="$floor" 'BEGIN { exit !(c > f) }' || { echo "FAIL: the $tile tile painted ${c} coverage, under ${floor}" >&2; failed=1; }
done
# The solid tile asks for a vertical #336699 -> #993366 blend; the fallback must
# draw it as the shader does, top to bottom and opaque. Each sample is held to
# within 6 of the straight line between the stops at its row, so a flat fill, a
# reversed blend or another colour fails (measured on both renderers: rows 10
# and 182 of the 192 px tile read 57,99,150 and 148,54,105).
if [[ -f $scratch/out/solid.png ]]; then
  for y in 10 96 182; do
    rgb=$(magick "$scratch/out/solid.png" -crop 1x1+96+"$y" \
      -format '%[fx:int(255*r+0.5)] %[fx:int(255*g+0.5)] %[fx:int(255*b+0.5)] %[fx:int(255*a+0.5)]' info:)
    awk -v y="$y" -v rgb="$rgb" 'BEGIN {
      split(rgb, p, " "); t = (y + 0.5) / 192
      split("51 102 153", top, " "); split("153 51 102", bot, " ")
      for (i = 1; i <= 3; i++) {
        d = p[i] - (top[i] + (bot[i] - top[i]) * t)
        if (d > 6 || d < -6) exit 1
      }
      exit !(p[4] == 255)
    }' || { echo "FAIL: the solid tile drew ($rgb) at row $y, not the opaque solidColor -> solidColorBottom blend" >&2; failed=1; }
  done
fi
(( failed == 0 )) || exit 1
echo 'OK: every tile paints its material under the software renderer, gradient included'
