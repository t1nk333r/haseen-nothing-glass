import QtQuick
import Quickshell
import Quickshell.Hyprland

// The widget browser's surface: a real toplevel window the shell summons.
//
// It used to live inside the per-screen widget surface (GlassSurface.qml) as a
// full-screen layer-shell overlay. A layer surface is not a window Hyprland
// can rule, so the browser could not be floated, sized or centred by the
// compositor, and an Overlay layer with exclusive keyboard took the desktop
// away while it was up. This file is manifest.json's `panel` entry point: the
// shell loads it once per summon (shell.qml's panel Instantiator) and hands it
// `shell`, `manifest` and `service`; `open(payloadJson)`/`close()` are the
// lifecycle the loader calls. Nothing visual comes from the shell - a plugin
// that wants a window makes its own, which is what the FloatingWindow below
// is, the same shape t1nk33r.settings and omarchy.dev-gallery use.
//
// Two consequences worth stating, because they are why this file exists at
// all rather than an instance in each screen's Scope:
//
//   * One instance, not one per screen. The browser is a window (one head),
//     and which desktop it acts on is a value resolved at open time, not a
//     second window that then has to be told which one to show.
//   * It reads the store, the registry and the settings from `service` - this
//     plugin's service singleton, injected because the manifest also declares
//     the `service` kind. GlassSurface's per-screen values are reachable only
//     from GlassSurface, so the surface exposes them through Service.qml
//     (widgetStore/widgetRegistry/widgetSettings/widgetTheme and the three
//     style functions); there is still exactly one store and one style
//     precedence.
Item {
  id: root

  // ── Host injections (shell.qml's panel loader) ─────────────────────
  property var shell: null
  property var manifest: null
  property var service: null

  readonly property string pluginId: identity.id

  PluginId { id: identity }

  // True only while the shell is the one closing the window. Its own
  // `close()` fires the FloatingWindow's onVisibleChanged too, and without
  // this the plugin would tell the shell to hide a panel the shell is already
  // hiding - harmless, but it makes an honest compositor-initiated close
  // indistinguishable from an echo. GalleryPanel.qml's flag, same reason.
  property bool closingFromHost: false

  // Which desktop this summon is for: where a widget the browser adds lands,
  // and whose reserved edges the settings pane resets against. Resolved in
  // open(), never injected at construction - the shell loads this file once,
  // before any summon names a screen.
  property string screenName: ""

  // The monitor the user is looking at when "" arrives: the bar icon and the
  // plain `launcher ''` verb both mean "here". Guessing the first monitor
  // opened the sheet on the wrong head of a two-monitor desk, which is why
  // Hyprland is asked rather than assumed; the first Quickshell screen is the
  // fallback for a compositor that cannot answer.
  function resolveScreen(requested) {
    var wanted = String(requested || "")
    if (wanted !== "") return wanted
    var mon = Hyprland.focusedMonitor
    if (mon && String(mon.name || "") !== "") return String(mon.name)
    var screens = Quickshell.screens || []
    return screens.length > 0 ? String(screens[0].name || "") : ""
  }

  // Called by the shell when this panel is summoned. The payload is optional:
  // `{"screen":"HDMI-A-1"}` picks the desktop, `{"widget":"<id>"}` opens on
  // that widget with its settings beside it (the right-click sheet's "open in
  // browser" control), and "" is the plain "open it here".
  function open(payloadJson) {
    root.closingFromHost = false
    var payload = null
    try { payload = payloadJson ? JSON.parse(String(payloadJson)) : null } catch (e) { payload = null }
    if (!payload || typeof payload !== "object") payload = null

    root.screenName = root.resolveScreen(payload ? payload.screen : "")

    var widget = payload && payload.widget ? String(payload.widget) : ""
    if (widget !== "") launcher.openForWidget(widget)
    else launcher.inspecting = ""

    window.visible = true
    // The window is mapped by the compositor; the key-catcher only becomes the
    // active focus item a frame later.
    Qt.callLater(launcher.takeFocus)
  }

  // Host-initiated close (`shell hide`). Visibility flips without notifying
  // the host back - it already knows.
  function close() {
    root.closingFromHost = true
    window.visible = false
    root.closingFromHost = false
  }

  // User-initiated close (Escape, or the compositor closing the window): tell
  // the shell, so its open state and this window agree and the next toggle
  // reopens instead of hiding nothing. dev-gallery's requestClose(), which is
  // the part t1nk33r.settings is missing.
  function requestClose() {
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    else window.visible = false
  }

  FloatingWindow {
    id: window
    title: identity.browserTitle
    // The card inside draws the sheet; a window colour would paint the
    // rounded corners' cut-outs opaque.
    color: "transparent"
    // Nothing maps until the shell summons it. Loading is what summon does;
    // an instance exists only while the panel is open (no `keepLoaded`), so
    // this is false only for the instant between construction and open().
    visible: false
    // Fallback geometry only. The authority is Hyprland's window rule
    // (`float_nothing_glass_browser`, matched on the title above), which
    // floats, sizes and centres the window; these numbers are the same ones
    // so the window does not jump when the rule applies.
    implicitWidth: 1100
    implicitHeight: 800

    onVisibleChanged: {
      // A compositor-initiated close (killactive on the focused window) drops
      // the window without going through requestClose(), and the shell would
      // otherwise keep believing the panel is open - the next toggle would
      // then hide a panel that is not there and never reopen it.
      if (!visible && !root.closingFromHost
          && root.shell && typeof root.shell.hide === "function")
        root.shell.hide(root.pluginId)
    }

    NothingLauncher {
      id: launcher
      anchors.fill: parent

      // Everything the browser used to be handed by GlassSurface, now read
      // from the one service that owns it. The bindings re-evaluate when the
      // shell injects `service` (one property assignment after construction),
      // and a missing service leaves the browser drawing its empty state
      // rather than failing to load.
      store: root.service ? root.service.widgetStore : null
      registry: root.service ? root.service.widgetRegistry : null
      pluginSettings: root.service ? root.service.widgetSettings : null
      injectedTheme: root.service ? root.service.widgetTheme : null
      setPluginSetting: root.service ? root.service.setPluginSetting : null
      styleForEntry: root.service ? root.service.styleForEntry : null
      styleForCategory: root.service ? root.service.styleForCategory : null
      setCategoryStyle: root.service ? root.service.setCategoryStyle : null

      manifest: root.manifest
      screenName: root.screenName
      insetLeft: insets.left
      insetTop: insets.top

      onCloseRequested: root.requestClose()
    }
  }

  // The resolved screen's reserved edges (bar and any other exclusive-zone
  // surface), for the settings pane's "Reset position". Bound to screenName,
  // so it answers for the desktop this summon is for - which is not
  // necessarily the screen the window itself sits on.
  ScreenInsets {
    id: insets
    screenName: root.screenName
  }
}
