import Quickshell

// Standalone dev harness for GlassSurface — no plugin install, no
// omarchy-restart-shell. Run: `qs -n -p glass-dev.qml` from the checkout root.
//
// This opens the same GlassSurface the plugin installs: one PanelWindow per
// screen on the Bottom layer, the wallpaper backdrop, and a WidgetHost per
// entry in the Store below. Edit anything under the checkout root and re-run
// this command — much faster than a plugin update plus omarchy-restart-shell.
//
// The Store is pointed at a SCRATCH file, not ~/.config/omarchy/nothing-glass.json.
// The installed plugin owns that file; a second writer on it (this harness)
// would debounce and rewrite its own snapshot and the later write would
// discard the other's change. Seed the scratch file by hand, e.g.
//   {"version":1,"widgets":[{"id":"w1","type":"clock-digital","screen":"HDMI-A-1",
//    "x":200,"y":200,"w":300,"h":300,"settings":{}}]}
//
// The runtime types are this file's own directory, so no import names them.
// Quickshell's standalone `qs -p <file>` runner treats the entry file's
// directory as a sandboxed config root and refuses any import that textually
// leaves it (logged as "Module path ... is outside of the config folder", then
// a hard "<Type> is not a type" load failure) — verified directly. That is why
// the runtime imports `components` relatively: the sibling directory is part of
// the sandbox, a path out of it is not.
//
// Does NOT import qs.Commons/qs.Ui — those only resolve inside the running
// omarchy-shell, not standalone. See README.md.
ShellRoot {
  GlassSurface {
    store: Store { path: Quickshell.env("HOME") + "/.cache/liquidglass-dev.json" }
  }
}
