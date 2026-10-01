#!/usr/bin/env bash
# A data source's child process that never answers - `df` on a dead NFS or
# FUSE mount, `khal` on a wedged vdir, `codeburn` on a huge corpus, `find` on
# a hung folder - must not hold the component for the rest of the session.
# Each source runs for real against a stub on a scratch PATH that ignores
# SIGTERM and parks a grandchild, the worst case a bound has to end:
#   storage    StorageData reports "df did not answer", and refresh runs again
#   calendar   EventSource reports "khal list did not answer"
#   codeburn   CodeburnData's `recomputing` latch clears, so Sync works again
#   photos     PhotoData reports "Photo folder did not answer", and refresh
#              runs again
#   reaped     no stub and no grandchild survives its bound - including the
#              second round, still in flight when the shell quits (Quickshell
#              SIGKILLs only the direct child on teardown)
# The bounds are shortened through each component's own properties (1 s, and
# a 1 s grace before SIGKILL) so the run takes seconds, not minutes.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for tool in qs timeout pgrep pkill; do
  command -v "$tool" >/dev/null || { echo "SKIP: child deadlines ($tool not on PATH)"; exit 0; }
done

scratch=$(mktemp -d)
marker="31337.$$"
cleanup() {
  pkill -KILL -f "sleep $marker" 2>/dev/null || true
  pkill -KILL -f "$scratch/bin/" 2>/dev/null || true
  rm -rf "$scratch"
}
trap cleanup EXIT
mkdir -p "$scratch/home" "$scratch/runtime" "$scratch/bin" "$scratch/pics" "$scratch/state"
chmod 700 "$scratch/runtime"
cp -r "$root/components" "$scratch/components"

# df obeys TERM but its grandchild does not (timeout alone leaves that child
# behind). The other three ignore TERM themselves and require the KILL grace.
for name in df khal codeburn find; do
  cat > "$scratch/bin/$name" <<EOF
#!/bin/sh
echo "$name" >> "$scratch/calls"
if [ "$name" = df ]; then
  trap 'exit 0' TERM
  sh -c 'trap "" TERM; exec sleep "\$1"' sh $marker &
else
  trap '' TERM
  sleep $marker &
fi
wait
EOF
  chmod +x "$scratch/bin/$name"
done

cat > "$scratch/probe.qml" <<'EOF'
import QtQuick
import Quickshell
import "components" as C
Scope {
    id: probe
    property var started: Date.now()
    property var at: ({})
    property int phase: 0
    property var storage: null
    property var calendar: null
    property var burn: null
    property var photos: null
    // Shortened bounds, set at creation; a build without them just runs the
    // stubs unbounded, and the deadline below reports that.
    readonly property var fast: ({ timeoutSec: 1, _killGraceSec: 1 })
    Component { id: storageC; C.StorageData {} }
    Component { id: calendarC; C.EventSource {} }
    Component { id: burnC; C.CodeburnData {} }
    Component { id: photosC; C.PhotoData {} }
    Component.onCompleted: {
        probe.storage = storageC.createObject(probe, probe.fast)
        probe.calendar = calendarC.createObject(probe, {
            eventsFile: Quickshell.env("PROBE_STATE") + "/none.json",
            khalTimeoutSec: 1, _khalKillGraceSec: 1 })
        probe.burn = burnC.createObject(probe, { syncTimeoutSec: 1, _syncKillGraceSec: 1 })
        probe.photos = photosC.createObject(probe, {
            folder: Quickshell.env("PROBE_PICS"), timeoutSec: 1, _killGraceSec: 1 })
        probe.burn.recompute()
        console.log("RECOMPUTING|" + probe.burn.recomputing)
    }
    function mark(name, done) {
        if (done && probe.at[name] === undefined) {
            var a = probe.at; a[name] = Date.now() - probe.started; probe.at = a
            console.log("SETTLED|" + name + "|" + a[name])
        }
    }
    Timer {
        interval: 50; repeat: true; running: true
        onTriggered: {
            if (probe.phase === 0) {
                probe.mark("storage", probe.storage.errorMessage === "df did not answer")
                probe.mark("calendar", probe.calendar.readError === "khal list did not answer")
                probe.mark("codeburn", !probe.burn.recomputing)
                probe.mark("photos", probe.photos.errorMessage === "Photo folder did not answer")
                var all = Object.keys(probe.at).length === 4
                if (!all && Date.now() - probe.started < 12000) return
                // Recovery: each one can be asked again.
                probe.storage.refresh()
                probe.photos.refresh()
                probe.burn.recompute()
                console.log("AGAIN|codeburn|" + probe.burn.recomputing)
                probe.phase = 1
                probe.started = Date.now()
                return
            }
            if (Date.now() - probe.started < 500) return
            console.log("DONE")
            Qt.quit()
        }
    }
}
EOF

failed=0
fail() { echo "FAIL $*" >&2; failed=1; }

out=$(env -i PATH="$scratch/bin:$PATH" HOME="$scratch/home" XDG_RUNTIME_DIR="$scratch/runtime" \
  XDG_STATE_HOME="$scratch/state" QT_QPA_PLATFORM=offscreen \
  PROBE_STATE="$scratch/state" PROBE_PICS="$scratch/pics" \
  timeout 60 qs -n -p "$scratch/probe.qml" 2>&1 || true)

grep -q '^.*RECOMPUTING|true' <<<"$out" || fail "codeburn: recompute() did not start a run"
# Bound 1 s + grace 1 s; 5 s is the slack for a loaded CI runner.
for name in storage calendar codeburn photos; do
  ms=$(sed -n "s/.*SETTLED|$name|//p" <<<"$out" | head -1)
  if [[ -z $ms ]]; then fail "$name: never settled after its child stopped answering"
  elif (( ms > 5000 )); then fail "$name: settled after ${ms} ms, past the bound"
  fi
done
(( failed == 0 )) && echo "OK: a hung df, khal, codeburn and find each settle within their bound"

grep -q 'AGAIN|codeburn|true' <<<"$out" || fail "codeburn: Sync could not start again after a hung run"
calls=$(cat "$scratch/calls" 2>/dev/null || true)
(( $(grep -c '^df$' <<<"$calls") >= 2 )) || fail "storage: refresh did not run df again after the bound"
(( $(grep -c '^find$' <<<"$calls") >= 2 )) || fail "photos: refresh did not scan again after the bound"
(( $(grep -c '^codeburn$' <<<"$calls") >= 2 )) || fail "codeburn: recompute did not run codeburn again"
(( failed == 0 )) && echo "OK: each source recovers after a bound expires (refresh/Sync run again)"

# The second round was still in flight when the shell quit; its bound and
# grace end it too. Nothing may outlive them.
for _ in $(seq 40); do
  pgrep -f "sleep $marker" >/dev/null || pgrep -f "$scratch/bin/" >/dev/null || break
  sleep 0.25
done
if pgrep -af "sleep $marker|$scratch/bin/" >&2; then fail "a stub or its grandchild outlived its bound"; fi
(( failed == 0 )) || exit 1
echo "OK: no hung child or grandchild is left behind"
