#!/usr/bin/env bash
# The DeepSeek tile's layout with a full ledger: tests/deepseek-layout.qml
# loads both drawings at every grid preset, through the widget sweep's own
# tile (the four ids WidgetHost.qml injects), and measures where the texts
# landed. The sweep cannot see this: its scratch HOME has no ledger, so every
# DeepSeek tile it draws is the "No reading" notice.
#
# The fixture fills all six breakdown rows and arms a low-balance threshold
# above the balance, so the header carries its verdict - the tile at its most
# crowded.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for tool in qs python3; do
  command -v "$tool" >/dev/null || { echo "SKIP: deepseek layout ($tool not on PATH)"; exit 0; }
done

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/runtime" "$scratch/home"
chmod 700 "$scratch/runtime"
cp "$root/tests/deepseek-layout.qml" "$root/tests/WidgetSweepTile.qml" "$scratch/"
# `qs` only loads modules under the root it was started from, so the plugin,
# its components and the fonts NTheme resolves are linked in beside the test.
ln -s "$root" "$scratch/plugin"
ln -s "$root/components" "$scratch/components"
ln -s "$root/fonts" "$scratch/fonts"

python3 - "$scratch/home" <<'EOF'
import json, os, sys, time
home = sys.argv[1]
now = int(time.time() * 1000)
day = 86400000
def put(rel, doc):
    path = os.path.join(home, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(doc, f)
# Read a minute ago, so the tile is neither stale nor dated in the future.
put(".local/state/omarchy/t1nk33r.agents/deepseek/usage.state", {
    "version": 2, "currency": "USD", "firstSeenAt": now - 30 * day,
    "lastAt": now - 60000, "lastTotal": 12.34, "spent": 210.56,
    "spentPeak": 63.84, "spentOffPeak": 146.72, "added": 248.70, "days": []})
put(".config/deepspend/config.json", {"lowBalanceThreshold": 50})
EOF

out=$(env -i PATH="$PATH" HOME="$scratch/home" XDG_STATE_HOME="$scratch/home/.local/state" \
  XDG_CONFIG_HOME="$scratch/home/.config" XDG_RUNTIME_DIR="$scratch/runtime" TMPDIR="$scratch" \
  QT_QPA_PLATFORM=offscreen timeout 60 qs -n -p "$scratch/deepseek-layout.qml" 2>&1 || true)
marker="OK: the DeepSeek balance stays the largest text and nothing on the tile overlaps, on every preset"
if grep -qF "$marker" <<<"$out"; then
  echo "$marker"
else
  { echo "deepseek-layout.qml failed ($(grep -c 'FAIL' <<<"$out" || true) failures, first 40 shown):"
    grep -E 'FAIL|ERROR|is not a type' <<<"$out" | sed 's/^.*FAIL/FAIL/' | head -40 || true; } >&2
  exit 1
fi
