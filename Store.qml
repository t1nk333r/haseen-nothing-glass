import QtQuick
import Quickshell
import Quickshell.Io

// The single on-disk store of widget instances: ~/.config/omarchy/nothing-glass.json
// — id, type, screen, geometry, the reserved `style` column, and sparse
// per-instance settings overrides.
// This is a separate file rather than living in shell.json/manifest.settings:
// an array of
// objects has no representation in the flat settings-schema the settings UI
// understands, and shell.json is rewritten by the shell itself, so a
// hand-maintained array in it would race those writes.
//
// One writer. Every mutation (add/remove/move/resize/set) goes through the
// functions here — the IPC surface (Service.qml), Placement.qml (drag/resize)
// and every UI that edits a widget (the bar panel, the browser, the
// right-click sheet) call into this object rather than touching the file
// directly. Adding a second writer means adding it here too, or two writers
// race and lose the user's layout.
//
// Root type is Item, not QtObject, purely so FileView/Timer children below
// have somewhere to live — QtObject has no default property, Item's
// ("data") does. Never parented into a window; matches Service.qml's own
// headless-Item precedent.
Item {
  id: store

  readonly property string _home: Quickshell.env("HOME")
  // Overridable so the standalone dev harness (glass-dev.qml)
  // can point at a scratch file. Two Store instances on the SAME file — the
  // running plugin's and a harness's — each debounce and rewrite their own
  // snapshot, and the later write discards the other's change.
  property PluginId identity: PluginId {}
  property string path: store._home + "/.config/omarchy/" + store.identity.storeName + ".json"
  readonly property string _backupPath: store.path + ".bak"

  // The parsed widget list everything else binds to:
  // [{ id, type, screen, x, y, w, h, settings }, ...]. Never mutated in
  // place — every writer replaces this with a new array so bindings that
  // read it re-evaluate.
  property var widgets: []
  property bool loaded: false

  // --- load -------------------------------------------------------------

  FileView {
    id: file
    path: store.path
    watchChanges: true
    atomicWrites: true
    printErrors: false

    onLoaded: store._applyText(file.text())
    onLoadFailed: function (error) {
      // Missing file (first run, or the plugin has never persisted a
      // layout yet) is not corruption — start with an empty list.
      store.widgets = []
      store.loaded = true
      // A missing file is also exactly what a rename looks like, and it is
      // the case where there IS something to migrate. The two FileViews load
      // independently, so whichever finishes last has to drive this: the
      // legacy view's onLoaded returns early while `loaded` is still false,
      // and without this call nothing would retry. Observed: the widgets
      // stayed behind while the options file came across.
      store._absorbLegacyStore()
    }
    onFileChanged: {
      // FileView.watchChanges fires on ANY change to the file, including
      // the ones this object just made itself via _flush()'s setText().
      // Without this guard, our own atomic write would immediately
      // re-trigger a reload of the exact data we just wrote — harmless by
      // itself, but if that reload ever raced a fresh in-flight edit it would
      // clobber it. Guarded, not
      // timed: cleared from FileView.onSaved below, which fires precisely
      // when our own write actually lands, rather than after a guessed
      // delay.
      if (store._selfWrite) { store._reloadPending = true; return }
      reload()
    }
  }

  // Bumped by every mutation, snapshotted by every flush. While the two
  // differ, memory holds edits the file has not been told about yet.
  property int _revision: 0
  property int _writtenRevision: 0
  readonly property bool _dirty: store._revision !== store._writtenRevision

  function _applyText(text) {
    // A reload that lands while local edits are pending would replace them
    // with the older document and the next flush would then persist that -
    // an add followed immediately by set/move/resize lost everything but the
    // add, reproducibly, because our own write triggers the watch and the
    // replayed reload arrives mid-burst. Memory is the newer copy; the
    // pending write will publish it.
    if (store._dirty) return

    var t = String(text || "").trim()
    if (!t) {
      store.widgets = []
      store.loaded = true
      return
    }
    var parsed
    try {
      parsed = JSON.parse(t)
    } catch (e) {
      store._rejectCorrupt(text, "parse failed: " + e)
      return
    }
    if (!parsed || typeof parsed !== "object" || !Array.isArray(parsed.widgets)) {
      store._rejectCorrupt(text, "missing or invalid 'widgets' array")
      return
    }
    store.widgets = store._adoptLegacyTypes(parsed.widgets)
    store.loaded = true
    if (parsed.widgets.length > 0) store._lastNonEmpty = t
    store._absorbLegacyStore()
  }

  // --- one-time TYPE renames ---------------------------------------------
  //
  // A widget `type` is also the directory its QML is loaded from
  // (`registry.urlFor()`), so renaming a type leaves every instance already
  // on disk pointing at a directory that no longer exists. Nothing throws:
  // WidgetHost finds no registry entry, the Loader's `source` stays "", and
  // the instance keeps its slot as a blank region with one console.warn. So
  // the retired name is absorbed HERE, at the single point rows enter
  // `store.widgets` from disk (both readers funnel through
  // `_adoptLegacyTypes()` below), and every consumer downstream — WidgetHost,
  // Placement, the inspector, the right-click sheet, the launcher, the bar
  // panel — only ever sees the living name.
  //
  // The mapping is an EXACT-MATCH table: a name it does not know is left
  // exactly as it was rather than guessed at, and a row already carrying the
  // new name is copied through untouched, so this is idempotent and cannot
  // invent a type. Unlike the legacy-FILE absorb above it is NOT gated on
  // `_mayAbsorb`: it moves no file the user did not already own, and a
  // scratch store (the dev harness, the test fixture) is exactly where a
  // stale-name row has to resolve too.
  //
  // The row's `id` is deliberately left alone: it is an opaque handle the
  // operator types at `omarchy-shell t1nk33r.nothing-glass remove <id>`, not
  // a type, and ids and types already drift (`tailscale-2`). The new name
  // reaches the file on the next mutation, which flushes `store.widgets`
  // whole — same as any other normalised row.
  readonly property var _legacyTypes: ({ music: "now-playing" })

  function _adoptLegacyType(type) {
    var name = String(type === undefined || type === null ? "" : type)
    return (_legacyTypes[name] !== undefined) ? _legacyTypes[name] : name
  }

  function _adoptLegacyTypes(rows) {
    var out = []
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      if (!row || row.type === undefined) { out.push(row); continue }
      var mapped = store._adoptLegacyType(row.type)
      if (mapped === String(row.type)) { out.push(row); continue }
      var next = {}
      for (var k in row) next[k] = row[k]
      next.type = mapped
      out.push(next)
    }
    return out
  }

  // --- one-time migration from an older store name -----------------------
  //
  // Three names came before this one and any of them may still be on disk:
  //
  //   liquidglass.json     the file this plugin kept while its id was
  //                       `t1nk33r.liquidglass`; its widgets keep whatever
  //                       style they already carried.
  //   nothing.json        the second plugin this port briefly shipped as;
  //                       its widgets arrive pinned to `style: "nothing"`.
  //   liquid-nothing.json  this plugin's own file before it was renamed
  //                       `t1nk33r.nothing-glass`; its widgets keep whatever
  //                       style they already carried.
  //
  // Whichever one they came from, the widgets move into this file keeping
  // screen, position, size and settings exactly.
  //
  // Ids collide across the files - two of them had a `tailscale-2` on this
  // machine - so an incoming id that is already taken is renamed rather than
  // overwriting a widget the user can see. The source file is renamed to
  // .migrated afterwards, which is both the "done" marker and the undo.
  //
  // Only the REAL store may do this. A Store pointed at a scratch file - the
  // dev harness does exactly that - would otherwise absorb the user's Nothing
  // widgets into the scratch file and rename the source away, so the
  // installed plugin finds nothing left to migrate and the widgets are gone
  // from the desktop. Caught in a smoke test, on real data, which is the only
  // reason this guard exists.
  readonly property string _defaultPath: store._home + "/.config/omarchy/" + store.identity.storeName + ".json"
  readonly property bool _mayAbsorb: store.path === store._defaultPath
  property bool _absorbed: false

  // One reader per old name, no shared cursor. An earlier version walked a
  // single FileView through a list by rebinding its `path`; the rebind raced
  // its own onLoaded and the widgets silently stayed behind while the
  // settings file came across. Static views cannot race a cursor that does
  // not exist.
  FileView {
    id: legacyGlass
    path: store._mayAbsorb ? (store._home + "/.config/omarchy/liquidglass.json") : ""
    printErrors: false
    onLoaded: store._absorbLegacy(legacyGlass, "liquidglass.json", "")
    onLoadFailed: store._legacyGlassDone = true
  }

  FileView {
    id: legacyNothing
    path: store._mayAbsorb ? (store._home + "/.config/omarchy/nothing.json") : ""
    printErrors: false
    onLoaded: store._absorbLegacy(legacyNothing, "nothing.json", "nothing")
    onLoadFailed: store._legacyNothingDone = true
  }

  // The name this store had until plan 053 renamed the plugin. Without this
  // reader a store that was never renamed by hand - a restored backup, or a
  // machine whose operator took the new id rather than moving the file -
  // would be ignored and the desktop would come up empty. These rows carry
  // their own style, so nothing is pinned here.
  FileView {
    id: legacyLiquidNothing
    path: store._mayAbsorb ? (store._home + "/.config/omarchy/liquid-nothing.json") : ""
    printErrors: false
    onLoaded: store._absorbLegacy(legacyLiquidNothing, "liquid-nothing.json", "")
    onLoadFailed: store._legacyLiquidNothingDone = true
  }

  property bool _legacyGlassDone: false
  property bool _legacyNothingDone: false
  property bool _legacyLiquidNothingDone: false

  // Called again whenever our own file settles, because either side may load
  // first and the migration needs both: the source text AND `store.loaded`.
  function _absorbLegacyStore() {
    if (!store._legacyGlassDone) store._absorbLegacy(legacyGlass, "liquidglass.json", "")
    if (!store._legacyNothingDone) store._absorbLegacy(legacyNothing, "nothing.json", "nothing")
    if (!store._legacyLiquidNothingDone)
      store._absorbLegacy(legacyLiquidNothing, "liquid-nothing.json", "")
  }

  // `pinStyle` is the style incoming rows get when they carry none: the
  // second plugin's rows were all Nothing; this plugin's own older files
  // already recorded a style per row and keep it.
  function _absorbLegacy(view, name, pinStyle) {
    if (!store.loaded || !store._mayAbsorb) return
    var text = ""
    try { text = view.text() } catch (e) { return }
    if (!text || text.trim() === "") return

    var parsed
    try { parsed = JSON.parse(text) } catch (e) {
      console.warn(name + " could not be parsed, leaving it alone: " + e)
      return
    }
    if (!parsed || !Array.isArray(parsed.widgets)) return

    var list = store.widgets.slice()
    var taken = {}
    for (var i = 0; i < list.length; i++) taken[String(list[i].id)] = true

    var moved = 0
    for (var j = 0; j < parsed.widgets.length; j++) {
      var w = parsed.widgets[j]
      if (!w || !w.type) continue
      // A row out of a retired FILE may also carry a retired TYPE — the two
      // renames are independent, and both readers end up here or in
      // `_applyText`, the only two places rows are built.
      var type = store._adoptLegacyType(w.type)
      var id = String(w.id || "")
      if (id === "" || taken[id]) id = store._genId(type, taken)
      taken[id] = true
      var row = {
        id: id, type: type, screen: String(w.screen || ""),
        x: w.x | 0, y: w.y | 0, w: w.w | 0, h: w.h | 0,
        settings: (w.settings && typeof w.settings === "object") ? w.settings : ({})
      }
      var style = String(w.style || "") || pinStyle
      if (style !== "") row.style = style
      list.push(row)
      moved++
    }

    var from = String(view.path)
    if (name === "liquidglass.json") store._legacyGlassDone = true
    else if (name === "nothing.json") store._legacyNothingDone = true
    else store._legacyLiquidNothingDone = true
    if (moved === 0) return

    store.widgets = list
    store._scheduleWrite()
    Quickshell.execDetached(["mv", "-n", from, from + ".migrated"])
    console.log("nothing-glass: absorbed " + moved + " widget(s) from " + name)
  }

  // A malformed nothing-glass.json must never destroy the user's layout: log
  // once, copy the bad bytes to nothing-glass.json.bak, and render nothing.
  // The ORIGINAL is preserved only until the next mutation — an add/move/set
  // after this point writes a fresh document over it, and the .bak is the
  // recovery path. (Earlier wording here claimed the original was never
  // overwritten; it was not true and a read-only-after-corruption mode would
  // silently drop the user's next edit instead, which is worse.)
  property bool _warnedCorrupt: false
  function _rejectCorrupt(text, reason) {
    if (!store._warnedCorrupt) {
      console.warn("nothing-glass.json: " + reason + " — rendering no widgets, leaving the file on disk untouched.")
      store._warnedCorrupt = true
    }
    if (String(text || "").trim().length > 0) store._backupOnce(text)
    store.widgets = []
    store.loaded = true
  }

  property bool _backedUp: false
  function _backupOnce(text) {
    if (store._backedUp) return
    store._backedUp = true
    backupFile.setText(text)
  }

  // Write-only sink for the corrupt-file backup. Never read.
  FileView {
    id: backupFile
    path: store._backupPath
    printErrors: false
  }

  // --- write --------------------------------------------------------------

  // Writes are LEADING-edge and synchronous, with a trailing coalesce.
  //
  // The first mutation after a quiet moment goes to disk immediately and
  // blocks until the bytes are there; further mutations inside the next
  // 250 ms are coalesced into one trailing write. That is the opposite of
  // the original trailing-only debounce, and it is deliberate:
  //
  //   A trailing debounce means every single mutation spends 250 ms living
  //   only in memory. `Component.onDestruction` was supposed to be the net
  //   for that, but it does NOT run when the process is signalled - and
  //   `omarchy-restart-shell` signals (`quickshell kill`). Reproduced
  //   2026-09-07 with a scratch store: add a widget, SIGTERM 150 ms later,
  //   and the widget is simply not in the file. It is what ate two resizes
  //   during this session's deploys.
  //
  // Cost of blocking: the document is a couple of kilobytes and at most one
  // write per 250 ms per store, so this is tens of microseconds on the GUI
  // thread - cheaper than the class of bug it removes.
  Timer {
    id: writeTimer
    interval: 250
    onTriggered: store._flush()
  }

  property bool _selfWrite: false

  // Wall-clock ms of the last write actually issued, leading or trailing.
  property double _lastWriteAt: 0

  function _scheduleWrite() {
    store._revision++
    var now = Date.now()
    if (now - store._lastWriteAt >= writeTimer.interval) {
      writeTimer.stop()
      store._flush()
      return
    }
    // Inside the coalescing window (a drag committing, a settings field
    // being typed into): let the trailing write pick it up.
    writeTimer.restart()
  }

  // The last document seen on disk that actually had widgets in it. Kept so
  // an empty write can never be the only copy.
  property string _lastNonEmpty: ""

  function _flush() {
    store._selfWrite = true
    store._lastWriteAt = Date.now()
    store._writtenRevision = store._revision
    var payload = { version: 1, widgets: store.widgets }
    var text = JSON.stringify(payload, null, 2) + "\n"

    // Writing an EMPTY layout over a non-empty one is either the user
    // removing their last widget or something going wrong; the two are
    // indistinguishable from here, and one of them is unrecoverable. So the
    // previous document goes to nothing-glass.json.bak first, every time.
    // (A layout was lost on this machine on 2026-09-06 with no reproduction
    // and no backup; this is the net, not a fix for a known cause.)
    if (store.widgets.length === 0 && store._lastNonEmpty !== "") {
      backupFile.setText(store._lastNonEmpty)
      store._lastNonEmpty = ""
    } else if (store.widgets.length > 0) {
      store._lastNonEmpty = text
    }

    // Blocking: setText returns once the bytes are on disk. See the write
    // section's header for why this is unconditional rather than only at
    // destruction - a signalled process runs no destructor, so "we will
    // write it properly on the way out" was never true.
    file.blockWrites = true
    file.setText(text)
  }

  // Belt and braces for the one case a signal cannot reach: a clean QML
  // teardown (plugin hot-reload through the shell's own unload path) that
  // happens to land inside the coalescing window. Writes are already
  // synchronous, so this only has to fire the pending trailing write.
  Component.onDestruction: {
    if (!writeTimer.running) return
    writeTimer.stop()
    store._flush()
  }

  Connections {
    target: file
    function onSaved() {
      // Our own write landed — the FileView watch's corresponding
      // onFileChanged (if it fires at all for a write we issued ourselves)
      // arrives at essentially the same tick; clear the guard shortly after
      // rather than exactly on onSaved so that near-simultaneous delivery
      // ordering can't slip a self-triggered reload through.
      selfWriteGuardClear.restart()
    }
    function onSaveFailed(error) {
      console.warn("nothing-glass.json: write failed:", error)
      store._selfWrite = false
    }
  }

  // An external edit that lands while the guard is up is not dropped: it is
  // replayed once the guard clears, so memory never silently diverges from
  // the file and the next local mutation cannot write a stale snapshot over
  // someone else's change.
  property bool _reloadPending: false

  Timer {
    id: selfWriteGuardClear
    interval: 300
    onTriggered: {
      store._selfWrite = false
      if (store._reloadPending) { store._reloadPending = false; file.reload() }
    }
  }

  // --- mutations ------------------------------------------------------

  function _indexOf(id) {
    for (var i = 0; i < store.widgets.length; i++) {
      if (store.widgets[i] && store.widgets[i].id === id) return i
    }
    return -1
  }

  function _idExists(id) {
    return store._indexOf(id) !== -1
  }

  // `alsoTaken` is an optional { id: true } set of ids that are not in
  // `widgets` yet - the migration builds its new entries before committing
  // them, and two incoming widgets of the same type must not both mint the
  // same id.
  function _genId(type, alsoTaken) {
    var base = String(type || "widget")
    var extra = alsoTaken || {}
    var n = 1
    var id = base + "-" + n
    while (store._idExists(id) || extra[id] === true) {
      n++
      id = base + "-" + n
    }
    return id
  }

  // Every mutation refuses until the first load has finished. Before that,
  // `widgets` is still the empty initializer: an add() would be flushed over
  // the real on-disk layout (if the debounce wins) or silently discarded by
  // _applyText replacing the array (if the load wins). The window is tens of
  // milliseconds after service creation, but IPC can land in it.
  function _writable(op) {
    if (store.loaded) return true
    console.warn("nothing-glass.json: " + op + " refused — store not loaded yet")
    return false
  }

  // opts: optional { x, y, w, h, settings } — anything omitted gets a sane
  // default so a bare `add(type, screen)` IPC call always produces a usable
  // instance.
  function add(type, screen, opts) {
    if (!store._writable("add")) return ""
    opts = opts || {}
    var id = store._genId(type)
    var entry = {
      id: id,
      type: String(type),
      screen: String(screen),
      x: opts.x !== undefined ? opts.x : 120,
      y: opts.y !== undefined ? opts.y : 120,
      w: opts.w !== undefined ? opts.w : 300,
      h: opts.h !== undefined ? opts.h : 300,
      settings: opts.settings || {}
    }
    var list = store.widgets.slice()
    list.push(entry)
    store.widgets = list
    store._scheduleWrite()
    return id
  }

  function remove(id) {
    if (!store._writable("remove")) return false
    var idx = store._indexOf(id)
    if (idx === -1) return false
    var list = store.widgets.slice()
    list.splice(idx, 1)
    store.widgets = list
    store._scheduleWrite()
    return true
  }

  function move(id, x, y) {
    if (!store._writable("move")) return false
    var idx = store._indexOf(id)
    if (idx === -1) return false
    var list = store.widgets.slice()
    var entry = {}
    for (var k in list[idx]) entry[k] = list[idx][k]
    entry.x = x
    entry.y = y
    list[idx] = entry
    store.widgets = list
    store._scheduleWrite()
    return true
  }

  function resize(id, w, h) {
    if (!store._writable("resize")) return false
    var idx = store._indexOf(id)
    if (idx === -1) return false
    var list = store.widgets.slice()
    var entry = {}
    for (var k in list[idx]) entry[k] = list[idx][k]
    entry.w = w
    entry.h = h
    list[idx] = entry
    store.widgets = list
    store._scheduleWrite()
    return true
  }

  // `style` is a COLUMN on the row, not one of the widget's own settings:
  // GlassSurface resolves it (widget -> category -> plugin default) before a
  // host is ever built, and the migration from the old second plugin writes
  // it the same way. Routing it through `settings` instead would put it
  // somewhere nothing reads. Empty string means "inherit", which is the
  // absence of the field, so it is deleted rather than stored blank.
  readonly property var _reservedKeys: ["style"]
  function _isReserved(key) { return store._reservedKeys.indexOf(String(key)) !== -1 }

  function set(id, key, value) {
    if (!store._writable("set")) return false
    var idx = store._indexOf(id)
    if (idx === -1) return false
    var list = store.widgets.slice()
    var entry = {}
    for (var k in list[idx]) entry[k] = list[idx][k]
    if (store._isReserved(key)) {
      if (String(value || "") === "") delete entry[String(key)]
      else entry[String(key)] = String(value)
      list[idx] = entry
      store.widgets = list
      store._scheduleWrite()
      return true
    }
    var settings = {}
    var prevSettings = entry.settings || {}
    for (var sk in prevSettings) settings[sk] = prevSettings[sk]
    settings[key] = value
    entry.settings = settings
    list[idx] = entry
    store.widgets = list
    store._scheduleWrite()
    return true
  }

  // Drop one per-instance override so the plugin-wide value applies again.
  // The control panel's per-widget editor uses it for a cleared field.
  function unset(id, key) {
    if (!store._writable("unset")) return false
    var idx = store._indexOf(id)
    if (idx === -1) return false
    if (store._isReserved(key)) return store.set(id, key, "")
    var prevSettings = store.widgets[idx].settings || {}
    if (!(key in prevSettings)) return true
    var list = store.widgets.slice()
    var entry = {}
    for (var k in list[idx]) entry[k] = list[idx][k]
    var settings = {}
    for (var sk in prevSettings) if (sk !== key) settings[sk] = prevSettings[sk]
    entry.settings = settings
    list[idx] = entry
    store.widgets = list
    store._scheduleWrite()
    return true
  }

  function reload() {
    file.reload()
  }
}
