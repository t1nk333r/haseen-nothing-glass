import QtQuick
import Quickshell
import Quickshell.Io
import "plugin"
import "components/nothing"

// Driven by tests/cover-art.sh: the REAL Now Playing tile ($STYLE "glass" or
// "nothing"), hosted the way WidgetHost hosts it - the `plugin`, `theme`,
// `backdrop` and `nothing` ids, manifest defaults for settings - with a stand-in
// MPRIS player whose `trackArtUrl` the scenario sets. It prints RESULT lines:
//
//   RESULT|art|<i>|<albumArt>|<drawn>|<sampled>   per entry of $ARTS
//   RESULT|rss|<label>|<kB>                       this shell's RSS, now
//   RESULT|hwm|<kB>                               this shell's peak RSS
FloatingWindow {
    id: probe
    implicitWidth: Number(Quickshell.env("W") || "400")
    implicitHeight: Number(Quickshell.env("H") || "400")
    color: "black"

    readonly property string style: Quickshell.env("STYLE") || "glass"
    readonly property var arts: (Quickshell.env("ARTS") || "").split(" ").filter(function (u) { return u !== "" })
    // Seconds to stay on each entry before reporting it, when it is not
    // expected to settle on a picture (a refused or endless URL).
    readonly property int holdMs: Number(Quickshell.env("HOLD_MS") || "0")
    // Report RSS after this entry, as the baseline the end is compared with.
    readonly property int baselineAt: Number(Quickshell.env("BASELINE_AT") || "-1")

    property var pluginSettings: ({})
    property bool settingsReady: false
    FileView {
        id: manifestFile
        path: Qt.resolvedUrl("plugin/manifest.json")
        printErrors: false
        onLoaded: {
            var s = JSON.parse(text()).settings.defaults || ({})
            // A stand-in player: no pause/play nudge, and the tile always shown.
            s.artRefreshEnabled = false
            s.autoHideEnabled = false
            probe.pluginSettings = s
            probe.settingsReady = true
        }
    }

    // ── the injection chain, as WidgetHost / tests/WidgetSweepTile.qml ──
    Config { id: plugin; settings: probe.pluginSettings }
    QtObject {
        id: theme
        readonly property color systemBackground: "#1c1c1e"
        readonly property var palette: null
    }
    QtObject {
        id: backdrop
        readonly property Item item: null
    }
    NTheme { id: nothing }

    QtObject {
        id: player
        property string identity: "probe"
        property string trackTitle: "A track"
        property string trackArtist: "An artist"
        property string trackArtUrl: ""
        property bool isPlaying: false
        property bool canGoPrevious: true
        property bool canGoNext: true
        property bool canPlay: true
        property bool canPause: true
        property bool canSeek: false
        property bool lengthSupported: false
        property real length: 0
        property real position: 0
        function play() {}
        function pause() {}
        function togglePlaying() {}
        function next() {}
        function previous() {}
        function seek(s) {}
    }

    Loader {
        id: tile
        anchors.fill: parent
        active: probe.settingsReady
        source: Qt.resolvedUrl("plugin/" + (probe.style === "nothing" ? "widgets-nothing" : "widgets")
                               + "/now-playing/main.qml")
        onStatusChanged: {
            if (status === Loader.Ready) item._activePlayer = player
            else if (status === Loader.Error) { probe.log("load-error"); Qt.quit() }
        }
    }

    function log(s) { console.log("RESULT|" + s) }

    // Every Image in the tile that shows `url`, visibly, and has decoded it.
    function drawnCount(item, url) {
        var n = 0
        var kids = item.children || []
        for (var i = 0; i < kids.length; i++) {
            var k = kids[i]
            // Older FlipAlbumArt stamped its drawn URL with ?_t=. Compare the
            // same picture, not that incidental cache key, on the baseline too.
            if (String(k).indexOf("QQuickImage") === 0
                    && String(k.source).replace(/[?&]_t=[0-9]+$/, "") === url
                    && k.visible && k.status === Image.Ready)
                n++
            n += probe.drawnCount(k, url)
        }
        return n
    }

    Process {
        id: mem
        property string field: "VmRSS"
        property string label: ""
        property var then: null
        command: ["sh", "-c", "sed -n \"s/^$1:[[:space:]]*\\([0-9]*\\).*/\\1/p\" /proc/$PPID/status", "sh", mem.field]
        stdout: StdioCollector {
            onStreamFinished: {
                var kb = String(this.text).trim()
                probe.log(mem.field === "VmHWM" ? "hwm|" + kb : "rss|" + mem.label + "|" + kb)
                var t = mem.then
                mem.then = null
                if (t) t()
            }
        }
    }
    function measure(field, label, then) {
        mem.field = field
        mem.label = label
        mem.then = then
        mem.running = true
    }

    property int at: -1
    property double atStart: 0
    property bool waiting: false
    property string lastArt: ""

    function next() {
        probe.at++
        if (probe.at >= probe.arts.length) {
            probe.waiting = true
            probe.measure("VmRSS", "end", function () {
                probe.measure("VmHWM", "", function () { Qt.quit() })
            })
            return
        }
        probe.atStart = Date.now()
        player.trackArtUrl = probe.arts[probe.at]
    }

    function settled(t) {
        var item = tile.item
        var art = item.albumArt
        var drawn = art === "" ? 0 : probe.drawnCount(item, art)
        var sampled = probe.style === "glass" ? (item._hasSampledColor && item._lastSampledUrl === art) : true
        if (t < probe.holdMs) return false
        // A new picture is expected when the entry is not held: wait for it
        // to be the one drawn (and, on glass, the one sampled).
        if (probe.holdMs === 0 && (art === "" || art === probe.lastArt || drawn === 0 || !sampled) && t < 10000)
            return false
        probe.lastArt = art
        probe.log("art|" + probe.at + "|" + art + "|" + drawn + "|" + (sampled ? "sampled" : "unsampled"))
        return true
    }

    Timer {
        interval: 50
        repeat: true
        running: true
        property int ticks: 0
        onTriggered: {
            ticks++
            if (ticks > 1100) { probe.log("timeout|" + probe.at); Qt.quit(); return }
            if (probe.waiting || !tile.item || tile.item._activePlayer !== player) return
            if (probe.at < 0) { probe.next(); return }
            if (!probe.settled(Date.now() - probe.atStart)) return
            if (probe.at === probe.baselineAt) {
                probe.waiting = true
                // Let the decoder and the sampler finish with this entry first.
                Qt.callLater(function () {
                    probe.measure("VmRSS", "baseline", function () { probe.waiting = false; probe.next() })
                })
                return
            }
            probe.next()
        }
    }
}
