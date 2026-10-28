#!/usr/bin/env bash
# Which DeepSpend ledger the DeepSeek tile reads. `t1nk33r.agents` moved its
# ledger from $XDG_STATE_HOME/omarchy/t1nk33r.agents/deepseek/usage.state to
# $XDG_STATE_HOME/haseen/agents/deepseek/usage.state and left the old file
# behind with its last sample; reading only the old path pinned the tile to
# that sample. Runs the real DeepSeekData against a scratch state directory:
#   legacy only, haseen only, the newer `lastAt` winning in either direction,
#   a broken new ledger losing to a readable old one, neither file, an empty
#   one, and two atomic replacements of the haseen ledger observed while the
#   reader runs.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
command -v qs >/dev/null || { echo 'SKIP: DeepSeek ledgers (qs unavailable)'; exit 0; }
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
legacy="$scratch/state/omarchy/t1nk33r.agents/deepseek"
native="$scratch/state/haseen/agents/deepseek"
mkdir -p "$scratch/runtime" "$scratch/config" "$scratch/cache" "$legacy" "$native"
chmod 700 "$scratch/runtime"
cp "$root/tests/deepseek-ledger.qml" "$scratch/"
cp -r "$root/components" "$scratch/components"
# ledger DIR TOTAL LASTAT_MS
ledger() {
  printf '{"version":2,"currency":"USD","firstSeenAt":1789144294532,"lastAt":%s,"lastTotal":%s,"spent":1,"spentPeak":0,"spentOffPeak":1,"added":0,"days":[]}' "$3" "$2" > "$1/usage.state"
}
run() {
  env -i PATH="$PATH" HOME="$scratch" XDG_STATE_HOME="$scratch/state" XDG_CONFIG_HOME="$scratch/config" \
    XDG_CACHE_HOME="$scratch/cache" XDG_RUNTIME_DIR="$scratch/runtime" QT_QPA_PLATFORM=offscreen "$@" \
    timeout 10 qs -n -p "$scratch/deepseek-ledger.qml" 2>&1 || true
}
check() {
  local result
  result=$(run EXPECTED_TOTAL="$1")
  [[ $result == *DEEPSEEK_PASS* ]] || { printf 'FAIL: DeepSeek ledger selection (%s)\n%s\n' "$2" "$result"; exit 1; }
}
check none "neither ledger"
: > "$native/usage.state"
check none "an empty haseen ledger alone"
rm "$native/usage.state"
ledger "$legacy" 11.00 1789000000000
check 11.00 "legacy only"
ledger "$native" 22.00 1790000000000
check 22.00 "haseen newer"
ledger "$legacy" 33.00 1791000000000
check 33.00 "legacy newer"
printf '{"version":2,' > "$native/usage.state"
check 33.00 "broken haseen ledger"
rm "$legacy/usage.state"
ledger "$native" 44.00 1792000000000
check 44.00 "haseen only"

ledger "$native" 1.00 1793000000000
run LIVE_UPDATES=1 > "$scratch/live.log" &
pid=$!
for step in 1 2; do
  for attempt in {1..60}; do
    grep -q "DEEPSEEK_STEP_$step" "$scratch/live.log" && break
    sleep 0.05
  done
  grep -q "DEEPSEEK_STEP_$step" "$scratch/live.log" || { wait "$pid" || :; echo 'FAIL: DeepSeek did not observe a live update'; cat "$scratch/live.log"; exit 1; }
  next=$((step + 1))
  ledger "$scratch" "$next.00" "$((1793000000000 + step))"
  mv "$scratch/usage.state" "$native/usage.state"
done
wait "$pid"
grep -q DEEPSEEK_PASS "$scratch/live.log" || { echo 'FAIL: DeepSeek lost the atomic-file watch'; cat "$scratch/live.log"; exit 1; }
echo 'OK: the newer DeepSpend ledger wins across both paths, and repeated atomic refreshes arrive'
