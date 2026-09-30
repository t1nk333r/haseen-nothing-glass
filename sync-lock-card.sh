#!/usr/bin/env bash
# Push this repo's prayer card into the lock screen plugin.
#
# `t1nk33r.lock` renders the same card the desktop `prayer` widget does, from
# COPIES of these files (it is a separate plugin, outside this repo, and QML
# cannot import across plugin directories). Copies drift: the first hand-written
# lock card was on a different font and palette within a day, which is what the
# shared `components/PrayerCard.qml` exists to prevent - but only if the copy
# is refreshed. Run it by hand whenever the lock plugin is installed.
#
# Refuses to touch anything if the lock plugin is not installed, and never
# creates it: this is a mirror, not an installer.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOCK_DIR="${LOCK_PLUGIN_DIR:-$HOME/.config/omarchy/plugins/t1nk33r.lock}"

if [[ ! -d $LOCK_DIR ]]; then
  echo ":: lock plugin not installed ($LOCK_DIR) — nothing to mirror"
  exit 0
fi
if [[ ! -f $LOCK_DIR/LockView.qml ]]; then
  echo ":: $LOCK_DIR has no LockView.qml — refusing to write into it" >&2
  exit 1
fi

mkdir -p "$LOCK_DIR/glass/shaders" "$LOCK_DIR/prayers"

install -m 644 "$SCRIPT_DIR/components/PrayerCard.qml"   "$LOCK_DIR/glass/PrayerCard.qml"
install -m 644 "$SCRIPT_DIR/components/MacOSColors.qml" "$LOCK_DIR/glass/MacOSColors.qml"
install -m 644 "$SCRIPT_DIR/components/LiquidGlass.qml" "$LOCK_DIR/glass/LiquidGlass.qml"

for shader in liquidglass crop kawase_down kawase_up; do
  src="$SCRIPT_DIR/components/shaders/$shader.frag.qsb"
  [[ -f $src ]] && install -m 644 "$src" "$LOCK_DIR/glass/shaders/"
done

# PrayerTimes lives one directory deeper in the lock plugin, so its two
# relative paths to the engine need rewriting on the way in.
sed -e 's|import "prayers/Engine.js" as Engine|import "../prayers/Engine.js" as Engine|' \
    -e 's|Qt.resolvedUrl("prayers/prayer-zone.sh")|Qt.resolvedUrl("../prayers/prayer-zone.sh")|' \
    "$SCRIPT_DIR/components/PrayerTimes.qml" > "$LOCK_DIR/glass/PrayerTimes.qml"

install -m 644 "$SCRIPT_DIR/components/prayers/Engine.js"          "$LOCK_DIR/prayers/Engine.js"
install -m 755 "$SCRIPT_DIR/components/prayers/prayer-zone.sh"     "$LOCK_DIR/prayers/prayer-zone.sh"
install -m 644 "$SCRIPT_DIR/components/prayers/LICENSE.omaprayers" "$LOCK_DIR/prayers/LICENSE.omaprayers"
# No font: the card's face is the lock plugin's own copy under its `fonts/`.
# This script used to mirror the SF Pro Display Regular cut there, and that
# face was removed from this repo (fonts/LICENSES.md) - the lock
# plugin's `LockView.qml` still loads the copy it already has, which is not
# ours to manage.

echo ":: mirrored the prayer card into $LOCK_DIR (glass/, prayers/)"
