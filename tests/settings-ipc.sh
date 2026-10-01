#!/usr/bin/env bash
# What the IPC verbs may write, driven the way `omarchy-shell <id> <verb>`
# drives them: `qs ipc call` against the real Service (tests/settings-ipc.qml)
# in a headless compositor, with a stand-in shell that logs what would have
# reached shell.json. Each start has its own scratch HOME.
#
#   option keys    `option` takes only a key manifest.json's settings.defaults
#                  declares, with a value of that default's type: `id`,
#                  `enabled`, `kind`, `__proto__`, `constructor`, Infinity, a
#                  word for a number, a 20 000-character string are refused,
#                  and neither the options file nor the shell.json entry is
#                  touched. A real key still goes through.
#   set keys       `set <id> <key>` takes the row's `style` (a known style) or
#                  one of those settings, nothing else, and the store file is
#                  not touched by a refusal; geometry from `move`/`resize` is
#                  clamped (to the type's minimum for a size).
#   options load   a `__proto__` key in the options file does not reach the
#                  merged settings.
#   parse caps     an options file or a shell.json past 4 MiB is not parsed.
#   file modes     the store and the options file end up 0600.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for tool in qs gamescope jq stat cmp timeout python3; do
  command -v "$tool" >/dev/null || { echo "SKIP: settings IPC ($tool not on PATH)"; exit 0; }
done

scratch=$(mktemp -d)
gpid=""
qpid=""
cleanup() {
  [[ -n $qpid ]] && kill -KILL "$qpid" 2>/dev/null || true
  # gamescope runs under setsid: its pid is its process group.
  [[ -n $gpid ]] && kill -TERM -- "-$gpid" 2>/dev/null || true
  rm -rf "$scratch"
}
trap cleanup EXIT

id=$(jq -r .id "$root/manifest.json")
name=${id##*.}

# `qs` loads QML only from inside its config folder, so the host sits in a
# scratch folder with the plugin linked beside it, and the `qs.Commons` the
# Service imports is a stub there.
app="$scratch/app"
mkdir -p "$app/Commons"
cp "$root/tests/settings-ipc.qml" "$app/settings-ipc.qml"
ln -s "$root" "$app/plugin"
ln -s "$root/components" "$app/components"
ln -s "$root/fonts" "$app/fonts"
printf '%s\n' 'module qs.Commons' 'singleton Color 1.0 Color.qml' >"$app/Commons/qmldir"
cat >"$app/Commons/Color.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject {
  property color background: "#000000"
  property color foreground: "#ffffff"
  property color accent: "#d71921"
  property color urgent: "#d71921"
  property var bar: null
}
QML

# A headless gamescope per start: it does not survive its last client going
# away, so a second start cannot reuse the first one's.
runtime=""
start_compositor() {
  runtime="$1"
  mkdir -p "$runtime"
  chmod 700 "$runtime"
  env -u WAYLAND_DISPLAY -u DISPLAY XDG_RUNTIME_DIR="$runtime" setsid \
    gamescope --backend headless --expose-wayland -W 1280 -H 720 -- sleep 300 \
    >"$runtime/compositor.log" 2>&1 &
  gpid=$!
  for _ in $(seq 200); do
    [[ -S $runtime/gamescope-0 ]] && return 0
    kill -0 "$gpid" 2>/dev/null || break
    sleep 0.1
  done
  echo "SKIP: settings IPC (headless compositor did not come up)"
  exit 0
}

failed=0
group_failed=0
fail() { echo "FAIL $*"; failed=$((failed + 1)); group_failed=1; }
group_ok() { (( group_failed == 0 )) && echo "OK: $1"; group_failed=0; }

# new_home <name>: a scratch HOME with an empty omarchy config folder.
new_home() {
  local home="$scratch/$1/home"
  mkdir -p "$home/.config/omarchy"
  echo "$home"
}

# start_shell <home>: a compositor, then the host until it prints READY; the
# line is left in $ready and the pid in $qpid.
ready=""
start_shell() {
  local home="$1"
  start_compositor "$(dirname "$home")/runtime"
  env HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_CACHE_HOME="$home/.cache" \
    XDG_STATE_HOME="$home/.local/state" TMPDIR="$scratch" \
    XDG_RUNTIME_DIR="$runtime" WAYLAND_DISPLAY=gamescope-0 QT_QPA_PLATFORM=wayland \
    qs -n -p "$app/settings-ipc.qml" >"$home/qs.log" 2>&1 &
  qpid=$!
  ready=""
  for _ in $(seq 200); do
    ready=$(grep -o 'READY.*' "$home/qs.log" || true)
    [[ -n $ready ]] && return 0
    kill -0 "$qpid" 2>/dev/null || break
    sleep 0.1
  done
  echo "settings IPC: the host did not start:" >&2
  grep -E 'ERROR|WARN qml' "$home/qs.log" | head -20 >&2
  exit 1
}

