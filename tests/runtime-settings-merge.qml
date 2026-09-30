import QtQuick
import Quickshell
import Quickshell.Io
import "plugin"

// NOTE: `qs` refuses to load a QML module path outside the config folder, so
// run.sh copies this file into a scratch directory that also carries a
// `plugin` symlink to the runtime under test - hence the plain
// `import "plugin"`.
//
// Headless check of the two things every widget's configuration passes
// through: GlassSurface._mergedSettings() (manifest defaults, then the
// plugin's shell.json entry, then its own options file) and the three-tier
// style chain (the widget's own row, its category, the plugin default).
//
// Both defects this guards against shipped:
//
//   * shell.json is the shell's file and the shell relocates its plugin entry
//     and strips the settings off it on restart (measured on this machine),
//     so the options file - the plugin's own durable copy - has to win. The
//     bar panel wrote the losing copy, and a value set there did not survive.
//   * five settings used to be stored as integers scaled by 10 or 100, so a
//     config written by an older build still carries `roundnessX10` and
//     friends, which nothing reads any more.
//
// The fixtures (shell.json and the options file) are written by run.sh into a
// scratch HOME for this process, so nothing here reads the user's own
// settings. GlassSurface builds PanelWindows, which quickshell refuses to
// create without a Wayland compositor, so run.sh runs this one against a
// private headless compositor; it draws nothing anywhere, and a machine
// without one skips the test rather than failing it.
//
// Every numeric expectation below is a value an IEEE double holds exactly
// (0.25, 0.5, 7.5, ...), so the assertions compare with === and need no
// tolerance.
ShellRoot {
  Item {
    id: host

    GlassSurface {
      id: surface
      // No screens, so no per-screen window delegate is built: the merge and
      // the style chain are the subject here, not the windows.
      model: []
    }

    // The manifest the plugin actually ships, so "a key reads its manifest
    // default" is held against that file rather than against a copy of it.
    // GlassSurface falls back to its own literal during shell startup anyway
    // (see its _fallbackDefaults comment), and run.sh section 1 keeps that
    // literal and this file identical.
    FileView {
      id: manifestFile
      path: Qt.resolvedUrl("plugin/manifest.json")
      printErrors: false
      onLoaded: {
        try { surface.manifest = JSON.parse(text()) }
        catch (e) { console.log("FAIL manifest.json did not parse: " + e) }
      }
    }

    property int failures: 0
    property int checks: 0
    property int waited: 0

    // The three inputs the merge reads, each loaded from disk on its own
    // schedule: shell.json and the options file through GlassSurface's own
    // FileViews, the manifest above.
    readonly property bool ready: surface._shellConfig !== null &&
                                  surface.options.loaded &&
                                  surface.manifest !== null

    function check(label, ok, detail) {
      host.checks++
      if (!ok) {
        host.failures++
        console.log("FAIL " + label + (detail ? "  (" + detail + ")" : ""))
      }
    }

    Timer {
      id: driver
      interval: 100
      repeat: true
      running: true

      onTriggered: {
        host.waited++
        if (host.waited > 100) {
          console.log("FAIL timed out waiting for the fixtures: shellConfig=" +
            (surface._shellConfig !== null) + " options=" + surface.options.loaded +
            " manifest=" + (surface.manifest !== null))
          Qt.exit(1)
        }
        if (!host.ready) return
        driver.stop()
        host.verify()
      }
    }

    function verify() {
      // The settings a widget body reads, as `plugin.settings.X`.
      var s = surface.plugin.settings

      // 1. A key nothing overrides reads its manifest default.
      host.check("a key nothing overrides reads its manifest default",
                 s.refractThickness === 35 && s.blurRadiusPx === 6,
                 "refractThickness=" + s.refractThickness + " blurRadiusPx=" + s.blurRadiusPx)

      // 2. The shell.json entry beats that default.
      host.check("the shell.json entry overrides the manifest default",
                 s.appearance === 1, "appearance=" + s.appearance)

      // 3. And our own options file beats the shell.json entry. This is the
      //    precedence a live bug depended on: the bar panel wrote shell.json,
      //    the shell relocated and stripped that entry on its next restart,
      //    and the value was gone. The options file is the durable copy.
      host.check("the options file overrides the shell.json entry",
                 s.styleMode === 2, "styleMode=" + s.styleMode)

      // 4. `omarchy bar set` stores a string unless told --json, so a value
      //    read back from either file is coerced to its default's type - a
      //    string "1" silently breaks every strict === the widgets make.
      host.check("a numeric string from shell.json becomes a number",
                 s.cornerRadius === 42 && typeof s.cornerRadius === "number",
                 "cornerRadius=" + JSON.stringify(s.cornerRadius))
      host.check("a \"true\" string from shell.json becomes a boolean",
                 s.realtimeRefraction === true && typeof s.realtimeRefraction === "boolean",
                 "realtimeRefraction=" + JSON.stringify(s.realtimeRefraction))
      host.check("the options file's values are coerced the same way",
                 s.refreshMinutes === 30 && typeof s.refreshMinutes === "number",
                 "refreshMinutes=" + JSON.stringify(s.refreshMinutes))

      // 5. The five settings that used to be stored as scaled integers convert
      //    at the single point every source is merged, so no read site has to
      //    cope with two spellings.
      host.check("the legacy scaled keys convert to their current spelling",
                 s.roundness === 7.5 && s.refractIOR === 1.5 && s.tintAlpha === 0.25 &&
                 s.chromaStrength === 0.75 && s.specStrength === 0.5,
                 "roundness=" + s.roundness + " refractIOR=" + s.refractIOR +
                 " tintAlpha=" + s.tintAlpha + " chromaStrength=" + s.chromaStrength +
                 " specStrength=" + s.specStrength)
      host.check("the legacy keys themselves are gone from the merged settings",
                 !("roundnessX10" in s) && !("refractIORx100" in s) &&
                 !("tintAlphaPct" in s) && !("chromaStrengthPct" in s) &&
                 !("specStrengthPct" in s))

      // 6. Style resolves most specific first: the widget's own row, then its
      //    category's entry, then the plugin-wide `widgetStyle`. The fixtures
      //    make each tier disagree with the next, so passing one of these by
      //    accident is not possible.
      host.check("a row with its own style uses it",
                 surface.styleForEntry({ id: "w1", type: "clock-digital", style: "nothing" }) === "nothing")
      host.check("a row without one uses its category's style",
                 surface.styleForEntry({ id: "w2", type: "clock-digital" }) === "liquid-glass")
      host.check("with neither, the plugin-wide widgetStyle applies",
                 surface.styleForEntry({ id: "w3", type: "weather" }) === "nothing")
      host.check("a category's style is readable on its own",
                 surface.styleForCategory("Time") === "liquid-glass" &&
                 surface.styleForCategory("Weather") === "nothing",
                 "Time=" + surface.styleForCategory("Time") +
                 " Weather=" + surface.styleForCategory("Weather"))

      console.log(host.failures === 0
        ? "OK: settings merge and style resolution (" + host.checks + " checks)"
        : host.failures + " of " + host.checks + " merge checks FAILED")
      Qt.exit(host.failures === 0 ? 0 : 1)
    }
  }
}
