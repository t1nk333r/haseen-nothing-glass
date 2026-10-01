#!/usr/bin/env bash
# The weather tile's requests are bounded. Each case runs the real
# WeatherDataQs - real curl - against a local server that answers, stalls,
# or streams a body that never ends:
#   ok         a normal answer still renders (the bounds cost nothing)
#   deadline   a stalled forecast fails at the deadline instead of hanging
#   size cap   an endless body is cut off at the byte cap, well before the
#              deadline, so it never piles up in the shell
#   supersede  refreshes during a stalled request leave exactly one request
#              in flight, and tearing the tile down leaves none
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for tool in qs curl python3 pgrep; do
  command -v "$tool" >/dev/null || { echo "SKIP: weather request bounds ($tool not on PATH)"; exit 0; }
done

scratch=$(mktemp -d)
server_pid=""
cleanup() {
  [[ -n $server_pid ]] && kill "$server_pid" 2>/dev/null || true
  rm -rf "$scratch"
}
trap cleanup EXIT
mkdir -p "$scratch/home" "$scratch/runtime"
chmod 700 "$scratch/runtime"
cp -r "$root/components" "$scratch/components"

cat > "$scratch/server.py" <<'EOF'
import json, sys, time, datetime
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

def forecast():
    now = datetime.datetime.now().replace(minute=0, second=0, microsecond=0)
    hours = [(now + datetime.timedelta(hours=h)).strftime("%Y-%m-%dT%H:%M") for h in range(48)]
    days = [(now + datetime.timedelta(days=d)).strftime("%Y-%m-%d") for d in range(7)]
    return {
        "current": {"temperature_2m": 23.4, "weather_code": 1, "wind_speed_10m": 9.0, "wind_direction_10m": 180},
        "hourly": {"time": hours, "temperature_2m": [20.0] * 48, "weather_code": [1] * 48},
        "daily": {"time": days, "temperature_2m_max": [25.0] * 7, "temperature_2m_min": [15.0] * 7,
                  "weather_code": [1] * 7,
                  "sunrise": [d + "T06:00" for d in days], "sunset": [d + "T18:00" for d in days]},
    }

class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): pass
    def send_json(self, obj):
        body = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/geo":
            self.send_json({"results": [{"name": "Testville", "latitude": 10.5, "longitude": 20.5, "country_code": "DE"}]})
        elif path == "/ok":
            self.send_json(forecast())
        elif path == "/stall":
            time.sleep(120)
        elif path == "/huge":
            # Chunked, no Content-Length: the cap must hold without one.
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            block = b"x" * 65536
            try:
                for _ in range(100000):
                    self.wfile.write(b"%x\r\n%s\r\n" % (len(block), block))
            except (BrokenPipeError, ConnectionResetError):
                pass

srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
srv.daemon_threads = True
print(srv.server_address[1], flush=True)
srv.serve_forever()
EOF
python3 "$scratch/server.py" > "$scratch/port" &
server_pid=$!
for _ in $(seq 50); do [[ -s $scratch/port ]] && break; sleep 0.1; done
port=$(head -1 "$scratch/port")
[[ -n $port ]] || { echo "weather request bounds: the local server did not start" >&2; exit 1; }

cat > "$scratch/probe.qml" <<'EOF'
import QtQuick
import Quickshell
import Quickshell.Io
import "components" as C
Scope {
    id: probe
    readonly property string base: "http://127.0.0.1:" + Quickshell.env("PROBE_PORT")
    readonly property string scenario: Quickshell.env("PROBE_SCENARIO")
    property var started: Date.now()
    property bool reported: false

    C.WeatherDataQs {
        id: wd
        location: "Testville"
        _geocodeEndpoint: probe.base + "/geo"
        _forecastEndpoint: probe.base + "/" + Quickshell.env("PROBE_MODE")
        _httpProtocols: "=http"
        _httpTimeoutSec: Number(Quickshell.env("PROBE_TIMEOUT"))
        _httpMaxBytes: Number(Quickshell.env("PROBE_MAXBYTES"))
    }

    // How many curls are talking to the stalling endpoint right now.
    Process {
        id: count
        command: ["pgrep", "-fc", "--", "127.0.0.1:" + Quickshell.env("PROBE_PORT") + "/stall"]
        stdout: StdioCollector {
            onStreamFinished: {
                console.log("RESULT|inflight|" + String(this.text || "0").trim())
                Qt.quit()
            }
        }
    }

    function report(what) {
        if (probe.reported) return
        probe.reported = true
        console.log("RESULT|" + what + "|" + ((Date.now() - probe.started) / 1000).toFixed(1)
                    + "|" + wd.errorMessage + "|" + wd.currentTemp)
        Qt.quit()
    }

    Timer {
        property int ticks: 0
        interval: 100; repeat: true; running: true
        onTriggered: {
            ticks++
            if (probe.scenario === "supersede") {
                // Let the forecast start stalling, refresh twice, then count.
                if (ticks === 15) wd.forceRefresh()
                if (ticks === 17) wd.forceRefresh()
                if (ticks === 25) count.running = true
                return
            }
            if (wd.currentTemp !== "--") probe.report("rendered")
            else if (wd.errorMessage !== "") probe.report("failed")
            else if (ticks > 250) probe.report("timeout")
        }
    }
}
EOF

# run <scenario> <mode> <timeout s> <max bytes>
run() {
  env -i PATH="$PATH" HOME="$scratch/home" XDG_RUNTIME_DIR="$scratch/runtime" QT_QPA_PLATFORM=offscreen \
    PROBE_PORT="$port" PROBE_SCENARIO="$1" PROBE_MODE="$2" PROBE_TIMEOUT="$3" PROBE_MAXBYTES="$4" \
    timeout 40 qs -n -p "$scratch/probe.qml" 2>&1 | sed -n 's/.*RESULT|//p' | head -1 || true
}

failed=0
fail() { echo "weather request bounds, $1" >&2; failed=1; }

r=$(run ok ok 10 1048576)
[[ $r == rendered\|*\|\|23 ]] || fail "ok: expected the forecast to render 23, got '${r:-<nothing>}'"

r=$(run deadline stall 2 1048576)
IFS='|' read -r what secs msg _ <<<"$r"
[[ $what == failed && $msg == "Failed to fetch weather" ]] || fail "deadline: expected the fetch to fail, got '${r:-<nothing>}'"
[[ $what != failed ]] || (( ${secs%.*} < 6 )) || fail "deadline: took ${secs}s with a 2s deadline"

r=$(run size huge 30 65536)
IFS='|' read -r what secs msg _ <<<"$r"
[[ $what == failed && $msg == "Failed to fetch weather" ]] || fail "size cap: expected the fetch to fail, got '${r:-<nothing>}'"
[[ $what != failed ]] || (( ${secs%.*} < 10 )) || fail "size cap: took ${secs}s, so the cap did not cut it off (deadline is 30s)"

r=$(run supersede stall 30 1048576)
[[ $r == "inflight|1" ]] || fail "supersede: expected exactly 1 request in flight after two refreshes, got '${r:-<nothing>}'"
sleep 0.5
left=$(pgrep -fc -- "127.0.0.1:$port/stall" || true)
[[ $left == 0 ]] || fail "supersede: $left request(s) outlived the tile"

(( failed == 0 )) || exit 1
echo "OK: weather requests are bounded in time and size, one at a time (4 cases)"
