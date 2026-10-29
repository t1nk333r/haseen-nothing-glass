import QtQuick
import QtQuick.Window
import Quickshell
import "components"
import "components/nothing"
import "components/Squircle.js" as Squircle
import "widgets/timer/widget"
import "widgets/now-playing/widget"

// Driven by tests/software-renderer.sh, under QT_QPA_PLATFORM=offscreen,
// which is Qt's software scene graph - the renderer haseen's shell runs by
// default (QT_QUICK_BACKEND=software). No ShaderEffect draws there, and every
// material below used to be one: a frosted Nothing card made its own fill
// transparent and handed the material to a shader that never ran, and a
// LiquidGlass tile, glass or solid, was drawn only by its shader. Each must
// now paint its own fallback. So must every MultiEffect layer, all of which
// composite to nothing there: a picture cut to the card's squircle, a
// colourised icon, the now-playing cover and buttons, the timer's buttons and
// its rolling digits mid-roll. The tiles are grabbed to PNGs in $OUT for the
// script to measure; halves.svg (red left, blue right) and dot.svg (a black
// disc) are written by the script.
ShellRoot {
  Window {
    width: 1000
    height: 440
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
      // A background link that dangles: the Image fails, and a frost over it
      // would hand every card an empty material on a GPU scene graph.
      Image { id: missingWallpaper; anchors.fill: parent; visible: false; source: Qt.resolvedUrl("no-such-wallpaper.png") }
      FrostLayer { id: deadFrost; anchors.fill: parent; wallpaper: missingWallpaper; active: true }
      NTheme { id: nothing; frost: 1; surfaceAlpha: 0.81; frostSource: frostLayer.output }

      NCard { id: card; x: 8; y: 8; width: 192; height: 192; theme: nothing }
      LiquidGlass { id: glassTile; x: 208; y: 8; width: 192; height: 192; radius: 40; wallpaperItem: wallpaper }
      // The bottom stop is translucent on purpose: the shader's solid blend is
      // opaque whatever alpha the colours carry, and so must the fallback be.
      LiquidGlass {
        id: solidTile; x: 408; y: 8; width: 192; height: 192; radius: 40
        wallpaperItem: wallpaper; solidMode: true; solidColor: "#336699"; solidColorBottom: "#80993366"
      }
      // A flat solid tile at the family's default corner (radius 100,
      // roundness 7.5, the shader clamping the radius to 96 here): translucent
      // solidColor, opaque card, and the shader's squircle rather than the disc
      // a Rectangle of that radius is.
      LiquidGlass {
        id: flatTile; x: 608; y: 8; width: 192; height: 192; radius: 100; roundness: 7.5
        wallpaperItem: wallpaper; solidMode: true; solidColor: "#80336699"
      }

      readonly property url halves: Qt.resolvedUrl("halves.svg")
      readonly property url dot: Qt.resolvedUrl("dot.svg")

      // The photos frame's drawing where no shader runs: cropped, cut to the
      // squircle, a caption band over the bottom half.
      SoftwarePicture {
        id: picture; x: 8; y: 228; width: 192; height: 192
        source: host.halves
        points: Squircle.outline(192, 192, 100, 7.5)
        overlayTop: 96
        overlayStops: [{ position: 0, color: Qt.rgba(0, 0, 0, 0) }, { position: 1, color: Qt.rgba(0, 0, 0, 0.7) }]
      }
      SoftwarePicture { id: icon; x: 208; y: 228; width: 48; height: 48; source: host.dot; crop: false; tint: "#00ff00" }
      TimerButton { id: timerButton; x: 264; y: 228; diameter: 64; iconSource: host.dot; iconColor: "#00ff00"; backgroundColor: "transparent" }
      ControlButton { id: controlButton; x: 336; y: 228; iconSize: 24; iconSource: host.dot; iconColor: "#00ff00" }
      AlbumArt { id: albumArt; x: 408; y: 228; width: 120; height: 120; artUrl: host.halves; radius: 30 }
      // Resized step by step, as the resize grip does on every mouse move: the
      // picture must stay up throughout and be decoded again once, at the new
      // bound, when the size holds.
      SoftwarePicture {
        id: resized; x: 620; y: 228; width: 120; height: 120; source: host.halves
        property int drops: 0
        onReadyChanged: if (!ready) drops++
      }
      RollingDigit { id: digit; x: 536; y: 228; width: 70; height: 120; value: "1"; fontPixelSize: 72; textColor: "#ffffff"; digitOpacity: 1 }

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
        id: resizeSteps
        interval: 40
        repeat: true
        property int step: 0
        onTriggered: {
          resized.width += 4
          if (++step >= 8) { stop(); resizeSettled.start() }
        }
      }
      Timer {
        id: resizeSettled
        interval: 1000
        onTriggered: {
          var data = resized.getContext("2d").createImageData(String(resized.source))
          host.check("a resized picture never stops being ready", resized.drops === 0, "drops " + resized.drops)
          host.check("a resized picture is decoded again at its new bound",
                     resized.ready && data && data.width === resized.sourceSize.width,
                     data ? data.width + " wide for a bound of " + resized.sourceSize.width : "no decode")
          if (--host.pending === 0) host.finish()
        }
      }

      // Mid-roll: both digits are layers, and a blurred layer drew nothing.
      Timer {
        id: rollGrab
        interval: 200
        onTriggered: digit.grabToImage(function (result) {
          result.saveToFile(Quickshell.env("OUT") + "/digit.png")
          if (--host.pending === 0) host.finish()
        })
      }

      Timer {
        interval: 100
        running: true
        repeat: true
        property int ticks: 0
        property int settled: 0
        onTriggered: {
          ticks++
          if (host.GraphicsInfo.api !== GraphicsInfo.Software) {
            if (ticks >= 50) { console.log("FAIL the scene graph never reported the software renderer"); Qt.quit() }
            return
          }
          // The pictures decode asynchronously; a few ticks more lets the
          // components that load the same files catch up.
          if (!picture.ready || !icon.ready || !resized.ready) {
            if (ticks >= 80) { console.log("FAIL the software pictures never loaded"); Qt.quit() }
            return
          }
          if (++settled < 4) return
          stop()
          host.check("FrostLayer reports no output it cannot draw", frostLayer.output === null)
          host.check("a wallpaper that drew counts as drawn", frostLayer._wallpaperDrawn === true)
          host.check("a wallpaper that failed to load counts as none",
                     missingWallpaper.status === Image.Error && deadFrost._wallpaperDrawn === false,
                     "status " + missingWallpaper.status)
          host.check("a frost-1 card is not frosted without shaders", !card.frosted)
          host.check("a frost-1 card keeps its surface fill", card.color.a > 0.5, "alpha " + card.color.a)
          host.check("glass LiquidGlass is inactive without shaders", !glassTile.active)
          host.check("solid LiquidGlass knows no shader runs", solidTile.shadersRun === false)
          host.check("a software picture painted", picture.paints > 0, "paints " + picture.paints)
          host.check("the timer button knows no shader runs", timerButton.shadersRun === false)
          host.check("the control button knows no shader runs", controlButton.shadersRun === false)
          host.check("the album art knows no shader runs", albumArt.shadersRun === false)
          host.check("the rolling digit knows no shader runs", digit.shadersRun === false)
          host.grab(card, "card")
          host.grab(glassTile, "glass")
          host.grab(solidTile, "solid")
          host.grab(flatTile, "flat")
          host.grab(picture, "picture")
          host.grab(icon, "icon")
          host.grab(timerButton, "timerbutton")
          host.grab(controlButton, "controlbutton")
          host.grab(albumArt, "albumart")
          host.pending++
          digit.value = "8"
          rollGrab.start()
          host.pending++
          resized.drops = 0
          resizeSteps.start()
        }
      }
    }
  }
}
