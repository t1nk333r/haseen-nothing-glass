#!/usr/bin/env bash
# Text that arrives from outside - a city from a web service, a calendar
# title from an organizer or a subscribed feed - is drawn, never obeyed. Left
# on Qt's default AutoText, an <img src="http://…"> in such a string made the
# shell fetch that URL just by drawing it. This draws the real weather header
# and the real calendar event card with such strings and counts what the shell
# asks a local server for.
#
# A control element in the same window is drawn as AutoText on purpose and
# MUST fetch: without it, a Qt that stopped loading inline images offscreen
# would make "no fetch" pass for the wrong reason. (Every Text being
# PlainText is checked statically by tests/run.sh section 4e; this proves the
# setting does what it claims, in the components that met real input.)
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for tool in qs python3; do
  command -v "$tool" >/dev/null || { echo "SKIP: untrusted text ($tool not on PATH)"; exit 0; }
done

scratch=$(mktemp -d)
server_pid=""
cleanup() {
  [[ -n $server_pid ]] && kill "$server_pid" 2>/dev/null || true
  rm -rf "$scratch"
}
trap cleanup EXIT
mkdir -p "$scratch/home" "$scratch/runtime" "$scratch/widgets/weather" "$scratch/widgets/calendar"
chmod 700 "$scratch/runtime"
# The components' own layout: the header loads icons from ../../../icons.
cp -r "$root/widgets/weather/widget" "$scratch/widgets/weather/widget"
cp -r "$root/widgets/calendar/widget" "$scratch/widgets/calendar/widget"
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
[[ -n $port ]] || { echo "untrusted text: the local server did not start" >&2; exit 1; }

cat > "$scratch/probe.qml" <<'EOF'
import QtQuick
import Quickshell
import "widgets/weather/widget" as W
import "widgets/calendar/widget" as Cal
FloatingWindow {
    id: win
    implicitWidth: 400; implicitHeight: 360; color: "black"
    function img(path) { return '<img src="http://127.0.0.1:' + Quickshell.env("PROBE_PORT") + '/' + path + '">' }

    QtObject {
        id: report
        property string cityName: win.img("weather-city")
        property string condition: win.img("weather-condition")
        property string currentTemp: "20"
        property string tempSymbol: "°C"
        property string highTemp: "25"
        property string lowTemp: "15"
        property int weatherCode: 0
        property bool isNight: false
        function iconNameForCode(code, night) { return "sunny" }
    }
    Column {
        anchors.fill: parent
        W.WeatherHeader {
            width: parent.width; height: 200
            weatherData: report
            colors: QtObject {
                property color weatherForeground: "white"
                property string weatherIconSet: "default"
            }
        }
        Cal.EventCard {
            width: parent.width
            title: win.img("calendar-title")
            timeLabel: win.img("calendar-time")
        }
        // The control: the same markup, drawn as AutoText on purpose.
        Text {
            textFormat: Text.AutoText
            color: "white"
            text: win.img("control")
        }
    }
    // Long enough for a fetch the layout started to reach the server.
    Timer { interval: 1500; running: true; onTriggered: { console.log("RESULT|drawn"); Qt.quit() } }
}
EOF

out=$(env -i PATH="$PATH" HOME="$scratch/home" XDG_RUNTIME_DIR="$scratch/runtime" QT_QPA_PLATFORM=offscreen \
  PROBE_PORT="$port" timeout 20 qs -n -p "$scratch/probe.qml" 2>&1 || true)
if ! grep -q 'RESULT|drawn' <<<"$out"; then
  echo "untrusted text: the components did not draw:" >&2
  grep -iE 'error|warn' <<<"$out" | head -5 >&2
  exit 1
fi

count() { grep -c -- "^/$1\$" "$scratch/hits" 2>/dev/null || true; }
control=$(count control)
if [[ ${control:-0} == 0 ]]; then
  echo "untrusted text: the AutoText control fetched nothing, so this run cannot tell plain text from rich" >&2
  exit 1
fi
failed=0
for sink in weather-city weather-condition calendar-title calendar-time; do
  n=$(count "$sink")
  if [[ ${n:-0} != 0 ]]; then
    echo "untrusted text: drawing '$sink' made the shell fetch a URL ($n request(s))" >&2
    failed=1
  fi
done
(( failed == 0 )) || exit 1
echo "OK: text from outside is drawn as plain text, never obeyed (4 sinks, control fetched)"
