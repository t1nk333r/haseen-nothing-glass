import QtQuick
import Quickshell
import Quickshell.Io

// A screen-sized copy of the compositor's current wallpaper, used as the
// backdrop LiquidGlass refracts. Omarchy renders the desktop wallpaper in its
// own layer-shell window, and ShaderEffectSource cannot sample across windows,
// so each of our surfaces loads the same file itself. PreserveAspectCrop and
// the full-screen size match Background.qml, which is what keeps our sampled
// pixels aligned with what the user actually sees.
//
// Invariant: this Image must live in the same PanelWindow as the LiquidGlass
// instance(s) that sample it via ShaderEffectSource — see GlassSurface.qml.
// Moving widgets into their own per-widget windows breaks this silently (the
// glass falls back to its flat Rectangle) because ShaderEffectSource.sourceItem
// does not work across windows.
Image {
  id: wallpaper

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string backgroundLink: stateHome + "/omarchy/current/background"

  // Resolved by a `readlink -f` Process; the state path is a symlink that
  // theme switches repoint.
  property string resolvedPath: ""

  source: resolvedPath ? "file://" + resolvedPath : ""
  fillMode: Image.PreserveAspectCrop
  cache: true
  asynchronous: true
  // Must render into the scene graph for ShaderEffectSource to capture it,
  // but must not be drawn on top of the desktop. ShaderEffectSource captures
  // a non-visible source item; LiquidGlass's hideSource handles the rest.
  visible: false

  function refresh() {
    if (!resolveProc.running) resolveProc.running = true
  }

  Process {
    id: resolveProc
    command: ["readlink", "-f", wallpaper.backgroundLink]
    stdout: StdioCollector {
      onStreamFinished: {
        const p = String(text || "").trim()
        if (p && p !== wallpaper.resolvedPath) wallpaper.resolvedPath = p
      }
    }
  }

  // The symlink swap that a theme/wallpaper change performs does not always
  // raise an inotify event on the link itself, so a FileView watch is paired
  // with a low-frequency polling backstop.
  FileView {
    id: linkWatch
    path: wallpaper.backgroundLink
    watchChanges: true
    onFileChanged: wallpaper.refresh()
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: wallpaper.refresh()
  }

  Component.onCompleted: refresh()
}
