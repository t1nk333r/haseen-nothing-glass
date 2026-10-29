#!/usr/bin/env bash
# Under Qt's software scene graph - haseen's shell default - every tile still
# has a material. tests/software-renderer.qml checks the components' own
# verdicts; with ImageMagick present this also measures the grabbed tiles,
# because the defect was a tile that painted no pixels at all: a frosted
# Nothing card's coverage must be its surface (81% opaque here), both
# LiquidGlass modes must cover their squircle, and a solid tile's
# solidColor -> solidColorBottom blend must survive the fallback, opaque. And
# every MultiEffect layer drew nothing there, so the shader-free drawings of a
# masked picture, a colourised icon, the now-playing cover and buttons, the
# timer's buttons and its rolling digits are each measured too.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
command -v qs >/dev/null || { echo 'SKIP: software renderer (qs unavailable)'; exit 0; }
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/runtime" "$scratch/home" "$scratch/out"
chmod 700 "$scratch/runtime"
cp "$root/tests/software-renderer.qml" "$root/FrostLayer.qml" "$scratch/"
cp -r "$root/components" "$scratch/components"
mkdir -p "$scratch/widgets/timer" "$scratch/widgets/now-playing"
cp -r "$root/widgets/timer/widget" "$scratch/widgets/timer/widget"
cp -r "$root/widgets/now-playing/widget" "$scratch/widgets/now-playing/widget"
ln -s "$root/fonts" "$scratch/fonts"
# Red on the left, blue on the right; and a black disc for the icon tints.
printf '%s\n' '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100">' \
  '<rect width="100" height="100" fill="#ff0000"/><rect x="100" width="100" height="100" fill="#0000ff"/></svg>' \
  >"$scratch/halves.svg"
printf '%s\n' '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">' \
  '<circle cx="12" cy="12" r="10" fill="#000000"/></svg>' >"$scratch/dot.svg"
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
# The solid tile asks for a vertical #336699 -> #993366 blend, its bottom stop
# at alpha 0x80; the fallback must draw it as the shader does, top to bottom
# and opaque. Each sample is held to within 6 of the straight line between the
# stops at its row, so a flat fill, a reversed blend, a translucent stop or
# another colour fails (measured with this fixture on both renderers: rows 10
# and 182 of the 192 px tile read 57,99,150 and 148,54,104 under the GPU
# shader, 57,99,150 and 148,54,105 under the software fallback).
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
# px <tile> <x> <y>: the pixel as "r g b a", 0..255 each.
px() {
  magick "$scratch/out/$1.png" -crop 1x1+"$2"+"$3" \
    -format '%[fx:int(255*r+0.5)] %[fx:int(255*g+0.5)] %[fx:int(255*b+0.5)] %[fx:int(255*a+0.5)]' info:
}
# expect <tile> <x> <y> <awk condition on r g b a> <what it should be>
expect() {
  local tile=$1 x=$2 y=$3 cond=$4 what=$5 rgba
  [[ -f $scratch/out/$tile.png ]] || { echo "FAIL: no grab of the $tile tile" >&2; failed=1; return; }
  rgba=$(px "$tile" "$x" "$y")
  awk -v p="$rgba" "BEGIN { split(p, c, \" \"); r = c[1]; g = c[2]; b = c[3]; a = c[4]; exit !($cond) }" \
    || { echo "FAIL: the $tile tile drew ($rgba) at $x,$y, not $what" >&2; failed=1; }
}
# The flat solid tile: opaque in its translucent colour, and shaped like the
# shader's squircle - (20,20) is outside the disc a 96 px Rectangle radius
# draws on 192 px but inside the superellipse, (2,2) is outside both. The GPU
# shader draws the same three pixels (measured: 51,102,153,255 at the centre
# and at 20,20, clear at 2,2).
expect flat 96 96 'r == 51 && g == 102 && b == 153 && a == 255' 'the opaque #336699 card'
expect flat 20 20 'a == 255' 'inside the squircle'
expect flat 2 2 'a == 0' 'outside the squircle'
# The picture: cropped (red left, blue right), cut to the same squircle, and
# darkened under its caption band.
expect picture 2 2 'a == 0' 'cut away by the squircle'
expect picture 20 20 'r > 200 && b < 60 && a == 255' 'the opaque red half'
expect picture 170 40 'b > 200 && r < 60 && a == 255' 'the opaque blue half'
expect picture 170 186 'b < 150 && a == 255' 'the blue half darkened by the band'
# Colourised glyphs: the disc in the tint, the corners left clear.
expect icon 24 24 'r == 0 && g == 255 && b == 0 && a == 255' 'the disc in #00ff00'
expect icon 1 1 'a == 0' 'clear outside the disc'
expect timerbutton 32 32 'r < 30 && g > 225 && b < 30 && a > 225' 'the glyph in #00ff00'
expect controlbutton 19 19 'r < 30 && g > 225 && b < 30 && a > 225' 'the glyph in #00ff00'
# The cover: cropped, its corners rounded to the art radius.
expect albumart 2 2 'a == 0' 'cut away by the corner radius'
expect albumart 30 60 'r > 200 && b < 60 && a == 255' 'the opaque red half'
expect albumart 90 60 'b > 200 && r < 60 && a == 255' 'the opaque blue half'
# The digits mid-roll: white glyphs, where the blurred layers drew nothing.
if [[ -f $scratch/out/digit.png ]]; then
  peak=$(magick "$scratch/out/digit.png" -alpha extract -format '%[fx:maxima]' info:)
  awk -v m="$peak" 'BEGIN { exit !(m > 0.4) }' \
    || { echo "FAIL: the rolling digit drew nothing mid-roll (peak alpha $peak)" >&2; failed=1; }
else
  echo "FAIL: no grab of the digit tile" >&2; failed=1
fi
(( failed == 0 )) || exit 1
echo 'OK: every tile paints its material under the software renderer, gradient, pictures, glyphs and digits included'
