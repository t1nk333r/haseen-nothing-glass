#!/usr/bin/env bash
# Now Playing cover art is bounded, and only https and local files are drawn.
#
# An MPRIS player's art URL is chosen by whatever owns the bus name - for a
# browser, by the web page - and used to go straight into Image.source and
# Canvas.loadImage, where Qt buffers the whole body with no deadline and no
# size limit. This runs the REAL components/CoverArt.qml (and FlipAlbumArt)
# and the REAL Now Playing tiles, both styles, against a local HTTPS/HTTP
# server, with real curl, and checks:
#
#   cap        an endless image/png body is refused at the byte cap, and the
#              shell's peak RSS stays under $RSS_CAP_KB
#   deadline   a stalled body settles at the deadline, and the next URL loads
#   oversize   announced and unannounced bodies over the cap are refused
#   good       a good PNG becomes a file:// copy inside a 0700 directory under
#              $XDG_RUNTIME_DIR, and draws
#   http       http:// is refused with zero requests reaching the server
#   redirect   a redirect to http is refused (a redirect to https is followed)
#   file       file:///dev/zero, a FIFO and an oversize file are refused within
#              the deadline; a small file is copied; another host is refused
#   data       a small data:image URL is drawn, one over the cap is not
#   supersede  a new URL kills the old curl
#   destroy    destroying the component removes its directory and its curl
#   no curl    no art, and no hang
#   flip       FlipAlbumArt does not wedge on a load that never completes
#   tile       the real tiles draw through it; they ask http:// for nothing;
#              an endless body leaves the shell's RSS flat; 40 distinct 2000px
#              covers do not grow it (the colour sampler keeps nothing)
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for tool in qs curl python3 pgrep openssl mkfifo base64 cut stat mkdir rm rmdir sleep sed; do
  command -v "$tool" >/dev/null || { echo "SKIP: cover art bounds ($tool not on PATH)"; exit 0; }
done

# Peak RSS allowed for a shell that was handed an endless body. A probe shell
# peaks well under 300 MB here; Qt buffering the body reached 24 GB in 5 s.
RSS_CAP_KB=$((600 * 1024))
# Growth allowed across 35 distinct 2000x2000 covers: decoded at full size
# and kept, that is ~16 MB each.
GROWTH_CAP_KB=$((96 * 1024))

