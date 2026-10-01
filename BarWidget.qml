import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar-widget entry point (manifest.json `entryPoints.barWidget`): one bar
// icon that opens the Liquid Glass control panel, and nothing beside it.
// This replaced the weather readout that plan 008 put in the bar — the
// operator wanted the bar slot to *control* the desktop widgets rather than
// be one of them; the weather widget itself lives on as the desktop
// `weather` type.
//
// The focused workspace figure sat beside this icon from plan 050 to plan
// 055, and is gone: the operator asked for the bar entry to be the icon
// alone. It had been drawn here on the report that a desktop `workspace`
// tile is useless as a glance — the tile draws on the bottom layer, so it is
// only visible when no window is open, which is exactly when nobody needs
// it, and the bar is above every window. That figure was the last reader of
// the shared component that spoke to the compositor: a socket and three
// `hyprctl` processes per bar instance per screen, kept alive to elide one
// glyph into a fixed box. With the figure gone there was no reader left, so
// the component was deleted in plan 055 — its `qmldir` entry and the shared
// directory import with it. The figure is one bar placement away if it is
// wanted: the first-party `omarchy.workspaces` widget draws the numbers,
// dims the unoccupied ones and focuses a workspace on click.
//
// The focused window used to share this entry, as a class column beside the
// workspace. It left in plan 054 — the operator's report was that the entry
// is long, and the window name was the length — and is a bar widget of its
// own (`t1nk33r.window-title`), which is also where the title now lives.
// Nothing here reads a class, a title or a workspace any more.
//
// Everything the panel does goes through the service's own Store and
// WidgetRegistry (`bar.shell.serviceFor(moduleName)` — the t1nk33r.omarr
// pattern), so it is the same single writer the IPC surface and Placement
// use; nothing here touches nothing-glass.json directly. Plugin-wide settings
// go through `Service`'s `option` verb — the same writer the IPC surface and
// the browser's Appearance pane use, and the only one that reaches the durable
// options file. NOT `bar.shell.updateEntryInline` on this plugin's shell.json
// entry: that is the copy GlassSurface's merge deliberately overrides, so a
// write there moves nothing on screen. See setPluginSetting() below.
// It draws both the Liquid Glass and the
// Nothing style, and which one a given widget gets is chosen on the widget
// or on its category in the browser, not here.
//
// No `plasmoid`/`theme`/`backdrop` shims here: the bar loads this file, not
// WidgetHost, and injects only bar/moduleName/settings.
BarWidget {
  id: root
  PluginId { id: identity }

  moduleName: identity.id

  property bool popupOpen: false

  // Popout lifecycle the bar coordinator expects on the owner item
  // (Ui/PopupCard.qml close(), plugins/bar/Bar.qml:316-322, :412, :509).
  readonly property bool opened: popupOpen
  function open() { root._resolveService(); root.popupOpen = true }
  function close() { root.popupOpen = false }
  function toggle() { if (!root.popupOpen) root._resolveService(); root.popupOpen = !root.popupOpen }

  // Empty screen name = the focused monitor, which is what Service.launcher
  // does with it. Prefer the in-process call when this entry is un-placed and
  // the service is reachable; otherwise the CLI, which reaches the same
  // IpcHandler from outside.
  function openLauncher() {
    root._resolveService()
    root.popupOpen = false
    if (root.service && typeof root.service.toggleLauncher === "function") {
      root.service.toggleLauncher("")
      return
    }
    Quickshell.execDetached(["/usr/share/omarchy/bin/omarchy-shell", root.moduleName, "launcher", ""])
  }

  // `serviceFor()` is a plain function on the shell, not a bound property, so
  // asking it once is asking it at exactly the wrong moment: when the plugin
  // entry sits in `bar.layout` this widget is constructed during bar startup,
  // often BEFORE Service.qml exists, and a one-shot binding then holds null
  // for the rest of the session - the panel opens and says "The Liquid Glass
  // service is not loaded" while the service is up and answering IPC.
  // Observed on this machine 2026-09-09, after the entry went back into the
  // bar layout.
  //
  // So it is re-asked: on completion, whenever the id changes, every half
  // second until it resolves, and again each time the panel is opened. The
  // probe stops itself the moment it has an answer.
  property var service: null

  function _resolveService() {
    var s = (bar && bar.shell && typeof bar.shell.serviceFor === "function" && root.moduleName !== "")
      ? bar.shell.serviceFor(root.moduleName) : null
    if (s !== root.service) root.service = s
    return root.service
  }

  Component.onCompleted: root._resolveService()
  onModuleNameChanged: root._resolveService()

  // Bounded, not forever: when the plugin's entry is PLACED in the bar
  // layout the shell hands this widget `pluginShellForBarEntry`, a facade
  // built with `_summon/_hide/_toggle/_isOpen/_updateSettings` and NO
  // `_serviceLookup` (shell.qml:706-729), so `serviceFor()` is null by
  // construction and will never become anything else. Retrying twice a second
  // for the life of the session would just be a heartbeat with no pulse.
  // Ten tries covers the un-placed case, where the service is reachable but
  // may not exist yet at bar-startup time.
  property int _serviceTries: 0

  Timer {
    interval: 500
    repeat: true
    running: root.service === null && root._serviceTries < 10
    triggeredOnStart: true
    onTriggered: {
      root._serviceTries++
      root._resolveService()
    }
  }
  readonly property var store: service ? service.widgetStore : null
  readonly property var registry: service ? service.widgetRegistry : null
  readonly property var widgets: store && store.widgets ? store.widgets : []

  readonly property color fg: bar ? bar.barForeground : Color.foreground
  readonly property color popupFg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.rgba(popupFg.r, popupFg.g, popupFg.b, 0.55)
  readonly property string family: bar ? bar.fontFamily : Style.font.family

  // Plugin-wide settings, as the DESKTOP reads them: Options.qml's durable file
  // (`~/.config/omarchy/<storeName>-options.json`), which GlassSurface's merge
  // applies LAST and therefore wins over this plugin's shell.json entry. The
  // path is derived from `identity.storeName` exactly as Options.path is —
  // identity, never a literal, so a rename moves both together.
  readonly property string _optionsPath:
    Quickshell.env("HOME") + "/.config/omarchy/" + identity.storeName + "-options.json"

  // {} until the file loads, and {} again if it is missing or half-written.
  // Deliberately no `loading` gate: the injected entry below covers the first
  // moments, so an empty map just means "the entry is still the best answer".
  property var _optionValues: ({})

  // Watched, like Options._file: a write from any other process — the browser,
  // the IPC verb, this panel's own shell-out — reaches the highlight without a
  // restart. Guarded parse: an unreadable or unparseable file falls back, and
  // never throws.
  property FileView _optionsFile: FileView {
    id: optionsFile
    path: root._optionsPath
    watchChanges: true
    printErrors: false

    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        root._optionValues = (parsed && typeof parsed.options === "object" && parsed.options !== null)
          ? parsed.options : {}
      } catch (e) {
        root._optionValues = ({})
      }
    }
    onLoadFailed: root._optionValues = ({})
    onFileChanged: reload()
  }

  // How the glass itself draws — translucent or opaque, macOS palette or
  // Omarchy theme. Read from the durable file, because that is the copy the
  // widgets render; the injected bar entry (this plugin's ONE shell.json entry
  // — CONVENTIONS.md, "A dual-kind plugin has exactly ONE entry") is only the
  // fallback for the moment before the file loads, and for a key no writer has
  // put in the file yet. Coerced the same way GlassSurface does, since
  // `omarchy bar set` stores strings.
  readonly property int styleMode: {
    var raw = Object.prototype.hasOwnProperty.call(root._optionValues, "styleMode")
      ? root._optionValues["styleMode"]
      : root.setting("styleMode", 0)
    var v = Number(raw)
    return (v === 1 || v === 2 || v === 3) ? v : 0
  }

  // Mirrors manifest.json's styleMode enum. Kept here rather than read from
  // the manifest because the bar widget is handed `settings`, not the
  // manifest, and this is the one place the labels are shown.
  readonly property var styleModes: [
    { value: 0, label: "Glass",  description: "Refracts the wallpaper, macOS palette" },
    { value: 1, label: "Solid",  description: "Opaque, macOS palette" },
    { value: 3, label: "Glass (theme)", description: "Refracts the wallpaper, coloured by the Omarchy theme" },
    { value: 2, label: "Solid (theme)", description: "Opaque, coloured by the Omarchy theme" }
  ]

  // A plugin-wide setting has to land in the copy the desktop RENDERS, and
  // that is not this plugin's shell.json entry. GlassSurface's merge applies
  // the Options file LAST (it may relocate its own entry and drop what was on
  // it — measured), so writing `bar.shell.updateEntryInline` here changed a
  // value nothing reads: the button highlighted, the widgets did not move —
  // the original "changing from solid to glass does nothing" report, still
  // there once the same key had been written from anywhere else.
  //
  // So go through the route everything else uses: `Service`'s `option` verb,
  // which reaches GlassSurface.setPluginSetting and with it the durable file.
  // In process through the service's own forwarder when it resolves; otherwise
  // the CLI, which reaches that same IpcHandler from outside — the shape
  // openLauncher() above already uses. The shell-out is the COMMON branch, not
  // the edge: a PLACED bar entry is handed a facade with no `_serviceLookup`,
  // so `service` is null in exactly the state where this panel is visible
  // (PORTING.md item 28).
  function setPluginSetting(key, value) {
    root._resolveService()
    if (root.service && typeof root.service.setPluginSetting === "function") {
      root.service.setPluginSetting(String(key), value)
      return
    }
    // argv is strings and the verb coerces bare words and numbers itself
    // (`option` in Service.qml), so pass the value spelled out.
    Quickshell.execDetached(["/usr/share/omarchy/bin/omarchy-shell", root.moduleName,
                             "option", String(key), String(value)])
  }

  // A PLACED entry is handed a facade with no `_serviceLookup`, so `store`
  // above is null in exactly the state this panel is normally in (item 28) -
  // but the IPC target belongs to the SERVICE, which exists while the plugin
  // is enabled whether or not its entry is on the bar (plan 021, measured).
  property var ipcWidgets: []
  property string ipcError: ""

  // One read, on demand. NOT a timer: a binding that re-asks on an interval is
  // the heartbeat item 28 forbids.
  function refreshFromIpc() {
    if (!root._listProc.running) root._listProc.running = true
  }

  property Process _listProc: Process {
    id: listProc
    running: false
    command: ["/usr/share/omarchy/bin/omarchy-shell", root.moduleName, "listWidgets"]
    stdout: StdioCollector {
      // Emit once, on a complete stream, so the handler cannot parse half a
      // document.
      waitForEnd: true
      onStreamFinished: root._applyIpcList(String(this.text || ""))
    }
    onExited: function (exitCode) {
      // The CLI prints only on success and exits 1 on everything else. Order
      // against onStreamFinished is not depended on: an empty stream sets the
      // same error, and a good read exits 0.
      if (exitCode !== 0 && root.ipcError === "")
        root.ipcError = "the service did not answer"
    }
  }

  // Parse, or keep the last good list: this runs in a signal handler, where a
  // throw would take the panel's other bindings with it.
  function _applyIpcList(text) {
    var raw = String(text).trim()
    if (raw === "") return
    var parsed = null
    try { parsed = JSON.parse(raw) } catch (e) { parsed = null }
    if (!parsed || !Array.isArray(parsed)) {
      root.ipcError = "the reply was not a widget list"
      return
    }
    var out = []
    for (var i = 0; i < parsed.length; i++) {
      var w = parsed[i]
      if (!w || typeof w !== "object" || !w.id) continue
      out.push(w)
    }
    root.ipcWidgets = out
    root.ipcError = ""
  }

  // Every action goes out through here, so the binary path and the verb
  // spelling live in one place.
  function _ipcCall(verb, args) {
    Quickshell.execDetached(["/usr/share/omarchy/bin/omarchy-shell",
                             root.moduleName, String(verb)].concat(args))
  }

  // Widget types worth offering. `placeholder` and `test-glass` are runtime
  // scaffolding, `test-timer` is a dev tile; everything else is a real widget.
  readonly property var addableTypes: {
    var all = registry ? registry.listTypes() : []
    var hide = { placeholder: true, "test-glass": true, "test-timer": true }
    return all.filter(function (t) { return !hide[t] })
  }
  readonly property var screenNames: Quickshell.screens.map(function (s) { return s.name })

  property string addType: ""
  property string addScreen: ""

  function addWidget() {
    if (!store || !registry) return
    var type = root.addType || (root.addableTypes.length ? root.addableTypes[0] : "")
    var screen = root.addScreen || (root.screenNames.length ? root.screenNames[0] : "")
    if (!type || !screen || !registry.hasType(type)) return
    // New tiles arrive as the type's smallest grid size, like a fresh
    // home-screen widget - not the old hard-coded 300².
    var size = registry.defaultSize(type)
    store.add(type, screen, { w: size.width, h: size.height })
  }

  function removeWidget(id) {
    if (store) { store.remove(id); return }
    // The store path is optimistic; this one cannot be, so the list is
    // re-read. One process per click, never on a timer.
    root._ipcCall("remove", [String(id)])
    root.refreshFromIpc()
  }

  // Per-instance settings the panel edits. The field table itself lives in
  // WidgetFields.qml because the desktop edits the same keys - the right-click
  // sheet (WidgetSettingsWindow) and the browser's inspector - and the three
  // must not drift apart.
  WidgetFields { id: fieldModel }

  function editableFields(type) {
    return fieldModel.forType(type)
  }

  // Effective value for a field: the instance override if present, else the
  // plugin-wide value from this bar entry, else the manifest default (the
  // same precedence GlassSurface._mergedSettings applies to the tile).
  // The bar entry only carries keys the settings UI has written, so a key
  // added to the manifest after the plugin was placed is absent from it.
  // (The desktop sheet reads plugin.settings instead, which is that
  // merge already done - the bar widget has no access to it.)
  function effectiveValue(entry, key) {
    if (fieldModel.isOverridden(entry, key)) return String(entry.settings[key])
    var v = root.setting(key, undefined)
    if (v === undefined || v === null) {
      var m = service && service.manifest && service.manifest.settings
      var d = m && m.defaults ? m.defaults[key] : undefined
      v = d
    }
    return v === undefined || v === null ? "" : String(v)
  }

  function isOverridden(entry, key) {
    return fieldModel.isOverridden(entry, key)
  }

  // Save one field: empty text clears the override (plugin-wide applies
  // again); numbers are stored as numbers so the widgets' strict comparisons
  // keep working.
  function saveField(id, field, text) {
    fieldModel.save(store, id, field, text)
  }

  // Geometry, typed. The grip on the widget is a mouse gesture; this is the
  // exact-value path (and the only one that works when the widget sits on a
  // monitor that is currently off). Clamped to the type's registry minimum
  // and to the screen, the same bounds Placement.qml enforces on a drag.
  function screenSize(name) {
    var list = Quickshell.screens || []
    for (var i = 0; i < list.length; i++)
      if (String(list[i].name) === String(name))
        return { width: list[i].width, height: list[i].height }
    return null
  }


  function savePosition(entry, xText, yText) {
    var x = Math.round(Number(xText)), y = Math.round(Number(yText))
    if (isNaN(x) || isNaN(y)) return
    var scr = root.screenSize(entry.screen)
    if (scr) {
      x = Math.min(Math.max(0, x), Math.max(0, scr.width - entry.w))
      y = Math.min(Math.max(0, y), Math.max(0, scr.height - entry.h))
    } else {
      x = Math.max(0, x)
      y = Math.max(0, y)
    }
    if (store) { store.move(entry.id, x, y); return }
    // Placed there is no store to be optimistic against, so the list is
    // re-read after the verb - one process per click, never on a timer.
    root._ipcCall("move", [String(entry.id), x, y])
    root.refreshFromIpc()
  }

  property string editingId: ""

  // PanelKeyCatcher runs Keys.priority: BeforeItem, so it would eat the digits
  // and arrows an editor field needs. It has to be blocked for exactly as long
  // as SOME field holds focus, and focus moves field-to-field (the losing
  // field's false arrives after the winner's true), so this is a count, not a
  // bool.
  property int _focusCount: 0
  readonly property bool editorFocused: _focusCount > 0
  function noteFocus(on) {
    root._focusCount = Math.max(0, root._focusCount + (on ? 1 : -1))
  }

  // Nudge an instance back on screen: a widget dragged/resized off a
  // now-disconnected monitor is otherwise unreachable without the IPC.
  // Reset = back onto the grid at its first VISIBLE cell (below the bar, see
  // ScreenInsets.qml - the widget surface ignores exclusive zones, so
  // 16,16 used to land underneath it), at the type's small size.
  ScreenInsets { id: screenInsets }

  function resetWidget(id) {
    if (!store || !registry) return
    var entry = null
    for (var i = 0; i < root.widgets.length; i++)
      if (String(root.widgets[i].id) === String(id)) entry = root.widgets[i]
    var size = registry.defaultSize(entry ? entry.type : "")
    screenInsets.refresh()
    var inset = screenInsets.forScreen(entry ? entry.screen : "")
    store.move(id, registry.originX(inset.left), registry.originY(inset.top))
    store.resize(id, size.width, size.height)
  }

  function setSize(entry, preset) {
    if (!store || !preset) return
    store.resize(entry.id, preset.width, preset.height)
  }

  // Keybindable and scriptable. Separate target from the service's
  // "t1nk33r.nothing-glass" — the shell refuses a second handler on a target.
  //
  // The bar instantiates one of these per monitor, and every instance would
  // claim the same target: the second one onward logs "Handler was
  // registered but will not be used". Only the instance on the first screen
  // registers; `broadcast()` reaches the others anyway (it walks
  // bar.shell's widgets), so the single handler still toggles every bar.
  readonly property bool _ipcOwner: {
    var screens = Quickshell.screens
    if (!screens || !screens.length) return true
    var win = root.QsWindow ? root.QsWindow.window : null
    if (!win || !win.screen) return true
    return String(win.screen.name) === String(screens[0].name)
  }

  IpcHandler {
    target: identity.id + "-panel"
    enabled: root._ipcOwner
    function toggle(): void { root.broadcast("toggle") }
    function open(): void { root.broadcast("open") }
    function close(): void { root.broadcast("close") }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: button.implicitWidth
    bar: root.bar
    active: root.popupOpen
    // identity.label, never a literal: the plugin's name lives in PluginId
    // and nowhere else, so the bar icon, the panel header and this tooltip
    // cannot drift apart.
    tooltipText: (root.service
      ? identity.label + " — " + root.widgets.length + (root.widgets.length === 1 ? " widget" : " widgets")
      : identity.label)
      + "\nClick to browse widgets · right-click for glass or solid"
    // The tooltip's first line, and nothing more: a name is what a reader
    // announces, not a set of instructions. Pressing the control does what
    // the left click does.
    Accessible.role: Accessible.Button
    Accessible.name: root.service
      ? identity.label + " — " + root.widgets.length + (root.widgets.length === 1 ? " widget" : " widgets")
      : identity.label
    Accessible.onPressAction: root.openLauncher()
    // A squircle-in-a-squircle, drawn as shapes: the bar's font is remapped by
    // fontconfig and glyph icons are not reliable here (plan 008 finding).
    iconComponent: Component {
      Item {
        Rectangle {
          anchors.centerIn: parent
          width: parent.width * 0.9
          height: width
          radius: width * 0.3
          color: "transparent"
          border.width: Math.max(1, Math.round(width * 0.11))
          border.color: root.popupOpen ? (root.bar ? root.bar.urgent : Color.accent) : root.fg
          Behavior on border.color { ColorAnimation { duration: 160 } }
        }
        Rectangle {
          anchors.centerIn: parent
          width: parent.width * 0.38
          height: width
          radius: width * 0.3
          color: root.popupOpen ? (root.bar ? root.bar.urgent : Color.accent) : root.fg
          Behavior on color { ColorAnimation { duration: 160 } }
        }
      }
    }
    // Left click opens the WIDGET BROWSER, which is the thing a person
    // wants from this icon: the catalogue, the live previews, the
    // per-category style and both styles' knobs. It used to open the panel
    // instead, and a placed bar entry gets a facade with no service
    // (shell.qml:706-729), so that panel could not reach the widget list and
    // the icon effectively did nothing.
    //
    // With no service to call, shell out to the shell's own CLI - the same
    // command the panel used to print at the user. It is a real, supported
    // entry point (`omarchy-shell <plugin> launcher <screen>`), not a guess.
    // Right click still opens the panel, which keeps the one control that
    // lives nowhere else: Glass or Solid.
    onPressed: function (buttonCode) {
      // Anything that is not explicitly right or middle counts as left, so a
      // button enum that does not arrive as expected still opens the browser
      // rather than doing nothing - which is the failure this whole change
      // exists to fix.
      if (buttonCode === Qt.RightButton || buttonCode === Qt.MiddleButton) root.toggle()
      else root.openLauncher()
    }
  }

  // KeyboardPanel, not PopupCard: the per-widget editor has text fields, and
  // an xdg-popup never receives keys here without a click routing focus
  // through its parent surface (Ui/KeyboardPanel.qml's header).
  KeyboardPanel {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(440))
    contentHeight: popup.fittedContentHeight(content.implicitHeight)

    onOpenChanged: {
      if (!open) { root.editingId = ""; root._focusCount = 0 }
      else if (root.service === null) root.refreshFromIpc()
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // While a text field has focus every key goes to it; otherwise Esc
      // closes the panel.
      blocked: root.editorFocused
      onCloseRequested: root.close()

    Column {
      id: content
      anchors.fill: parent
      spacing: Style.space(10)

      // ── Header ──────────────────────────────────────────────────────
      Column {
        width: parent.width
        spacing: Style.space(2)
        Text {
          textFormat: Text.PlainText
          text: identity.label
          color: root.popupFg
          font.family: root.family
          font.pixelSize: Style.font.title
          font.weight: Font.DemiBold
        }
        Text {
          textFormat: Text.PlainText
          // Both sources say the same thing: un-placed the count is the
          // store's, placed it is the IPC read's. Zero (and not-read-yet)
          // say nothing rather than "service not running", which reads as a
          // fault when the plugin is working.
          text: {
            var n = root.service ? root.widgets.length : root.ipcWidgets.length
            if (!n) return ""
            return n + (n === 1 ? " widget" : " widgets") + " on the desktop"
          }
          color: root.dim
          font.family: root.family
          font.pixelSize: Style.font.caption
        }
      }

      // ── Glass ───────────────────────────────────────────────────────
      // How the glass itself draws: four combinations of translucency and
      // palette, plugin-wide. This is NOT the Liquid Glass/Nothing choice —
      // that one is per widget, or per category, and lives in the browser's
      // Appearance pane, which is also the only place the categories are
      // listed.
      PanelSectionHeader { text: "GLASS OR SOLID"; foreground: root.dim; fontFamily: root.family }

      Row {
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: root.styleModes

          Button {
            required property var modelData
            text: modelData.label
            tooltipText: modelData.description
            active: root.styleMode === modelData.value
            bordered: root.styleMode !== modelData.value
            foreground: root.popupFg
            fontFamily: root.family
            fontSize: Style.font.caption
            onClicked: root.setPluginSetting("styleMode", modelData.value)
          }
        }
      }

      PanelSeparator { width: parent.width; foreground: root.popupFg }

      // ── Widgets ───────────────────────────────────────────────────────
      PanelSectionHeader { text: "WIDGETS"; foreground: root.dim; fontFamily: root.family }

      Row {
        width: parent.width
        spacing: Style.space(6)

        Button {
          id: browseBtn
          width: refreshBtn.visible ? parent.width - refreshBtn.width - parent.spacing : parent.width
          text: "Browse widgets…"
          bordered: true
          foreground: root.popupFg
          fontFamily: root.family
          onClicked: root.openLauncher()
        }

        // Placed, the count above and the list below come from the IPC read,
        // so there is a way to ask for it again without closing the panel.
        // Un-placed the store is live and needs no button.
        Button {
          id: refreshBtn
          visible: root.service === null
          text: "Refresh"
          bordered: true
          foreground: root.popupFg
          fontFamily: root.family
          fontSize: Style.font.caption
          onClicked: root.refreshFromIpc()
        }
      }

      // When the entry is PLACED in the bar, the shell hands this widget a
      // facade built with no `_serviceLookup` (shell.qml:706-729). That no
      // longer hides the list — it goes over the plugin's own IPC verbs — so
      // this line is now only the honest end of the road: the command that
      // opens the browser, printed when the IPC did not answer either.
      Text {
        textFormat: Text.PlainText
        width: parent.width
        visible: root.service === null && root.ipcError !== ""
        text: "omarchy-shell " + root.moduleName + " launcher ''"
        color: root.dim
        font.pixelSize: Style.font.caption
        font.family: root.family
        elide: Text.ElideRight
      }

      PanelSeparator { width: parent.width; foreground: root.popupFg }

      // ── Add ───────────────────────────────────────────────────────────
      PanelSectionHeader { text: "ADD A WIDGET"; foreground: root.dim; fontFamily: root.family
                           visible: root.service !== null }

      Row {
        width: parent.width
        spacing: Style.space(6)
        visible: root.service !== null

        Dropdown {
          id: typePick
          width: Math.round((parent.width - addBtn.width - parent.spacing * 2) * 0.58)
          showLabel: false
          foreground: root.popupFg
          fontFamily: root.family
          options: root.addableTypes
          value: root.addType || (root.addableTypes.length ? root.addableTypes[0] : "")
          onChanged: function (v) { root.addType = v }
        }
        Dropdown {
          id: screenPick
          width: parent.width - typePick.width - addBtn.width - parent.spacing * 2
          showLabel: false
          foreground: root.popupFg
          fontFamily: root.family
          options: root.screenNames
          value: root.addScreen || (root.screenNames.length ? root.screenNames[0] : "")
          onChanged: function (v) { root.addScreen = v }
        }
        Button {
          id: addBtn
          text: "Add"
          bordered: true
          foreground: root.popupFg
          fontFamily: root.family
          enabled: root.store !== null && root.addableTypes.length > 0
          onClicked: root.addWidget()
        }
      }

      PanelSeparator { width: parent.width; foreground: root.popupFg }

      // ── Instances ─────────────────────────────────────────────────────
      PanelSectionHeader { text: "ON THE DESKTOP"; foreground: root.dim; fontFamily: root.family
                           visible: root.service !== null || root.ipcWidgets.length > 0 }

      Text {
        textFormat: Text.PlainText
        // The empty state, speaking for whichever source is live.
        visible: root.service ? root.widgets.length === 0
                              : root.ipcWidgets.length === 0
        width: parent.width
        text: root.service
          ? "Nothing yet — add one above."
          : (root._listProc.running
              ? "Reading the widget list…"
              : (root.ipcError !== ""
                  ? "Can't read the widget list: " + root.ipcError + "."
                  : "Nothing on the desktop yet."))
        color: root.dim
        font.family: root.family
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
      }

      Column {
        width: parent.width
        spacing: Style.space(4)
        visible: root.service !== null || root.ipcWidgets.length > 0

        Repeater {
          model: root.service ? root.widgets : root.ipcWidgets

          Column {
            id: instanceRow
            required property var modelData
            readonly property bool offScreen: root.screenNames.indexOf(String(modelData.screen)) === -1
            readonly property var fields: root.editableFields(String(modelData.type))
            readonly property bool editing: root.editingId === String(modelData.id)

            width: parent.width
            spacing: Style.space(4)

            Item {
            width: parent.width
            height: Math.max(rowLeft.implicitHeight, rowRight.implicitHeight) + Style.space(8)

            // The row whose editor is open, marked the same way over either
            // source - bold title plus this rule - so the expanded block
            // below is never ambiguous. The gutter is always reserved, so
            // nothing shifts when the marker appears.
            Rectangle {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: 2
              visible: instanceRow.editing
              color: root.dim
            }

            Column {
              id: rowLeft
              anchors.left: parent.left
              anchors.leftMargin: Style.space(6)
              anchors.right: rowRight.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Text {
                textFormat: Text.PlainText
                width: parent.width
                elide: Text.ElideRight
                text: modelData.type + "  ·  " + modelData.id
                color: root.popupFg
                font.family: root.family
                font.pixelSize: Style.font.body
                font.weight: instanceRow.editing ? Font.DemiBold : Font.Normal
              }
              Text {
                textFormat: Text.PlainText
                width: parent.width
                elide: Text.ElideRight
                text: modelData.screen + (offScreen ? " (not connected)" : "")
                  + "  ·  " + modelData.x + "," + modelData.y + "  " + modelData.w + "×" + modelData.h
                color: offScreen ? (root.bar ? root.bar.urgent : Color.urgent) : root.dim
                font.family: root.family
                font.pixelSize: Style.font.caption
              }
            }

            Row {
              id: rowRight
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              Button {
                text: instanceRow.editing ? "Done" : "Edit"
                active: instanceRow.editing
                tooltipText: instanceRow.editing ? "Close the editor" : "Settings for this widget only"
                foreground: root.popupFg
                fontFamily: root.family
                fontSize: Style.font.caption
                onClicked: root.editingId = instanceRow.editing ? "" : String(modelData.id)
              }
              Button {
                text: "Reset"
                tooltipText: "Move to the first grid cell, at this type's default size"
                foreground: root.popupFg
                fontFamily: root.family
                fontSize: Style.font.caption
                onClicked: root.resetWidget(modelData.id)
              }
              Button {
                text: "Remove"
                bordered: true
                foreground: root.bar ? root.bar.urgent : Color.urgent
                fontFamily: root.family
                fontSize: Style.font.caption
                onClicked: root.removeWidget(modelData.id)
              }
            }
            }

            // -- Inline per-widget editor ---------------------------------
            Column {
              visible: instanceRow.editing
              width: parent.width
              spacing: Style.space(6)

              // -- Size: the type's grid presets, not free pixels ---------
              // Needs `registry.sizes()`, which only the service has, so it
              // stays un-placed-only (deferred, see PORTING item 32).
              Row {
                width: parent.width
                spacing: Style.space(6)
                visible: instanceRow.editing && root.service !== null

                Text {
                  textFormat: Text.PlainText
                  width: Style.space(76)
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Size"
                  color: root.popupFg
                  font.family: root.family
                  font.pixelSize: Style.font.caption
                }

                Repeater {
                  model: instanceRow.editing && root.registry
                    ? root.registry.sizes(String(instanceRow.modelData.type)) : []

                  Button {
                    required property var modelData
                    readonly property bool current:
                      Number(instanceRow.modelData.w) === modelData.width
                      && Number(instanceRow.modelData.h) === modelData.height
                    text: modelData.label
                    tooltipText: modelData.width + "×" + modelData.height
                    active: current
                    bordered: !current
                    foreground: root.popupFg
                    fontFamily: root.family
                    fontSize: Style.font.caption
                    onClicked: root.setSize(instanceRow.modelData, modelData)
                  }
                }
              }

              // -- Position: still exact pixels ---------------------------
              Repeater {
                model: instanceRow.editing
                  ? [{ label: "Position", a: "x", b: "y", unitA: "X", unitB: "Y" }]
                  : []

                Row {
                  id: geomRow
                  required property var modelData
                  readonly property var spec: modelData
                  readonly property bool isSize: spec.a === "w"
                  width: parent.width
                  spacing: Style.space(6)

                  Text {
                    textFormat: Text.PlainText
                    width: Style.space(76)
                    anchors.verticalCenter: parent.verticalCenter
                    text: geomRow.spec.label
                    color: root.popupFg
                    font.family: root.family
                    font.pixelSize: Style.font.caption
                  }
                  // NumberField.value is an INPUT bound to the store row; a
                  // typed/stepped edit arrives as modified(v) and leaves the
                  // binding alone, so the pending value is held here and the
                  // field re-seeds itself whenever the row changes (a drag on
                  // the desktop updates the panel live).
                  property int pendingA: Number(instanceRow.modelData[geomRow.spec.a]) || 0
                  property int pendingB: Number(instanceRow.modelData[geomRow.spec.b]) || 0

                  NumberField {
                    id: fieldA
                    anchors.verticalCenter: parent.verticalCenter
                    from: 0
                    to: 99999
                    stepSize: 8
                    label: geomRow.spec.unitA
                    value: geomRow.pendingA
                    foreground: root.popupFg
                    fontFamily: root.family
                    fontSize: Style.font.caption
                    onModified: function (v) { geomRow.pendingA = v }
                    Connections {
                      target: fieldA.field
                      function onActiveFocusChanged() { root.noteFocus(fieldA.field.activeFocus) }
                    }
                  }
                  NumberField {
                    id: fieldB
                    anchors.verticalCenter: parent.verticalCenter
                    from: 0
                    to: 99999
                    stepSize: 8
                    label: geomRow.spec.unitB
                    value: geomRow.pendingB
                    foreground: root.popupFg
                    fontFamily: root.family
                    fontSize: Style.font.caption
                    onModified: function (v) { geomRow.pendingB = v }
                    Connections {
                      target: fieldB.field
                      function onActiveFocusChanged() { root.noteFocus(fieldB.field.activeFocus) }
                    }
                  }
                  Button {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Apply"
                    bordered: true
                    foreground: root.popupFg
                    fontFamily: root.family
                    fontSize: Style.font.caption
                    onClicked: geomRow.isSize
                      ? root.saveSize(instanceRow.modelData, geomRow.pendingA, geomRow.pendingB)
                      : root.savePosition(instanceRow.modelData, geomRow.pendingA, geomRow.pendingB)
                  }
                }
              }

              Text {
                textFormat: Text.PlainText
                visible: root.service !== null
                width: parent.width
                text: {
                  var g = root.registry
                  if (!g) return ""
                  return "Three tile sizes on an " + g.gridCell + " px grid (" + g.gridGap
                    + " px gutter). Dragging the widget's corner steps through the same "
                    + "sizes; dragging the widget snaps it onto the grid. Position is exact."
                }
                color: root.dim
                font.family: root.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              // Needs `WidgetFields.save`, which writes through a Store, and
              // clearing a field must REMOVE the override - `set` cannot do
              // that, so this stays un-placed-only too (deferred, item 32).
              Repeater {
                model: instanceRow.editing && root.service !== null ? instanceRow.fields : []

                Column {
                  id: fieldRow
                  required property var modelData
                  readonly property var field: modelData
                  readonly property bool overridden: root.isOverridden(instanceRow.modelData, field.key)
                  width: parent.width
                  spacing: Style.space(2)

                  Row {
                    width: parent.width
                    spacing: Style.space(6)
                    Text {
                      textFormat: Text.PlainText
                      width: Style.space(76)
                      anchors.verticalCenter: parent.verticalCenter
                      text: fieldRow.field.label
                      color: fieldRow.overridden ? root.popupFg : root.dim
                      font.family: root.family
                      font.pixelSize: Style.font.caption
                      font.weight: fieldRow.overridden ? Font.DemiBold : Font.Normal
                    }
                    // A boolean gets a switch, not a field to type "true" in.
                    ToggleSwitch {
                      visible: fieldRow.field.kind === "bool"
                      anchors.verticalCenter: parent.verticalCenter
                      checked: fieldModel.isTrue(
                        root.effectiveValue(instanceRow.modelData, fieldRow.field.key))
                      foreground: root.popupFg
                      onToggled: fieldModel.save(root.store, instanceRow.modelData.id,
                                                 fieldRow.field, !checked)
                    }
                    TextField {
                      visible: fieldRow.field.kind !== "bool"
                      id: fieldInput
                      width: parent.width - Style.space(76) - saveBtn.width - parent.spacing * 2
                      foreground: root.popupFg
                      text: root.effectiveValue(instanceRow.modelData, fieldRow.field.key)
                      placeholderText: fieldRow.field.hint
                      font.family: root.family
                      font.pixelSize: Style.font.body
                      onActiveFocusChanged: root.noteFocus(activeFocus)
                      onAccepted: root.saveField(instanceRow.modelData.id, fieldRow.field, text)
                    }
                    Button {
                      id: saveBtn
                      visible: fieldRow.field.kind !== "bool"
                      anchors.verticalCenter: parent.verticalCenter
                      text: "Save"
                      bordered: true
                      foreground: root.popupFg
                      fontFamily: root.family
                      fontSize: Style.font.caption
                      onClicked: root.saveField(instanceRow.modelData.id, fieldRow.field, fieldInput.text)
                    }
                  }
                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: fieldRow.overridden
                      ? "Set for this widget only. Clear the field and Save to follow the plugin-wide value again."
                      : fieldRow.field.hint
                    color: root.dim
                    font.family: root.family
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }
                }
              }
            }
          }
        }
      }

    }
    }
  }
}
