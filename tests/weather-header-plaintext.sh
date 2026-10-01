#!/usr/bin/env bash
# The weather header draws a city name that comes from a web service (the
# geocoder, or wttr.in for the IP's city). Drawn as rich text, a name like
# <img src="http://…"> made the shell fetch that URL - outside every limit
# the weather requests have. This draws the real Liquid Glass header with
# such a name and counts what the shell asks a local server for.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for tool in qs python3; do
  command -v "$tool" >/dev/null || { echo "SKIP: weather header plain text ($tool not on PATH)"; exit 0; }
done

scratch=$(mktemp -d)
server_pid=""
cleanup() {
  [[ -n $server_pid ]] && kill "$server_pid" 2>/dev/null || true
  rm -rf "$scratch"
}
trap cleanup EXIT
mkdir -p "$scratch/home" "$scratch/runtime" "$scratch/widgets/weather"
chmod 700 "$scratch/runtime"
# The header's own layout: it loads icons from ../../../icons.
cp -r "$root/widgets/weather/widget" "$scratch/widgets/weather/widget"
cp -r "$root/icons" "$scratch/icons"

cat > "$scratch/server.py" <<'EOF'
import sys, http.server
hits = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        with open(hits, "a") as f: f.write(self.path + "\n")
        self.send_response(404)
        self.send_header("Content-Length", "0")
        self.end_headers()
s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
print(s.server_address[1], flush=True)
s.serve_forever()
EOF
python3 "$scratch/server.py" "$scratch/hits" > "$scratch/port" &
server_pid=$!
for _ in $(seq 50); do [[ -s $scratch/port ]] && break; sleep 0.1; done
port=$(head -1 "$scratch/port")
[[ -n $port ]] || { echo "weather header plain text: the local server did not start" >&2; exit 1; }

cat > "$scratch/probe.qml" <<'EOF'
import QtQuick
import Quickshell
import "widgets/weather/widget" as W
FloatingWindow {
    implicitWidth: 400; implicitHeight: 200; color: "black"
    QtObject {
        id: report
        property string cityName: '<img src="http://127.0.0.1:' + Quickshell.env("PROBE_PORT") + '/beacon">'
        property string condition: '<img src="http://127.0.0.1:' + Quickshell.env("PROBE_PORT") + '/beacon">'
        property string currentTemp: "20"
        property string tempSymbol: "°C"
        property string highTemp: "25"
        property string lowTemp: "15"
        property int weatherCode: 0
        property bool isNight: false
        function iconNameForCode(code, night) { return "sunny" }
    }
    W.WeatherHeader {
        anchors.fill: parent
        weatherData: report
        colors: QtObject {
            property color weatherForeground: "white"
            property string weatherIconSet: "default"
        }
    }
    // Long enough for a fetch the layout started to reach the server.
    Timer { interval: 1500; running: true; onTriggered: { console.log("RESULT|drawn"); Qt.quit() } }
}
EOF

out=$(env -i PATH="$PATH" HOME="$scratch/home" XDG_RUNTIME_DIR="$scratch/runtime" QT_QPA_PLATFORM=offscreen \
  PROBE_PORT="$port" timeout 20 qs -n -p "$scratch/probe.qml" 2>&1 || true)
if ! grep -q 'RESULT|drawn' <<<"$out"; then
  echo "weather header plain text: the header did not draw:" >&2
  grep -iE 'error|warn' <<<"$out" | head -5 >&2
  exit 1
fi
hits=$(grep -c beacon "$scratch/hits" 2>/dev/null || true)
if [[ ${hits:-0} != 0 ]]; then
  echo "weather header plain text: a city name made the shell fetch a URL ($hits request(s))" >&2
  exit 1
fi
echo "OK: the weather header draws service-supplied names as plain text"
