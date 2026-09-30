import QtQuick
import "components/nothing"

// The widget browser's content: what is on the desktop, what can be added, and
// which style everything is drawn in.
//
// The window around it is Panel.qml's FloatingWindow - a toplevel, not the
// full-screen layer-shell overlay this used to be. That is why this file is a
// plain Item with no layer-shell properties and no scrim: it draws the sheet,
// and the compositor owns the window. Everything inside is unchanged - the
// rail, the catalogue, the desktop grid, the inspector and the appearance
// pane.
//
// Plain QtQuick plus this repo's own Nothing primitives: `qs.Ui` does not
// resolve under the standalone dev harness, and one failed import takes the
// whole file with it.
Item {
  id: launcher

  // Handed down by Panel.qml, which reads them from the shell's injections.
  // Default values rather than `required`: `service` is injected one property
  // step after the panel is constructed, so the store and the registry arrive
  // a moment later than the object does, and every reader below is null-safe.
  property var store: null
  property var registry: null
  property var pluginSettings: null
  property var injectedTheme: null
  property string screenName: ""

  // The plugin's own manifest.json, injected by the shell into Panel.qml and
  // passed down. It is the one authority for what each setting means - the
  // Appearance pane's knob ranges are read from its `settings.schema`. Null
  // under the dev harness, which installs no plugin at all, so every read of
  // it here is null-safe.
  property var manifest: null

  // Writes a plugin-wide setting through the shell (Service.setPluginSetting,
  // passed down by Panel.qml). Absent under the dev harness, where the
  // launcher still adds, removes and places widgets.
  property var setPluginSetting: null

  // How a widget's style is resolved, and how a whole category's is set.
  // All three are the surface's own functions, reached through Service.qml:
  // the browser has to show the style the surface would actually draw, and a
  // second copy of that precedence here would drift from it. Null when the
  // service is not reachable, where every row falls back to the plugin-wide
  // default.
  property var styleForEntry: null
  property var styleForCategory: null
  property var setCategoryStyle: null

  // This screen's reserved edges, forwarded to the settings pane so "Reset
  // position" lands on the first visible cell instead of behind the bar.
  property int insetLeft: 0
  property int insetTop: 0

  // The browser is non-modal and has no scrim: there is nothing to click
  // "outside" of, so the only ways out are Escape and the compositor closing
  // the window. Both are the shell's business - Panel.qml owns the toplevel
  // and tells the shell - so this file asks rather than closes itself.
  signal closeRequested()

  PluginId { id: identity }

  // The window's keyboard focus lands here a frame after it is mapped; without
  // it the browser opens but nothing typed reaches the search box.
  function takeFocus() { keys.forceActiveFocus() }

  Component.onCompleted: Qt.callLater(launcher.takeFocus)

  // Opens the browser on the Desktop section with one widget selected and
  // its settings beside it. The widget's own right-click sheet hands over to
  // here for the rest - it asks the shell for the panel with this widget in
  // the payload, and Panel.qml lands here. The tiles' own SETTINGS action
  // calls it directly.
  // NOT `id` as the parameter name: inside a QML function that identifier
  // resolves to the object's own id, not the argument, and the pane silently
  // opened on nothing.
  function openForWidget(widgetId) {
    launcher.query = ""
    launcher.section = "desktop"
    launcher.inspecting = String(widgetId || "")
    var list = launcher.desktopEntries
    for (var i = 0; i < list.length; i++)
      if (String(list[i].id) === launcher.inspecting) { launcher.selected = i; break }
  }

  // Id of the widget whose settings are open, "" for none.
  property string inspecting: ""

  readonly property var inspectedEntry: {
    if (launcher.inspecting === "") return null
    var list = (launcher.store && launcher.store.widgets) || []
    for (var i = 0; i < list.length; i++)
      if (String(list[i].id) === launcher.inspecting) return list[i]
    return null
  }

  // ── State ──────────────────────────────────────────────────────────
  // Sections are fixed: the desktop, then the catalogue by group, then the
  // appearance pane. The rail is a list of these, not a scroll of everything
  // at once.
  readonly property var sections: {
    var out = [{ id: "desktop", label: "Desktop" }]
    var gs = launcher.registry ? launcher.registry.groups : []
    for (var i = 0; i < gs.length; i++) {
      if (launcher.registry.typesInGroup(gs[i]).length === 0) continue
      out.push({ id: "group:" + gs[i], label: gs[i] })
    }
    // One plugin, one appearance pane: which style draws a widget and what
    // each style is made of are the same question asked at two depths, and
    // the bar entry cannot be relied on to ask it (Omarchy un-places a
    // dual-kind plugin's entry, and an un-placed entry's panel cannot reach
    // the service at all - see BarWidget.qml).
    out.push({ id: "appearance", label: "Appearance" })
    return out
  }

  property string section: "desktop"
  property string query: ""
  property int selected: 0

  // ── Which style draws what ─────────────────────────────────────────
  // The plugin-wide default, for the row the categories fall back to.
  readonly property string defaultStyle: {
    var v = launcher.pluginSettings ? launcher.pluginSettings.widgetStyle : ""
    return (v && String(v) !== "") ? String(v) : "liquid-glass"
  }

  // A category's own override, "" when it inherits the default.
  function categoryOverride(group) {
    var map = launcher.pluginSettings ? launcher.pluginSettings.categoryStyles : null
    var g = String(group || "")
    return (map && typeof map === "object" && map[g]) ? String(map[g]) : ""
  }

  function resolvedCategoryStyle(group) {
    if (typeof launcher.styleForCategory === "function")
      return String(launcher.styleForCategory(String(group || "")))
    return launcher.defaultStyle
  }

  function resolvedEntryStyle(entry) {
    if (typeof launcher.styleForEntry === "function") return String(launcher.styleForEntry(entry))
    var own = entry ? String(entry.style || "") : ""
    if (own !== "") return own
    return launcher.resolvedCategoryStyle(entry && launcher.registry
      ? launcher.registry.group(entry.type) : "")
  }

  // What a tile is really drawn in. A type with no drawing in the resolved
  // style is drawn in the one it does have - `urlFor` falls back the same way
  // - so the tile's chip must not claim a style its file is not.
  function drawableStyle(type, wanted) {
    var styles = launcher.registry ? launcher.registry.stylesFor(String(type)) : []
    if (styles.indexOf(String(wanted)) !== -1) return String(wanted)
    return styles.length ? String(styles[0]) : "liquid-glass"
  }

  // { total, render, miss } for a list of types against one style. `miss`
  // holds the types that cannot be drawn in it, and they are exactly the ones
  // urlFor will fall back for - so this reports what will render, not what was
  // asked for.
  function coverage(types, style) {
    var want = String(style || "")
    var list = types || []
    var render = 0
    var miss = []
    for (var i = 0; i < list.length; i++) {
      var styles = launcher.registry ? launcher.registry.stylesFor(String(list[i])) : []
      if (styles.indexOf(want) !== -1) render++
      else miss.push(String(list[i]))
    }
    return { total: list.length, render: render, miss: miss }
  }

  // The fallbacks as one sentence, grouped by the drawing every one of them
  // has instead - a category may one day hold single-drawing types on both
  // sides. "" when nothing falls back.
  function missNote(types, style) {
    var by = ({})
    var miss = launcher.coverage(types, style).miss
    for (var i = 0; i < miss.length; i++) {
      var only = String(launcher.registry.stylesFor(miss[i])[0] || "liquid-glass")
      if (!by[only]) by[only] = []
      by[only].push(launcher.registry.label(miss[i]))
    }
    var parts = []
    for (var k in by) parts.push(by[k].join(", ") + " always draw " + identity.styleLabel(k))
    return parts.join("; ")
  }

  // Every user-facing type, for the default row, in registry order
  // (typesInGroup already skips the dev tiles).
  readonly property var allTypes: {
    var out = []
    var gs = launcher.registry ? launcher.registry.groups : []
    for (var i = 0; i < gs.length; i++) out = out.concat(launcher.registry.typesInGroup(gs[i]))
    return out
  }

  // Categories that actually have a widget installed, in the registry's own
  // order - the rows the Appearance pane offers a style for.
  readonly property var categoryRows: {
    var out = []
    var gs = launcher.registry ? launcher.registry.groups : []
    for (var i = 0; i < gs.length; i++)
      if (launcher.registry.typesInGroup(gs[i]).length > 0) out.push(gs[i])
    return out
  }

  // The glass shader's own knobs, plugin-wide, in the order the pane shows
  // them. This table names the keys and carries display fields only: the
  // RANGE comes from manifest.json's settings.schema (`_knobRange` below), so
  // a knob here and the setting the Omarchy settings UI edits cannot disagree
  // about what the value means. A range restated here is what went stale when
  // this tree was severed from Plasma, leaving two handles pinned left.
  //
  // `mult` is the one display transform. Three keys are stored `0..1` and read
  // as a percentage, so they carry 100 and every other knob 1; it is applied
  // in both directions (`* mult` on display, `/ mult` on write) and the value
  // that reaches disk is unchanged by it.
  //
  // `step` is a fallback drag granularity, used only for a key whose schema
  // entry declares no step of its own. The four integer keys are the ones that
  // do not, and `valueAt()` would snap those to `Math.round(raw / undefined) *
  // undefined`, i.e. NaN, were the field removed; the five number-typed keys
  // declare a step and it wins over this one.
  readonly property var glassKnobs: [
    { key: "cornerRadius", label: "Corner radius", step: 2, mult: 1, unit: " px" },
    { key: "roundness", label: "Roundness", step: 0.5, mult: 1, unit: "" },
    { key: "refractThickness", label: "Band", step: 1, mult: 1, unit: " px" },
    { key: "refractIOR", label: "Index", step: 0.05, mult: 1, unit: "" },
    { key: "refractScale", label: "Strength", step: 5, mult: 1, unit: "" },
    { key: "tintAlpha", label: "Tint", step: 1, mult: 100, unit: "%" },
    { key: "chromaStrength", label: "Dispersion", step: 1, mult: 100, unit: "%" },
    { key: "specStrength", label: "Corner specular", step: 1, mult: 100, unit: "%" },
    { key: "blurRadiusPx", label: "Backdrop blur", step: 1, mult: 1, unit: " px" }
  ]

  // The Nothing style's own knobs, the same shape as the table above. The
  // material pair, in the order the pane shows them: the surface's coverage of
  // the card and the blurred wallpaper behind it, composed rather than one
  // replacing the other - see NTheme.qml's frost comment for the algebra and for
  // what the exclusivity it replaces cost. Both are stored `0..1` and drawn as
  // percentages, hence the `mult` the glass `tintAlpha` also carries. Nothing
  // binds either in the launcher's own NTheme: the sheet is the compositor's
  // toplevel with no wallpaper behind it, and stays opaque.
  readonly property var nothingKnobs: [
    { key: "surfaceAlpha", label: "Card opacity", step: 1, mult: 100, unit: "%" },
    { key: "frost", label: "Frost", step: 1, mult: 100, unit: "%" }
  ]

  // manifest.json's settings.schema, or an empty list while the manifest has
  // not arrived.
  readonly property var manifestSchema: {
    var m = launcher.manifest
    var s = (m && m.settings) ? m.settings.schema : null
    return Array.isArray(s) ? s : []
  }

  // One schema entry's range, in the units the setting is stored in, or null
  // when the key has no entry or its entry declares no usable range. A caller
  // must skip such a knob rather than draw it against a zero span, where the
  // handle would pin left and a drag would write `undefined`.
  function _knobRange(key) {
    var schema = launcher.manifestSchema
    for (var i = 0; i < schema.length; i++) {
      var e = schema[i]
      if (!e || String(e.key) !== String(key)) continue
      var lo = Number(e.min)
      var hi = Number(e.max)
      if (!isFinite(lo) || !isFinite(hi) || hi <= lo) return null
      return { min: lo, max: hi, step: Number(e.step) }
    }
    return null
  }

  // The knobs the pane can actually draw: one table resolved against the
  // schema, so each row's `min`/`max`/`step` are in the knob's own units -
  // `min`/`max` scaled by `mult`, since the handle spans the range the row
  // displays and one write scales the pending value back out. A key the schema
  // does not range is dropped here, where the drop is deliberate and visible,
  // instead of rendering a dead control. Both drawings' tables come through
  // this one function, so the range rule lives in one place.
  function _knobRows(table) {
    var out = []
    for (var i = 0; i < table.length; i++) {
      var k = table[i]
      var r = launcher._knobRange(k.key)
      if (r === null) continue
      var mult = Number(k.mult) > 0 ? Number(k.mult) : 1
      out.push({
        key: k.key, label: k.label, unit: k.unit, mult: mult,
        min: r.min * mult, max: r.max * mult,
        step: r.step > 0 ? r.step * mult : k.step
      })
    }
    return out
  }

  readonly property var glassKnobRows: launcher._knobRows(launcher.glassKnobs)
  readonly property var nothingKnobRows: launcher._knobRows(launcher.nothingKnobs)

  // The widget rows on THIS screen, newest last - the desktop section.
  readonly property var desktopEntries: {
    var out = []
    var list = (launcher.store && launcher.store.widgets) || []
    for (var i = 0; i < list.length; i++)
      if (String(list[i].screen) === launcher.screenName) out.push(list[i])
    return out
  }

  // How many rows the desktop grid is showing. A plain int, so the grid's
  // Repeater can bind to it and survive `desktopEntries` being recomputed -
  // see that Repeater's own comment for why that matters.
  readonly property int desktopCount: launcher.desktopEntries.length

  function _typesFor(sectionId) {
    if (!launcher.registry) return []
    if (sectionId.indexOf("group:") === 0)
      return launcher.registry.typesInGroup(sectionId.substring(6))
    return []
  }

  // Search cuts across every group: a query replaces the section's own list
  // rather than filtering inside it, because "where did I put the timer" is
  // the question being asked.
  readonly property var visibleTypes: {
    var q = launcher.query.trim().toLowerCase()
    var all = []
    if (q === "") {
      all = launcher._typesFor(launcher.section)
    } else {
      var types = launcher.registry ? launcher.registry.listTypes() : []
      for (var i = 0; i < types.length; i++) {
        var t = types[i]
        if (launcher.registry.isDev(t)) continue
        var hay = (t + " " + launcher.registry.label(t) + " " +
                   launcher.registry.group(t) + " " + launcher.registry.hint(t)).toLowerCase()
        if (hay.indexOf(q) !== -1) all.push(t)
      }
    }
    return all
  }

  readonly property int itemCount: {
    if (launcher.query.trim() !== "") return launcher.visibleTypes.length
    if (launcher.section === "desktop") return launcher.desktopEntries.length
    if (launcher.section === "appearance") return 0
    return launcher.visibleTypes.length
  }

  // How many instances of a type are already on this screen - the count the
  // catalogue tile shows, so adding a second clock is a deliberate act.
  function countOf(type) {
    var n = 0
    var list = launcher.desktopEntries
    for (var i = 0; i < list.length; i++) if (String(list[i].type) === String(type)) n++
    return n
  }

  // ── Actions ────────────────────────────────────────────────────────
  function addType(type) {
    if (!launcher.store) return
    var size = launcher.registry ? launcher.registry.minSize(type) : null
    var cell = launcher._freeCell()
    launcher.store.add(type, launcher.screenName, {
      x: cell.x, y: cell.y,
      w: 192, h: 192
    })
  }

  // First lattice cell that no widget on this screen already occupies, so a
  // burst of adds from the launcher does not stack every new tile on one
  // spot. The grid itself is the registry's (cell + gutter).
  function _freeCell() {
    var pitch = launcher.registry ? (launcher.registry.gridCell + launcher.registry.gridGap) : 104
    var originX = 16, originY = 16
    for (var row = 0; row < 8; row++) {
      for (var col = 0; col < 12; col++) {
        var x = originX + col * pitch
        var y = originY + row * pitch
        var free = true
        var list = launcher.desktopEntries
        for (var i = 0; i < list.length; i++) {
          var e = list[i]
          if (x < e.x + e.w && x + 192 > e.x && y < e.y + e.h && y + 192 > e.y) { free = false; break }
        }
        if (free) return { x: x, y: y }
      }
    }
    return { x: originX, y: originY }
  }

  NTheme {
    id: nothing
    scale: {
      var v = Number(launcher.pluginSettings ? launcher.pluginSettings.uiScale : 100)
      return (isFinite(v) && v > 0) ? v / 100 : 1
    }
    accent: {
      var c = launcher.pluginSettings ? launcher.pluginSettings.accentColor : ""
      return (c && String(c) !== "") ? String(c) : "#D71921"
    }
    followTheme: !!(launcher.pluginSettings && launcher.pluginSettings.followTheme)
    systemFont: !!(launcher.pluginSettings && launcher.pluginSettings.systemFont)
    themePalette: launcher.injectedTheme ? launcher.injectedTheme.palette : null
  }

  FocusScope {
    id: keys
    anchors.fill: parent
    // The instance exists only while the panel is open, so this scope always
    // wants the keyboard; takeFocus() puts it there once the window is mapped.
    focus: true

    Keys.onEscapePressed: {
      // Escape backs out one level: the settings pane first, then the window.
      // The window is the shell's, so ask it to hide - a self-close would
      // leave the shell believing the panel is still open.
      if (launcher.inspecting !== "") launcher.inspecting = ""
      else launcher.closeRequested()
    }
    Keys.onPressed: function (event) {
      // A text field in the settings pane owns the keyboard while it is
      // focused; without this, typing a folder path would land in the search
      // box instead.
      if (inspector.editing) return
      var cols = grid.columns
      if (event.key === Qt.Key_Down) { launcher.selected = Math.min(launcher.itemCount - 1, launcher.selected + cols); event.accepted = true }
      else if (event.key === Qt.Key_Up) { launcher.selected = Math.max(0, launcher.selected - cols); event.accepted = true }
      else if (event.key === Qt.Key_Right) { launcher.selected = Math.min(launcher.itemCount - 1, launcher.selected + 1); event.accepted = true }
      else if (event.key === Qt.Key_Left) { launcher.selected = Math.max(0, launcher.selected - 1); event.accepted = true }
      else if (event.key === Qt.Key_Tab) {
        var i = 0
        for (var s = 0; s < launcher.sections.length; s++)
          if (launcher.sections[s].id === launcher.section) i = s
        var dir = (event.modifiers & Qt.ShiftModifier) ? -1 : 1
        launcher.section = launcher.sections[(i + dir + launcher.sections.length) % launcher.sections.length].id
        launcher.selected = 0
        event.accepted = true
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        grid.activate(launcher.selected)
        event.accepted = true
      } else if (event.key === Qt.Key_Backspace) {
        launcher.query = launcher.query.slice(0, -1)
        event.accepted = true
      } else if (event.text && event.text.length === 1 && event.text >= " ") {
        launcher.query += event.text
        launcher.selected = 0
        event.accepted = true
      }
    }

    // ── The sheet ────────────────────────────────────────────────────
    // The card IS the window now, so it fills it: the size policy that used
    // to keep a centred sheet from swallowing the desktop moved to the
    // compositor, which sizes and centres the toplevel (Hyprland rule
    // `float_nothing_glass_browser` in ~/.config/hypr/rules.lua).
    //
    // The frame is the compositor's too (plan 054). Hyprland already draws
    // its border and rounds the toplevel's corners with the operator's
    // globals, so the card draws neither: an outline here would sit inside
    // Hyprland's border as a second frame, and a radius here would not match
    // the compositor's, leaving a sliver of the transparent window colour in
    // each corner. Opacity is the compositor's for the same reason - a rule
    // `opacity` multiplies whatever is drawn, so the fill stays opaque.
    NCard {
      id: sheet
      theme: nothing
      level: 0
      radius: 0
      outlined: false
      anchors.fill: parent

      // ── Left rail ──────────────────────────────────────────────────
      Item {
        id: rail
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        anchors.margins: nothing.pad
        width: nothing.px(210)

        NLabel {
          id: wordmark
          theme: nothing
          loud: true
          text: identity.label
          font.pixelSize: nothing.fBody
          anchors { top: parent.top; left: parent.left }
        }
        NLabel {
          id: subMark
          theme: nothing
          text: "Launcher"
          anchors { top: wordmark.bottom; topMargin: nothing.px(2); left: parent.left }
        }

        // Search is a label, not a field: the whole sheet has keyboard
        // focus and every printable key already goes here, so a focusable
        // TextField would only add a place for focus to get lost.
        NCard {
          id: searchBox
          theme: nothing
          level: 1
          radius: nothing.rChip
          anchors { top: subMark.bottom; topMargin: nothing.gap; left: parent.left; right: parent.right }
          height: nothing.px(34)

          NMono {
            anchors { fill: parent; leftMargin: nothing.px(10); rightMargin: nothing.px(10) }
            verticalAlignment: Text.AlignVCenter
            theme: nothing
            elide: Text.ElideLeft
            font.pixelSize: nothing.fLabel
            color: launcher.query === "" ? nothing.onQuiet : nothing.on
            text: launcher.query === "" ? "TYPE TO SEARCH" : launcher.query
          }
          Rectangle {
            width: nothing.px(2); height: nothing.px(14); radius: 1
            color: nothing.red
            visible: launcher.query !== ""
            anchors { verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: nothing.px(10) }
            SequentialAnimation on opacity {
              // The content exists only while the browser's toplevel is up, so
              // a query is the whole condition the old `launcher.open` added.
              running: launcher.query !== ""
              loops: Animation.Infinite
              NumberAnimation { to: 0.15; duration: 500 }
              NumberAnimation { to: 1.0; duration: 500 }
            }
          }
        }

        Column {
          id: railList
          anchors { top: searchBox.bottom; topMargin: nothing.gap; left: parent.left; right: parent.right }
          spacing: nothing.px(2)

          Repeater {
            model: launcher.sections
            delegate: Item {
              id: railRow
              required property var modelData
              required property int index
              readonly property bool current: launcher.section === railRow.modelData.id && launcher.query === ""
              width: railList.width
              height: nothing.px(30)

              Rectangle {
                anchors.fill: parent
                radius: nothing.rChip
                color: railRow.current ? nothing.surface3 : "transparent"
                border.width: railRow.current ? nothing.hair : 0
                border.color: nothing.outline
              }
              Rectangle {
                visible: railRow.current
                width: nothing.px(3); height: nothing.px(12); radius: 1.5
                color: nothing.red
                anchors { left: parent.left; leftMargin: nothing.px(8); verticalCenter: parent.verticalCenter }
              }
              NLabel {
                theme: nothing
                loud: railRow.current
                text: railRow.modelData.label
                anchors { left: parent.left; leftMargin: nothing.px(18); verticalCenter: parent.verticalCenter }
              }
              NMono {
                theme: nothing
                color: nothing.onQuiet
                font.pixelSize: nothing.fMicro
                anchors { right: parent.right; rightMargin: nothing.px(10); verticalCenter: parent.verticalCenter }
                text: {
                  var id = railRow.modelData.id
                  if (id === "desktop") return String(launcher.desktopEntries.length)
                  if (id.indexOf("group:") === 0) return String(launcher._typesFor(id).length)
                  return ""
                }
              }
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  launcher.query = ""
                  launcher.section = railRow.modelData.id
                  launcher.selected = 0
                }
              }
            }
          }
        }

        NMono {
          theme: nothing
          color: nothing.onQuiet
          font.pixelSize: nothing.fMicro
          wrapMode: Text.WordWrap
          anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
          text: "TAB SECTION · ENTER ADD\nBACKSPACE SEARCH · ESC CLOSE"
        }
      }

      NDivider {
        theme: nothing
        vertical: true
        anchors { left: rail.right; leftMargin: nothing.pad; top: parent.top; bottom: parent.bottom }
        anchors.topMargin: nothing.pad
        anchors.bottomMargin: nothing.pad
      }

      // ── Right pane ─────────────────────────────────────────────────
      // The settings of the widget you clicked, beside the grid rather than
      // in a window of its own. Takes the right-hand strip only while it is
      // open, so the grid keeps the whole pane the rest of the time.
      NDivider {
        theme: nothing
        vertical: true
        visible: inspector.open
        anchors {
          right: inspector.left; rightMargin: nothing.pad
          top: parent.top; topMargin: nothing.pad
          bottom: parent.bottom; bottomMargin: nothing.pad
        }
      }

      WidgetInspector {
        id: inspector
        theme: nothing
        store: launcher.store
        registry: launcher.registry
        pluginSettings: launcher.pluginSettings
        entry: launcher.inspectedEntry
        insetLeft: launcher.insetLeft
        insetTop: launcher.insetTop
        onClosed: launcher.inspecting = ""

        width: inspector.open ? inspector.implicitWidth : 0
        anchors {
          right: parent.right; rightMargin: nothing.pad
          top: parent.top; topMargin: nothing.pad
          bottom: parent.bottom; bottomMargin: nothing.pad
        }
      }

      Item {
        id: pane
        anchors {
          left: rail.right; leftMargin: nothing.pad * 2
          right: inspector.open ? inspector.left : parent.right
          rightMargin: inspector.open ? nothing.pad * 2 : nothing.pad
          top: parent.top; topMargin: nothing.pad
          bottom: parent.bottom; bottomMargin: nothing.pad
        }

        NLabel {
          id: paneTitle
          theme: nothing
          loud: true
          text: {
            if (launcher.query.trim() !== "") return "Search · " + launcher.itemCount
            for (var i = 0; i < launcher.sections.length; i++)
              if (launcher.sections[i].id === launcher.section) return launcher.sections[i].label
            return ""
          }
          anchors { top: parent.top; left: parent.left }
        }
        NLabel {
          theme: nothing
          text: identity.label
          anchors { top: parent.top; right: parent.right }
        }

        // The tile grid, for the desktop and catalogue sections.
        Flickable {
          id: flick
          anchors { top: paneTitle.bottom; topMargin: nothing.gap; left: parent.left; right: parent.right; bottom: parent.bottom }
          clip: true
          contentHeight: grid.height
          visible: launcher.section !== "appearance"
          boundsBehavior: Flickable.StopAtBounds

          Grid {
            id: grid
            width: parent.width
            // Aim for a column a little wider than the 192 preview it holds,
            // and cap the count: past five across, the tiles start shrinking
            // below life size on a wide screen and the previews stop being
            // previews.
            columns: Math.max(1, Math.min(5, Math.floor(width / nothing.px(260))))
            spacing: nothing.gap

            readonly property real cellW: (width - (columns - 1) * spacing) / columns

            // Enter on a DESKTOP tile opens its settings - it must never
            // delete. It used to remove, which was survivable when removal
            // was the tile's only action; now that a text field lives one
            // pane away it was lethal: committing a field with Enter dropped
            // focus, and the same key press then reached this function and
            // deleted the widget being configured. Removal lives in the
            // settings pane, behind two taps.
            function activate(i) {
              if (launcher.section === "desktop" && launcher.query.trim() === "") {
                var e = launcher.desktopEntries[i]
                if (e) launcher.openForWidget(String(e.id))
              } else {
                var t = launcher.visibleTypes[i]
                if (t) launcher.addType(t)
              }
            }

            // Live instances: what is on this screen, with its own style.
            //
            // Bound to a stable COUNT, not to the entries array. That array is
            // recomputed on every store write - a drag release, a resize, a
            // settings save, an IPC call - and a freshly built array is a new
            // model, which makes the Repeater destroy and re-create every
            // delegate. Each delegate holds a real widget document, so that
            // was 16 engine start-ups per commit on this layout. With an int
            // model the delegates persist and only the live `modelData`
            // binding below re-evaluates. Same lesson, same shape as
            // widgets/city-1/main.qml, which spells it out.
            Repeater {
              model: (launcher.section === "desktop" && launcher.query.trim() === "")
                ? launcher.desktopCount : 0
              delegate: LauncherTile {
                required property int index
                readonly property var modelData: launcher.desktopEntries[index] || ({})
                theme: nothing
                registry: launcher.registry
                pluginSettings: launcher.pluginSettings
                injectedTheme: launcher.injectedTheme
                width: grid.cellW
                type: String(modelData.type)
                title: launcher.registry.label(modelData.type)
                subtitle: Math.round(modelData.w) + "×" + Math.round(modelData.h)
                settingsOverrides: modelData.settings || {}
                onDesktop: true
                current: launcher.selected === index
                style: launcher.drawableStyle(String(modelData.type),
                                              launcher.resolvedEntryStyle(modelData))
                badge: launcher.inspecting === String(modelData.id) ? "open" : ""
                actionLabel: "SETTINGS"
                onPrimary: launcher.openForWidget(String(modelData.id))
                onEntered: launcher.selected = index
              }
            }

            // The catalogue. Its model legitimately changes with the query -
            // a different set of types is a different set of tiles - and it
            // does not depend on the store, so it is left as it is. The
            // previews still have to know whether the browser is showing.
            Repeater {
              model: (launcher.section === "desktop" && launcher.query.trim() === "")
                ? [] : launcher.visibleTypes
              delegate: LauncherTile {
                required property var modelData
                required property int index
                theme: nothing
                registry: launcher.registry
                pluginSettings: launcher.pluginSettings
                injectedTheme: launcher.injectedTheme
                width: grid.cellW
                type: String(modelData)
                style: launcher.drawableStyle(String(modelData),
                                              launcher.resolvedCategoryStyle(launcher.registry.group(modelData)))
                title: launcher.registry.label(modelData)
                subtitle: launcher.registry.hint(modelData)
                current: launcher.selected === index
                badge: launcher.countOf(modelData) > 0 ? ("ON DESKTOP · " + launcher.countOf(modelData)) : ""
                actionLabel: "ADD"
                onPrimary: launcher.addType(String(modelData))
                onEntered: launcher.selected = index
              }
            }
          }
        }


        // ── Appearance pane ──────────────────────────────────────────
        // One plugin draws both styles, so both sets of knobs live here,
        // under their own headings: first which drawing a widget gets, then
        // what each drawing is made of. It scrolls because the two knob
        // groups together are taller than the sheet on a laptop screen.
        Flickable {
          id: appearanceFlick
          anchors { top: paneTitle.bottom; topMargin: nothing.gap; left: parent.left; right: parent.right; bottom: parent.bottom }
          visible: launcher.section === "appearance" && launcher.query.trim() === ""
          clip: true
          contentHeight: appearance.height
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: appearance
            width: appearanceFlick.width
            spacing: nothing.gap

            // ── Which style draws a widget ────────────────────────────
            NText { theme: nothing; text: "Which style draws a widget"
                    font.family: nothing.sansBold; font.pixelSize: nothing.fBody }
            NMono {
              theme: nothing
              color: nothing.onDim
              font.pixelSize: nothing.fMicro
              width: appearance.width
              wrapMode: Text.WordWrap
              text: "Three levels, most specific first: a widget's own choice in its right-click sheet, then its category, then this default."
            }

            NLabel { theme: nothing; loud: true; text: "Default" }
            Row {
              spacing: nothing.gap
              Repeater {
                model: identity.styles
                delegate: NButton {
                  required property var modelData
                  theme: nothing
                  label: identity.styleLabel(modelData)
                  active: launcher.defaultStyle === String(modelData)
                  onClicked: if (typeof launcher.setPluginSetting === "function")
                    launcher.setPluginSetting("widgetStyle", String(modelData))
                }
              }
            }
            // What the default really draws. A plugin-wide choice only moves
            // the types that have both drawings, so the sentence names the
            // single-drawing ones it cannot move - recorded from `stylesFor`,
            // which is also what the counter is computed from.
            NMono {
              theme: nothing
              color: nothing.onQuiet
              font.pixelSize: nothing.fMicro
              width: appearance.width
              wrapMode: Text.WordWrap
              text: {
                var cov = launcher.coverage(launcher.allTypes, launcher.defaultStyle)
                var note = launcher.missNote(launcher.allTypes, launcher.defaultStyle)
                var line = "Drawn by " + cov.render + " of " + cov.total + " widget types"
                return note === "" ? line + "." : line + "; " + note + "."
              }
            }

            NLabel { theme: nothing; loud: true; text: "Categories" }
            NMono {
              theme: nothing
              color: nothing.onDim
              font.pixelSize: nothing.fMicro
              width: appearance.width
              wrapMode: Text.WordWrap
              text: "One style for a whole shelf at a time - every clock, every system readout. A category set to Default follows the row above; the style it ends up with is shown on the right."
            }

            Repeater {
              model: launcher.categoryRows
              delegate: Item {
                id: catRow
                required property var modelData
                readonly property string group: String(catRow.modelData)
                readonly property string override: launcher.categoryOverride(catRow.group)
                // What this category will render, not what it was asked for:
                // `wanted` is the resolved style, `cov` counts the types that
                // actually draw it. A type in `cov.miss` is drawn by urlFor's
                // fallback instead.
                readonly property var wanted: String(launcher.resolvedCategoryStyle(catRow.group))
                readonly property var cov: launcher.coverage(
                  launcher.registry ? launcher.registry.typesInGroup(catRow.group) : [],
                  catRow.wanted)
                width: appearance.width
                height: catControls.implicitHeight
                  + (catRow.cov.miss.length > 0 ? nothing.px(12) : 0)

                NText {
                  id: catName
                  theme: nothing
                  text: catRow.group
                  elide: Text.ElideRight
                  width: nothing.px(80)
                  anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                }
                Row {
                  id: catControls
                  spacing: nothing.gap
                  anchors { left: catName.right; leftMargin: nothing.gap; verticalCenter: parent.verticalCenter }

                  NButton {
                    theme: nothing
                    label: "Default"
                    active: catRow.override === ""
                    onClicked: if (typeof launcher.setCategoryStyle === "function")
                      launcher.setCategoryStyle(catRow.group, "")
                  }
                  Repeater {
                    model: identity.styles
                    delegate: NButton {
                      required property var modelData
                      // A style no type in this category can draw is a button
                      // that would draw exactly what the current one does.
                      // Hide the button, not the label: NButton takes
                      // px(22) of width even with empty text, so an empty
                      // label would still leave a gap in the Row. No category
                      // reaches zero render today - every one holds a type
                      // with both drawings - so this guard is unfired and is
                      // here for the day one does not.
                      visible: launcher.coverage(
                        launcher.registry ? launcher.registry.typesInGroup(catRow.group) : [],
                        String(modelData)).render > 0
                      theme: nothing
                      label: identity.styleLabel(modelData)
                      active: catRow.override === String(modelData)
                      onClicked: if (typeof launcher.setCategoryStyle === "function")
                        launcher.setCategoryStyle(catRow.group, String(modelData))
                    }
                  }
                }
                NMono {
                  theme: nothing
                  color: nothing.onQuiet
                  font.pixelSize: nothing.fMicro
                  horizontalAlignment: Text.AlignRight
                  anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                  text: identity.styleLabel(catRow.wanted).toUpperCase()
                        + " · " + catRow.cov.render + " OF " + catRow.cov.total
                        + (catRow.override === "" ? " · INHERITED" : "")
                }
                // Which types in this category the resolved style cannot
                // reach. Absent when the style covers the category.
                NMono {
                  theme: nothing
                  color: nothing.onQuiet
                  font.pixelSize: nothing.fMicro
                  elide: Text.ElideRight
                  anchors { left: catName.left; right: parent.right
                            top: catControls.bottom; topMargin: nothing.px(2) }
                  visible: catRow.cov.miss.length > 0
                  text: launcher.missNote(
                    launcher.registry ? launcher.registry.typesInGroup(catRow.group) : [],
                    catRow.wanted)
                }
              }
            }

            // ── Typography ────────────────────────────────────────────
            // The one style with a bundled face left to swap: Barlow. The
            // glass drawings are always in the desktop's font, since the
            // Apple faces were removed (fonts/LICENSES.md).
            NLabel { theme: nothing; loud: true; text: "Typography" }
            NMono {
              theme: nothing
              color: nothing.onDim
              font.pixelSize: nothing.fMicro
              width: appearance.width
              wrapMode: Text.WordWrap
              text: "Bundled face: Barlow, for the Nothing style. System font: the desktop's own - the fontconfig alias `omarchy font set` writes; the glass widgets always draw in it, having no bundled face left. The dot matrix has no font and never changes."
            }
            Row {
              spacing: nothing.gap
              Repeater {
                model: [{ v: false, l: "Bundled faces" }, { v: true, l: "System font" }]
                delegate: NButton {
                  required property var modelData
                  theme: nothing
                  label: modelData.l
                  active: !!launcher.pluginSettings.systemFont === modelData.v
                  onClicked: if (typeof launcher.setPluginSetting === "function")
                    launcher.setPluginSetting("systemFont", modelData.v)
                }
              }
            }

            NDivider { theme: nothing; width: appearance.width }

            // ── Liquid Glass ──────────────────────────────────────────
            NText { theme: nothing; text: identity.styleLabel("liquid-glass")
                    font.family: nothing.sansBold; font.pixelSize: nothing.fBody }
            NMono {
              theme: nothing
              color: nothing.onDim
              font.pixelSize: nothing.fMicro
              width: appearance.width
              wrapMode: Text.WordWrap
              text: "How the glass is drawn. A widget in the Nothing style ignores every knob in this group."
            }

            NLabel { theme: nothing; loud: true; text: "Glass or solid" }
            NMono {
              theme: nothing
              color: nothing.onDim
              font.pixelSize: nothing.fMicro
              width: appearance.width
              wrapMode: Text.WordWrap
              text: "The (theme) options take their colours from the active Omarchy theme instead of the macOS palette."
            }
            Row {
              spacing: nothing.gap
              Repeater {
                model: [
                  { value: 0, label: "Glass" },
                  { value: 1, label: "Solid" },
                  { value: 3, label: "Glass (theme)" },
                  { value: 2, label: "Solid (theme)" }
                ]
                delegate: NButton {
                  required property var modelData
                  theme: nothing
                  label: modelData.label
                  active: Number(launcher.pluginSettings.styleMode) === modelData.value
                  onClicked: if (typeof launcher.setPluginSetting === "function")
                    launcher.setPluginSetting("styleMode", modelData.value)
                }
              }
            }

            NLabel { theme: nothing; loud: true; text: "Light or dark" }
            Row {
              spacing: nothing.gap
              Repeater {
                model: [
                  { value: 0, label: "Dark" },
                  { value: 1, label: "Light" },
                  { value: 2, label: "Follow system" }
                ]
                delegate: NButton {
                  required property var modelData
                  theme: nothing
                  label: modelData.label
                  active: Number(launcher.pluginSettings.appearance) === modelData.value
                  onClicked: if (typeof launcher.setPluginSetting === "function")
                    launcher.setPluginSetting("appearance", modelData.value)
                }
              }
            }

            NLabel { theme: nothing; loud: true; text: "Refraction" }
            Repeater {
              model: launcher.glassKnobRows
              // The row itself is KnobRow.qml, shared with the Nothing section
              // below: one drag, one write-on-release rule, one write site.
              // Everything it draws with is passed in - see that file for why
              // it may not close over this document's ids - and its width comes
              // from the pane column, which is where the delegate used to take
              // it from too.
              delegate: KnobRow {
                required property var modelData
                knob: modelData
                theme: nothing
                pluginSettings: launcher.pluginSettings
                setSetting: launcher.setPluginSetting
                width: appearance.width
              }
            }

            NLabel { theme: nothing; loud: true; text: "Re-sample every frame" }
            NMono {
              theme: nothing
              color: nothing.onDim
              font.pixelSize: nothing.fMicro
              width: appearance.width
              wrapMode: Text.WordWrap
              text: "Only an animated wallpaper needs this. On a still one it re-captures identical pixels every frame - pure GPU cost, no visible difference."
            }
            Row {
              spacing: nothing.gap
              Repeater {
                model: [{ v: false, l: "On wallpaper change" }, { v: true, l: "Every frame" }]
                delegate: NButton {
                  required property var modelData
                  theme: nothing
                  label: modelData.l
                  active: !!launcher.pluginSettings.realtimeRefraction === modelData.v
                  onClicked: if (typeof launcher.setPluginSetting === "function")
                    launcher.setPluginSetting("realtimeRefraction", modelData.v)
                }
              }
            }

            NDivider { theme: nothing; width: appearance.width }

            // ── Nothing ───────────────────────────────────────────────
            NText { theme: nothing; text: identity.styleLabel("nothing")
                    font.family: nothing.sansBold; font.pixelSize: nothing.fBody }
            NMono {
              theme: nothing
              color: nothing.onDim
              font.pixelSize: nothing.fMicro
              width: appearance.width
              wrapMode: Text.WordWrap
              text: "How the Nothing style is drawn - the dot matrix, the type and the accent. It also dresses this sheet, so a change here is visible immediately - except the card material, the opacity and the frost: those are what a desktop card is made of over the wallpaper, and this sheet is the compositor's toplevel with no wallpaper behind it, so it stays matte."
            }

            NLabel { theme: nothing; loud: true; text: "Accent" }
            Row {
              spacing: nothing.gap
              Repeater {
                model: ["#D71921", "#FF6B00", "#FFFFFF", "#4B9EFF", "#34C759"]
                delegate: Rectangle {
                  required property var modelData
                  width: nothing.px(34); height: nothing.px(34); radius: nothing.rChip
                  color: modelData
                  border.width: nothing.hair
                  border.color: String(nothing.accent).toUpperCase() === String(modelData).toUpperCase()
                    ? nothing.on : nothing.outline
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (typeof launcher.setPluginSetting === "function")
                      launcher.setPluginSetting("accentColor", String(modelData))
                  }
                }
              }
            }

            NLabel { theme: nothing; loud: true; text: "Scale" }
            Row {
              spacing: nothing.gap
              Repeater {
                model: [80, 90, 100, 115, 130]
                delegate: NButton {
                  required property var modelData
                  theme: nothing
                  label: modelData + "%"
                  active: Number(launcher.pluginSettings.uiScale) === modelData
                  onClicked: if (typeof launcher.setPluginSetting === "function")
                    launcher.setPluginSetting("uiScale", modelData)
                }
              }
            }

            NLabel { theme: nothing; loud: true; text: "Follow the Omarchy theme" }
            Row {
              spacing: nothing.gap
              Repeater {
                model: [{ v: false, l: "Stock black" }, { v: true, l: "Theme colours" }]
                delegate: NButton {
                  required property var modelData
                  theme: nothing
                  label: modelData.l
                  active: !!launcher.pluginSettings.followTheme === modelData.v
                  onClicked: if (typeof launcher.setPluginSetting === "function")
                    launcher.setPluginSetting("followTheme", modelData.v)
                }
              }
            }

            // The two knobs of this section that do NOT show here: the sheet is
            // a toplevel and the launcher's own NTheme leaves both unbound (see
            // the sheet's comment), so the copy above says so. They are the two
            // halves of one card's material - opacity of the surface, frost of
            // the wallpaper - composed together rather than chosen between,
            // which is why they share a heading.
            NLabel { theme: nothing; loud: true; text: "Card material" }
            Repeater {
              model: launcher.nothingKnobRows
              delegate: KnobRow {
                required property var modelData
                knob: modelData
                theme: nothing
                pluginSettings: launcher.pluginSettings
                setSetting: launcher.setPluginSetting
                width: appearance.width
              }
            }
          }
        }
      }
    }
  }
}
