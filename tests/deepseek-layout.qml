import QtQuick
import Quickshell
import Quickshell.Io
import "plugin"

// The DeepSeek tile's layout, measured: both drawings, every grid preset, with
// a ledger that fills all six breakdown rows and an armed low-balance
// threshold, so the header carries its verdict too - the most crowded the tile
// gets. For each case:
//
//   * the balance is the largest text on the tile - it is what the tile is for,
//     and a stage squeezed to nothing shrinks it below the row text
//   * no two drawn texts overlap
//   * every drawn text stays inside the tile
//
// A large tile used to hand its whole height to the breakdown rows and none to
// the balance: the stage collapsed, the Liquid Glass figure fell to its 12 px
// floor under the "last read" line, and at the larger Nothing scales the
// figure was drawn over the footer and the first row.
// tests/deepseek-layout.sh writes the fixture.
ShellRoot {
  id: shell

  WidgetRegistry { id: registry }
  Theme { id: injectedTheme }

  property var defaults: ({})
  property bool ready: false
  FileView {
    path: Qt.resolvedUrl("plugin/manifest.json")
    onLoaded: {
      shell.defaults = JSON.parse(text()).settings.defaults
      shell.ready = true
    }
  }

  // The figure the fixture's lastTotal formats to, in either drawing (the
  // Nothing one draws the currency mark as a separate, smaller text).
  readonly property string figure: "12.34"

  readonly property var cases: [
    { style: "liquid-glass", w: 400, h: 400, scale: 100 },
    { style: "liquid-glass", w: 320, h: 320, scale: 100 },
    { style: "liquid-glass", w: 300, h: 300, scale: 100 },
    { style: "liquid-glass", w: 400, h: 192, scale: 100 },
    { style: "liquid-glass", w: 192, h: 192, scale: 100 },
    { style: "nothing", w: 400, h: 400, scale: 100 },
    { style: "nothing", w: 400, h: 192, scale: 100 },
    { style: "nothing", w: 192, h: 192, scale: 100 },
    // The large preset higher up the Scale knob, and only that one: a tile is
    // the same pixel size at any scale, and at 200% a 192 px DeepSeek tile has
    // no room for its doubled type however its rows are counted.
    { style: "nothing", w: 400, h: 400, scale: 200 },
    { style: "nothing", w: 400, h: 400, scale: 150 }
  ]

  property int failures: 0
  function fail(c, what) {
    console.log("FAIL " + c.style + " " + c.w + "x" + c.h + " @" + c.scale + "%: " + what)
    shell.failures++
  }

  // Every drawn text under `item`: effectively visible (Item.visible already
  // folds in the ancestors), not transparent, not empty. A Text is recognised
  // by shape, since `instanceof` does not reach QML element types.
  function texts(item, out) {
    if (!item || !item.visible || item.opacity <= 0) return out
    if (typeof item.text === "string" && item.text !== "" &&
        item.contentWidth !== undefined && item.font !== undefined)
      out.push(item)
    var kids = item.children
    for (var i = 0; i < kids.length; i++) shell.texts(kids[i], out)
    return out
  }

  // The rectangle the glyphs occupy, in tile coordinates - not the item's
  // box, which for an elided or fitted Text is wider than what it paints.
  function painted(t, tile) {
    var dx = 0
    if (t.horizontalAlignment === Text.AlignRight) dx = t.width - t.contentWidth
    else if (t.horizontalAlignment === Text.AlignHCenter) dx = (t.width - t.contentWidth) / 2
    var p = t.mapToItem(tile, dx, 0)
    return { x: p.x, y: p.y, w: t.contentWidth, h: t.contentHeight, t: t }
  }

  function check(c, tile) {
    var list = shell.texts(tile, [])
    var rects = []
    for (var i = 0; i < list.length; i++) rects.push(shell.painted(list[i], tile))

    var hero = null
    for (i = 0; i < rects.length; i++)
      if (rects[i].t.text.indexOf(shell.figure) >= 0) hero = rects[i]
    if (!hero) { shell.fail(c, "no text draws the balance " + shell.figure); return }
    if (rects.length < 3) { shell.fail(c, "only " + rects.length + " texts drawn - the ledger did not load"); return }

    for (i = 0; i < rects.length; i++) {
      var r = rects[i]
      if (r !== hero && r.t.font.pixelSize >= hero.t.font.pixelSize)
        shell.fail(c, "'" + r.t.text + "' is " + r.t.font.pixelSize + " px, the balance only " + hero.t.font.pixelSize + " px")
      // Half a pixel either way is rounding, not a collision.
      if (r.x < -0.5 || r.y < -0.5 || r.x + r.w > c.w + 0.5 || r.y + r.h > c.h + 0.5)
        shell.fail(c, "'" + r.t.text + "' is drawn outside the tile at " +
                   [r.x, r.y, r.w, r.h].map(Math.round).join(","))
      for (var j = i + 1; j < rects.length; j++) {
        var q = rects[j]
        var ox = Math.min(r.x + r.w, q.x + q.w) - Math.max(r.x, q.x)
        var oy = Math.min(r.y + r.h, q.y + q.h) - Math.max(r.y, q.y)
        if (ox > 0.5 && oy > 0.5)
          shell.fail(c, "'" + r.t.text + "' overlaps '" + q.t.text + "' by " + Math.round(ox) + "x" + Math.round(oy))
      }
    }
  }

  Component {
    id: tileComponent
    WidgetSweepTile {}
  }

  // In a window, so the scene's polish pass runs: a Column positions its rows
  // there, and without it every breakdown row sits at y 0.
  Window {
    width: 1600
    height: 1200
    visible: true

    Item {
      id: stage
      anchors.fill: parent
      property var tiles: []
      property int ticks: 0
    }
  }

  Timer {
    interval: 250
    repeat: true
    running: true
    onTriggered: {
      if (!shell.ready) {
        if (++stage.ticks > 40) { console.log("FAIL manifest.json never loaded"); Qt.exit(1) }
        return
      }
      if (stage.tiles.length === 0) {
        stage.ticks = 0
        for (var i = 0; i < shell.cases.length; i++) {
          var c = shell.cases[i]
          var settings = Object.assign({}, shell.defaults, { uiScale: c.scale })
          stage.tiles.push(tileComponent.createObject(stage, {
            type: "deepseek", style: c.style, width: c.w, height: c.h,
            registry: registry, pluginSettings: settings,
            injectedTheme: injectedTheme, backdropSource: stage
          }))
        }
        return
      }
      // Loaded, then long enough for the ledger's FileView to have answered.
      var pending = stage.tiles.filter(function (t) { return !t.settledDone }).length
      if (++stage.ticks < 12 || (pending > 0 && stage.ticks < 80)) return
      for (i = 0; i < stage.tiles.length; i++) {
        if (stage.tiles[i].stateName() !== "ready") shell.fail(shell.cases[i], "did not load")
        else shell.check(shell.cases[i], stage.tiles[i])
      }
      if (shell.failures === 0)
        console.log("OK: the DeepSeek balance stays the largest text and nothing on the tile overlaps, on every preset")
      Qt.exit(shell.failures === 0 ? 0 : 1)
    }
  }
}