stop_shell() {
  kill -TERM "$qpid" 2>/dev/null || true
  wait "$qpid" 2>/dev/null || true
  qpid=""
  kill -TERM -- "-$gpid" 2>/dev/null || true
  wait "$gpid" 2>/dev/null || true
  gpid=""
}

# The `qs ipc` client itself now and then never returns when an argument is
# tens of kilobytes long - measured against a "Target not found." reply too,
# so it is the client, not the handler. A call that times out without a reply
# is asked again; every verb here is safe to repeat.
call() {
  local reply="" _
  for _ in 1 2 3 4 5; do
    reply=$(env XDG_RUNTIME_DIR="$runtime" timeout 5 qs ipc --pid "$qpid" call "$id" "$@" 2>&1) && break
    [[ -n $reply ]] && break
  done
  printf '%s' "$reply"
}

# expect_error <description> <verb> [args...]
expect_error() {
  local what="$1" reply
  shift
  reply=$(call "$@")
  [[ $reply == error:* ]] || fail "$what was accepted: $reply"
}

# expect_reply <prefix> <verb> [args...]
expect_reply() {
  local want="$1" reply
  shift
  reply=$(call "$@")
  [[ $reply == "$want"* ]] || fail "$* answered '$reply', expected '$want...'"
}

# mode_is <file> <mode>: polls, because the chmod follows the write.
mode_is() {
  local _
  for _ in $(seq 50); do
    [[ $(stat -c %a "$1") == "$2" ]] && return 0
    sleep 0.1
  done
  return 1
}

long=$(head -c 20000 /dev/zero | tr '\0' x)
# Multibyte JSON below 4 Mi characters but above 4 Mi UTF-8 bytes.
pad=$(python3 -c 'print("界" * 1500000, end="")')

# ── The verbs, against a running service ───────────────────────────────────
home=$(new_home verbs)
cfg="$home/.config/omarchy"
jq -n --arg id "$id" '{plugins: [{id: $id, styleMode: 1}], bar: {layout: {left: [], center: [], right: []}}}' \
  >"$cfg/shell.json"
printf '%s\n' '{"version":1,"options":{"widgetStyle":"nothing","__proto__":{"polluted":true}}}' \
  >"$cfg/$name-options.json"
printf '%s\n' '{"version":1,"widgets":[{"id":"weather-1","type":"weather","screen":"TEST-1","x":16,"y":16,"w":192,"h":192,"settings":{}}]}' \
  >"$cfg/$name.json"
chmod 644 "$cfg/$name-options.json" "$cfg/$name.json"
start_shell "$home"

[[ $ready == *"polluted=false"* ]] || fail "a __proto__ key in the options file reached the merged settings: $ready"
[[ $ready == *"widgetStyle=nothing"* ]] || fail "the options file's real value was lost: $ready"
group_ok "the options file loads without prototype keys"

cp "$cfg/$name-options.json" "$scratch/options.before"
expect_error "option id" option id x
expect_error "option enabled" option enabled false
expect_error "option kind" option kind x
expect_error "option __proto__" option __proto__ '{"polluted":true}'
expect_error "option constructor" option constructor 1
expect_error "option toString" option toString x
expect_error "option cornerRadius Infinity" option cornerRadius Infinity
expect_error "option styleMode abc" option styleMode abc
expect_error "option categoryStyles [1]" option categoryStyles '[1]'
expect_error "a 20000-character option" option location "$long"
expect_error "a multibyte option above 16 KiB" option location "$(printf '界%.0s' $(seq 6000))"
cmp -s "$scratch/options.before" "$cfg/$name-options.json" \
  || fail "a refused option changed the options file"
grep -q 'UPDATE ' "$home/qs.log" \
  && fail "a refused option reached the shell.json entry"
group_ok "option refuses structural, prototype and malformed keys and values, and writes nothing"

expect_reply "set styleMode = 2" option styleMode 2
expect_reply "set categoryStyles" option categoryStyles '{"Time":"nothing"}'
[[ $(jq -c '.options | {styleMode, categoryStyles, widgetStyle}' "$cfg/$name-options.json") == \
   '{"styleMode":2,"categoryStyles":{"Time":"nothing"},"widgetStyle":"nothing"}' ]] \
  || fail "the options file does not carry the real settings: $(cat "$cfg/$name-options.json")"
update=$(grep -m1 -o 'UPDATE .*' "$home/qs.log" | cut -d' ' -f2-)
[[ $(jq -c '{styleMode, id}' <<<"$update") == '{"styleMode":2,"id":null}' ]] \
  || fail "the shell.json entry update is not the real setting: $update"
group_ok "option still writes a real setting to both places"

