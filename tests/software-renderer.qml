import QtQuick
import QtQuick.Window
import Quickshell
import "components"
import "components/nothing"

// Driven by tests/software-renderer.sh, under QT_QPA_PLATFORM=offscreen,
// which is Qt's software scene graph - the renderer haseen's shell runs by
// default (QT_QUICK_BACKEND=software). No ShaderEffect draws there, and every
// material below used to be one: a frosted Nothing card made its own fill
// transparent and handed the material to a shader that never ran, and a
// LiquidGlass tile, glass or solid, was drawn only by its shader. Each must
// now paint its own fallback. The tiles are grabbed to PNGs in $OUT for the
// script to measure.
ShellRoot {
  Window {
    width: 600
    height: 220
    visible: true
    color: "#000000"

    Item {
      id: host
      anchors.fill: parent

      // Stands in for Wallpaper.qml: what FrostLayer and LiquidGlass sample.
      Rectangle {
        id: wallpaper
        anchors.fill: parent
        visible: false
        gradient: Gradient {
          GradientStop { position: 0; color: "#c0392b" }
          GradientStop { position: 1; color: "#2980b9" }
        }
      }

      FrostLayer { id: frostLayer; anchors.fill: parent; wallpaper: wallpaper; active: true }
      NTheme { id: nothing; frost: 1; surfaceAlpha: 0.81; frostSource: frostLayer.output }

      NCard { id: card; x: 8; y: 8; width: 192; height: 192; theme: nothing }
      LiquidGlass { id: glassTile; x: 208; y: 8; width: 192; height: 192; radius: 40; wallpaperItem: wallpaper }
      LiquidGlass {
        id: solidTile; x: 408; y: 8; width: 192; height: 192; radius: 40
        wallpaperItem: wallpaper; solidMode: true; solidColor: "#336699"; solidColorBottom: "#993366"
      }

      property int failures: 0
      function check(label, ok, detail) {
        if (!ok) {
          host.failures++
          console.log("FAIL " + label + (detail ? "  (" + detail + ")" : ""))
        }
      }

      property int pending: 0
      function grab(item, name) {
        host.pending++
        item.grabToImage(function (result) {
          result.saveToFile(Quickshell.env("OUT") + "/" + name + ".png")
          if (--host.pending === 0) host.finish()
        })
      }
      function finish() {
        console.log(host.failures === 0 ? "OK: software renderer fallbacks" : "FAILED: software renderer fallbacks")
        Qt.quit()
      }

      Timer {
        interval: 100
        running: true
        repeat: true
        property int ticks: 0
        onTriggered: {
          ticks++
          if (host.GraphicsInfo.api !== GraphicsInfo.Software) {
            if (ticks >= 50) { console.log("FAIL the scene graph never reported the software renderer"); Qt.quit() }
            return
          }
          stop()
          host.check("FrostLayer reports no output it cannot draw", frostLayer.output === null)
          host.check("a frost-1 card is not frosted without shaders", !card.frosted)
          host.check("a frost-1 card keeps its surface fill", card.color.a > 0.5, "alpha " + card.color.a)
          host.check("glass LiquidGlass is inactive without shaders", !glassTile.active)
          host.check("solid LiquidGlass knows no shader runs", solidTile.shadersRun === false)
          host.grab(card, "card")
          host.grab(glassTile, "glass")
          host.grab(solidTile, "solid")
        }
      }
    }
  }
}
