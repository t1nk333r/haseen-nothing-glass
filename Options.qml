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
  property bool _corrupt: false

  // Which keys and values are allowed is GlassSurface.checkPluginSetting's
  // call, made before anything reaches set(). This file only guarantees that
  // what it holds is plain data: unsafe keys and non-JSON values never enter
  // `values` (PlainData.qml), from disk or from set().
  PlainData { id: plain }

  // A document larger than this is not parsed: it takes the unreadable path
  // below (ignored, values {}), the same as one that does not parse.
  readonly property int maxFileChars: 4 * 1024 * 1024

  // chmod 600 after our own writes, and the checked rename of the retired file.
  OwnFiles { id: chores }

  function get(key, fallback) {
    var k = String(key)
    return Object.prototype.hasOwnProperty.call(options.values, k) ? options.values[k] : fallback
  }

  function set(key, value) {
    if (!options.loaded || options._corrupt) return false
    var k = String(key || "")
    if (plain.isUnsafeKey(k)) return false
    var c = plain.clean(value)
    if (!c.ok) return false
    var next = plain.cleanObject(options.values)
    next[k] = c.value
    options.values = next
    options._write()
    return true
  }

  function clear(key) {
    if (!options.loaded || options._corrupt) return false
    var k = String(key || "")
    if (!Object.prototype.hasOwnProperty.call(options.values, k)) return false
    var next = {}
    var keys = Object.keys(options.values)
    for (var i = 0; i < keys.length; i++) if (keys[i] !== k) next[keys[i]] = options.values[keys[i]]
    options.values = next
    options._write()
    return true
  }

  // The `options` object of a parsed document, as plain data; {} for a
  // document that is not one.
  function _optionsOf(parsed) {
    return (parsed && typeof parsed === "object") ? plain.cleanObject(parsed.options) : {}
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
    if (text.trim() !== "" && !plain.exceedsBytes(text, options.maxFileChars)) {
      try {
        next = options._optionsOf(JSON.parse(text))
      } catch (e) {
        next = {}
      }
    }

    options.values = next
    options.loaded = true
    if (Object.keys(next).length === 0) return  // nothing on offer: leave the old file where it is

    options._write()
    // Checked: `mv -n` keeps the source when the target exists. Nothing
    // depends on it going - adoption only ever runs while our own file is
    // absent, and the write above has just created it.
    chores.retire(options._legacyPath, options._legacyPath + ".migrated")
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
      var t = String(text() || "")
      if (plain.exceedsBytes(t, options.maxFileChars)) {
        options._corrupt = true
        console.warn("nothing-glass: " + options.path + " is larger than " +
                     options.maxFileChars + " bytes, ignoring it")
        options.values = {}
      } else {
        try {
          options.values = options._optionsOf(JSON.parse(t))
          options._corrupt = false
        } catch (e) {
          options._corrupt = true
          console.warn("nothing-glass: " + options.path + " unreadable, ignoring it")
          options.values = {}
        }
      }
      options.loaded = true
    }
    // Plugin settings: owner-only (OwnFiles.qml).
    onSaved: chores.restrict(options.path)
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