sleep 0.6   # past the store's 250 ms coalescing window
cp "$cfg/$name.json" "$scratch/store.before"
expect_error "set __proto__" set weather-1 __proto__ '{"polluted":true}'
expect_error "set id" set weather-1 id '"x"'
expect_error "set an undeclared key" set weather-1 textColor '"#ffffff"'
expect_error "set a word for a number" set weather-1 refreshMinutes '"abc"'
expect_error "set 1e400" set weather-1 refreshMinutes '1e400'
expect_error "set a 20000-character value" set weather-1 location "\"$long\""
expect_error "a multibyte per-row value above 16 KiB" set weather-1 location "\"$(printf '界%.0s' $(seq 6000))\""
expect_error "set an unknown style" set weather-1 style '"bogus"'
expect_error "set a numeric style" set weather-1 style '42'
sleep 0.6
cmp -s "$scratch/store.before" "$cfg/$name.json" \
  || fail "a refused set changed the store"
group_ok "set takes only real per-instance settings, and a refusal writes nothing"

expect_reply "set weather-1.location" set weather-1 location '"Oslo"'
expect_reply "set weather-1.style" set weather-1 style '"nothing"'
expect_reply "resized weather-1" resize weather-1 -5 99999999
expect_reply "moved weather-1" move weather-1 -100 99999999
sleep 0.6
row=$(jq -c '.widgets[0] | {x, y, w, h, style, location: .settings.location}' "$cfg/$name.json")
[[ $row == '{"x":0,"y":32768,"w":160,"h":16384,"style":"nothing","location":"Oslo"}' ]] \
  || fail "the store row after real set/move/resize is $row"
group_ok "set, move and resize still write, with geometry clamped"

mode_is "$cfg/$name.json" 600 || fail "the store is mode $(stat -c %a "$cfg/$name.json"), not 600"
mode_is "$cfg/$name-options.json" 600 || fail "the options file is mode $(stat -c %a "$cfg/$name-options.json"), not 600"
group_ok "the store and the options file are mode 0600 after a write"
stop_shell

# ── Parse caps ──────────────────────────────────────────────────────────────
# An options file past the cap is ignored: the shell.json entry's value wins.
home=$(new_home big-options)
cfg="$home/.config/omarchy"
jq -n --arg id "$id" '{plugins: [{id: $id, styleMode: 1}], bar: {layout: {left: [], center: [], right: []}}}' \
  >"$cfg/shell.json"
printf '{"version":1,"options":{"styleMode":2,"pad":"%s"}}\n' "$pad" >"$cfg/$name-options.json"
cp "$cfg/$name-options.json" "$scratch/big-options.before"
start_shell "$home"
[[ $ready == *"styleMode=1"* ]] || fail "an options file past the cap was parsed: $ready"
expect_error "option on an oversized options file" option styleMode 2
stop_shell
cmp -s "$scratch/big-options.before" "$cfg/$name-options.json" || fail "the oversized options file was rewritten"

# A shell.json past the cap is ignored: the manifest default stands.
home=$(new_home big-shell)
cfg="$home/.config/omarchy"
printf '{"plugins":[{"id":"%s","styleMode":1}],"pad":"%s"}\n' "$id" "$pad" >"$cfg/shell.json"
start_shell "$home"
[[ $ready == *"styleMode=0"* ]] || fail "a shell.json past the cap was parsed: $ready"
stop_shell
group_ok "an options file or shell.json past 4 MiB is not parsed"

# A malformed store must stay untouched even when a client tries to add.
home=$(new_home corrupt-store)
cfg="$home/.config/omarchy"
printf '%s\n' '{"widgets":[' >"$cfg/$name.json"
cp "$cfg/$name.json" "$scratch/corrupt.before"
start_shell "$home"
expect_error "add on an unparsable store" add weather TEST-1
stop_shell
cmp -s "$scratch/corrupt.before" "$cfg/$name.json" || fail "a corrupt store was overwritten"
cmp -s "$scratch/corrupt.before" "$cfg/$name.json.bak" || fail "a corrupt store was not backed up unchanged"
group_ok "an unparsable store refuses writes and preserves its original and backup"

# The options file itself is the durable migration marker even when mv -n
# cannot retire the legacy source. A subsequent user choice must survive.
home=$(new_home legacy-options)
cfg="$home/.config/omarchy"
printf '%s\n' '{"plugins":[]}' >"$cfg/shell.json"
printf '%s\n' '{"version":1,"options":{"styleMode":1}}' >"$cfg/liquidglass-options.json"
printf '%s\n' '{}' >"$cfg/liquidglass-options.json.migrated"
start_shell "$home"
[[ $ready == *"styleMode=1"* ]] || fail "legacy options were not adopted"
expect_reply "set styleMode = 2" option styleMode 2
stop_shell
start_shell "$home"
[[ $ready == *"styleMode=2"* ]] || fail "legacy options were adopted again after restart"
stop_shell
group_ok "options migration is durable when the retired filename already exists"

(( failed == 0 )) || exit 1
