import QtQuick
import Quickshell
import Quickshell.Io

// A folder of pictures, as a list of file URLs plus a cursor that advances on
// its own. No thumbnailing and no cache: Image with `sourceSize` set does the
// downscaling, and the folder is re-read only when it changes or on request.
QtObject {
  id: photos

  // Absolute path. Defaults to the XDG pictures folder.
  property string folder: ""
  // `active` is what a view binds to its own `visible`: false only while the
  // monitor is switched off (DPMS) - the one "not being drawn" state the shell
  // can see, since a widget sits on every workspace by design - and the folder
  // is not rescanned while it is false. Unknown reads as true.
  property bool active: true
  property bool shuffle: true
  // Seconds between frames; 0 parks on the current picture.
  property int intervalSec: 30

  property bool loaded: false
  property string errorMessage: ""
  property var files: []
  property int index: 0

  readonly property int count: photos.files.length
  readonly property string current: (photos.count > 0 && photos.index < photos.count)
    ? photos.files[photos.index] : ""
  readonly property string currentName: {
    var p = photos.current
    if (p === "") return ""
    var s = String(p).split("/")
    return decodeURIComponent(s[s.length - 1])
  }

  // `~` and `~/x` are what a person types into a settings field, and a
  // trailing slash is what they leave behind when they paste one; neither is
  // a path `find` understands as written.
  function _expand(path) {
    var p = String(path || "").trim()
    var home = Quickshell.env("HOME") || ""
    if (p === "~") p = home
    else if (p.indexOf("~/") === 0) p = home + p.substring(1)
    while (p.length > 1 && p.charAt(p.length - 1) === "/") p = p.substring(0, p.length - 1)
    return p
  }

  readonly property string _dir: photos.folder.trim() !== ""
    ? photos._expand(photos.folder)
    : photos._expand(Quickshell.env("XDG_PICTURES_DIR") || (Quickshell.env("HOME") + "/Pictures"))

  // What a view shows when it wants to name the source: the folder, short.
  readonly property string folderLabel: {
    var d = photos._dir
    var home = Quickshell.env("HOME") || ""
    if (home !== "" && d.indexOf(home) === 0) return "~" + d.substring(home.length)
    return d
  }

  function next() { if (photos.count > 0) photos.index = (photos.index + 1) % photos.count }
  function previous() { if (photos.count > 0) photos.index = (photos.index + photos.count - 1) % photos.count }
  function refresh() { scan.running = true }

  on_DirChanged: photos.refresh()

  property Process _scan: Process {
    id: scan
    running: false
    // -maxdepth 1: a wallpaper folder with a nested archive should not turn
    // one widget into a recursive directory walk.
    // The folder is passed as an argument, never interpolated into the
    // script: the setting is editable from the settings sheet and the IPC
    // `set` verb, so a name holding a shell metacharacter would otherwise be
    // expanded by the shell instead of used literally - and a name holding a
    // command would be executed.
    command: ["sh", "-c",
      "find \"$1\" -maxdepth 1 -type f " +
      "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) " +
      "2>/dev/null | head -400 | sort",
      "sh", photos._dir]
    stdout: StdioCollector {
      onStreamFinished: {
        var out = []
        var lines = String(this.text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var p = lines[i].trim()
          if (p !== "") out.push("file://" + encodeURI(p).replace(/#/g, "%23"))
        }
        if (photos.shuffle) {
          for (var j = out.length - 1; j > 0; j--) {
            var k = Math.floor(Math.random() * (j + 1))
            var tmp = out[j]; out[j] = out[k]; out[k] = tmp
          }
        }
        photos.files = out
        photos.index = 0
        photos.loaded = true
        photos.errorMessage = out.length === 0 ? "No pictures in " + photos.folderLabel : ""
      }
    }
  }

  property Timer _tick: Timer {
    interval: Math.max(2, photos.intervalSec) * 1000
    running: photos.active && photos.intervalSec > 0 && photos.count > 1
    repeat: true
    onTriggered: photos.next()
  }

  Component.onCompleted: photos.refresh()
}
