#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
command -v qs >/dev/null || { echo 'SKIP: Claude records (qs unavailable)'; exit 0; }
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/runtime" "$scratch/config" "$scratch/cache" "$scratch/state/omarchy/agents/usage" "$scratch/state/haseen/agents/usage"
chmod 700 "$scratch/runtime"
cp "$root/tests/claude-record.qml" "$scratch/"
cp -r "$root/components" "$scratch/components"
record() {
  printf '{"schemaVersion":1,"id":"claude","name":"%s","updatedAt":"%s","ready":true,"limits":[{"label":"Session","percent":0.17}]}' "$2" "$3" > "$scratch/state/$1/agents/usage/claude.json"
}
check() {
  local result
  result=$(env -i PATH="$PATH" HOME="$scratch" XDG_STATE_HOME="$scratch/state" XDG_CONFIG_HOME="$scratch/config" XDG_CACHE_HOME="$scratch/cache" XDG_RUNTIME_DIR="$scratch/runtime" QT_QPA_PLATFORM=offscreen EXPECTED_SOURCE="$1" timeout 8 qs -n -p "$scratch/claude-record.qml" 2>&1 || true)
  [[ $result == *CLAUDE_PASS* ]] || { printf 'FAIL: Claude record selection (%s)\n%s\n' "$1" "$result"; exit 1; }
}
record omarchy Legacy 2026-10-08T10:10:07+00:00
check Legacy
record haseen Native 2026-10-09T02:38:04+00:00
check Native
record omarchy NewLegacy 2026-10-10T02:38:04+00:00
check NewLegacy
rm "$scratch/state/omarchy/agents/usage/claude.json"
check Native
printf '{"schemaVersion":1,"id":"claude","name":"SignedOut","updatedAt":"2026-10-11T02:38:04+00:00","ready":false,"limits":[]}' > "$scratch/state/haseen/agents/usage/claude.json"
record omarchy Legacy 2026-10-08T10:10:07+00:00
check SignedOut
record haseen Live1 2026-10-12T02:38:04+00:00
env -i PATH="$PATH" HOME="$scratch" XDG_STATE_HOME="$scratch/state" XDG_CONFIG_HOME="$scratch/config" XDG_CACHE_HOME="$scratch/cache" XDG_RUNTIME_DIR="$scratch/runtime" QT_QPA_PLATFORM=offscreen LIVE_UPDATES=1 timeout 8 qs -n -p "$scratch/claude-record.qml" > "$scratch/live.log" 2>&1 &
pid=$!
for step in 1 2; do
  for attempt in {1..30}; do
    grep -q "CLAUDE_STEP_$step" "$scratch/live.log" && break
    sleep 0.03
  done
  grep -q "CLAUDE_STEP_$step" "$scratch/live.log" || { wait "$pid" || :; echo 'FAIL: Claude did not observe a live update'; exit 1; }
  next=$((step + 1))
  printf '{"id":"claude","name":"Live%s","updatedAt":"2026-10-%sT02:38:04+00:00","ready":true,"limits":[]}' "$next" "$((12 + step))" > "$scratch/replacement.json"
  mv "$scratch/replacement.json" "$scratch/state/haseen/agents/usage/claude.json"
done
wait "$pid"
grep -q CLAUDE_PASS "$scratch/live.log" || { echo 'FAIL: Claude lost the atomic-file watch'; exit 1; }
echo 'OK: newest Claude record, signed-out state, and repeated atomic refreshes'
