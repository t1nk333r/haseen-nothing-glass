#!/usr/bin/env bash
# Every document a data source reads from disk is parsed on the shell's GUI
# thread, so each source refuses one over its size cap (JsonRead.js) instead
# of parsing it, and lands in the state it already has for an unreadable
# file. Runs the real components against real files in a scratch HOME, twice:
#   small   the same documents, a few bytes each, are read as data - so the
#           probe is really reading every source
#   huge    each document padded past its cap (a valid JSON string field, so
#           only the size is wrong) is refused:
#             calendar-events.json (4 MiB)  -> no-backend, "larger than 4 MiB"
#             omarr feed (4 MiB)            -> unreadable
#             claude usage record (1 MiB)   -> invalid
#             DeepSpend ledger (4 MiB)      -> "too large", no balance
#             omarchy weather.json (1 MiB)  -> unset
#             shell.json (4 MiB)            -> no prayer coordinates, and
#                                              PrayerTimes says it is too large
#             codeburn daily cache (8 MiB)  -> "No readable codeburn cache"
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for tool in qs python3; do
  command -v "$tool" >/dev/null || { echo "SKIP: json caps ($tool not on PATH)"; exit 0; }
done

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/runtime"
chmod 700 "$scratch/runtime"
cp -r "$root/components" "$scratch/components"

# write_docs <home> <pad bytes, or 0>
write_docs() {
  python3 - "$1" "$2" <<'EOF'
import json, os, sys
home, pad = sys.argv[1], int(sys.argv[2])
def put(rel, doc, cap_mib):
    if pad:
        # UTF-8 bytes exceed the cap, while UTF-16 length stays below it.
        doc = dict(doc, pad="€" * ((cap_mib * 1048576 + pad) // 3 + 1))
    path = os.path.join(home, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(doc, f, ensure_ascii=False)
put(".local/state/omarchy/calendar-events.json", {"events": []}, 4)
put(".local/state/omarchy/omarr/feed.json", {"version": 1}, 4)
put(".local/state/omarchy/agents/usage/claude.json", {"limits": []}, 1)
put(".local/state/t1nk33r.deepseek/usage.state", {"version": 2, "lastTotal": 5}, 4)
put(".local/state/omarchy/settings/weather.json", {"name": "Padville", "latitude": 1.5, "longitude": 2.5}, 1)
put(".config/omarchy/shell.json", {"plugins": [{"id": "t1nk33r.omaprayers", "latitude": 10.5,
    "longitude": 20.5, "timezone": "UTC", "calculationMethod": 4}]}, 4)
put(".cache/codeburn/daily-cache.v31.json", {"days": [{"date": "2026-09-30", "cost": 1.25}]}, 8)
EOF
}

cat > "$scratch/probe.qml" <<'EOF'
import QtQuick
import Quickshell
import "components" as C
Scope {
    C.EventSource { id: cal; khalEnabled: false }
    C.OmarrData { id: omarr }
    C.ClaudeUsageData { id: claude }
    C.DeepSeekData { id: deep }
    C.OmarchyLocation { id: loc }
    C.GeoLocation { id: geo }
    C.PrayerTimes { id: prayer }
    C.CodeburnData { id: burn }
    Timer {
        // OmarchyLocation's first-read correction fires at 1.5 s.
        interval: 3500; running: true
        onTriggered: {
            console.log("R|calendar|" + cal.state + "|" + cal.readError)
            console.log("R|omarr|" + omarr.state + "|" + omarr.errorMessage)
            console.log("R|claude|" + claude.state)
            console.log("R|deepseek|" + deep.hasBalance + "|" + deep.errorMessage)
            console.log("R|weather|" + loc.name)
            console.log("R|geo|" + geo.source)
            console.log("R|prayer|" + (prayer.error === "shell.json is too large"))
            console.log("R|codeburn|" + burn.cost + "|" + burn.errorMessage)
            Qt.quit()
        }
    }
}
EOF

# run_ <home> -> the R| lines, prefix stripped
run_() {
  env -i PATH="$PATH" HOME="$1" XDG_STATE_HOME="$1/.local/state" XDG_RUNTIME_DIR="$scratch/runtime" \
    QT_QPA_PLATFORM=offscreen timeout 60 qs -n -p "$scratch/probe.qml" 2>&1 \
    | sed -n 's/.*R|//p' || true
}

failed=0
fail() { echo "FAIL $*" >&2; failed=1; }
# expect <label> <output> <expected line>
expect() { grep -qxF -- "$3" <<<"$2" || fail "$1: expected '$3' in:"$'\n'"$2"; }

write_docs "$scratch/small" 0
small=$(run_ "$scratch/small")
expect "small calendar" "$small" "calendar|empty|"
expect "small claude" "$small" "claude|empty"
expect "small deepseek" "$small" "deepseek|true|"
expect "small weather.json" "$small" "weather|Padville"
expect "small shell.json" "$small" "geo|prayer settings"
expect "small codeburn" "$small" "codeburn|1.25|"
(( failed == 0 )) && echo "OK: every capped source reads its document when it is small"

write_docs "$scratch/huge" 4096
huge=$(run_ "$scratch/huge")
expect "huge calendar" "$huge" "calendar|no-backend|the file is larger than 4 MiB"
expect "huge omarr" "$huge" "omarr|unreadable|The omarr feed is too large."
expect "huge claude" "$huge" "claude|invalid"
expect "huge deepseek" "$huge" "deepseek|false|The DeepSpend ledger is too large."
expect "huge weather.json" "$huge" "weather|"
expect "huge shell.json" "$huge" "geo|manual"
expect "huge shell.json (prayer)" "$huge" "prayer|true"
expect "huge codeburn" "$huge" "codeburn|0|No readable codeburn cache"
(( failed == 0 )) || exit 1
echo "OK: a document over its cap is refused unparsed and reads as unreadable"
