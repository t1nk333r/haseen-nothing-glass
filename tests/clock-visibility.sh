#!/usr/bin/env bash
# Load both real analog clocks; the hand must freeze hidden and resume visible.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for tool in qs timeout jq; do
  command -v "$tool" >/dev/null || { echo "SKIP: clock visibility ($tool not on PATH)"; exit 0; }
done
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/runtime" "$scratch/home" "$scratch/widgets"
chmod 700 "$scratch/runtime"
cp -r "$root/components" "$scratch/"
cp -r "$root/widgets/clock-analog-2" "$root/widgets/clock-analog-3" "$scratch/widgets/"
jq '.settings.defaults' "$root/manifest.json" > "$scratch/settings.json"
cat > "$scratch/probe.qml" <<'EOF'
import QtQuick
import Quickshell
import Quickshell.Io
Scope {
    id: probe
    QtObject { id: plugin; property var settings: JSON.parse(settingsFile.text()) }
    QtObject { id: theme; property color systemBackground: "#202020"; property var palette: null }
    QtObject { id: backdrop; property Item item: null }
    FileView { id: settingsFile; path: Qt.resolvedUrl("settings.json").toString().replace("file://", ""); blockLoading: true }
    Window {
      width: 192; height: 192; visible: true
    Item {
        id: host; width: 192; height: 192
        Loader { id: two; anchors.fill: parent; source: "widgets/clock-analog-2/main.qml" }
        Loader { id: three; anchors.fill: parent; source: "widgets/clock-analog-3/main.qml" }
    }
    }
    property int stage: 0
    property var angles: []
    property bool passed: true
    Timer {
        interval: 400; running: true; repeat: true
        onTriggered: {
            if (!two.item || !three.item) { console.log("FAIL clocks did not load"); Qt.quit(); return }
            var items = [two.item, three.item]
            if (probe.stage === 0) host.visible = false
            else if (probe.stage === 1) probe.angles = items.map(function (x) { return x._secondAngle })
            else if (probe.stage === 2) {
                for (var i = 0; i < items.length; i++) {
                    if (items[i]._secondAngle !== probe.angles[i]) {
                        console.log("FAIL clock-analog-" + (i + 2) + " hand advanced while hidden")
                        probe.passed = false
                    }
                }
                host.visible = true
            } else {
                for (var j = 0; j < items.length; j++) {
                    if (items[j]._secondAngle === probe.angles[j]) {
                        console.log("FAIL clock-analog-" + (j + 2) + " hand did not resume")
                        probe.passed = false
                    }
                }
                if (probe.passed) console.log("OK: both analog clock hands pause hidden and resume visible")
                Qt.quit()
            }
            probe.stage++
        }
    }
}
EOF
out=$(env -i PATH="$PATH" HOME="$scratch/home" XDG_RUNTIME_DIR="$scratch/runtime" QT_QPA_PLATFORM=offscreen timeout 15 qs -n -p "$scratch/probe.qml" 2>&1 || true)
if ! grep -q 'OK: both analog clock hands pause hidden and resume visible' <<<"$out"; then
  echo "FAIL clock visibility probe:" >&2
  printf '%s\n' "$out" >&2
  exit 1
fi
echo 'OK: both analog clock hands pause hidden and resume visible'
