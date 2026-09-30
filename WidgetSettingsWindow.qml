import QtQuick
import Quickshell
import Quickshell.Wayland
import "components"

// The settings sheet a right-click on a widget opens, on the desktop, next to
// the widget it belongs to. It configures exactly ONE widget: its style, its
// own per-type fields, its size and its position. Everything that is about
// more than one widget lives in the browser, one cog away in the title row.
//
// Why its own window per screen instead of an item inside GlassSurface's
// PanelWindow: that surface is deliberately on the Bottom layer with
// `keyboardFocus: None` (see its header - it must stay behind application
// windows), and a Wayland surface with no keyboard focus receives no key
// events at all, so the location and city fields could not be typed into.
// This window is Top + OnDemand and only exists while the sheet is open.
//
// It is also the reason the sheet is plain QtQuick rather than qs.Ui
// components: GlassSurface is instantiated directly by the standalone dev
// harness (glass-dev.qml), where `qs.Ui` does not resolve,
// and one failed import takes the whole file with it.
PanelWindow {
  id: sheet

  required property var store
  required property var registry
  required property var pluginSettings
  required property var themePalette

  PluginId { id: identity }

  // This screen's reserved edges, so "Reset position" lands on the first
  // visible cell instead of behind the bar.
  property int insetLeft: 0
  property int insetTop: 0

  // The store row being edited; null closes the window.
  property var entry: null
  property real anchorX: 0
  property real anchorY: 0

  readonly property bool open: entry !== null

  // The type the sheet is showing, kept apart from `entry.type` on purpose.
  // `Store.set` builds a NEW entry object for the row it writes (see its
  // header), so anything that read `sheet.entry` would re-evaluate on every
  // save - including a field's `focus` binding, which would then pull the
  // keyboard back to the first box while the operator was editing another.
  // This changes only when the sheet opens for a widget.
  property string openType: ""

  // Index of the first field in the open type's table that a keyboard can type
  // into - the first that is not a bool pill - or -1 when every field is a
  // switch (or the type has none, which is the same thing to the keyboard).
  // The text boxes below use it to hand the keyboard to the first of them the
  // moment the sheet opens, and the card uses it to stay out of the way.
  readonly property int firstTextField: {
    var list = fieldModel.forType(sheet.openType)
    for (var i = 0; i < list.length; i++) {
      if (list[i].kind !== "bool") return i
    }
    return -1
  }

  function openFor(entry, x, y) {
    sheet.openType = String(entry ? entry.type : "")
    sheet.entry = entry
    sheet.anchorX = x
    sheet.anchorY = y
    // Cheap, and it means Reset uses the bar's CURRENT reserved edge even if
    // the bar moved or was hidden since the shell started.
    sheet.refreshInsets()
  }

  // Set by GlassSurface to its per-screen ScreenInsets.refresh.
  property var refreshInsets: function () {}

  // Set by GlassSurface to its `styleForCategory(group)`: what this widget's
  // category resolves to when the widget itself names no style. Only read for
  // the Inherit button's label - the resolution itself belongs to the surface.
  property var styleForCategory: null

  // Set by GlassSurface: opens the widget browser on this widget. The sheet
  // is deliberately single-widget, and this is the one way out of it.
  property var openBrowser: null

  function close() {
    sheet.entry = null
  }

  // Re-read the row after every store write, so the size buttons, the style
  // row and the overridden markers follow an edit made from here (or a drag
  // made on the widget) instead of freezing at the value the sheet opened
  // with.
  function _refresh() {
    if (!sheet.entry || !sheet.store) return
    var id = String(sheet.entry.id)
    var list = sheet.store.widgets || []
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].id) === id) { sheet.entry = list[i]; return }
    }
    sheet.close()   // removed from under us
  }

  // What this widget would be drawn in if it named no style of its own, so
  // the Inherit button can say so instead of hiding the consequence. Reads
  // `pluginSettings` as well as calling the surface, because the plugin
  // default and the category map both live in that configuration and the
  // label has to re-evaluate when either changes.
  readonly property string inheritedStyle: {
    var cfg = sheet.pluginSettings
    var fallback = String((cfg && cfg.widgetStyle) || "liquid-glass")
    if (!sheet.open || !sheet.registry) return fallback
    if (typeof sheet.styleForCategory !== "function") return fallback
    var group = sheet.registry.group(String(sheet.entry.type))
    return String(sheet.styleForCategory(group) || fallback)
  }

  // Inherit, then every style this TYPE can actually be drawn in. A type with
  // one drawing gets an empty list and the row disappears: offering a choice
  // between one option and inheriting it is noise.
  function styleOptions() {
    if (!sheet.open || !sheet.registry) return []
    var list = sheet.registry.stylesFor(String(sheet.entry.type))
    if (!list || list.length < 2) return []
    var out = [{ value: "", label: "Inherit", sub: identity.styleLabel(sheet.inheritedStyle) }]
    for (var i = 0; i < list.length; i++) {
      out.push({ value: String(list[i]), label: identity.styleLabel(list[i]), sub: "" })
    }
    return out
  }

  // Drawn, not spelled: a glyph here renders as colour emoji under
  // NotoColorEmoji and ignores `color`. BarWidget.qml:367 says the same for
  // the bar icon (plan 008 finding). No Canvas: a Rectangle repaints itself,
  // a Canvas would need a requestPaint per tint change.
  component CogMark: Item {
    id: cog
    property color tint: "#ffffff"

    Rectangle {
      anchors.centerIn: parent
      width: Math.round(parent.width * 0.62)
      height: width
      radius: width / 2
      color: "transparent"
      border.width: Math.max(1, Math.round(parent.width / 7))
      border.color: cog.tint
    }
    Repeater {
      model: 8
      delegate: Item {
        required property int index
        // Bound through `parent`, not the component's own id: a Repeater
        // delegate is its own component, where an outer id is not reliably in
        // scope, and a failed binding silently drops every tooth.
        readonly property color toothTint: parent.tint
        anchors.fill: parent
        rotation: index * 45
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          y: 0
          width: Math.max(1, Math.round(parent.width * 0.16))
          height: Math.round(parent.height * 0.24)
          radius: width * 0.3
          color: parent.toothTint
        }
      }
    }
  }

  component CloseMark: Item {
    id: mark
    property color tint: "#ffffff"

    Rectangle {
      anchors.centerIn: parent
      width: Math.round(Math.SQRT2 * parent.width)
      height: Math.max(2, Math.round(parent.width * 0.15))
      radius: height / 2
      color: mark.tint
      rotation: -45
      transformOrigin: Item.Center
    }
    Rectangle {
      anchors.centerIn: parent
      width: Math.round(Math.SQRT2 * parent.width)
      height: Math.max(2, Math.round(parent.width * 0.15))
      radius: height / 2
      color: mark.tint
      rotation: 45
      transformOrigin: Item.Center
    }
  }

  visible: sheet.open
  color: "transparent"
  anchors { top: true; bottom: true; left: true; right: true }

  WlrLayershell.namespace: identity.namespace + "-settings"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: sheet.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Ignore

  Connections {
    target: sheet.store
    function onWidgetsChanged() { sheet._refresh() }
  }

  MacOSColors {
    id: colors
    styleMode: sheet.pluginSettings ? sheet.pluginSettings.styleMode : 0
    appearance: sheet.pluginSettings ? sheet.pluginSettings.appearance : 0
    themePalette: sheet.themePalette
  }

  WidgetFields { id: fieldModel }

  // Outside click dismisses. The window is full-screen while open, so this
  // also means the sheet is modal to the desktop layer - deliberate: it is
  // the only way to close it with the pointer.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: sheet.close()
  }

  Rectangle {
    id: card

    readonly property int margin: 12
    readonly property int pad: 14

    width: 300
    height: body.implicitHeight + card.pad * 2
    radius: 18

    // Clamped so a right-click near an edge still shows the whole sheet.
    x: Math.max(card.margin, Math.min(sheet.anchorX + 8, sheet.width - card.width - card.margin))
    y: Math.max(card.margin, Math.min(sheet.anchorY + 8, sheet.height - card.height - card.margin))

    color: colors.isLight ? Qt.rgba(1, 1, 1, 0.98) : Qt.rgba(0.11, 0.11, 0.12, 0.98)
    border.width: 1
    border.color: Qt.rgba(colors.foreground.r, colors.foreground.g, colors.foreground.b, 0.14)

    // Swallow clicks that land on the sheet itself.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
    }

    // The keyboard belongs to the first text box below when the open type has
    // one, and to the card only when it has none.
    //
    // The card used to hold it unconditionally (`focus: sheet.open`), so until
    // a click landed INSIDE a box the keyboard sat on a Rectangle that can
    // neither type nor paste: the first keystroke - and every clipboard chord -
    // after the sheet opened reached an item that handles Escape and nothing
    // else. A box took the keyboard only from a click, which is what made the
    // sheet look like it accepted typing but not a paste. The two conditions
    // are complements, so exactly one of the card and the first box holds the
    // scope's focus item, whatever order the bindings evaluate in. A type
    // whose fields are all switches keeps the card - and Escape.
    focus: sheet.open && sheet.firstTextField < 0
    Keys.onEscapePressed: sheet.close()

    Column {
      id: body
      x: card.pad
      y: card.pad
      width: card.width - card.pad * 2
      spacing: 10

      // ── Title ─────────────────────────────────────────────────────────
      Item {
        width: parent.width
        height: title.implicitHeight

        Column {
          id: title
          anchors.left: parent.left
          anchors.right: browseControl.left
          anchors.rightMargin: 8
          spacing: 1

          Text {
            width: parent.width
            elide: Text.ElideRight
            text: sheet.entry ? String(sheet.entry.type) : ""
            color: colors.foreground
            font.pixelSize: 14
            font.weight: Font.DemiBold
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: sheet.entry
              ? sheet.entry.id + "  ·  " + sheet.entry.x + "," + sheet.entry.y
                + "  " + sheet.entry.w + "×" + sheet.entry.h
              : ""
            color: Qt.rgba(colors.foreground.r, colors.foreground.g, colors.foreground.b, 0.55)
            font.pixelSize: 11
          }
        }

        // Everything about MORE than this widget - the catalogue, the other
        // instances, the plugin-wide appearance - is in the browser.
        //
        // A FocusScope, not a Rectangle: the mark is painted, and a painted
        // shape driven by a MouseArea cannot take the keyboard. The scope
        // owns the tab stop, the accessible name and the Enter/Space action;
        // the mark inside it is exactly the 22x22 it always was, and the hit
        // area is grown past it (44 px tall) so a pointer reaches it too -
        // WCAG 2.2 asks 24x24 at AA, 44x44 at AAA.
        FocusScope {
          id: browseControl
          anchors.right: closeControl.left
          anchors.rightMargin: 6
          anchors.top: parent.top
          width: 22
          height: 22
          visible: typeof sheet.openBrowser === "function"
          activeFocusOnTab: true

          function activate() {
            var id = String(sheet.entry ? sheet.entry.id : "")
            sheet.close()
            if (id !== "") sheet.openBrowser(id)
          }

          Accessible.role: Accessible.Button
          Accessible.name: "Open this widget in the browser"
          Accessible.onPressAction: browseControl.activate()
          Keys.onReturnPressed: browseControl.activate()
          Keys.onEnterPressed: browseControl.activate()
          Keys.onSpacePressed: browseControl.activate()

          Rectangle {
            id: browseButton
            anchors.fill: parent
            radius: 11
            color: browseArea.containsMouse
              ? Qt.rgba(colors.foreground.r, colors.foreground.g, colors.foreground.b, 0.18)
              : Qt.rgba(colors.foreground.r, colors.foreground.g, colors.foreground.b, 0.10)

            CogMark {
              anchors.centerIn: parent
              width: 13
              height: 13
              tint: colors.foreground
            }
          }
          MouseArea {
            id: browseArea
            anchors.fill: parent
            // The painted circle stays 22; the target is 28x44. Vertically
            // the full 11 either side (a 22 px strip is the hard one to
            // hit); horizontally only 3, which is half the 6 px gap to the
            // close button - the two targets tile exactly and neither
            // reaches under the title text, 8 px to the left.
            anchors.leftMargin: -3
            anchors.topMargin: -11
            anchors.bottomMargin: -11
            anchors.rightMargin: -3
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: browseControl.activate()
          }
          // Around the mark, not on it, and in the style's accent token so
          // it reads on the dark card of one appearance and the light card
          // of the other.
          Rectangle {
            anchors.centerIn: parent
            width: parent.width + 4
            height: parent.height + 4
            radius: (parent.width + 4) / 2
            color: "transparent"
            border.width: 2
            border.color: colors.accent
            visible: browseControl.activeFocus
          }
        }

        FocusScope {
          id: closeControl
          anchors.right: parent.right
          anchors.top: parent.top
          width: 22
          height: 22
          activeFocusOnTab: true

          function activate() { sheet.close() }

          Accessible.role: Accessible.Button
          Accessible.name: "Close"
          Accessible.onPressAction: closeControl.activate()
          Keys.onReturnPressed: closeControl.activate()
          Keys.onEnterPressed: closeControl.activate()
          Keys.onSpacePressed: closeControl.activate()

          Rectangle {
            id: closeButton
            anchors.fill: parent
            radius: 11
            color: closeArea.containsMouse
              ? Qt.rgba(colors.foreground.r, colors.foreground.g, colors.foreground.b, 0.18)
              : Qt.rgba(colors.foreground.r, colors.foreground.g, colors.foreground.b, 0.10)

            CloseMark {
              anchors.centerIn: parent
              width: 13
              height: 13
              tint: colors.foreground
            }
          }
          MouseArea {
            id: closeArea
            anchors.fill: parent
            // 28x44, mirroring the cog and tiling with it across the gap.
            anchors.leftMargin: -3
            anchors.rightMargin: -3
            anchors.topMargin: -11
            anchors.bottomMargin: -11
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: closeControl.activate()
          }
          Rectangle {
            anchors.centerIn: parent
            width: parent.width + 4
            height: parent.height + 4
            radius: (parent.width + 4) / 2
            color: "transparent"
            border.width: 2
            border.color: colors.accent
            visible: closeControl.activeFocus
          }
        }
      }

      // ── Style ─────────────────────────────────────────────────────────
      // One plugin draws both styles, and this is where a single widget
      // picks. Inherit is a real choice, not the absence of one: it follows
      // the widget's category, and says which style that currently is.
      Column {
        width: parent.width
        spacing: 4
        visible: styleRow.count > 0

        Text {
          text: "Style"
          color: Qt.rgba(colors.foreground.r, colors.foreground.g, colors.foreground.b, 0.45)
          font.pixelSize: 10
        }

        Row {
          width: parent.width
          spacing: 6

          Repeater {
            id: styleRow
            model: sheet.open ? sheet.styleOptions() : []

            Rectangle {
              id: styleOption
              required property var modelData
              readonly property bool current: sheet.entry
                && String(sheet.entry.style || "") === String(modelData.value)

              width: (body.width - 12) / 3
              height: 34
              radius: 9
              color: styleOption.current
                ? Qt.rgba(colors.foreground.r, colors.foreground.g, colors.foreground.b, 0.22)
                : (styleArea.containsMouse
                    ? Qt.rgba(colors.foreground.r, colors.foreground.g, colors.foreground.b, 0.12)
                    : Qt.rgba(colors.foreground.r, colors.foreground.g, colors.foreground.b, 0.07))

              Column {
                anchors.centerIn: parent
                width: parent.width - 4
                spacing: 0

                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                  text: modelData.label
                  color: colors.foreground
                  // A size down from the rest of the sheet: "Liquid Glass"
                  // has to fit a third of the card without eliding.
                  font.pixelSize: 10
                  font.weight: styleOption.current ? Font.DemiBold : Font.Normal
                }
                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                  visible: text !== ""
                  text: modelData.sub
                  color: Qt.rgba(colors.foreground.r, colors.foreground.g, colors.foreground.b, 0.5)
                  font.pixelSize: 9
                }
              }

              MouseArea {
                id: styleArea
                anchors.fill: parent
                hoverEnabled: true
                // "" is stored, not deleted: an empty style means "inherit",
                // and writing it is how a widget stops overriding.
                onClicked: sheet.store.set(sheet.entry.id, "style", String(modelData.value))
              }
            }
          }
        }
      }

      // ── Size ──────────────────────────────────────────────────────────
      Row {
        width: parent.width
        spacing: 6

        Repeater {
          model: sheet.open && sheet.registry ? sheet.registry.sizes(String(sheet.entry.type)) : []

          Rectangle {
            required property var modelData
            readonly property bool current: sheet.entry
              && Number(sheet.entry.w) === modelData.width
              && Number(sheet.entry.h) === modelData.height

            width: (body.width - 12) / 3
            height: 30
            radius: 9
            color: current
              ? Qt.rgba(colors.foreground.r, colors.foreground.g, colors.foreground.b, 0.22)
              : (sizeArea.containsMouse
                  ? Qt.rgba(colors.foreground.r, colors.foreground.g, colors.foreground.b, 0.12)
                  : Qt.rgba(colors.foreground.r, colors.foreground.g, colors.foreground.b, 0.07))

            Column {
              anchors.centerIn: parent
              spacing: 0
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: modelData.label
                color: colors.foreground
                font.pixelSize: 11
                font.weight: parent.parent.current ? Font.DemiBold : Font.Normal
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: modelData.width + "×" + modelData.height
                color: Qt.rgba(colors.foreground.r, colors.foreground.g, colors.foreground.b, 0.5)
                font.pixelSize: 9
              }
            }

            MouseArea {
              id: sizeArea
              anchors.fill: parent
              hoverEnabled: true
              onClicked: sheet.store.resize(sheet.entry.id, modelData.width, modelData.height)
            }
          }
        }
      }

      // ── Per-type settings ─────────────────────────────────────────────
      Repeater {
        model: sheet.open ? fieldModel.forType(String(sheet.entry.type)) : []

        Column {
          id: fieldRow
          required property int index
          required property var modelData
          readonly property var field: modelData
          readonly property bool overridden: fieldModel.isOverridden(sheet.entry, field.key)
          readonly property string value:
            fieldModel.effective(sheet.entry, field.key, sheet.pluginSettings)

          width: body.width
          spacing: 3

          Row {
            width: parent.width
            spacing: 8

            Text {
              width: 74
              anchors.verticalCenter: parent.verticalCenter
              text: fieldRow.field.label
              color: fieldRow.overridden
                ? colors.foreground
                : Qt.rgba(colors.foreground.r, colors.foreground.g, colors.foreground.b, 0.6)
              font.pixelSize: 11
              font.weight: fieldRow.overridden ? Font.DemiBold : Font.Normal
            }

            // Boolean: a pill switch, not a field to type "true" into.
            Rectangle {
              visible: fieldRow.field.kind === "bool"
              anchors.verticalCenter: parent.verticalCenter
              width: 40
              height: 22
              radius: 11
              color: fieldModel.isTrue(fieldRow.value)
                ? colors.accent
                : Qt.rgba(colors.foreground.r, colors.foreground.g, colors.foreground.b, 0.18)

              Rectangle {
                width: 18
                height: 18
                radius: 9
                y: 2
                x: fieldModel.isTrue(fieldRow.value) ? parent.width - width - 2 : 2
                color: "#ffffff"
                Behavior on x { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
              }

              MouseArea {
                anchors.fill: parent
                onClicked: fieldModel.save(sheet.store, sheet.entry.id, fieldRow.field,
                                           !fieldModel.isTrue(fieldRow.value))
              }
            }

            // Everything else: a text box that commits on Enter and on
            // losing focus, so there is no Save button to forget.
            Rectangle {
              visible: fieldRow.field.kind !== "bool"
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - 74 - parent.spacing
              height: 26
              radius: 8
              color: Qt.rgba(colors.foreground.r, colors.foreground.g, colors.foreground.b,
                             input.activeFocus ? 0.16 : 0.09)

              TextInput {
                id: input
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                verticalAlignment: Text.AlignVCenter
                clip: true
                color: colors.foreground
                selectionColor: colors.accent
                selectedTextColor: colors.foreground
                font.pixelSize: 12
                text: fieldRow.value

                // The first box takes the keyboard as the sheet opens (the
                // card keeps it only when there is no box - see its `focus`),
                // so typing and the clipboard chords work immediately instead
                // of after a click. QQuickTextInput implements Ctrl+C/X/V
                // itself; it just has to be the item that receives them.
                // Clicking another box still moves the keyboard there.
                focus: fieldRow.index === sheet.firstTextField

                // Qt's own default is false, and a box the pointer cannot
                // sweep is a box you cannot copy out of either: Ctrl+C copies
                // the selection and nothing else, so a drag across the value
                // left the clipboard exactly as it was. Keyboard selection
                // (Ctrl+A) did work, which is how a copy inside this sheet
                // ever succeeded.
                selectByMouse: true

                function commit() {
                  fieldModel.save(sheet.store, sheet.entry.id, fieldRow.field, input.text)
                }

                onAccepted: input.commit()
                onActiveFocusChanged: if (!activeFocus) input.commit()
                Keys.onEscapePressed: sheet.close()
              }
            }
          }

          Text {
            width: parent.width
            text: fieldModel.hintFor(sheet.entry, fieldRow.field)
            color: Qt.rgba(colors.foreground.r, colors.foreground.g, colors.foreground.b, 0.45)
            font.pixelSize: 10
            wrapMode: Text.WordWrap
          }
        }
      }

      // ── Actions ───────────────────────────────────────────────────────
      Row {
        width: parent.width
        spacing: 6

        Repeater {
          model: [
            { id: "reset", label: "Reset position" },
            { id: "remove", label: "Remove" }
          ]

          Rectangle {
            required property var modelData
            readonly property bool danger: modelData.id === "remove"

            width: (body.width - 6) / 2
            height: 30
            radius: 9
            color: actionArea.containsMouse
              ? (danger
                  ? Qt.rgba(colors.accentRed.r, colors.accentRed.g, colors.accentRed.b, 0.22)
                  : Qt.rgba(colors.foreground.r, colors.foreground.g, colors.foreground.b, 0.14))
              : Qt.rgba(colors.foreground.r, colors.foreground.g, colors.foreground.b, 0.07)

            Text {
              anchors.centerIn: parent
              text: modelData.label
              color: danger ? colors.accentRed : colors.foreground
              font.pixelSize: 11
            }

            MouseArea {
              id: actionArea
              anchors.fill: parent
              hoverEnabled: true
              onClicked: {
                if (danger) {
                  var id = sheet.entry.id
                  sheet.close()
                  sheet.store.remove(id)
                  return
                }
                var size = sheet.registry.defaultSize(String(sheet.entry.type))
                sheet.store.move(sheet.entry.id,
                                 sheet.registry.originX(sheet.insetLeft),
                                 sheet.registry.originY(sheet.insetTop))
                sheet.store.resize(sheet.entry.id, size.width, size.height)
              }
            }
          }
        }
      }

      Text {
        width: parent.width
        text: "Right-drag to move · corner grip to resize · the cog opens the browser, where categories and the plugin-wide appearance are set"
        color: Qt.rgba(colors.foreground.r, colors.foreground.g, colors.foreground.b, 0.4)
        font.pixelSize: 10
        wrapMode: Text.WordWrap
      }
    }
  }
}
