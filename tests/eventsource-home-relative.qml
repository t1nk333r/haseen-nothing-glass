import QtQuick
import Quickshell
import "components" as Components

// Reports what the calendar's empty state would draw, once the seam has
// settled. tests/eventsource-home-relative.sh varies HOME and XDG_STATE_HOME
// around it and judges the value; this file only reads it.
Scope {
    // PROBE_EVENTS_FILE, when set, overrides the path the way a harness would.
    Components.EventSource {
        id: source
        khalEnabled: false
        Component.onCompleted: {
            var p = Quickshell.env("PROBE_EVENTS_FILE")
            if (p) source.eventsFile = p
        }
    }
    Timer {
        interval: 10
        repeat: true
        running: true
        onTriggered: {
            if (!source._settled) return
            console.log("DETAIL|" + source.state + "|" + source.stateDetail)
            Qt.quit()
        }
    }
}
