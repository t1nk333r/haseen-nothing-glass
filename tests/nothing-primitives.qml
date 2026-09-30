import QtQuick
import QtQuick.Window
import Quickshell
import "components/nothing"

// NOTE: `qs` refuses to load a QML module path outside the config folder, so
// run.sh copies this file next to a dereferenced `components/` in a temp
// directory and runs it there - hence the plain `import "components/nothing"`.
//
// Headless check of the three Nothing primitives, run by tests/run.sh
// when `qs` is on PATH.
//
// Each group is a defect that was invisible in the source:
//
//   (a) NDial's painter reads `ticks`, `majorEvery`, `accent` and the theme
//       colours, and observed none of them - the only Canvas in the tree that
//       draws values it does not trigger on, so a call site setting `accent`
//       got a ring that still looked like the old one.
//   (b) NDotField built its whole dot grid while hidden, because nothing in
//       the Repeater's model depended on `visible`: the presets that hide the
//       field paid for 1,681 Rectangles nobody drew.
//   (c) NDotMatrix's gap floor could contradict its own fit solver, so a
//       fitted glyph drew a box larger than the box it was fitted to.
//
// A Canvas paints once onto a texture and keeps it; nothing repaints it but
// `requestPaint()`. So (a) is measured twice over: a counter on the Canvas'
// `painted` signal, and the pixels themselves, grabbed to PNGs the suite
// compares. A trigger that fires without the painter drawing anything new
// passes the counter and fails the bytes.
//
// The items must live in a real `Window`: an Item sitting directly under
// ShellRoot is never attached to one, its Canvas never paints, and
// grabToImage() logs "item is not attached to a window".
ShellRoot {
  id: shell

  Window {
    id: win
    width: 400
    height: 400
    visible: true
    color: "#000000"

    Item {
      id: host
      anchors.fill: parent

      property int failures: 0
      property int checks: 0
      // Bumped by the dial's `painted` signal, sampled at each grab.
      property int painted: 0
      property int mark: 0

      function check(label, ok, detail) {
        host.checks++
        if (!ok) {
          host.failures++
          console.log("FAIL " + label + (detail ? "  (" + detail + ")" : ""))
        }
      }

      // ── (a) NDial: every drawn input must move the canvas ────────────
      //
      // `themePalette` + `followTheme` is how the desktop palette reaches
      // the style: NTheme's colours are `readonly property color` on a
      // stable object, so following a theme mutates that object in place
      // rather than replacing it - which is exactly the case a handler on
      // `theme` itself would miss.
      NTheme { id: dialTheme }

      NDial {
        id: dial
        width: 200
        height: 200
        theme: dialTheme
        value: 0.5
        ticks: 60
        majorEvery: 5
      }

      Connections {
        target: dial
        function onPainted() { host.painted++ }
      }

      function grab(name) {
        var path = Quickshell.env("OUT") + "/" + name + ".png"
        dial.grabToImage(function (r) {
          if (!r.saveToFile(path))
            host.check("grab " + name, false, "could not write " + path)
        })
      }

      // ── (b) NDotField: hidden means built, count and all ─────────────
      //
      // `theme.px(9)` at scale 1 is the default spacing; the 400x400 box at
      // that spacing is 44x44 = 1,936 dots, and the Grid also holds the
      // Repeater, hence 1,937.
      NTheme { id: fieldTheme }

      NDotField {
        id: hiddenSmall
        x: 210
        y: 0
        width: 192
        height: 192
        theme: fieldTheme
        visible: false
      }

      NDotField {
        id: shownBig
        x: 0
        y: 200
        width: 400
        height: 400
        theme: fieldTheme
      }

      NDotField {
        id: hiddenSpaced
        x: 210
        y: 200
        width: 400
        height: 400
        theme: fieldTheme
        spacing: fieldTheme.px(12)
        visible: false
      }

      // ── (c) NDotMatrix: the glyph must fit the box it was fitted to ──
      //
      // `12` is 11 columns x 7 rows at a 14 px fit height - below the dot
      // size where the gap can honour its ratio, which is where the solver
      // and the gap floor used to disagree.
      //
      // `HH:MM` lays out as the colon alone (dots.js has no H or M, so the
      // unknown glyphs are skipped): 3 columns x 7 rows, a fit whose dot is
      // well above the floor - the solver must keep answering exactly what
      // it always did, or a glyph that fitted would move.
      NTheme { id: matrixTheme }

      NDotMatrix {
        id: tight
        x: 0
        y: 0
        theme: matrixTheme
        text: "12"
        fitWidth: 60
        fitHeight: 14
      }

      NDotMatrix {
        id: ratio
        x: 210
        y: 200
        theme: matrixTheme
        text: "HH:MM"
        fitWidth: 40
        fitHeight: 40
      }

      NDotMatrix {
        id: wide
        x: 210
        y: 260
        theme: matrixTheme
        text: "8"
        fitWidth: 100
        fitHeight: 60
      }

      // c*dot + (c-1)*gap is the box the glyph actually occupies. It must
      // not exceed the box it was fitted to, and the binding axis must still
      // fill that box: the first half alone would be passed by a "fix" that
      // shrank every glyph, which is not the defect being repaired.
      function fits(m, label) {
        var w = m.colCount * m.dot + (m.colCount - 1) * m.gap
        var h = m.rowCount * m.dot + (m.rowCount - 1) * m.gap
        var drawn = w.toFixed(2) + "x" + h.toFixed(2) +
          " in " + m.fitWidth + "x" + m.fitHeight
        host.check(label + " draws inside its fit box",
                   w <= m.fitWidth + 0.01 && h <= m.fitHeight + 0.01, drawn)
        host.check(label + " still fills its fit box on the binding axis",
                   Math.abs(w - m.fitWidth) < 0.01 || Math.abs(h - m.fitHeight) < 0.01,
                   drawn)
      }

      function report() {
        if (host.painted === 0) {
          host.check("NDial paints at all", false, "no painted() signal in 9s")
          host.finish()
          return
        }
        host.advance()
      }

      function finish() {
        check("hidden 192x192 field builds its dots only when drawn",
              hiddenSmall.children[0].children.length === 1,
              "children=" + hiddenSmall.children[0].children.length + " (was 442)")
        check("visible 400x400 field builds every dot",
              shownBig.children[0].children.length === 1937,
              "children=" + shownBig.children[0].children.length)
        check("hidden 400x400 field at px(12) spacing builds its dots only when drawn",
              hiddenSpaced.children[0].children.length === 1,
              "children=" + hiddenSpaced.children[0].children.length + " (was 1,090)")

        fits(tight, "60x14 over `12`")
        fits(ratio, "40x40 over `HH:MM`")
        fits(wide, "100x60 over `8`")

        console.log(host.failures === 0
          ? "OK: nothing primitives repaint, gate and fit (" + host.checks + " checks)"
          : host.failures + " of " + host.checks + " nothing-primitive checks FAILED")
        Qt.exit(host.failures === 0 ? 0 : 1)
      }

      // One stage per tick: a change on one tick, the grab that measures it
      // on the next, so the frame it caused has been rendered by then.
      function advance() {
        host.step++
        switch (host.step) {
        case 1:
          host.grab("p0")
          host.mark = host.painted
          break
        case 2:
          host.grab("p0b")
          // The control: nothing changed, so the canvas must not have
          // repainted - which is also what makes the PNGs comparable.
          host.check("an unchanged NDial does not repaint",
                     host.painted === host.mark, "painted=" + host.painted)
          host.mark = host.painted
          break
        case 3:
          dial.ticks = 12
          break
        case 4:
          host.grab("p1")
          host.check("NDial repaints when ticks changes",
                     host.painted > host.mark, "painted=" + host.painted)
          host.mark = host.painted
          break
        case 5:
          dial.majorEvery = 3
          break
        case 6:
          host.grab("p2")
          host.check("NDial repaints when majorEvery changes",
                     host.painted > host.mark, "painted=" + host.painted)
          host.mark = host.painted
          break
        case 7:
          dial.accent = true
          break
        case 8:
          host.grab("p3")
          host.check("NDial repaints when accent changes",
                     host.painted > host.mark, "painted=" + host.painted)
          host.mark = host.painted
          break
        case 9:
          dialTheme.themePalette = { "foreground": "#00FF00", "accent": "#0000FF" }
          dialTheme.followTheme = true
          break
        case 10:
          host.grab("p4")
          host.check("NDial repaints when the palette follows the theme",
                     host.painted > host.mark, "painted=" + host.painted)
          host.mark = host.painted
          break
        default:
          host.finish()   // no break: finish() exits
        }
      }

      property int step: 0

      Timer {
        id: driver
        interval: 300
        repeat: true
        running: true
        property int waited: 0

        onTriggered: {
          // Nothing below is meaningful until the canvas has painted once.
          if (host.painted === 0) {
            if (++driver.waited > 30) host.finish()
            return
          }
          host.report()
        }
      }
    }
  }
}