scratch=$(mktemp -d)
server_pid=""
cleanup() {
  [[ -n $server_pid ]] && kill "$server_pid" 2>/dev/null || true
  # Anything this test started that is still talking to its server.
  [[ -n ${https_port:-} ]] && pkill -f -- "127.0.0.1:$https_port/" 2>/dev/null || true
  [[ -n ${http_port:-} ]] && pkill -f -- "127.0.0.1:$http_port/" 2>/dev/null || true
  rm -rf "$scratch"
}
trap cleanup EXIT
mkdir -p "$scratch/home" "$scratch/runtime" "$scratch/nocurl" "$scratch/files"
chmod 700 "$scratch/runtime"
# Snapshot the drawing and its imports: Quickshell watches source directories,
# so unrelated concurrent edits must not reload a probe mid-measurement.
mkdir "$scratch/plugin"
cp -a "$root"/*.qml "$root/manifest.json" "$root/components" "$root/fonts" \
  "$root/icons" "$root/widgets" "$root/widgets-nothing" "$scratch/plugin/"
ln -s "$scratch/plugin/components" "$scratch/components"
ln -s "$scratch/plugin/fonts" "$scratch/fonts"
cp "$root/tests/cover-art-component.qml" "$root/tests/cover-art-tile.qml" "$root/tests/cover-art-directory.qml" "$root/tests/cover-art-flip.qml" "$scratch/"
# A PATH with everything the probes use, and no curl.
for t in qs sh sed pgrep stat mkdir rm rmdir sleep; do ln -s "$(command -v "$t")" "$scratch/nocurl/$t"; done
mkdir "$scratch/mkdir-path"
ln -s "$root/tests/cover-art-mkdir.sh" "$scratch/mkdir-path/mkdir"

openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 2 \
  -subj /CN=127.0.0.1 -addext subjectAltName=IP:127.0.0.1 \
  -keyout "$scratch/key.pem" -out "$scratch/cert.pem" 2>/dev/null
python3 "$root/tests/cover-art-server.py" "$scratch" "$scratch/cert.pem" "$scratch/key.pem" &
server_pid=$!
for _ in $(seq 50); do [[ -s $scratch/ports ]] && break; sleep 0.1; done
read -r https_port http_port < "$scratch/ports" || { echo "cover art bounds: the local server did not start" >&2; exit 1; }
https="https://127.0.0.1:$https_port"
http="http://127.0.0.1:$http_port"

# Local files a player could name.
python3 - "$scratch/files" <<'EOF'
import sys, struct, zlib
d = sys.argv[1]
def png(w, h, rgb):
    def chunk(k, data):
        b = k + data
        return struct.pack(">I", len(data)) + b + struct.pack(">I", zlib.crc32(b) & 0xFFFFFFFF)
    raw = zlib.compress((b"\x00" + bytes(rgb) * w) * h)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", raw) + chunk(b"IEND", b"")
open(d + "/good.png", "wb").write(png(120, 120, (34, 170, 34)))
open(d + "/blue.png", "wb").write(png(120, 120, (34, 34, 200)))
open(d + "/not-an-image", "wb").write(b"plain text")
for n in range(40):
    open("%s/cover-%02d.png" % (d, n), "wb").write(png(2000, 2000, ((n * 53) % 256, (n * 97) % 256, (n * 151) % 256)))
with open(d + "/oversize", "wb") as f:
    f.truncate(6 * 1024 * 1024)
EOF
mkfifo "$scratch/files/fifo"
files="file://$scratch/files"

# A bound on the shell's address space, so a regression cannot take the
# machine down with it: a shell that blows it dies, and the run fails.
qs_run() {
  ( ulimit -v $((6 * 1024 * 1024)); exec python3 "$root/tests/cover-art-run.py" env -i PATH="${QS_PATH:-$PATH}" HOME="$scratch/home" \
      XDG_RUNTIME_DIR="$scratch/runtime" QT_QPA_PLATFORM=offscreen \
      CURL_CA_BUNDLE="$scratch/cert.pem" SSL_CERT_FILE="$scratch/cert.pem" \
      HTTPS_PORT="$https_port" HTTP_PORT="$http_port" FILES="$scratch/files" "$@" \
      qs -n -p "$scratch/$PROBE" ) 2>&1 | sed -n 's/.*RESULT|//p' || true
}
component() { PROBE=cover-art-component.qml qs_run "$@"; }
tile() { PROBE=cover-art-tile.qml qs_run "$@"; }
hits() { local n; n=$(grep -cF -- "$2" "$scratch/hits-$1" 2>/dev/null) || true; echo "${n:-0}"; }

# One OK line per check group, printed only if that group had no FAIL.
failed=0
group_failed=0
fail() { echo "FAIL cover art bounds, $1" >&2; failed=1; group_failed=1; }
ok() { (( group_failed == 0 )) && echo "OK: $1"; group_failed=0; return 0; }
field() { cut -d'|' -f"$2" <<<"$1"; }
# step <output> <i> -> "<seconds>|<url>|<drawn>"
step() { sed -n "s/^step|$2|//p" <<<"$1" | head -1; }
line() { sed -n "s/^$2|//p" <<<"$1" | head -1; }
in_runtime() { [[ $1 == "file://$scratch/runtime/cover-art."*/cover-[0-3]\?g=* ]]; }
# refused <case> <output> <i> <under seconds>: settled on no art, in time.
refused() {
  local r secs
  r=$(step "$2" "$3")
  secs=$(field "$r" 1)
  if [[ -z $r || -n $(field "$r" 2) ]]; then
    fail "$1: expected no art, got '${r:-<nothing - the event loop stopped>}'"
  elif (( ${secs%.*} >= $4 )); then
    fail "$1: took ${secs}s to refuse, expected under $4s"
  fi
}
# copied <case> <output> <i>: a file:// copy under the runtime dir, drawn.
copied() {
  local r
  r=$(step "$2" "$3")
  if ! in_runtime "$(field "$r" 2)" || [[ $(field "$r" 3) != "drawn 96" ]]; then
    fail "$1: expected a drawn copy under \$XDG_RUNTIME_DIR, got '${r:-<nothing - the event loop stopped>}'"
  fi
}

# ── The component ─────────────────────────────────────────────────────────

if [[ -f $root/components/CoverArt.qml ]]; then
out=$(component URLS="$https/good.png $https/redirect-https $files/good.png file://localhost$scratch/files/blue.png")
copied "good PNG over https" "$out" 0
copied "https redirected to https" "$out" 1
copied "local file" "$out" 2
copied "local file, localhost spelled out" "$out" 3
ok "a good cover becomes a local copy under \$XDG_RUNTIME_DIR and draws (https, https->https, file://)"

