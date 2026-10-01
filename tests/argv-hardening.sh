#!/usr/bin/env bash
# Values that come from outside the plugin and end up in a child's argv or
# environment are confined to what they are meant to be. Each case runs the
# real component against a stub on a scratch PATH that records what it got:
#   tailscale  a peer address from `tailscale status --json` that is not a
#              dotted quad (`--socket=...`, `256.1.1.1`) is never handed to
#              `tailscale ping`; the ping is refused with a reason. A real one
#              still pings.
#   notify     a title starting with `-` reaches notify-send after `--`, as
#              text, never as an option
#   tzclock    a `clocks` zone that is not an IANA name (an absolute path, a
#              `:` file spec, a `..` walk) never becomes TZ for `date`, and is
#              shown as the unknown zone; a real zone still resolves
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for tool in qs which timeout; do
  command -v "$tool" >/dev/null || { echo "SKIP: argv hardening ($tool not on PATH)"; exit 0; }
done
real_date=$(command -v date)

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/home" "$scratch/runtime" "$scratch/bin"
chmod 700 "$scratch/runtime"
cp -r "$root/components" "$scratch/components"

cat > "$scratch/status.json" <<EOF
{"BackendState": "Running", "Self": {"DNSName": "me.tn.ts.net.", "TailscaleIPs": ["100.64.0.1"]},
 "Peer": {
  "k1": {"ID": "evil", "DNSName": "evil.tn.ts.net.", "Online": true, "TailscaleIPs": ["--socket=$scratch/sock"]},
  "k2": {"ID": "bad", "DNSName": "bad.tn.ts.net.", "Online": true, "TailscaleIPs": ["256.1.1.1"]},
  "k3": {"ID": "good", "DNSName": "good.tn.ts.net.", "Online": true, "TailscaleIPs": ["100.64.0.2", "fd7a::2"]}
 }}
EOF
cat > "$scratch/bin/tailscale" <<EOF
#!/bin/sh
case "\$1" in
  status) cat "$scratch/status.json" ;;
  serve) echo '{}' ;;
  debug) echo '{"Regions": {}}' ;;
  ping) printf '%s\n' "\$*" >> "$scratch/ping-argv"
        echo "pong from good (100.64.0.2) via DERP(fra) in 7ms" ;;
esac
EOF
cat > "$scratch/bin/notify-send" <<EOF
#!/bin/sh
for a in "\$@"; do printf '[%s]\n' "\$a"; done >> "$scratch/notify-argv"
EOF
cat > "$scratch/bin/date" <<EOF
#!/bin/sh
printf 'TZ=%s\n' "\${TZ-<unset>}" >> "$scratch/date-tz"
exec "$real_date" "\$@"
EOF
chmod +x "$scratch/bin/"*

cat > "$scratch/probe.qml" <<'EOF'
import QtQuick
import Quickshell
import "components" as C
Scope {
    id: probe
    property var started: Date.now()
    property int step: 0
    C.TailscaleData { id: ts; intervalMs: 600000 }
    C.Notify { id: notify }
    readonly property var zones: ["/etc/passwd", ":/etc/localtime", "../../../../etc/passwd", "Asia/Tokyo"]
    Instantiator {
        id: clocks
        model: probe.zones
        delegate: C.TzClock { timeZone: modelData }
    }
    Component.onCompleted: notify.send("-x evil", "--body")
    Timer {
        interval: 50; repeat: true; running: true
        onTriggered: {
            var late = Date.now() - probe.started > 12000
            if (probe.step === 0) {
                if (ts.peers.length < 3 && !late) return
                console.log("PING|evil|" + ts.ping("evil") + "|" + ts.pingError)
                console.log("PING|bad|" + ts.ping("bad") + "|" + ts.pingError)
                ts.ping("good")
                probe.step = 1
                return
            }
            if (probe.step === 1) {
                if ((ts.pinging || ts.pingResultId !== "good") && !late) return
                console.log("PING|good|" + ts.pingResultId + "|" + ts.pingMs + "|" + ts.pingError)
                probe.step = 2
                return
            }
            for (var i = 0; i < clocks.count; i++) {
                var c = clocks.objectAt(i)
                if (!c || (c.timeZoneOffset === "" && !late)) return
            }
            for (var j = 0; j < clocks.count; j++) {
                var k = clocks.objectAt(j)
                console.log("ZONE|" + k.timeZone + "|" + k.zoneValid + "|" + k.timeZoneOffset)
            }
            Qt.quit()
        }
    }
}
EOF

out=$(env -i PATH="$scratch/bin:$PATH" HOME="$scratch/home" XDG_RUNTIME_DIR="$scratch/runtime" \
  QT_QPA_PLATFORM=offscreen timeout 60 qs -n -p "$scratch/probe.qml" 2>&1 || true)

failed=0
fail() { echo "FAIL $*" >&2; failed=1; }
# line <key> -> what the probe printed after "<key>|", literally matched.
line() {
  local key="$1|" l
  while IFS= read -r l; do
    if [[ $l == *"$key"* ]]; then printf '%s\n' "${l#*"$key"}"; return; fi
  done <<<"$out"
}

[[ $(line 'PING|evil') == "false|no IPv4 address to ping" ]] \
  || fail "tailscale: ping of a peer whose address is '--socket=...' was not refused with a reason (got '$(line 'PING|evil')')"
[[ $(line 'PING|bad') == "false|no IPv4 address to ping" ]] \
  || fail "tailscale: ping of a peer at 256.1.1.1 was not refused (got '$(line 'PING|bad')')"
[[ $(line 'PING|good') == "good|7|" ]] \
  || fail "tailscale: a real peer did not ping (got '$(line 'PING|good')')"
pings=$(cat "$scratch/ping-argv" 2>/dev/null || true)
[[ $pings == "ping -c 1 --timeout 3s 100.64.0.2" ]] \
  || fail "tailscale: ping argv was '$pings', expected exactly one ping of 100.64.0.2"
(( failed == 0 )) && echo "OK: tailscale ping only ever targets a dotted-quad address"

expected_notify=$'[-u]\n[normal]\n[-a]\n[Liquid Glass]\n[--]\n[-x evil]\n[--body]'
got_notify=$(cat "$scratch/notify-argv" 2>/dev/null || true)
[[ $got_notify == "$expected_notify" ]] \
  || fail "notify: argv was $(tr '\n' ' ' <<<"$got_notify"), expected the title and body after --"
(( failed == 0 )) && echo "OK: notify-send gets a dash-led title after --"

for z in "/etc/passwd" ":/etc/localtime" "../../../../etc/passwd"; do
  [[ $(line "ZONE|$z") == "false|UTC+00:00" ]] \
    || fail "tzclock: zone '$z' was not shown as unknown (got '$(line "ZONE|$z")')"
done
[[ $(line 'ZONE|Asia/Tokyo') == "true|UTC+09:00" ]] \
  || fail "tzclock: Asia/Tokyo did not resolve (got '$(line 'ZONE|Asia/Tokyo')')"
tzs=$(sort -u "$scratch/date-tz" 2>/dev/null || true)
[[ $tzs == "TZ=Asia/Tokyo" ]] || fail "tzclock: date ran with $(tr '\n' ' ' <<<"$tzs"), expected only TZ=Asia/Tokyo"
(( failed == 0 )) || exit 1
echo "OK: a clocks zone that is not an IANA name never becomes TZ"
