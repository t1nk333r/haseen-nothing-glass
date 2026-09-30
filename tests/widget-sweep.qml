import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "plugin"

// Runtime half of tests/run.sh: the static half already checks that
// every type the registry offers has a file that exists, in both styles. This
// one loads them all and looks at the pixels.
//
// Why it exists: this plugin's signature failure is silent. A QML type that
// does not resolve - a missing qmldir line, a rename that missed a call site -
// renders an EMPTY TILE AND NO ERROR (PORTING.md items 20-21), and nothing in
// a build or a static check sees it. The only observer that catches it is a
// renderer: a tile that produces no ink is broken even when every file parses.
//
// So the contract, per tile, is two-sided:
//
//   1. it loads - the registry's own urlFor(type, style) resolves to a
//      component and the Loader reaches Ready, and
//   2. it draws  - the tile's pixels are not blank and not one flat colour.
//
// (2) is measured outside QML: QML cannot read pixels back, so each tile is
// grabbed to a PNG and the sweep script measures it. The backdrop here is
// deliberately FLAT, which is what makes (2) sharp - a tile whose own drawing
// is missing measures a single flat colour, while a structured backdrop would
// leak texture through the glass and read as ink a broken tile does not have.
//
// Driven by tests/sweep-widgets.sh, which copies this file and
// WidgetSweepTile.qml into a scratch directory carrying a `plugin` symlink
// (the dev-harness trick from glass-dev.qml: `qs -p` refuses an import
// that textually leaves the entry file's directory), gives it a private
// headless gamescope and a scratch HOME, and measures the PNGs it writes to
// $OUT.
//
// Output protocol, one line per statement, parsed by that script:
//
//   SWEEP tile <type> <style> <url>            every pair, before loading
//   SWEEP load <type> <style> <state> <url>    once each Loader settles
//   SWEEP pairs <n>                            how many pairs the registry gave
//   SWEEP loaded <n> errors <m>                after every loader settled
//   SWEEP grab <type> <style> <png> ok         per tile, after the settle delay
//   SWEEP done <n>                             all tiles grabbed, exiting
//
// It renders in a real Window (not under ShellRoot alone: an Item that is not
// attached to one never attaches to a scene graph, its Canvas never paints and
// grabToImage() refuses) against a real compositor - see the script's comment
// on why QT_QPA_PLATFORM=offscreen is not enough for the glass.
ShellRoot {
  id: shell

  // The registry under test is the plugin's own, and it is the only list of
  // types: a hand-written one could not catch a type registered wrongly,
  // which is the case this sweep exists for.
  WidgetRegistry { id: registry }
  Theme { id: injectedTheme }

  // The plugin-wide settings, exactly as production builds them for a widget
  // host: manifest.json's settings.defaults. Under the scratch HOME there is
  // no shell.json entry and no options file, so this is also what
  // GlassSurface._mergedSettings() would produce there - the two agree by
  // construction, which run.sh section 1 enforces.
  property var pluginSettings: ({})
  property bool settingsReady: false

  FileView {
    id: manifestFile
    path: Qt.resolvedUrl("plugin/manifest.json")
    printErrors: false
    onLoaded: {
      try {
        shell.pluginSettings = JSON.parse(text()).settings.defaults || ({})
        shell.settingsReady = true
      } catch (e) {
        console.log("SWEEP fatal manifest.json did not parse: " + e)
        Qt.exit(2)
      }
    }
    onLoadFailed: {
      console.log("SWEEP fatal manifest.json not readable at " + manifestFile.path)
      Qt.exit(2)
    }
  }

  // Every (type, style) the registry offers, in registry order. stylesFor() is
  // the authority on which styles a type has, urlFor() on where they live.
  readonly property var pairs: {
    var out = []
    var types = registry.listTypes()
    for (var i = 0; i < types.length; i++) {
      var t = types[i]
      var styles = registry.stylesFor(t)
      for (var s = 0; s < styles.length; s++)
        out.push({ type: t, style: styles[s] })
    }
    return out
  }

  readonly property int columns: 10
  readonly property int tileSize: 192

  Window {
    id: win
    width: shell.columns * shell.tileSize
    height: Math.ceil(shell.pairs.length / shell.columns) * shell.tileSize
    visible: true
    color: "#000000"

    // The compositor's virtual output, handed in by the script. A grid larger
    // than the output would be resized by the compositor under the driver's
    // feet, and the tiles that fell off it would be missing rather than
    // failing - a silent hole in the sweep, which is the one thing this
    // harness must not have. So the fit is checked, not assumed.
    readonly property int outputWidth: Number(Quickshell.env("SWEEP_OUTPUT_W"))
    readonly property int outputHeight: Number(Quickshell.env("SWEEP_OUTPUT_H"))

    // What a widget's LiquidGlass samples. In production this is Wallpaper.qml
    // - a screen-sized Image of the compositor's wallpaper, `visible: false`
    // because ShaderEffectSource captures it rather than showing it. Same
    // trick here, flat on purpose (see the header comment): the refraction
    // chain still runs, but nothing on this canvas can be mistaken for the
    // widget's own drawing.
    Rectangle {
      id: wallpaper
      x: 0
      y: 0
      width: win.width
      height: win.height
      color: "#404040"
      visible: false
    }

    Grid {
      id: grid
      columns: shell.columns
    }

    // The tiles are created here rather than by a Repeater delegate: the
    // driver needs the list of them anyway (to wait on, and to grab one at a
    // time), and a delegate's `modelData` role is one more thing that can
    // silently not resolve in a QML runtime - which is the class of failure
    // this sweep exists to catch, so it has no business being part of the
    // harness. They are built only once the settings are in: a tile created
    // before that would hand plugin.settings.* to the widget body as
    // `undefined`, which is a stream of warnings that would read as a failure
    // of the widget rather than of this harness.
    Component {
      id: tileComponent
      WidgetSweepTile {
        width: 192
        height: 192
      }
    }

    function buildTiles() {
      var pairs = shell.pairs
      win.allTiles = []
      for (var i = 0; i < pairs.length; i++) {
        var t = tileComponent.createObject(grid, {
          "type": pairs[i].type,
          "style": pairs[i].style,
          "registry": registry,
          "pluginSettings": shell.pluginSettings,
          "injectedTheme": injectedTheme,
          "backdropSource": wallpaper
        })
        // A tile that could not be created would simply not appear in the
        // report, and a type missing from the report reads exactly like a type
        // that passed. Loud, not quiet.
        if (!t) {
          win.fatal("could not instantiate the " + pairs[i].style + " tile for '" + pairs[i].type + "'")
          return
        }
        win.allTiles.push(t)
      }
    }

    // --- the driver ------------------------------------------------------
    //
    // A tick per 250 ms, one stage at a time. Grabs are serialised on purpose:
    // grabToImage() is asynchronous, and firing fifty of them at once would
    // measure different tiles at different points of their first paint and
    // make a failure impossible to place.
    property string stage: "manifest"
    property int ticks: 0
    property var allTiles: []
    property int grabIndex: 0
    property bool grabBusy: false

    function fatal(what) {
      console.log("SWEEP fatal " + what)
      Qt.exit(2)
    }

    function step() {
      win.ticks++
      if (win.stage === "manifest") win.stageManifest()
      else if (win.stage === "load") win.stageLoad()
      else if (win.stage === "settle") win.stageSettle()
      else win.stageGrab()
    }

    function stageManifest() {
      if (!shell.settingsReady) {
        if (win.ticks > 80) win.fatal("manifest.json never loaded")
        return
      }
      if (win.width > win.outputWidth || win.height > win.outputHeight) {
        win.fatal("the grid for " + shell.pairs.length + " pairs is " + win.width + "x" +
                  win.height + ", larger than the " + win.outputWidth + "x" + win.outputHeight +
                  " headless output - raise the output in sweep-widgets.sh, or add columns")
        return
      }
      win.buildTiles()
      if (win.allTiles.length === 0) win.fatal("the registry offered no type/style pairs")
      win.stage = "load"
      win.ticks = 0
    }

    function stageLoad() {
      var i
      var pending = 0
      for (i = 0; i < win.allTiles.length; i++)
        if (!win.allTiles[i].settledDone) pending++
      // The cap is 40 s. A widget whose Loader never settles is worth
      // reporting as an error in its own right, not a reason to hang.
      if (pending > 0 && win.ticks < 160) return
      var errors = 0
      for (i = 0; i < win.allTiles.length; i++)
        if (win.allTiles[i].stateName() !== "ready") errors++
      console.log("SWEEP pairs " + win.allTiles.length)
      console.log("SWEEP loaded " + win.allTiles.length + " errors " + errors +
                  (pending > 0 ? " (timed out with " + pending + " still loading)" : ""))
      win.stage = "settle"
      win.ticks = 0
    }

    function stageSettle() {
      // Long enough for the widgets that read live state - /proc, the
      // Hyprland socket, a state file, a curl - to have drawn whatever they
      // are going to draw. The sweep is about whether a tile draws at all,
      // not about which numbers it found.
      if (win.ticks < 20) return
      win.stage = "grab"
      win.ticks = 0
    }

    function stageGrab() {
      if (win.grabBusy) return
      if (win.grabIndex >= win.allTiles.length) {
        console.log("SWEEP done " + win.allTiles.length)
        Qt.exit(0)
        return
      }
      var t = win.allTiles[win.grabIndex]
      var path = Quickshell.env("OUT") + "/" + t.type + "__" + t.style + ".png"
      win.grabBusy = true
      t.grabToImage(function (result) {
        // `result` exposes only url/saveToFile in Qt 6 - no width/height - so
        // the size the script reports is the PNG's own, measured where it
        // lands. That is the honest number anyway: it is what was written.
        var ok = result.saveToFile(path)
        console.log("SWEEP grab " + t.type + " " + t.style + " " + path + " " + (ok ? "ok" : "savefail"))
        win.grabIndex++
        win.grabBusy = false
      })
    }

    Timer {
      interval: 250
      repeat: true
      running: true
      onTriggered: win.step()
    }
  }
}
