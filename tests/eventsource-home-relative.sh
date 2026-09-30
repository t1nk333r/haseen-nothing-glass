#!/usr/bin/env bash
# The calendar's no-backend state draws the watched events path onto the
# desktop. It must never carry the account name - not for the spellings of
# HOME and XDG_STATE_HOME that defeated the first, string-matching version:
# a trailing-slash HOME, a doubled slash, a state dir outside HOME, and a
# symlinked HOME whose state dir is spelled canonically.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
command -v qs >/dev/null || { echo 'SKIP: calendar path privacy (qs not on PATH)'; exit 0; }

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
acct="$scratch/users/acct"
mkdir -p "$acct/.local/state" "$scratch/external" "$scratch/canonical/.local/state" \
  "$scratch/config" "$scratch/cache" "$scratch/runtime"
ln -s "$scratch/canonical" "$scratch/linked"
chmod 700 "$scratch/runtime"
cp "$root/tests/eventsource-home-relative.qml" "$scratch/"
cp -r "$root/components" "$scratch/components"

# The labels are the literal text the tile draws, tilde and dollar included.
# shellcheck disable=SC2088
std='~/.local/state/omarchy/calendar-events.json'
# shellcheck disable=SC2016
xdg='$XDG_STATE_HOME/omarchy/calendar-events.json'
failed=0

# case_ <label> <expected stateDetail> <env assignments...>
case_() {
  local label="$1" expected="$2"; shift 2
  local out detail
  out=$(env -i PATH="$PATH" XDG_CONFIG_HOME="$scratch/config" XDG_CACHE_HOME="$scratch/cache" \
    XDG_RUNTIME_DIR="$scratch/runtime" QT_QPA_PLATFORM=offscreen "$@" \
    timeout 15 qs -n -p "$scratch/eventsource-home-relative.qml" 2>&1 || true)
  detail=$(printf '%s\n' "$out" | sed -n 's/.*DETAIL|no-backend|//p' | head -1)
  if [[ $detail != "$expected" ]] || [[ $detail == *"$scratch"* ]]; then
    echo "calendar path privacy, $label: expected '$expected', drew '${detail:-<nothing>}'" >&2
    failed=1
  fi
}

case_ "HOME with a trailing slash"           "$std" HOME="$acct/"
case_ "trailing slash + standard state dir"  "$std" HOME="$acct/" XDG_STATE_HOME="$acct/.local/state"
case_ "doubled slash in HOME"                "$std" HOME="${acct/users/users/}"
case_ "state dir outside HOME"               "$xdg" HOME="$acct" XDG_STATE_HOME="$scratch/external"
case_ "symlinked HOME, canonical state dir"  "$xdg" HOME="$scratch/linked" XDG_STATE_HOME="$scratch/canonical/.local/state"
# An overridden path draws none of itself: not a suffix under HOME, not a
# `..` walk out of it into another account, not a bare file name.
custom='a custom calendar-events.json'
case_ "override under HOME"                  "$custom" HOME="$acct" PROBE_EVENTS_FILE="$acct/acct/events.json"
case_ "override walking out of HOME"         "$custom" HOME="$acct" PROBE_EVENTS_FILE="$acct/../../users/other-acct/events.json"
case_ "override outside HOME, telling name"  "$custom" HOME="$acct" PROBE_EVENTS_FILE="/outside/acct.json"

(( failed == 0 )) || exit 1
echo "OK: the calendar never draws an account path (8 environments)"
