import QtQuick
import Quickshell
import Quickshell.Io
import "plugin"

// Hosts the real Service - its IpcHandler, Store, GlassSurface and Options -
// for tests/settings-ipc.sh, which drives it from outside with
// `qs ipc call`, the way `omarchy-shell <id> <verb>` does. The shell itself
// is a stand-in that only logs what would have been written to shell.json,
// and `qs.Commons` is a stub the script writes beside this file.
//
// It prints one READY line once the store has loaded, with what the merged
// plugin-wide settings say about the fixture it was started on.
ShellRoot {
  QtObject {
    id: fakeShell
    // The shell's entry writer: every call is logged, so the script can see
    // exactly what would have reached the plugin's shell.json entry.
    function updateEntryInline(id, next) {
      console.log("UPDATE " + JSON.stringify(next))
      return true
    }
  }

  // The real manifest, handed over after creation as the shell does.
  FileView {
    id: manifestFile
    path: Quickshell.shellDir + "/plugin/manifest.json"
    blockLoading: true
  }

  Service {
    id: svc
    shell: fakeShell
    Component.onCompleted: svc.manifest = JSON.parse(manifestFile.text())
  }

  Timer {
    property int ticks: 0
    interval: 100
    repeat: true
    running: true
    onTriggered: {
      // The store, the options file and shell.json load independently; a
      // few ticks after the store lets the other two land as well.
      if (!svc.widgetStore.loaded || ++ticks < 5) return
      running = false
      var s = svc.widgetSettings
      console.log("READY polluted=" + ("polluted" in s) + " styleMode=" + s.styleMode +
                  " widgetStyle=" + s.widgetStyle)
    }
  }
}