# Deadline 30 s, so a refusal in a few seconds is the cap, not the clock.
out=$(component TIMEOUT=30 URLS="$https/endless $https/oversize $https/oversize-chunked")
refused "endless body" "$out" 0 6
refused "oversize body (Content-Length)" "$out" 1 6
refused "oversize body (chunked)" "$out" 2 6
hwm=$(line "$out" hwm)
(( ${hwm:-999999999} < RSS_CAP_KB )) || fail "endless body: peak RSS ${hwm:-?} kB, cap $RSS_CAP_KB kB"
ok "an endless or oversize body is refused at the 4 MiB cap, before the deadline (peak RSS ${hwm} kB < $RSS_CAP_KB kB)"

out=$(component TIMEOUT=2 URLS="$https/stall $https/good.png")
refused "stalled body" "$out" 0 5
secs=$(field "$(step "$out" 0)" 1)
secs=${secs:-0}
(( ${secs%.*} >= 1 )) || fail "stalled body: settled after ${secs}s, before the 2 s deadline could have"
copied "the URL after a stall" "$out" 1
ok "a stalled body settles at the deadline, and the next cover then loads"

out=$(component URLS="$http/good.png?component $https/redirect-http relative.png ftp://127.0.0.1/x.png file://otherhost$scratch/files/good.png")
for i in 0 1 2 3 4; do refused "refused scheme ($i)" "$out" "$i" 2; done
[[ $(hits http 'good.png?component') == 0 ]] || fail "http: the plain-http server was asked for $(hits http 'good.png?component') cover(s)"
[[ $(hits https '/redirect-http') -ge 1 ]] || fail "redirect to http: the https request was never made, so nothing was proved"
ok "http://, a redirect to http, relative, ftp:// and another host's file:// are refused; zero requests reach http"

out=$(component TIMEOUT=2 URLS="file:///dev/zero $files/fifo $files/oversize")
refused "file:///dev/zero" "$out" 0 5
refused "a FIFO nobody writes" "$out" 1 5
refused "an oversize file" "$out" 2 5
ok "file:///dev/zero, a FIFO and an oversize file are refused within the deadline"

