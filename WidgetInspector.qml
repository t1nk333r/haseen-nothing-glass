import QtQuick
import "components/nothing"

// Everything you can change about ONE widget, in the widget browser.
//
// The desktop's right-click sheet (WidgetSettingsWindow) covers the same one
// widget in place; this pane is where the browser puts it, beside the grid,
// because the browser already knows every instance, already previews them and
// already owns the keyboard. The sheet's cog hands over to here.
//
// It edits through the store only (`store.move/resize/set/remove`) and reads
// the field table from `WidgetFields`, which the sheet and the bar panel read
// too - the three UIs cannot disagree about a key's name, type, or what an
// empty value means.
Item {
  id: inspector

  required property var theme
  required property var store
  required property var registry
  required property var pluginSettings

  // The store row being edited; null hides the pane.
  property var entry: null
  readonly property bool open: inspector.entry !== null

  // This screen's reserved edges, so "Reset position" lands on the first
  // visible cell rather than behind the bar.
  property int insetLeft: 0
  property int insetTop: 0

  // True while a text field has the keyboard, so the launcher stops treating
  // keystrokes as search input.
  property bool editing: false

  signal closed()

  WidgetFields { id: fieldModel }
  // For `styleLabel()` on the style buttons. QML ids are file-scoped, so
  // this pane cannot see the launcher's own PluginId; the object is
  // stateless, so a second one costs nothing.
  PluginId { id: identity }

  // Re-read the row after every store write, so the size buttons and the
  // "set for this widget" markers follow an edit made here or a drag made on
  // the widget itself, instead of freezing at what the pane opened with.
  function _refresh() {
    if (!inspector.entry || !inspector.store) return
    var id = String(inspector.entry.id)
    var list = inspector.store.widgets || []
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].id) === id) { inspector.entry = list[i]; return }
    }
    inspector.entry = null          // removed from under us
    inspector.closed()
  }

  Connections {
    target: inspector.store
    function onWidgetsChanged() { inspector._refresh() }
  }

  readonly property string _type: inspector.open ? String(inspector.entry.type) : ""
  readonly property var _fields: inspector.open ? fieldModel.forType(inspector._type) : []

  // The styles this type can actually be drawn in. Fewer than two means
  // there is no choice to offer and the Style row stays hidden.
  readonly property var _styles: inspector.open && inspector.registry
    ? inspector.registry.stylesFor(inspector._type) : []
  // This widget's own pin. Empty is the normal state: the style then comes
  // from the widget's category, and from the plugin-wide default behind it.
  readonly property string _style: inspector.open ? String(inspector.entry.style || "") : ""
  readonly property string _group: inspector.open && inspector.registry
    ? inspector.registry.group(inspector._type) : ""

  visible: inspector.open
  implicitWidth: theme.px(300)

  Column {
    id: body
    anchors { fill: parent; leftMargin: inspector.theme.pad }
    spacing: inspector.theme.gap

    // ── Which widget ────────────────────────────────────────────────
    NText {
      theme: inspector.theme
      text: inspector.open ? inspector.registry.label(inspector._type) : ""
      font.family: inspector.theme.sansBold
      font.pixelSize: inspector.theme.fBody
      width: body.width
      elide: Text.ElideRight
    }
    NMono {
      theme: inspector.theme
      color: inspector.theme.onDim
      font.pixelSize: inspector.theme.fMicro
      width: body.width
      elide: Text.ElideRight
      text: inspector.open
        ? (inspector.entry.id + "  ·  " + Math.round(inspector.entry.x) + "," + Math.round(inspector.entry.y)
           + "  ·  " + Math.round(inspector.entry.w) + "×" + Math.round(inspector.entry.h))
        : ""
    }

    NDivider { theme: inspector.theme; width: body.width }

    // ── Size ────────────────────────────────────────────────────────
    NLabel { theme: inspector.theme; text: "Size" }

    Row {
      spacing: inspector.theme.px(6)
      Repeater {
        model: inspector.open && inspector.registry ? inspector.registry.sizes(inspector._type) : []
        delegate: NButton {
          required property var modelData
          theme: inspector.theme
          label: modelData.label
          active: inspector.open
            && Number(inspector.entry.w) === modelData.width
            && Number(inspector.entry.h) === modelData.height
          onClicked: inspector.store.resize(inspector.entry.id, modelData.width, modelData.height)
        }
      }
    }

    // ── Style ───────────────────────────────────────────────────────
    // Which of the plugin's two drawings this one tile uses. It is the same
    // override idiom as the per-type fields below: unset follows something
    // broader - here the category, which the browser's Categories pane sets
    // - and set applies to this widget alone.
    NLabel {
      theme: inspector.theme
      loud: inspector._style !== ""
      text: "Style"
      visible: inspector._styles.length > 1
    }

    Row {
      spacing: inspector.theme.px(6)
      visible: inspector._styles.length > 1

      NButton {
        theme: inspector.theme
        label: "Category"
        active: inspector._style === ""
        onClicked: inspector.store.set(inspector.entry.id, "style", "")
      }

      Repeater {
        model: inspector._styles
        delegate: NButton {
          required property var modelData
          theme: inspector.theme
          label: identity.styleLabel(modelData)
          active: inspector._style === String(modelData)
          onClicked: inspector.store.set(inspector.entry.id, "style", String(modelData))
        }
      }
    }

    NLabel {
      theme: inspector.theme
      visible: inspector._styles.length > 1
      width: body.width
      wrapMode: Text.WordWrap
      font.capitalization: Font.MixedCase
      font.letterSpacing: 0
      font.pixelSize: inspector.theme.fMicro
      text: inspector._style !== ""
        ? "Set for this widget only. Pick Category to follow " + inspector._group + " again."
        : "Following the " + inspector._group + " category."
    }

    NDivider { theme: inspector.theme; width: body.width; visible: inspector._fields.length > 0 }

    // ── Per-type settings ───────────────────────────────────────────
    Repeater {
      model: inspector._fields

      delegate: Column {
        id: fieldRow
        required property var modelData
        readonly property var field: modelData
        readonly property bool overridden: fieldModel.isOverridden(inspector.entry, field.key)
        readonly property string value:
          fieldModel.effective(inspector.entry, field.key, inspector.pluginSettings)

        width: body.width
        spacing: inspector.theme.px(3)

        NLabel {
          theme: inspector.theme
          loud: fieldRow.overridden
          text: fieldRow.field.label
        }

        // Boolean: a switch, never a box to type "true" into.
        Rectangle {
          visible: fieldRow.field.kind === "bool"
          width: inspector.theme.px(40)
          height: inspector.theme.px(22)
          radius: height / 2
          color: fieldModel.isTrue(fieldRow.value) ? inspector.theme.red : inspector.theme.surface3
          border.width: inspector.theme.hair
          border.color: inspector.theme.outline

          Rectangle {
            width: parent.height - inspector.theme.px(4)
            height: width
            radius: width / 2
            y: inspector.theme.px(2)
            x: fieldModel.isTrue(fieldRow.value) ? parent.width - width - inspector.theme.px(2)
                                                 : inspector.theme.px(2)
            color: fieldModel.isTrue(fieldRow.value) ? inspector.theme.redInk : inspector.theme.on
            Behavior on x { NumberAnimation { duration: inspector.theme.fast; easing.type: Easing.OutCubic } }
          }

          // The switch paints 40x22; WCAG 2.2 asks 24x24 at AA, so the hit
          // area is grown to 44x44 around it and the painting is untouched.
          MouseArea {
            anchors.fill: parent
            anchors.leftMargin: -2
            anchors.rightMargin: -2
            anchors.topMargin: -11
            anchors.bottomMargin: -11
            cursorShape: Qt.PointingHandCursor
            onClicked: fieldModel.save(inspector.store, inspector.entry.id, fieldRow.field,
                                       !fieldModel.isTrue(fieldRow.value))
          }
        }

        // Everything else: a box that commits on Enter and on losing focus,
        // so there is no Save button to forget.
        Rectangle {
          visible: fieldRow.field.kind !== "bool"
          width: parent.width
          height: inspector.theme.px(26)
          radius: inspector.theme.rChip
          color: input.activeFocus ? inspector.theme.surface3 : inspector.theme.surface2
          border.width: inspector.theme.hair
          border.color: input.activeFocus ? inspector.theme.red : inspector.theme.outline

          TextInput {
            id: input
            anchors { fill: parent; leftMargin: inspector.theme.px(8); rightMargin: inspector.theme.px(8) }
            verticalAlignment: Text.AlignVCenter
            clip: true
            color: inspector.theme.on
            selectionColor: inspector.theme.red
            selectedTextColor: inspector.theme.redInk
            font.family: inspector.theme.mono
            font.pixelSize: inspector.theme.fLabel
            text: fieldRow.value

            function commit() {
              fieldModel.save(inspector.store, inspector.entry.id, fieldRow.field, input.text)
            }

            // The launcher turns every printable key into search text; while
            // a field has the keyboard it must not.
            onActiveFocusChanged: {
              inspector.editing = activeFocus
              if (!activeFocus) input.commit()
            }
            // Commit, but keep the keyboard: dropping focus here would clear
            // `inspector.editing` in the same event, and the launcher's own
            // key handler would then act on the very Enter that committed.
            onAccepted: input.commit()
            Keys.onEscapePressed: {
              input.text = fieldRow.value
              input.focus = false
            }
          }
        }

        NLabel {
          theme: inspector.theme
          width: parent.width
          wrapMode: Text.WordWrap
          font.capitalization: Font.MixedCase
          font.letterSpacing: 0
          font.pixelSize: inspector.theme.fMicro
          text: fieldModel.hintFor(inspector.entry, fieldRow.field)
        }
      }
    }

    NDivider { theme: inspector.theme; width: body.width }

    // ── Actions ─────────────────────────────────────────────────────
    Row {
      spacing: inspector.theme.px(6)

      NButton {
        theme: inspector.theme
        label: "Reset position"
        onClicked: {
          var size = inspector.registry.defaultSize(inspector._type)
          inspector.store.move(inspector.entry.id,
                               inspector.registry.originX(inspector.insetLeft),
                               inspector.registry.originY(inspector.insetTop))
          inspector.store.resize(inspector.entry.id, size.width, size.height)
        }
      }

      NButton {
        theme: inspector.theme
        label: "Remove"
        active: removeArm.armed
        // Two taps: this pane is opened by a right-click on the widget
        // itself, so a stray double-click must not delete a tile.
        onClicked: {
          if (!removeArm.armed) { removeArm.armed = true; removeArm.restart(); return }
          var id = String(inspector.entry.id)
          removeArm.armed = false
          inspector.entry = null
          inspector.store.remove(id)
          inspector.closed()
        }
      }
    }

    Timer {
      id: removeArm
      property bool armed: false
      interval: 2500
      onTriggered: removeArm.armed = false
    }

    NLabel {
      theme: inspector.theme
      width: body.width
      wrapMode: Text.WordWrap
      font.capitalization: Font.MixedCase
      font.letterSpacing: 0
      font.pixelSize: inspector.theme.fMicro
      text: removeArm.armed
        ? "Tap Remove again to delete this widget."
        : "Right-drag the widget to move it, corner grip to resize. Appearance is plugin-wide, in Appearance and in the bar panel."
    }
  }
}
