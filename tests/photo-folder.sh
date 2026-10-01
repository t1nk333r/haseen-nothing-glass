#!/usr/bin/env bash
# The photo tile's folder setting is free text (settings sheet, IPC `set` and
# `option`, the config files) and becomes an argument of `find`. Runs the real
# PhotoData, real `find`, from a scratch working directory holding files:
#   expression   a folder of `-delete` or `-fprint <path>` is refused with an
#                error and never reaches `find` - every file in the working
#                directory survives and nothing is written
#   relative     a relative folder is refused the same way
#   urls         a real folder whose picture names hold `#`, `?` and `%`
#                yields file URLs that actually load
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for tool in qs python3 timeout; do
  command -v "$tool" >/dev/null || { echo "SKIP: photo folder ($tool not on PATH)"; exit 0; }
done

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/home" "$scratch/runtime" "$scratch/cwd" "$scratch/pics" "$scratch/probe"
chmod 700 "$scratch/runtime"
cp -r "$root/components" "$scratch/probe/components"

# A real 1x1 PNG, written with the stdlib only.
python3 - "$scratch" <<'EOF'
import struct, sys, zlib
def png():
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"\x00\xff\x00\x00")) + chunk(b"IEND", b""))
d = sys.argv[1]
for name in ("cwd/keep.png", "cwd/keep.jpg", "pics/a#b.png", "pics/c?d.png", "pics/e%41f.png"):
    open(d + "/" + name, "wb").write(png())
open(d + "/cwd/notes.txt", "w").write("keep me\n")
EOF

cat > "$scratch/probe/probe.qml" <<'EOF'
import QtQuick
import Quickshell
import "components" as C
Scope {
    id: probe
    property var started: Date.now()
    property int loadedImages: -1
    C.PhotoData {
        id: photos
        folder: Quickshell.env("PROBE_FOLDER")
        shuffle: false
        intervalSec: 0
    }
    Timer {
        interval: 150; running: Quickshell.env("PROBE_RACE") === "1"
        onTriggered: photos.folder = "-delete"
    }
    // One Image per URL the folder produced; each must reach Ready.
    Instantiator {
        id: imgs
        model: photos.files
        delegate: Image { source: modelData; asynchronous: true }
    }
    Timer {
        interval: 50; repeat: true; running: true
        onTriggered: {
            var settled = photos.loaded
            var ready = 0, failed = 0
            for (var i = 0; i < imgs.count; i++) {
                var it = imgs.objectAt(i)
                if (it && it.status === Image.Ready) ready++
                else if (it && it.status === Image.Error) failed++
            }
            if (settled && ready + failed < photos.count && Date.now() - probe.started < 8000) return
            if (!settled && Date.now() - probe.started < 8000) return
            // Give a refused folder's would-be scan time to have run.
            if (Date.now() - probe.started < 1500) return
            console.log("PHOTO|" + photos.loaded + "|" + photos.errorMessage + "|" + photos.count + "|" + ready)
            Qt.quit()
        }
    }
}
EOF

failed=0
fail() { echo "FAIL $*" >&2; failed=1; }

# run_ <folder> -> the PHOTO| line
run_() {
  (cd "$scratch/cwd" && env -i PATH="$PATH" HOME="$scratch/home" XDG_RUNTIME_DIR="$scratch/runtime" \
    QT_QPA_PLATFORM=offscreen PROBE_FOLDER="$1" PROBE_RACE="${PROBE_RACE:-}" \
    timeout 30 qs -n -p "$scratch/probe/probe.qml" 2>&1 || true) | sed -n 's/.*PHOTO|//p' | head -1
}

cwd_intact() {
  local f
  for f in keep.png keep.jpg notes.txt; do [[ -f $scratch/cwd/$f ]] || return 1; done
  [[ $(find "$scratch/cwd" -mindepth 1 | wc -l) -eq 3 ]]
}

refused='true|Photo folder must be an absolute path|0|0'
out=$(run_ "-delete")
cwd_intact || fail "photo folder '-delete': files in the working directory were removed"
[[ $out == "$refused" ]] || fail "photo folder '-delete': expected '$refused', got '${out:-<nothing>}'"
out=$(run_ "-fprint $scratch/written")
[[ ! -e $scratch/written ]] || fail "photo folder '-fprint': find wrote $scratch/written"
cwd_intact || fail "photo folder '-fprint': the working directory changed"
[[ $out == "$refused" ]] || fail "photo folder '-fprint': expected '$refused', got '${out:-<nothing>}'"
out=$(run_ "cwd")
[[ $out == "$refused" ]] || fail "photo folder 'cwd' (relative): expected '$refused', got '${out:-<nothing>}'"
(( failed == 0 )) && echo "OK: photo folder refuses expressions and relative paths (find never sees them)"

out=$(run_ "$scratch/pics")
[[ $out == 'true||3|3' ]] || fail "photo URLs for names with # ? %: expected 'true||3|3', got '${out:-<nothing>}'"

real_find=$(command -v find)
mkdir -p "$scratch/bin"
cat > "$scratch/bin/find" <<EOF
#!/bin/sh
sleep 1
exec "$real_find" "\$@"
EOF
chmod +x "$scratch/bin/find"
out=$(PATH="$scratch/bin:$PATH" PROBE_RACE=1 run_ "$scratch/pics")
[[ $out == "$refused" ]] || fail "photo folder changed to -delete during a scan: got '${out:-<nothing>}'"
(( failed == 0 )) || exit 1
echo "OK: photo URLs load for names holding # ? %"
echo "OK: an in-flight photo scan cannot overwrite rejection of a new invalid folder"
