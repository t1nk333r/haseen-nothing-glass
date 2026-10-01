import QtQuick
import Quickshell
import Quickshell.Io
import "components" as C

// Driven by tests/cover-art.sh, one scenario per run. It drives the real
// CoverArt and prints RESULT lines:
//
//   RESULT|step|<i>|<seconds>|<url>|<drawn>   per entry of $URLS, once the
//                                            component has settled on it
//   RESULT|hwm|<kB>                           this shell's peak RSS
//   RESULT|<scenario-specific>|…
//
// If the event loop blocks, the heartbeat stops and no RESULT is printed.
FloatingWindow {
    id: probe
    implicitWidth: 96
    implicitHeight: 96
    color: "black"

    readonly property string scenario: Quickshell.env("SCEN") || ""
    readonly property var urls: (Quickshell.env("URLS") || "").split(" ").filter(function (u) { return u !== "" })
    readonly property var art: loader.item
    property int step: -1
    property double stepStart: 0
    property string dir: ""

    LazyLoader {
        id: loader
        active: true
        C.CoverArt {
            _timeoutSec: Number(Quickshell.env("TIMEOUT") || "10")
            _maxBytes: Number(Quickshell.env("MAXBYTES") || "4194304")
            _maxDataChars: Number(Quickshell.env("DATAMAX") || "1048576")
        }
    }

    // What a tile does with the output: draw it.
    Image {
        id: drawn
        width: 96
        height: 96
        source: probe.art ? probe.art.url : ""
        sourceSize.width: 96
        sourceSize.height: 96
        asynchronous: true
        cache: false
    }

    function log(s) { console.log("RESULT|" + s) }
    function secs() { return ((Date.now() - probe.stepStart) / 1000).toFixed(1) }

    function next() {
        probe.step++
        if (probe.step >= probe.urls.length) { probe.finish(); return }
        probe.stepStart = Date.now()
        probe.art.source = probe.urls[probe.step] === "EMPTY" ? "" : probe.urls[probe.step]
    }

    // Peak RSS of this shell: the child's parent is the shell.
    Process {
        id: hwm
        command: ["sh", "-c", "sed -n 's/^VmHWM:[[:space:]]*\\([0-9]*\\).*/\\1/p' /proc/$PPID/status"]
        stdout: StdioCollector {
            onStreamFinished: { probe.log("hwm|" + String(this.text).trim()); probe.after() }
        }
    }

    Process {
        id: check
        property string tag: ""
        property var then: null
        stdout: StdioCollector {
            onStreamFinished: {
                probe.log(check.tag + "|" + String(this.text).trim().split("\n").join(","))
                var t = check.then
                check.then = null
                if (t) t()
            }
        }
    }
    function run(tag, cmd, then) { check.tag = tag; check.then = then; check.command = cmd; check.running = true }

    // How many curl processes are fetching a URL matching `pattern`. Anchored
    // on the executable, so the wrappers this test runs under - whose own
    // command lines carry the URLs - are not counted.
    function curls(pattern) {
        return "$(pgrep -fc -- '^[^ ]*curl .*127[.]0[.]0[.]1:" + Quickshell.env("HTTPS_PORT") + "/" + pattern + "' || true)"
    }

    function finish() { hwm.running = true }

    function after() {
        var port = Quickshell.env("HTTPS_PORT")
        if (probe.scenario === "supersede") {
            // The first stall was superseded a second ago; the second is
            // still in flight (its deadline is far off), so it is the control.
            probe.run("curls", ["sh", "-c", "echo " + probe.curls("stall[?]a") + " " + probe.curls("stall[?]b")], Qt.quit)
        } else if (probe.scenario === "destroy") {
            var u = probe.art.url
            probe.dir = decodeURIComponent(u.replace(/^file:\/\//, "").replace(/\/cover-[0-9]\?g=[0-9]+$/, ""))
            probe.log("dir|" + probe.dir)
            probe.run("mode", ["stat", "-c", "%a", "--", probe.dir], function () {
                // A fetch in flight when the component goes.
                probe.art.source = "https://127.0.0.1:" + port + "/stall?destroy"
                destroyTimer.start()
            })
        } else {
            Qt.quit()
        }
    }
    Timer {
        id: destroyTimer
        interval: 600
        onTriggered: {
            probe.run("before-destroy", ["sh", "-c", "echo " + probe.curls("stall[?]destroy")], function () {
                loader.active = false
                destroyCheck.start()
            })
        }
    }
    Timer {
        id: destroyCheck
        interval: 1500
        onTriggered: {
            probe.run("after-destroy", ["sh", "-c", "if [ -e \"$1\" ]; then echo present; else echo gone; fi; echo " + probe.curls("stall[?]destroy"),
                                        "sh", probe.dir], Qt.quit)
        }
    }

    Timer {
        interval: 50
        repeat: true
        running: true
        property int ticks: 0
        onTriggered: {
            ticks++
            if (ticks > 600) { probe.log("timeout|" + probe.step); Qt.quit(); return }
            if (!probe.art) return
            if (probe.step < 0) { probe.next(); return }
            if (probe.step >= probe.urls.length) return
            if (probe.scenario === "supersede") {
                // Never waits for a settle: the next URL lands mid-fetch.
                if (Date.now() - probe.stepStart < 1000) return
                probe.log("step|" + probe.step + "|" + probe.secs() + "|" + probe.art.url + "|-")
                probe.next()
                return
            }
            if (probe.art.busy) return
            var url = probe.art.url
            if (url !== "" && drawn.status !== Image.Ready && drawn.status !== Image.Error) return
            var shown = url === "" ? "-" : (drawn.status === Image.Ready ? "drawn " + drawn.implicitWidth : "error")
            probe.log("step|" + probe.step + "|" + probe.secs() + "|" + url + "|" + shown)
            probe.next()
        }
    }
}
