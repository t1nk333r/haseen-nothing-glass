import QtQuick
import Quickshell
import Quickshell.Io

// The only way cover art reaches a Now Playing tile.
//
// `source` is the URL an MPRIS player handed over, i.e. whatever the process
// owning that bus name - or, for a browser, the web page's MediaSession -
// chose to write there. `url` is what the tile may draw: a local copy of the
// picture, a small inline `data:image/…` URL, or "" (no art).
//
// Never hand `source` to an Image or a Canvas: Qt buffers a whole HTTP body
// before decoding it, with no deadline and no size limit (`sourceSize` bounds
// the decoded pixmap, not the download), so an endless body grows the desktop
// shell until it dies. What is accepted, and how:
//
//   https://…           copied by a `curl` child: https only, redirects only
//                       to https and at most 3 of them, `--max-time` and
//                       `--max-filesize`, never `-k`.
//   file://[localhost]/… copied by the same kind of child, `--proto =file`.
//                       A player can name /dev/zero, a FIFO or a 10 GB file;
//                       `--max-filesize` stops the first and the last, and a
//                       FIFO with no writer - where curl sits in open(2) and
//                       `--max-time` never fires - is killed by the deadline
//                       below. (Measured with curl 8.22: /dev/zero and an
//                       oversize file fail with exit 63 at the cap, the FIFO
//                       blocks until signalled.)
//   data:image/…        drawn as is, below `_maxDataChars`.
//   anything else       http://, relative, other schemes, file:// naming
//                       another host: refused, the tile shows no art.
//
// Copies land in a directory of this instance's own, created 0700 under
// $XDG_RUNTIME_DIR, as one of four rotating files: the one on screen, the one
// before it (the flip animation shows it on its other face), the one being
// fetched and the one fetched before that, which may still have a dying curl
// attached. So at most four files of at most `_maxBytes` each, and the
// directory goes when the instance does.
//
// One fetch at a time: a new `source` kills the running child and drops its
// result. A curl that cannot be started (not installed) settles the request
// as "no art" (the same test as WeatherDataQs), and so does one that outlives
// the deadline. While a fetch runs, `url` keeps the previous picture, so the
// cover does not blink to "no art" between two tracks.
QtObject {
    id: art

    property string source: ""
    readonly property string url: art._url
    // True while a copy is being made for the current `source`.
    readonly property bool busy: art._fetch !== null || art._pending !== null

    // Limits. Properties so tests/cover-art.sh can shrink them; nothing in
    // the plugin sets them.
    property int _timeoutSec: 10
    property int _maxBytes: 4194304
    property int _maxDataChars: 1048576
    property int _maxUrlChars: 8192
    // On top of `--max-time`: what curl gets to give up on its own before it
    // is killed. A FIFO open never reaches curl's own deadline.
    property int _killGraceMs: 1500

    property string _url: ""
    property int _gen: 0
    // {src, url, slot} of what is on screen, and of what was before it.
    property var _cur: null
    property var _prev: null
    property var _pending: null
    property Process _fetch: null
    property int _lastSlot: -1

    // The directory: "" until made. `_dirPath` is set the moment its mkdir is
    // launched (so teardown knows what to remove even mid-mkdir); `_dirReady`
    // only once that mkdir succeeded.
    property string _dirPath: ""
    property bool _dirReady: false
    property bool _dirFailed: false
    property int _dirAttempts: 0

    onSourceChanged: art._request()
    Component.onCompleted: art._request()

    function _classify(src) {
        if (src === "") return "none"
        // Whitespace and control characters belong in no URL a player means.
        if (/[\s\x00-\x1f\x7f]/.test(src)) return "refused"
        if (/^data:image\/[a-z0-9.+-]+[;,]/i.test(src))
            return src.length <= art._maxDataChars ? "data" : "refused"
        if (src.length > art._maxUrlChars) return "refused"
        if (/^https:\/\/[^\/?#@]/i.test(src)) return "https"
        if (/^file:\/\/(localhost)?\//i.test(src)) return "file"
        return "refused"
    }

    function _request() {
        var src = art.source
        art._gen = art._gen + 1
        art._cancelFetch()
        art._pending = null
        var kind = art._classify(src)
        if (kind === "none" || kind === "refused") {
            art._publish(null)
            return
        }
        if (kind === "data") {
            art._publish({ src: src, url: src, slot: -1 })
            return
        }
        // Already on screen, or the picture just before it (a track skipped
        // back to): no second fetch.
        if (art._cur && art._cur.src === src) return
        if (art._prev && art._prev.src === src) {
            var c = art._cur
            art._cur = art._prev
            art._prev = c
            art._url = art._cur.url
            return
        }
        art._pending = { gen: art._gen, src: src, kind: kind }
        if (art._dirReady) art._launchPending()
        else art._makeDir()
    }

    function _publish(entry) {
        if (art._cur && art._cur.url !== "") art._prev = art._cur
        art._cur = entry
        art._url = entry ? entry.url : ""
    }

    // ── The directory ───────────────────────────────────────────────────
    // `mkdir -m 700` of a random name rather than `mktemp -d`: the name is
    // known before the child runs, so teardown can always remove it, even when
    // the instance goes while the mkdir is in flight. It is still atomic and
    // exclusive - mkdir fails on any existing name, symlink or not - and it is
    // retried with a fresh name.
    function _runtimeDir() {
        var r = String(Quickshell.env("XDG_RUNTIME_DIR") || "")
        while (r.length > 1 && r.charAt(r.length - 1) === "/") r = r.slice(0, -1)
        if (r.charAt(0) !== "/" || r === "/" || /(^|\/)\.\.?(\/|$)/.test(r) || r.indexOf("//") >= 0)
            return ""
        return r
    }

    function _isOwnDir(d) {
        var r = art._runtimeDir()
        if (r === "" || d.indexOf(r + "/") !== 0) return false
        return /^cover-art\.[A-Za-z0-9]{12}$/.test(d.slice(r.length + 1))
    }

    function _makeDir() {
        if (art._dirFailed || dirProc.running) {
            if (art._dirFailed) art._failPending()
            return
        }
        var r = art._runtimeDir()
        if (r === "" || art._dirAttempts >= 3) {
            art._dirFailed = true
            art._dirPath = ""
            art._failPending()
            return
        }
        var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        var name = "cover-art."
        for (var i = 0; i < 12; i++) name += chars.charAt(Math.floor(Math.random() * chars.length))
        art._dirAttempts = art._dirAttempts + 1
        art._dirPath = r + "/" + name
        dirProc.started = false
        dirProc.command = ["mkdir", "-m", "700", "--", art._dirPath]
        dirProc.running = true
    }

    function _dirSettled(ok) {
        if (ok) {
            art._dirReady = true
            art._launchPending()
            return
        }
        // Not ours: never remove a path whose mkdir failed. Retried once the
        // child is fully down, with a fresh name.
        art._dirPath = ""
        if (art._pending) Qt.callLater(art._makeDir)
    }

    function _failPending() {
        if (!art._pending) return
        art._pending = null
        art._publish(null)
    }

    property Process _dirProc: Process {
        id: dirProc
        property bool started: false
        onStarted: dirProc.started = true
        onExited: function (code) { art._dirSettled(code === 0) }
        onRunningChanged: {
            if (dirProc.running || dirProc.started) return
            // mkdir could not be started at all: no directory, ever.
            art._dirPath = ""
            art._dirFailed = true
            art._failPending()
        }
    }

    // ── The fetch ───────────────────────────────────────────────────────
    function _freeSlot() {
        for (var s = 0; s < 4; s++) {
            if (art._cur && art._cur.slot === s) continue
            if (art._prev && art._prev.slot === s) continue
            if (s === art._lastSlot) continue
            return s
        }
        return 0
    }

    function _fileUrl(path) {
        var parts = path.split("/")
        for (var i = 0; i < parts.length; i++) parts[i] = encodeURIComponent(parts[i])
        return "file://" + parts.join("/")
    }

    property Component _fetchComponent: Component {
        Process {
            id: req
            property int gen: 0
            property string src: ""
            property string file: ""
            property int slot: -1
            property bool _started: false
            onExited: function (code) { art._fetchSettled(req, code === 0) }
            // A curl that could not be started never exits; it only stops
            // running. Settle it as "no art" instead of waiting forever.
            onStarted: req._started = true
            onRunningChanged: {
                if (req.running || req._started) return
                art._fetchSettled(req, false)
            }
        }
    }

    function _launchPending() {
        var p = art._pending
        art._pending = null
        if (!p || p.gen !== art._gen) return
        var slot = art._freeSlot()
        art._lastSlot = slot
        var file = art._dirPath + "/cover-" + slot
        var cmd = ["curl", "-q", "-sS", "-f",
                   "--max-time", String(art._timeoutSec),
                   "--max-filesize", String(art._maxBytes),
                   "-o", file]
        if (p.kind === "https")
            cmd = cmd.concat(["--proto", "=https", "--proto-redir", "=https",
                              "-L", "--max-redirs", "3"])
        else
            cmd = cmd.concat(["--proto", "=file"])
        cmd = cmd.concat(["--url", p.src])
        var proc = art._fetchComponent.createObject(art, {
            gen: p.gen, src: p.src, file: file, slot: slot, command: cmd
        })
        art._fetch = proc
        watchdog.restart()
        proc.running = true
    }

    function _cancelFetch() {
        var p = art._fetch
        art._fetch = null
        watchdog.stop()
        if (!p) return
        if (p.running) p.running = false
        p.destroy()
    }

    function _fetchSettled(p, ok) {
        // Superseded or cancelled: nothing it says is current.
        if (p !== art._fetch) return
        art._fetch = null
        watchdog.stop()
        var entry = ok && p.gen === art._gen
            ? { src: p.src, url: art._fileUrl(p.file) + "?g=" + p.gen, slot: p.slot }
            : null
        p.destroy()
        if (p.gen === art._gen) art._publish(entry)
    }

    property Timer _watchdog: Timer {
        id: watchdog
        interval: art._timeoutSec * 1000 + art._killGraceMs
        repeat: false
        onTriggered: {
            var p = art._fetch
            if (!p) return
            art._fetch = null
            if (p.running) p.running = false
            p.destroy()
            if (p.gen === art._gen) art._publish(null)
        }
    }

    // ── Teardown ────────────────────────────────────────────────────────
    // The children are signalled first; the removal is a detached process that
    // waits (bounded) for them to be gone, so a curl still dying cannot
    // re-create a file in a directory being removed. A directory whose mkdir
    // has not reported yet gets `rmdir`, which removes only the empty
    // directory that mkdir made, and nothing that happened to be there.
    Component.onDestruction: {
        var pids = []
        var f = art._fetch
        if (f && f.running && f.processId) pids.push(String(f.processId))
        var mkdirInFlight = dirProc.running
        if (mkdirInFlight && dirProc.processId) pids.push(String(dirProc.processId))
        art._pending = null
        art._cancelFetch()
        if (dirProc.running) dirProc.running = false
        var d = art._dirPath
        if (d === "" || !art._isOwnDir(d)) return
        if (!art._dirReady && !mkdirInFlight) return
        Quickshell.execDetached(["sh", "-c",
            'd=$1; how=$2; shift 2; for p do i=0; while [ $i -lt 50 ] && kill -0 "$p" 2>/dev/null; do i=$((i+1)); sleep 0.1; done; done; if [ "$how" = tree ]; then rm -rf -- "$d"; else rmdir -- "$d"; fi',
            "sh", d, art._dirReady ? "tree" : "empty"].concat(pids))
    }
}
