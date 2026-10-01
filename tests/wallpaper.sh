#!/usr/bin/env bash
# Wallpaper.qml, the backdrop every glass tile refracts. Runs the real
# component, real readlink behind a counting stub, against a scratch HOME
# whose `current/background` link points at a real PNG:
#   url     a wallpaper file named with `#`, `?` and `%` loads (the path is
#           percent-encoded into the file URL, not pasted into it)
#   paused  with `active` false - its screen switched off - the 5 s link poll
#           does not run; turning it back on re-reads the link at once
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for tool in qs python3 readlink; do
  command -v "$tool" >/dev/null || { echo "SKIP: wallpaper ($tool not on PATH)"; exit 0; }
done
real_readlink=$(command -v readlink)

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/home/.local/state/omarchy/current" "$scratch/runtime" "$scratch/bin" "$scratch/wp" \
  "$scratch/probe"
chmod 700 "$scratch/runtime"
cp "$root/Wallpaper.qml" "$scratch/probe/"
python3 - "$scratch/wp/a#b?c%41d.png" <<'EOF'
import struct, sys, zlib
def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
open(sys.argv[1], "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
    + chunk(b"IDAT", zlib.compress(b"\x00\xff\x00\x00")) + chunk(b"IEND", b""))
EOF
ln -s "$scratch/wp/a#b?c%41d.png" "$scratch/home/.local/state/omarchy/current/background"
cat > "$scratch/bin/readlink" <<EOF
#!/bin/sh
date +%s%3N >> "$scratch/readlink-calls"
exec "$real_readlink" "\$@"
EOF
chmod +x "$scratch/bin/readlink"

cat > "$scratch/probe/probe.qml" <<'EOF'
import QtQuick
import Quickshell
Scope {
    id: probe
    property var wp: null
    property var started: Date.now()
    property int step: 0
    Component { id: wpC; Wallpaper {} }
    // Set after creation, and only if the build has the property: an older
    // build then shows its unpaused poll instead of failing to load.
    Component.onCompleted: {
        probe.wp = wpC.createObject(probe)
        if ("active" in probe.wp) probe.wp.active = false
    }
    Timer {
        interval: 100; repeat: true; running: true
        onTriggered: {
            var t = Date.now() - probe.started
            if (probe.step === 0 && t >= 6000) {
                console.log("STATUS|" + (probe.wp.status === Image.Ready))
                console.log("RESUME|" + Date.now())
                if ("active" in probe.wp) probe.wp.active = true
                probe.step = 1
                probe.started = Date.now()
            } else if (probe.step === 1 && t >= 700) {
                Qt.quit()
            }
        }
    }
}
EOF

out=$(env -i PATH="$scratch/bin:$PATH" HOME="$scratch/home" XDG_RUNTIME_DIR="$scratch/runtime" \
  QT_QPA_PLATFORM=offscreen timeout 60 qs -n -p "$scratch/probe/probe.qml" 2>&1 || true)

failed=0
fail() { echo "FAIL $*" >&2; failed=1; }
grep -q 'STATUS|true' <<<"$out" || fail "wallpaper: a file named 'a#b?c%41d.png' did not load"
(( failed == 0 )) && echo "OK: a wallpaper path holding # ? % loads"

# One read at creation and none during the 6 s paused; then a read on resume.
resume=$(sed -n 's/.*RESUME|//p' <<<"$out" | head -1)
if [[ -z $resume ]]; then
  fail "wallpaper: the probe never reached the resume step"
else
  before=0 after=0
  while read -r ms; do
    if (( ms < resume )); then before=$((before + 1)); else after=$((after + 1)); fi
  done < <(cat "$scratch/readlink-calls" 2>/dev/null || true)
  (( before == 1 )) || fail "wallpaper: $before link reads in 6 s with active false, expected only the first"
  (( after == 1 )) || fail "wallpaper: $after link reads on resume, expected one at once"
fi
(( failed == 0 )) || exit 1
echo "OK: the wallpaper link poll pauses while the screen is not drawn, and resumes with a read"
