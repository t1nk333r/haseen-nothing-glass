import QtQuick
import "components/nothing"

// One draggable knob row in the browser's Appearance pane: its name on the
// left, its value in the knob's own units on the right, and the track between
// them.
//
// It is a file of its own because BOTH drawings' knob tables draw rows through
// it - the Liquid Glass refraction knobs and the Nothing style's card material
// (opacity and frost) - and a second copy of this drag would be a second place
// for the three rules that matter to rot: the pending value that is deliberately
// NOT written while the handle is held (a write per pixel of drag reaches disk),
// the step snap, and the one `mult` transform applied on display and undone on
// write.
//
// Everything it draws with is a required property rather than a name inherited
// from the document that used to hold it as an inline `Repeater` delegate. That
// delegate closed over NothingLauncher's `nothing`, `appearance` and `launcher`;
// in this file those names do not resolve, and QML raises that at run time as a
// ReferenceError rather than at load - so the failure would be a row drawn at
// zero width whose release handler writes nothing, and neither the suite nor
// any build step sees it. Taking them as properties is the contract
// LauncherTile.qml takes its `theme` and `pluginSettings` through, and a row
// cannot be created without them; the row's width is set where it is created,
// from the pane it is created in.
Item {
  id: row

  // `theme` is the pane's NTheme, `knob` one resolved row of a knob table
  // ({key, label, unit, mult, min, max, step}, `min`/`max` already scaled by
  // `mult`), and the last two are where the setting is read from and written
  // to. `setSetting` is null under the dev harness, where no shell is reachable.
  required property var theme
  required property var knob
  required property var pluginSettings
  required property var setSetting

  // The setting in the knob's own units: the three percent keys read `0..1` on
  // disk and `0..100` here, so the one transform is applied on the way in and
  // undone on the way out. Falls back to the range's floor when the setting is
  // not a number yet.
  readonly property real stored: {
    var v = Number(row.pluginSettings ? row.pluginSettings[row.knob.key] : NaN)
    return isFinite(v) ? v * row.knob.mult : row.knob.min
  }
  // While the handle is held the row follows the pointer and writes nothing:
  // setSetting reaches disk, and a write per pixel of drag would be a hundred
  // of them for one knob.
  property bool dragging: false
  property real pending: 0
  readonly property real value: row.dragging ? row.pending : row.stored
  readonly property real fraction: {
    var span = row.knob.max - row.knob.min
    return span > 0 ? Math.max(0, Math.min(1, (row.value - row.knob.min) / span)) : 0
  }

  function valueAt(mx) {
    var t = Math.max(0, Math.min(1, mx / Math.max(1, track.width)))
    var raw = row.knob.min + t * (row.knob.max - row.knob.min)
    // Snap to the step, then trim the float noise the round trip leaves behind
    // for a fractional step (7.2 comes back as 7.2000000000000002), so what
    // reaches disk is the value the label shows and not a long binary tail.
    var snapped = Number((Math.round(raw / row.knob.step) * row.knob.step).toFixed(6))
    return Math.max(row.knob.min, Math.min(row.knob.max, snapped))
  }

  height: row.theme.px(28)

  NLabel {
    id: knobName
    theme: row.theme
    text: row.knob.label
    elide: Text.ElideRight
    width: row.theme.px(112)
    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
  }
  NMono {
    id: knobValue
    theme: row.theme
    color: row.dragging ? row.theme.on : row.theme.onDim
    font.pixelSize: row.theme.fMicro
    horizontalAlignment: Text.AlignRight
    width: row.theme.px(44)
    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
    // In the knob's own units. `toFixed(2)` sheds the float noise a `* 100`
    // leaves behind (0.1 reads 10, not 10.000000000000002) without flattening
    // the two decimals a schema step of 0.01 can produce, so the label always
    // shows the value the setting actually holds.
    text: String(Number(row.value.toFixed(2))) + row.knob.unit
  }
  Item {
    id: track
    height: row.theme.px(16)
    anchors {
      left: knobName.right; leftMargin: row.theme.gap
      right: knobValue.left; rightMargin: row.theme.gap
      verticalCenter: parent.verticalCenter
    }

    Rectangle {
      anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
      height: row.theme.px(4)
      radius: height / 2
      color: row.theme.surface3
      border.width: row.theme.hair
      border.color: row.theme.outline
    }
    Rectangle {
      anchors { left: parent.left; verticalCenter: parent.verticalCenter }
      width: Math.round(track.width * row.fraction)
      height: row.theme.px(4)
      radius: height / 2
      color: row.theme.red
    }
    Rectangle {
      width: row.theme.px(10)
      height: width
      radius: width / 2
      color: row.theme.on
      x: Math.round(track.width * row.fraction - width / 2)
      anchors.verticalCenter: parent.verticalCenter
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onPressed: function (mouse) {
        row.pending = row.valueAt(mouse.x)
        row.dragging = true
      }
      onPositionChanged: function (mouse) {
        if (row.dragging) row.pending = row.valueAt(mouse.x)
      }
      onReleased: {
        row.dragging = false
        if (row.pending !== row.stored && typeof row.setSetting === "function")
          row.setSetting(row.knob.key, row.pending / row.knob.mult)
      }
    }
  }
}
