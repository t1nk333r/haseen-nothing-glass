import QtQuick
import Quickshell
import "plugin/widgets/now-playing/widget" as NP

FloatingWindow {
    id: probe
    implicitWidth: 96
    implicitHeight: 96
    property var plan: JSON.parse(Quickshell.env("FLIP_PLAN"))
    property int at: -1
    property double started: 0
    NP.FlipAlbumArt {
        id: flip
        width: 96
        height: 96
    }
    function next() {
        at++
        if (at >= plan.length) { Qt.quit(); return }
        started = Date.now()
        var urls = plan[at].set
        for (var i = 0; i < urls.length; i++) flip.artUrl = urls[i]
    }
    Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            if (probe.at < 0) { probe.next(); return }
            var front = flip._showingA ? flip._faceACanonical : flip._faceBCanonical
            if (flip._state === 0 && front === probe.plan[probe.at].front) {
                console.log("RESULT|flip|" + probe.at + "|" + (Date.now() - probe.started) / 1000)
                probe.next()
            } else if (Date.now() - probe.started > 8000) {
                console.log("RESULT|flip-stuck|" + probe.at + "|state " + flip._state)
                Qt.quit()
            }
        }
    }
}
