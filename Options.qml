import QtQuick
import Quickshell
import Quickshell.Io

// Plugin-wide settings that actually survive.
//
// Omarchy keeps a plugin's settings on its single `shell.json` entry, and
// that entry is not stable for a plugin like this one. Measured on this
// machine, 2026-09-09:
//
//   - the entry sat in `bar.layout.right` with `styleMode: 2`;
//   - `omarchy-shell … option styleMode 0` edited it in place, correctly;
//   - the shell was restarted, and the entry came back in `plugins[]` as
//     `{ id }` alone - relocated AND stripped of every setting on it.
//
// So a style the user picked is gone by the next restart, which is exactly
// the "it keeps going back to Glass" complaint. `shell.json` is the shell's
// file and it is entitled to normalise it; we are not entitled to lose the
// user's settings over that.
//
// This is therefore the durable copy, in a file this plugin owns, beside the
// widget layout it already owns. Precedence when the surface merges:
//
//   manifest defaults  <  shell.json entry  <  THIS FILE
//
// shell.json is still read, so the Omarchy settings UI keeps working and a
// value set there is picked up; anything written through our own UI lands
// here as well, and outlives the shell's housekeeping.
Item {
  id: options

  required property PluginId identity

  readonly property string _home: Quickshell.env("HOME")
  readonly property string path:
    options._home + "/.config/omarchy/" + options.identity.storeName + "-options.json"

  // The name this plugin's settings file had while the plugin was called
  // Liquid Glass - two names ago. It is read once, and only while our own file
  // is genuinely absent - a missing file is both the normal first run and what
  // the rename looks like from here - and the source is renamed to .migrated
  // afterwards so it cannot be adopted a second time. Reading it on every start
  // instead, as this once did, wrote it back over our own file, so a setting
  // changed after the rename was deleted by the next restart. The .migrated
  // file is the undo, so it is renamed, never deleted.
  //
  // The name in between, `liquid-nothing-options.json`, deliberately has no
  // reader here: plan 053 renamed that file in place, so only a config restored
  // from before the `liquid-nothing` rename ever reaches this path. Two
  // predecessors would need this one-legacy-file machine to grow a second
  // reader and an ordering rule; one file moved by hand does not.
  readonly property string _legacyPath:
    options._home + "/.config/omarchy/liquidglass-options.json"
  // Adoption is wanted only when our own file failed to load because it is not
  // there. Set from the main view's onLoadFailed and never cleared.
  property bool _legacyWanted: false
  // The legacy view has given its answer - loaded or failed - so _migrate() has
  // something to read. The two views load independently, so whichever settles
  // last has to drive the migration.
  property bool _legacyAnswered: false
  // Set once the decision has been carried out, so a second load of either view
  // cannot adopt again.
  property bool _legacyDone: false

  // { key: value } - only what the user actually changed, never the defaults.
  property var values: ({})
  property bool loaded: false

  function get(key, fallback) {
    var k = String(key)
    return Object.prototype.hasOwnProperty.call(options.values, k) ? options.values[k] : fallback
  }

  function set(key, value) {
    var k = String(key || "")
    if (k === "") return false
    var next = {}
    for (var existing in options.values) next[existing] = options.values[existing]
    next[k] = value
    options.values = next
    options._write()
    return true
  }

  function clear(key) {
    var k = String(key || "")
    if (!Object.prototype.hasOwnProperty.call(options.values, k)) return false
    var next = {}
    for (var existing in options.values) if (existing !== k) next[existing] = options.values[existing]
    options.values = next
    options._write()
    return true
  }

  // Written the same way the widget store is: blocking, so a shell that is
  // killed a moment later still has the bytes. There is at most one of these
  // per click; coalescing would only add a window to lose them in.
  function _write() {
    file.blockWrites = true
    file.setText(JSON.stringify({ version: 1, options: options.values }, null, 2) + "\n")
  }

  // The one migration path, called from both views because either may settle
  // first: the legacy text is only in hand after its own view loads, and
  // adoption is only wanted after our own file has been found missing. Both
  // conditions are checked here, and _legacyDone makes the outcome final, so
  // no ordering of the two loads can adopt twice or adopt over a live file.
  function _migrate() {
    if (!options._legacyWanted || !options._legacyAnswered || options._legacyDone) return
    options._legacyDone = true

    var next = {}
    var text = ""
    try { text = String(legacyOptions.text()) } catch (e) { text = "" }
    if (text.trim() !== "") {
      try {
        var parsed = JSON.parse(text)
        if (parsed && typeof parsed.options === "object" && parsed.options !== null) next = parsed.options
      } catch (e) {
        next = {}
      }
    }

    options.values = next
    options.loaded = true
    if (Object.keys(next).length === 0) return  // nothing on offer: leave the old file where it is

    options._write()
    Quickshell.execDetached(["mv", "-n", options._legacyPath, options._legacyPath + ".migrated"])
    console.log("nothing-glass: adopted plugin settings from liquidglass-options.json")
  }

  // Static path, never rebound. Store.qml walked a single FileView through a
  // list of names by rebinding `path` and the rebind raced its own onLoaded;
  // a fixed path cannot race anything.
  property FileView _legacyFile: FileView {
    id: legacyOptions
    path: options._legacyPath
    printErrors: false

    onLoaded: {
      options._legacyAnswered = true
      options._migrate()
    }
    onLoadFailed: {
      options._legacyAnswered = true
      options._migrate()
    }
  }

  property FileView _file: FileView {
    id: file
    path: options.path
    watchChanges: true
    atomicWrites: true
    printErrors: false

    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        options.values = (parsed && typeof parsed.options === "object" && parsed.options !== null)
          ? parsed.options : {}
      } catch (e) {
        console.warn("nothing-glass: " + options.path + " unreadable, ignoring it")
        options.values = {}
      }
      options.loaded = true
    }
    // No file yet is the normal first run - and it is also what a rename
    // looks like from here, so the previous name is consulted once, through
    // _migrate(). Only a genuinely absent file counts: a path that is there
    // but unreadable, or is not a file, is not absent and must not be
    // migrated over. _migrate() sets `loaded` once the legacy view answers.
    onLoadFailed: function (error) {
      if (error !== FileViewError.FileNotFound) {
        console.warn("nothing-glass: " + options.path + " could not be read")
        options.values = {}
        options.loaded = true
        return
      }
      options._legacyWanted = true
      options._migrate()
    }
    onFileChanged: reload()
  }
}
