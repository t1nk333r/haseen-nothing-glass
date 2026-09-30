#!/usr/bin/env bash
# One GeoClue2 position fix, printed as a single JSON line.
#
#   {"ok":true,"latitude":24.68,"longitude":46.72,"accuracy":1500}
#   {"ok":false,"error":"..."}
#
# Why a script and not QML: Quickshell 0.3.1 ships DBus bindings only for
# specific services (Bluetooth, DBusMenu, Mpris, Notifications, Pipewire,
# Polkit, SystemTray, UPower) - there is no generic D-Bus client - so the
# GeoClue2 client dance (GetClient -> DesktopId -> Start -> read Location)
# happens here and QML just parses the line.
#
# GeoClue2 refuses callers whose desktop id is not allowed in
# /etc/geoclue/geoclue.conf, and it has no usable source at all unless one of
# the `url=` providers in that file is uncommented - both are root edits, and
# the Wi-Fi provider sends nearby BSSIDs to a third party. So a failure here
# is expected, not exceptional: the caller falls back to configured
# coordinates and says which source it used.
set -uo pipefail

fail() { printf '{"ok":false,"error":"%s"}\n' "${1//\"/}"; exit 0; }

command -v gdbus >/dev/null 2>&1 || fail "gdbus not installed"

DESKTOP_ID="${1:-firefox}"   # an id already allowed in the stock geoclue.conf
TIMEOUT="${GEOCLUE_TIMEOUT:-8}"

call() {
  timeout "$TIMEOUT" gdbus call --system --dest org.freedesktop.GeoClue2 "$@" 2>&1
}

client=$(call --object-path /org/freedesktop/GeoClue2/Manager \
  --method org.freedesktop.GeoClue2.Manager.GetClient)
rc=$?
case "$client" in
  *objectpath*) ;;
  *)
    detail=$(printf '%s' "$client" | tr -d '\n' | cut -c1-120)
    # rc 124 is `timeout`: geoclue accepted the connection and then dropped
    # it, which is what it does with no geolocation provider configured.
    [[ -z $detail ]] && detail="no reply from geoclue (rc=$rc)"
    fail "geoclue unavailable: $detail"
    ;;
esac
client_path=$(printf '%s' "$client" | sed -n "s/.*objectpath '\([^']*\)'.*/\1/p")
[[ -n $client_path ]] || fail "could not parse client path"

set_prop() {
  timeout "$TIMEOUT" gdbus call --system --dest org.freedesktop.GeoClue2 \
    --object-path "$client_path" --method org.freedesktop.DBus.Properties.Set \
    org.freedesktop.GeoClue2.Client "$1" "$2" >/dev/null 2>&1
}
set_prop DesktopId "<'$DESKTOP_ID'>"
set_prop DistanceThreshold "<uint32 500>"

start=$(call --object-path "$client_path" --method org.freedesktop.GeoClue2.Client.Start) || true
case "$start" in
  *Error*) fail "Start failed: $(printf '%s' "$start" | tr -d '\n' | cut -c1-120)" ;;
esac

# The first Location arrives asynchronously; poll the property briefly.
location_path=""
for _ in $(seq 1 10); do
  out=$(timeout "$TIMEOUT" gdbus call --system --dest org.freedesktop.GeoClue2 \
    --object-path "$client_path" --method org.freedesktop.DBus.Properties.Get \
    org.freedesktop.GeoClue2.Client Location 2>&1)
  candidate=$(printf '%s' "$out" | sed -n "s/.*objectpath '\([^']*\)'.*/\1/p")
  if [[ -n $candidate && $candidate != "/" ]]; then location_path=$candidate; break; fi
  sleep 0.5
done

if [[ -z $location_path ]]; then
  call --object-path "$client_path" --method org.freedesktop.GeoClue2.Client.Stop >/dev/null 2>&1
  fail "no location produced (no geolocation provider configured?)"
fi

get() {
  timeout "$TIMEOUT" gdbus call --system --dest org.freedesktop.GeoClue2 \
    --object-path "$location_path" --method org.freedesktop.DBus.Properties.Get \
    org.freedesktop.GeoClue2.Location "$1" 2>/dev/null |
    sed -n 's/.*<\(-\?[0-9.]*\)>.*/\1/p'
}
lat=$(get Latitude); lon=$(get Longitude); acc=$(get Accuracy)
call --object-path "$client_path" --method org.freedesktop.GeoClue2.Client.Stop >/dev/null 2>&1

[[ -n ${lat:-} && -n ${lon:-} ]] || fail "location object carried no coordinates"
printf '{"ok":true,"latitude":%s,"longitude":%s,"accuracy":%s}\n' "$lat" "$lon" "${acc:-0}"
