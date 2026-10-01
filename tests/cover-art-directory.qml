import QtQuick
import Quickshell
import Quickshell.Io
import "components" as C

// Exercise ownership and teardown against a controlled mkdir race/collision.
FloatingWindow {
    id: probe
    implicitWidth: 16
    implicitHeight: 16
    property string dir: ""
    property bool destroyed: false
    LazyLoader {
        id: loader
        active: true
        C.CoverArt { source: "file://" + Quickshell.env("FILES") + "/good.png" }
    }
    Process {
        id: check
        command: ["sh", "-c", "test ! -e \"$1\" && echo gone", "sh", probe.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                console.log("RESULT|directory|" + String(this.text).trim())
                Qt.quit()
            }
        }
    }
    Timer {
        interval: 50
        running: true
        repeat: true
        property int ticks: 0
        onTriggered: {
            if (++ticks > 160) { console.log("RESULT|directory|timeout"); Qt.quit(); return }
            if (probe.destroyed) {
                if (ticks > 60) check.running = true
                return
            }
            var art = loader.item
            if (!art) return
            if (!art._isOwnDir(art._runtimeDir() + "/cover-art.ABCdef123456")
                    || art._isOwnDir(art._runtimeDir() + "/../victim")
                    || art._isOwnDir(art._runtimeDir() + "/cover-art.ABCdef123456/child")
                    || art._isOwnDir("/tmp/cover-art.ABCdef123456")) {
                console.log("RESULT|directory|invalid validation"); Qt.quit(); return
            }
            if (Quickshell.env("DIR_SCEN") === "collision") {
                if (art.busy || (!art._dirReady && !art._dirFailed)) return
                console.log("RESULT|collision|" + (art.url !== "" && art._dirAttempts >= 2 ? "retried" : "failed"))
            } else if (ticks < 10 || art._dirReady || art._dirPath === "") {
                return
            }
            probe.dir = art._dirPath
            console.log("RESULT|owned-dir|" + probe.dir)
            loader.active = false
            probe.destroyed = true
        }
    }
}
