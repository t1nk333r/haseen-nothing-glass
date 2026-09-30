#!/usr/bin/env bash
# GeoClue is an opt-in. Off - the default - the helper must never run; turned
# off while a lookup is in flight, the result it had already written must not
# land afterwards. The helper is replaced by a stub that records each start,
# prints a successful fix at once and then keeps running, which is exactly the
# window in which an opt-out used to be overturned.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
command -v qs >/dev/null || { echo 'SKIP: GeoClue opt-in (qs not on PATH)'; exit 0; }

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/home" "$scratch/runtime"
chmod 700 "$scratch/runtime"
cp -r "$root/components" "$scratch/components"
cat > "$scratch/components/geo/geoclue-fix.sh" <<EOF
#!/usr/bin/env bash
echo started >> "$scratch/starts"
echo '{"ok":true,"latitude":1.5,"longitude":2.5,"accuracy":10}'
sleep 5
EOF

cat > "$scratch/probe.qml" <<'EOF'
import QtQuick
import Quickshell
import "components" as C
Scope {
    C.GeoLocation { id: geo; fallbackLatitude: 40.7; fallbackLongitude: -74.0 }
    Timer {
        property int step: 0
        interval: 300; repeat: true; running: true
        onTriggered: {
            if (step === 0) console.log("RESULT|default|" + geo.source)
            else if (step === 1) geo.useGeoclue = true
            else if (step === 2) geo.useGeoclue = false
            else if (step === 5) { console.log("RESULT|after-opt-out|" + geo.source); Qt.quit() }
            step++
        }
    }
}
EOF

out=$(env -i PATH="$PATH" HOME="$scratch/home" XDG_RUNTIME_DIR="$scratch/runtime" \
  QT_QPA_PLATFORM=offscreen timeout 20 qs -n -p "$scratch/probe.qml" 2>&1 || true)
default=$(printf '%s\n' "$out" | sed -n 's/.*RESULT|default|//p')
after=$(printf '%s\n' "$out" | sed -n 's/.*RESULT|after-opt-out|//p')
starts=$(cat "$scratch/starts" 2>/dev/null | wc -l)

failed=0
[[ $default == manual ]] || { echo "GeoClue opt-in: by default the source was '${default:-<nothing>}', not manual" >&2; failed=1; }
(( starts == 1 )) || { echo "GeoClue opt-in: the helper started $starts time(s); expected exactly once, on opt-in" >&2; failed=1; }
[[ $after == manual ]] || { echo "GeoClue opt-in: after opting out mid-lookup the source was '${after:-<nothing>}', not manual" >&2; failed=1; }
(( failed == 0 )) || exit 1
echo "OK: GeoClue stays off by default and an opt-out holds (3 checks)"
