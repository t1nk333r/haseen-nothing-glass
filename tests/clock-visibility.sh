#!/usr/bin/env bash
# Load every analog clock that runs a 16 ms sweep timer, in both drawings, with
# the sweep turned on; each second hand must freeze hidden and resume visible.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for tool in qs timeout jq; do
  command -v "$tool" >/dev/null || { echo "SKIP: clock visibility ($tool not on PATH)"; exit 0; }
done
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/runtime" "$scratch/home" "$scratch/widgets" "$scratch/widgets-nothing"
chmod 700 "$scratch/runtime"
cp -r "$root/components" "$root/fonts" "$scratch/"
cp -r "$root/widgets/clock-analog" "$root/widgets/clock-analog-2" "$root/widgets/clock-analog-3" "$scratch/widgets/"
cp -r "$root/widgets-nothing/clock-analog" "$root/widgets-nothing/clock-analog-2" "$root/widgets-nothing/clock-analog-3" "$scratch/widgets-nothing/"
jq '.settings.defaults | .analogSecondSweep = true' "$root/manifest.json" > "$scratch/settings.json"
cat > "$scratch/probe.qml" <<'EOF'
import QtQuick
import Quickshell
import Quickshell.Io
import "components/nothing"
Scope {
    id: probe
    QtObject { id: plugin; property var settings: JSON.parse(settingsFile.text()) }
    QtObject { id: theme; property color systemBackground: "#202020"; property var palette: null }
    QtObject { id: backdrop; property Item item: null }
    NTheme { id: nothing }
    FileView { id: settingsFile; path: Qt.resolvedUrl("settings.json").toString().replace("file://", ""); blockLoading: true }
    // Glass clocks expose _secondAngle, Nothing clocks secondAngle.
    readonly property var sources: [
        "widgets/clock-analog/main.qml", "widgets/clock-analog-2/main.qml",
        "widgets/clock-analog-3/main.qml", "widgets-nothing/clock-analog/main.qml",
        "widgets-nothing/clock-analog-2/main.qml", "widgets-nothing/clock-analog-3/main.qml"
    ]
    function angleOf(item) { return item._secondAngle !== undefined ? item._secondAngle : item.secondAngle }
    Window {
        width: 192; height: 192; visible: true
        Item {
            id: host; width: 192; height: 192
            Repeater {
                id: clocks
                model: probe.sources
                Loader { width: 192; height: 192; source: modelData }
            }
        }
    }
    property int stage: 0
    property var angles: []
    property bool passed: true
    Timer {
        interval: 400; running: true; repeat: true
        onTriggered: {
            var items = []
            for (var k = 0; k < probe.sources.length; k++) {
                var l = clocks.itemAt(k)
                if (!l || !l.item) { console.log("FAIL " + probe.sources[k] + " did not load"); Qt.quit(); return }
                items.push(l.item)
            }
            if (probe.stage === 0) host.visible = false
            else if (probe.stage === 1) probe.angles = items.map(probe.angleOf)
            else if (probe.stage === 2) {
                for (var i = 0; i < items.length; i++) {
                    if (probe.angleOf(items[i]) !== probe.angles[i]) {
                        console.log("FAIL " + probe.sources[i] + " hand advanced while hidden")
                        probe.passed = false
                    }
                }
                host.visible = true
            } else {
                for (var j = 0; j < items.length; j++) {
                    if (probe.angleOf(items[j]) === probe.angles[j]) {
                        console.log("FAIL " + probe.sources[j] + " hand did not resume")
                        probe.passed = false
                    }
                }
                if (probe.passed) console.log("OK: every sweeping analog clock hand pauses hidden and resumes visible")
                Qt.quit()
            }
            probe.stage++
        }
    }
}
EOF
out=$(env -i PATH="$PATH" HOME="$scratch/home" XDG_RUNTIME_DIR="$scratch/runtime" QT_QPA_PLATFORM=offscreen timeout 15 qs -n -p "$scratch/probe.qml" 2>&1 || true)
if ! grep -q 'OK: every sweeping analog clock hand pauses hidden and resumes visible' <<<"$out"; then
  echo "FAIL clock visibility probe:" >&2
  grep -E 'FAIL|Error|error' <<<"$out" >&2 || printf '%s\n' "$out" >&2
  exit 1
fi
echo 'OK: every sweeping analog clock hand pauses hidden and resumes visible'