small="data:image/png;base64,$(base64 -w0 "$scratch/files/good.png")"
large="data:image/png;base64,$(base64 -w0 "$scratch/files/cover-00.png")"
out=$(component DATAMAX=${#small} URLS="$small $large")
r=$(step "$out" 0)
[[ $(field "$r" 2) == "$small" && $(field "$r" 3) == "drawn 96" ]] || fail "small data: URL: expected it drawn as is, got '${r:0:120}'"
refused "data: URL over the cap" "$out" 1 2
ok "a data:image URL is drawn under the cap and refused over it"

out=$(component URLS="$https/stall?a $https/stall?b" SCEN=supersede)
[[ $(line "$out" curls) == "0 1" ]] || fail "supersede: expected '0 1' curls (old killed, new running), got '$(line "$out" curls)'"
ok "a new cover kills the fetch it supersedes"

out=$(component URLS="$https/good.png" SCEN=destroy)
[[ $(line "$out" mode) == 700 ]] || fail "destroy: the copy directory is mode '$(line "$out" mode)', expected 700"
[[ $(line "$out" before-destroy) == 1 ]] || fail "destroy: no fetch in flight to tear down ('$(line "$out" before-destroy)'), so nothing was proved"
[[ $(line "$out" after-destroy) == "gone,0" ]] || fail "destroy: expected the directory gone and no curl left, got '$(line "$out" after-destroy)'"
ok "destroying the component kills its fetch and removes its 0700 directory"

out=$(QS_PATH="$scratch/nocurl" component URLS="$https/good.png $files/good.png")
refused "no curl (https)" "$out" 0 3
refused "no curl (file)" "$out" 1 3
[[ -n $(line "$out" hwm) ]] || fail "no curl: the shell stopped answering"
ok "with no curl there is no art and no hang"

# Directory creation is exclusive even on collision, and destruction during
# creation removes only the empty directory owned by this instance.
for scen in collision mid-create; do
  out=$(PROBE=cover-art-directory.qml QS_PATH="$scratch/mkdir-path:$PATH" qs_run \
    DIR_SCEN="$scen" DIR_STATE="$scratch/dir-$scen" REAL_MKDIR="$(command -v mkdir)")
  [[ $(line "$out" directory) == gone ]] || fail "directory $scen: $(line "$out" directory)"
  if [[ $scen == collision ]]; then
    [[ $(line "$out" collision) == retried ]] || fail "directory collision was not retried"
    collision=$(cat "$scratch/dir-$scen")
    [[ $(cat "$collision/sentinel") == keep ]] || fail "directory collision deleted unowned content"
    rm -rf -- "$collision"
  else
    [[ -s $scratch/dir-$scen ]] || fail "mid-create: mkdir never created a directory"
  fi
done
ok "cover directories are exclusive, validated, and cleaned even during creation; collisions remain untouched"
else
  fail "bounded cover component is absent"
  group_failed=0
fi

# FlipAlbumArt on its own: a load that never completes, then the next cover.
stall="$http/stall"
plan=$(printf '[{"set":["%s"],"front":"%s"},{"set":["%s","%s"],"front":"%s"},{"set":[""],"front":""},{"set":["%s","%s"],"front":"%s"},{"set":["%s",""],"front":""}]' \
  "$files/good.png" "$files/good.png" \
  "$stall" "$files/blue.png" "$files/blue.png" \
  "$files/not-an-image" "$files/good.png" "$files/good.png" \
  "$stall")
out=$(PROBE=cover-art-flip.qml qs_run FLIP_PLAN="$plan")
for i in 0 1 2 3 4; do
  grep -q "^flip|$i|" <<<"$out" || fail "flip: step $i never came to rest ($(line "$out" flip-stuck))"
done
ok "FlipAlbumArt comes to rest after a load that never completes, a failed one, and \"\""

# ── The tiles ─────────────────────────────────────────────────────────────

for style in glass nothing; do
  out=$(tile STYLE=$style ARTS="$https/good.png")
  r=$(line "$out" art)
  drawn=$(field "$r" 3)
  if ! in_runtime "$(field "$r" 2)" || (( ${drawn:-0} < 1 )) || [[ $(field "$r" 4) != sampled ]]; then
    fail "$style tile: expected the cover copied, drawn and (glass) sampled, got '${r:-<nothing>}'"
  fi

  out=$(tile STYLE=$style HOLD_MS=3000 ARTS="$http/good.png?tile-$style $http/endless?tile-$style")
  [[ $(hits http "tile-$style") == 0 ]] || fail "$style tile: asked plain http for $(hits http "tile-$style") cover(s)"
  [[ -n $(line "$out" hwm) ]] || fail "$style tile: died on http art including an endless body (no RESULT)"

  out=$(tile STYLE=$style HOLD_MS=4000 ARTS="$https/endless?tile-$style")
  hwm=$(line "$out" hwm)
  (( ${hwm:-999999999} < RSS_CAP_KB )) || fail "$style tile, endless body: peak RSS ${hwm:-<died>} kB, cap $RSS_CAP_KB kB"
done
ok "both tiles draw a copied cover, ask http for nothing, and stay under $RSS_CAP_KB kB on an endless body"

# 40 distinct 2000x2000 covers through the glass tile, in its wide layout (the
# flip faces and the colour sampler): RSS after the 5th against the 40th.
covers=""
for n in $(seq -w 0 39); do covers+=" $files/cover-$n.png"; done
out=$(tile STYLE=glass W=480 H=240 BASELINE_AT=4 ARTS="$covers")
base=$(field "$(line "$out" rss)" 2)
end=$(sed -n 's/^rss|end|//p' <<<"$out")
n_ok=$(grep -c '|sampled$' <<<"$out" || true)
if [[ -z $base || -z $end ]]; then
  fail "covers: no RSS reading (died or timed out: $(line "$out" timeout))"
elif (( end - base >= GROWTH_CAP_KB )); then
  fail "covers: RSS grew $(( (end - base) / 1024 )) MB over 35 covers (cap $(( GROWTH_CAP_KB / 1024 )) MB)"
fi
(( n_ok == 40 )) || fail "covers: $n_ok of 40 covers were drawn and sampled"
ok "40 distinct covers are each drawn and sampled, and RSS grows $(( (${end:-0} - ${base:-0}) / 1024 )) MB (cap $(( GROWTH_CAP_KB / 1024 )) MB)"

(( failed == 0 )) || exit 1
