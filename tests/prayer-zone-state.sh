#!/usr/bin/env bash
# components/prayers/prayer-zone.sh is vendored from t1nk33r.omaprayers, and
# that plugin's state directory is not ours: the script must write nothing
# outside its own mktemp work directory. Runs the real script with a scratch
# HOME, XDG_STATE_HOME and TMPDIR, with the other plugin's state directory
# already holding the files the vendored copy used to delete:
#   foreign   those files, and the directory's mode, survive untouched
#   own       nothing is created under HOME or XDG_STATE_HOME, and the work
#             directory is gone afterwards
#   works     the window it prints is still the published shape
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for tool in jq zdump; do
  command -v "$tool" >/dev/null || { echo "SKIP: prayer-zone state ($tool not on PATH)"; exit 0; }
done
[[ -f /usr/share/zoneinfo/Asia/Riyadh ]] || { echo "SKIP: prayer-zone state (no tzdata)"; exit 0; }

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
foreign="$scratch/state/omarchy/t1nk33r.omaprayers"
mkdir -p "$scratch/home" "$scratch/tmp" "$foreign"
chmod 755 "$foreign"
for f in cache-2026.json current.json fetch.lock; do echo "theirs" > "$foreign/$f"; done
snapshot() { (cd "$scratch" && find home state tmp -printf '%p %m %s\n' | sort); }
before=$(snapshot)

failed=0
fail() { echo "FAIL $*" >&2; failed=1; }

# With XDG_STATE_HOME set, and with it unset (the HOME fallback).
run_() {
  env -i PATH="$PATH" HOME="$scratch/home" TMPDIR="$scratch/tmp" "$@" \
    bash "$root/components/prayers/prayer-zone.sh" --timezone Asia/Riyadh --days 3 --now 1790000000
}
out=$(run_ XDG_STATE_HOME="$scratch/state") || fail "prayer-zone.sh exited non-zero: $out"
out2=$(run_) || fail "prayer-zone.sh (no XDG_STATE_HOME) exited non-zero: $out2"

after=$(snapshot)
if [[ $before != "$after" ]]; then
  fail "prayer-zone.sh changed files outside its work directory:"
  diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") >&2 || true
fi
(( failed == 0 )) && echo "OK: prayer-zone.sh leaves another plugin's state, HOME and TMPDIR untouched"

for o in "$out" "$out2"; do
  jq -e '.ok == true and .timezone == "Asia/Riyadh" and (.days | length) == 3 and (.offsets | length) >= 1' \
    <<<"$o" >/dev/null 2>&1 || fail "prayer-zone.sh did not print a valid window: $o"
done
(( failed == 0 )) || exit 1
echo "OK: prayer-zone.sh still prints the timezone window"
