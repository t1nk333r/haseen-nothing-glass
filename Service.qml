import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons

// Liquid Glass — desktop-layer service. Owns the widget instance store, the
// widget type registry, the IPC surface below, and one GlassSurface (a
// per-screen PanelWindow hosting the wallpaper backdrop + N widget
// instances). It also hands the widget browser (Panel.qml, a toplevel the
// shell summons) the store, registry, settings and style functions it draws
// with. See GlassSurface.qml, Panel.qml, WidgetHost.qml, and Store.qml for the
// actual mechanics.
//
// `import qs.Commons` is safe here because Service.qml is only ever loaded by
// a running omarchy-shell (shell.qml's ensureService()) — the standalone dev
// harness (glass-dev.qml) instantiates GlassSurface directly
// and never loads this file, so a missing qs.Commons module never gets a
// chance to fail this file's parse. See Theme.qml, and GlassSurface.qml's `_fallbackDefaults` comment.
Item {
  id: root

  // Injected by the shell at load time — see manifest.json's entryPoints.
  property var shell: null
  property var manifest: null

  Theme {
    id: liveTheme
    systemBackground: Color.background
    themeForeground: Color.foreground
    themeAccent: Color.accent
    themeUrgent: Color.urgent
    // Omarchy has no "surface" token; the bar's own background is the
    // nearest thing to one and moves with the theme.
    themeSurface: Color.bar && Color.bar.background ? Color.bar.background : Color.background
  }

  // Single instance of each, shared by every screen's PanelWindow inside
  // GlassSurface (and by the IpcHandler below) — "one writer" for the
  // store (see Store.qml's own header and PROJECT_MAP.md's maintenance
  // notes): every mutation from IPC or from a Placement.qml drag goes
  // through this same object.
  PluginId { id: plugin }

  Store { id: store; identity: plugin; registry: registry }
  WidgetRegistry { id: registry }

  // The bar panel's "Browse widgets" button and the IPC verb below reach the
  // browser through here. One toplevel now (Panel.qml, the manifest's `panel`
  // entry point), so the screen argument names the DESKTOP new widgets land
  // on, not which per-screen instance to toggle; "" means "the monitor the
  // user is on", resolved when the panel opens rather than here.
  function toggleLauncher(screen) {
    if (!root.shell || typeof root.shell.toggle !== "function") return
    root.shell.toggle(plugin.id, JSON.stringify({ screen: String(screen || "") }))
  }

  // ── The widget browser's data door ─────────────────────────────────
  // The browser is a toplevel the shell summons on its own, so it is not a
  // child of any screen's GlassSurface and cannot be handed the surface's
  // bindings at construction the way it used to be. It reads them through
  // here instead: the SAME store, registry, merged settings, theme and style
  // functions the desktop draws with - one writer, one style precedence, no
  // second copy to drift (see Store.qml's header).
  readonly property Store widgetStore: store
  readonly property WidgetRegistry widgetRegistry: registry
  readonly property var widgetSettings: surface.plugin.settings
  readonly property var widgetTheme: liveTheme
  function styleForEntry(entry) { return surface.styleForEntry(entry) }
  function styleForCategory(group) { return surface.styleForCategory(group) }
  function setCategoryStyle(group, style) { return surface.setCategoryStyle(group, style) }

  // The same door for this plugin's settings, so the bar panel's Glass/Solid
  // buttons can reach the durable copy with a call instead of a process when
  // the service resolves (it is un-placed; placed, `serviceFor()` is null by
  // construction and the panel shells out to the verb below instead). The
  // panel cannot see `surface` itself, and the copy it used to write - its
  // own shell.json entry - is the one GlassSurface's merge overrides.
  function setPluginSetting(key, value) {
    return surface.setPluginSetting(key, value)
  }

  GlassSurface {
    id: surface
    shell: root.shell
    manifest: root.manifest
    theme: liveTheme
    store: store
    registry: registry
  }

  IpcHandler {
    target: plugin.id

    function listTypes(): string {
      return JSON.stringify(registry.listTypes())
    }

    function listWidgets(): string {
      return JSON.stringify(store.widgets)
    }

    // `screen` may be empty, meaning the monitor the user is on - the same
    // contract `launcher ''` has, resolved the same way Panel.qml does it:
    // Hyprland's focused monitor, else the first screen Quickshell knows.
    function add(type: string, screen: string): string {
      if (!registry.hasType(type)) return "error: unknown widget type '" + type + "'"
      var target = String(screen || "")
      if (target === "") {
        var mon = Hyprland.focusedMonitor
        if (mon && String(mon.name || "") !== "") target = String(mon.name)
        else {
          var screens = Quickshell.screens || []
          if (screens.length > 0) target = String(screens[0].name || "")
        }
      }
      if (target === "") return "error: no screen to add to"
      var size = registry.defaultSize(type)
      var id = store.add(type, target, { w: size.width, h: size.height })
      return id ? id : ("error: " + store.lastError)
    }

    function remove(id: string): string {
      return store.remove(id) ? ("removed " + id) : ("error: " + store.lastError)
    }

    function move(id: string, x: int, y: int): string {
      return store.move(id, x, y) ? ("moved " + id + " to " + x + "," + y) : ("error: " + store.lastError)
    }

    function resize(id: string, w: int, h: int): string {
      return store.resize(id, w, h) ? ("resized " + id + " to " + w + "x" + h) : ("error: " + store.lastError)
    }

    // A per-instance override, so only what a widget can actually be told:
    // the row's own `style` column, or one of the plugin's settings (every
    // field WidgetFields.qml offers is one of those), with a value of that
    // setting's type - the same check `option` makes (GlassSurface's
    // checkPluginSetting). Anything else would sit in the row where nothing
    // reads it.
    function set(id: string, key: string, valueJson: string): string {
      var value
      try {
        value = JSON.parse(valueJson)
      } catch (e) {
        return "error: invalid JSON value: " + e
      }
      var k = String(key || "")
      if (k === "style") {
        // "" clears it back to the category/plugin default.
        if (value !== "" && plugin.styles.indexOf(value) === -1)
          return "error: style takes one of " + plugin.styles.join(", ") + ", or \"\" to inherit"
      } else {
        var checked = surface.checkPluginSetting(k, value)
        if (checked.error !== undefined) return "error: " + checked.error
        value = checked.value
      }
      return store.set(id, k, value) ? ("set " + id + "." + k) : ("error: " + store.lastError)
    }

    // Open the widget browser, or close it with the same call - a launcher
    // that can only be opened by IPC is a launcher you have to reach for the
    // mouse to close.
    //
    // The argument is the DESKTOP the browser acts on (`HDMI-A-1`, `eDP-1`),
    // not which window to toggle: there is one toplevel now. Empty - the form
    // the bar icon uses, `omarchy-shell t1nk33r.nothing-glass launcher ''` -
    // means the monitor the user is on, resolved when the panel opens.
    function launcher(screen: string): string {
      root.toggleLauncher(screen || "")
      return "launcher toggled"
    }



    // Plugin-wide settings, the ones that used to be reachable only by
    // clicking the bar panel. `omarchy bar set` refuses to write for a plugin
    // that is not placed on the bar (it reports success and changes nothing -
    // measured), and the bar entry cannot always be placed, so the plugin
    // exposes its own writer. Same path the panel and the launcher use:
    // shell.updateEntryInline, which edits the entry wherever it lives.
    //
    //   omarchy-shell t1nk33r.nothing-glass option styleMode 2
    //   omarchy-shell t1nk33r.nothing-glass option widgetStyle nothing
    function option(key: string, value: string): string {
      var k = String(key || "")
      if (k === "") return "error: key is required"
      // Two kinds of value reach this verb and both have to work. Bare words
      // are what a person types - `styleMode 2`, `followTheme true` - and a
      // JSON document is how a structured setting like `categoryStyles`
      // arrives: `option categoryStyles '{"Time":"nothing"}'`. Storing that
      // object as the STRING it arrived as is the bug this branch exists to
      // prevent; every reader then sees a string where it expects a map, and
      // silently falls back to the default.
      var v = value
      var t = String(value).trim()
      if (t.length > 1 && (t.charAt(0) === "{" || t.charAt(0) === "[")) {
        try {
          v = JSON.parse(t)
        } catch (e) {
          return "error: " + k + " looks like JSON but does not parse: " + e
        }
      }
      else if (value === "true") v = true
      else if (value === "false") v = false
      else if (value !== "" && !isNaN(Number(value))) v = Number(value)
      var checked = surface.checkPluginSetting(k, v)
      if (checked.error !== undefined) return "error: " + checked.error
      if (surface.options._corrupt)
        return "error: " + surface.options.path + " is unreadable or larger than 4 MiB; repair or remove it, then reload"
      return surface.setPluginSetting(k, checked.value)
        ? ("set " + k + " = " + JSON.stringify(checked.value))
        : ("error: could not write " + k + " - is the shell config reachable?")
    }

    function reload(): void {
      store.reload()
    }
  }
}
