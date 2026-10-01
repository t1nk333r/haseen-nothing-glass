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
  property bool _corrupt: false
  // The document holds more rows than maxWidgets: only the first maxWidgets
  // are drawn, and nothing is written, so the file keeps every row.
  property bool _overCap: false

  // --- bounds --------------------------------------------------------------
  //
  // The store is parsed whole on the GUI thread of the desktop shell, and every
  // row becomes a live widget, so what may enter it is bounded at the two
  // places rows come from: the mutations below (the single writer) and the
  // load path. Every limit is far above anything the UI can produce - a real
  // desktop is a few dozen tiles of a few hundred pixels with settings of a
  // few dozen bytes - so a legitimate layout passes through untouched; only
  // the impossible is clamped (a non-finite or absurd coordinate, a negative
  // size). A document with more than maxWidgets rows draws the first
  // maxWidgets and is left alone on disk: writes are refused until it is
  // trimmed by hand, so no row is ever dropped from the file.
  readonly property int maxWidgets: 256
  readonly property int maxSize: 16384
  readonly property int maxCoord: 32768
  // Characters of one row's serialised `settings`, and of a `style` value.
  readonly property int maxSettingsChars: 16384
  readonly property int maxStyleChars: 64
  // A store document larger than this is not parsed at all: it takes the
  // corrupt-file path (backed up, not loaded, not written over by the load).
  readonly property int maxFileChars: 4 * 1024 * 1024

  // For each type's minimum size, which the writers floor a size at. Service
  // hands over its own; anything else (the dev harness, a test) gets one of
  // its own - the registry is a stateless table.
  property WidgetRegistry registry: WidgetRegistry {}

  // Why the last mutation was refused, for the IPC reply. Empty after a
  // mutation that succeeded.
  property string lastError: ""

  // chmod 600 after our own writes, and the checked rename of a retired file.
  OwnFiles { id: chores }

  // --- load -------------------------------------------------------------

  FileView {
    id: file
    path: store.path
    watchChanges: true
    atomicWrites: true
    printErrors: false

    // A file written 0644 by an earlier build is made owner-only on load,
    // not only after the next write. A file that is 600 already is left
    // alone, so this load does not trigger another (OwnFiles.qml).
    onLoaded: {
      chores.restrict(store.path)
      store._applyText(file.text())
    }
    onLoadFailed: function (error) {
      // Missing file (first run, or the plugin has never persisted a
      // layout yet) is not corruption — start with an empty list. It is
      // also how a corrupt or over-cap file that was moved aside reads, and
      // edits must work again then, so both refusals are cleared here. Any
      // other read error leaves them as they were.
      if (error === FileViewError.FileNotFound) {
        store._corrupt = false
        store._overCap = false
      }
      store.widgets = []
      store._absorbedFiles = []
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

    var t = String(text || "")
    if (plain.exceedsBytes(t, store.maxFileChars)) {
      store._rejectCorrupt(text, "larger than " + store.maxFileChars + " bytes, not parsed")
      return
    }
    if (!t.trim()) {
      store.widgets = []
      store._absorbedFiles = []
      store._corrupt = false
      store._overCap = false
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
    store._absorbedFiles = store._readAbsorbed(parsed.absorbed)
    store._corrupt = false
    var rows = parsed.widgets
    store._overCap = rows.length > store.maxWidgets
    if (store._overCap) {
      console.warn("nothing-glass.json: " + rows.length + " widgets, more than the " + store.maxWidgets +
                   " drawn - drawing the first " + store.maxWidgets + " and leaving the file untouched")
      rows = rows.slice(0, store.maxWidgets)
    }
    store.widgets = store._adoptLegacyTypes(store._normaliseRows(rows))
    store.loaded = true
    if (parsed.widgets.length > 0) store._lastNonEmpty = t
    store._absorbLegacyStore()
  }

  // --- what a row may hold -------------------------------------------------

  // Unsafe keys and non-JSON values (PlainData.qml).
  PlainData { id: plain }

  // A coordinate off disk: returned as it is when it is a finite number in
  // [0, maxCoord] - the legitimate case - else the nearest bound for a
  // finite number (a numeric string counts), else 0.
  function _loadCoord(v) {
    if (typeof v === "number" && isFinite(v) && v >= 0 && v <= store.maxCoord) return v
    var n = store._finite(v)
    return n === null ? 0 : Math.min(store.maxCoord, Math.max(0, n))
  }

  // A size off disk: as it is when it is a finite number in [1, maxSize],
  // maxSize when it is larger, else `fallback` - a zero, negative or
  // non-numeric size has no nearest legal value worth keeping.
  function _loadSize(v, fallback) {
    if (typeof v === "number" && isFinite(v) && v >= 1 && v <= store.maxSize) return v
    var n = store._finite(v)
    if (n === null || n < 1) return fallback
    return Math.min(store.maxSize, n)
  }

  function _finite(v) {
    if (typeof v === "string" && v.trim() === "") return null
    var n = (typeof v === "number" || typeof v === "string") ? Number(v) : NaN
    return isFinite(n) ? n : null
  }

  // A row as it came off disk, made safe to bind: a fresh object with only
  // safe own keys, x/y in [0, maxCoord], w/h in [1, maxSize], `settings` a
  // plain JSON object within maxSettingsChars, `style` a short string. Values
  // already inside those bounds are returned exactly as they were, and the
  // row itself is always kept. A value that is not a row at all (null, a
  // number) is passed through unchanged, as the load always did.
  function _normaliseRow(row) {
    if (!row || typeof row !== "object" || Array.isArray(row)) return row
    var out = {}
    var keys = Object.keys(row)
    for (var i = 0; i < keys.length; i++)
      if (!plain.isUnsafeKey(keys[i])) out[keys[i]] = row[keys[i]]

    // An impossible size falls back to the type's default.
    var floor = store._sizeFloor(out.type)
    var size = store.registry ? store.registry.defaultSize(String(out.type || "")) : null
    out.x = store._loadCoord(out.x)
    out.y = store._loadCoord(out.y)
    out.w = store._loadSize(out.w, Math.max(floor.width, size ? Number(size.width) || 0 : 0))
    out.h = store._loadSize(out.h, Math.max(floor.height, size ? Number(size.height) || 0 : 0))

    var settings = plain.cleanObject(out.settings)
    if (plain.exceedsBytes(JSON.stringify(settings), store.maxSettingsChars)) {
      console.warn("nothing-glass.json: settings of '" + out.id + "' exceed " +
                   store.maxSettingsChars + " bytes; the widget is kept with none")
      settings = {}
    }
    out.settings = settings

    if ("style" in out && (typeof out.style !== "string" || out.style.length > store.maxStyleChars))
      delete out.style
    return out
  }

  function _normaliseRows(rows) {
    var out = []
    for (var i = 0; i < rows.length; i++) out.push(store._normaliseRow(rows[i]))
    return out
  }

  // The smallest size a writer may set for `type`, { width, height }: the
  // registry's minimum when it knows the type, else 1.
  function _sizeFloor(type) {
    var min = store.registry ? store.registry.minSize(String(type || "")) : null
    return {
      width: Math.max(1, min ? Number(min.width) || 0 : 0),
      height: Math.max(1, min ? Number(min.height) || 0 : 0)
    }
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
  // overwriting a widget the user can see.
  //
  // "Done" is recorded IN THIS DOCUMENT, as the source's name in its
  // `absorbed` list, written by the same atomic write that carries the
  // absorbed rows - so the rows and the record can never land apart, and a
  // name on that list is never read again. The source is still renamed to
  // .migrated afterwards, as the undo and to tidy up, but nothing depends on
  // that rename: `mv -n` silently keeps the source when a `.migrated` is
  // already there (a restored backup, a sync tool), and when the rename was
  // the only marker every start re-absorbed the same widgets under fresh ids
  // - one more copy of each per restart.
  //
  // Only the REAL store may do this. A Store pointed at a scratch file - the
  // dev harness does exactly that - would otherwise absorb the user's Nothing
  // widgets into the scratch file and rename the source away, so the
  // installed plugin finds nothing left to migrate and the widgets are gone
  // from the desktop. Caught in a smoke test, on real data, which is the only
  // reason this guard exists.
  readonly property string _defaultPath: store._home + "/.config/omarchy/" + store.identity.storeName + ".json"
  readonly property bool _mayAbsorb: store.path === store._defaultPath

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

  // The names this document records as already absorbed (see above). Only
  // the three known names are kept, so the list cannot grow.
  property var _absorbedFiles: []
  readonly property var _legacyNames: ["liquidglass.json", "nothing.json", "liquid-nothing.json"]

  function _readAbsorbed(list) {
    var out = []
    if (!Array.isArray(list)) return out
    for (var i = 0; i < list.length; i++) {
      var n = String(list[i])
      if (store._legacyNames.indexOf(n) !== -1 && out.indexOf(n) === -1) out.push(n)
    }
    return out
  }

  function _markLegacyDone(name) {
    if (name === "liquidglass.json") store._legacyGlassDone = true
    else if (name === "nothing.json") store._legacyNothingDone = true
    else store._legacyLiquidNothingDone = true
  }

  // `pinStyle` is the style incoming rows get when they carry none: the
  // second plugin's rows were all Nothing; this plugin's own older files
  // already recorded a style per row and keep it.
  function _absorbLegacy(view, name, pinStyle) {
    if (!store.loaded || store._corrupt || store._overCap || !store._mayAbsorb) return
    if (store._absorbedFiles.indexOf(name) !== -1) { store._markLegacyDone(name); return }
    var text = ""
    try { text = view.text() } catch (e) { return }
    if (!text || text.trim() === "") return
    if (plain.exceedsBytes(text, store.maxFileChars)) {
      console.warn(name + " is larger than " + store.maxFileChars + " bytes, leaving it alone")
      store._markLegacyDone(name)
      return
    }

    var parsed
    try { parsed = JSON.parse(text) } catch (e) {
      console.warn(name + " could not be parsed, leaving it alone: " + e)
      return
    }
    if (!parsed || !Array.isArray(parsed.widgets)) return

    var list = store.widgets.slice()
    var taken = {}
    for (var i = 0; i < list.length; i++) if (list[i]) taken[String(list[i].id)] = true

    var incoming = []
    for (var j = 0; j < parsed.widgets.length; j++) {
      var w = store._normaliseRow(parsed.widgets[j])
      if (!w || typeof w !== "object" || !w.type) continue
      // A row out of a retired FILE may also carry a retired TYPE — the two
      // renames are independent, and both readers end up here or in
      // `_applyText`, the only two places rows are built.
      var type = store._adoptLegacyType(w.type)
      var id = String(w.id || "")
      if (id === "" || taken[id]) id = store._genId(type, taken)
      taken[id] = true
      var row = {
        id: id, type: type, screen: String(w.screen || ""),
        x: w.x, y: w.y, w: w.w, h: w.h, settings: w.settings
      }
      var style = String(w.style || "") || pinStyle
      if (style !== "") row.style = style
      incoming.push(row)
    }

    store._markLegacyDone(name)
    if (incoming.length === 0) return
    // All or nothing: a partial absorb would have to be recorded as done (and
    // lose the rest) or not (and duplicate the part that came across).
    if (list.length + incoming.length > store.maxWidgets) {
      console.warn("nothing-glass: " + name + " has " + incoming.length + " widget(s), more than the " +
                   store.maxWidgets + "-widget limit leaves room for; leaving it where it is")
      return
    }

    var from = String(view.path)
    store._absorbedFiles = store._absorbedFiles.concat([name])
    store.widgets = list.concat(incoming)
    store._scheduleWrite()
    chores.retire(from, from + ".migrated")
    console.log("nothing-glass: absorbed " + incoming.length + " widget(s) from " + name)
  }

  // A malformed store is backed up and remains read-only until a successful
  // reload. An IPC mutation must not replace the only original bad document.
  property bool _warnedCorrupt: false
  function _rejectCorrupt(text, reason) {
    store._corrupt = true
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

  // Write-only sink for the corrupt-file backup; its text is never used. It
  // holds the same settings the store does, so it is made private the same
  // way, on load as well, for a .bak an earlier build left 0644.
  FileView {
    id: backupFile
    path: store._backupPath
    printErrors: false
    onLoaded: chores.restrict(store._backupPath)
    onSaved: chores.restrict(store._backupPath)
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
    if (store._corrupt || store._overCap) return
    store._selfWrite = true
    store._lastWriteAt = Date.now()
    store._writtenRevision = store._revision
    var payload = { version: 1, widgets: store.widgets }
    // Only once something has been absorbed, so an ordinary document keeps
    // its two keys.
    if (store._absorbedFiles.length > 0) payload.absorbed = store._absorbedFiles
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
      // The layout and every widget's settings: owner-only (OwnFiles.qml).
      chores.restrict(store.path)
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
    store.lastError = ""
    if (store._corrupt) return store._refuse("store is unreadable; repair it and reload before editing")
    if (store._overCap)
      return store._refuse("store holds more than " + store.maxWidgets + " widgets; remove some by hand and reload before editing")
    if (store.loaded) return true
    console.warn("nothing-glass.json: " + op + " refused — store not loaded yet")
    store.lastError = "store not loaded yet, retry"
    return false
  }

  function _refuse(message) {
    store.lastError = message
    return false
  }

  function _rowAt(id) {
    var idx = store._indexOf(id)
    if (idx === -1) store._refuse("no widget with id '" + id + "'")
    return idx
  }

  // A row's own keys onto a fresh object. Rows only ever hold safe keys (the
  // load and the writers below see to that), and Object.keys never walks a
  // prototype.
  function _copyRow(row) {
    var out = {}
    var keys = Object.keys(row)
    for (var i = 0; i < keys.length; i++) out[keys[i]] = row[keys[i]]
    return out
  }

  // A position or size handed to a writer: a finite number, clamped to
  // [lo, hi]; null for anything else (NaN, Infinity, a string, undefined).
  function _numberArg(v, lo, hi) {
    if (typeof v !== "number" || !isFinite(v)) return null
    return Math.min(hi, Math.max(lo, v))
  }

  // A per-instance `settings` object a writer may store: plain JSON data,
  // safe keys, within maxSettingsChars. Returns the clean copy, or null.
  function _settingsArg(settings) {
    if (settings === undefined || settings === null) return {}
    if (typeof settings !== "object" || Array.isArray(settings)) return null
    var c = plain.clean(settings)
    if (!c.ok || plain.exceedsBytes(JSON.stringify(c.value), store.maxSettingsChars)) return null
    return c.value
  }

  // opts: optional { x, y, w, h, settings } — anything omitted gets a sane
  // default so a bare `add(type, screen)` IPC call always produces a usable
  // instance. Returns the new id, or "" with `lastError` saying why.
  function add(type, screen, opts) {
    if (!store._writable("add")) return ""
    if (store.widgets.length >= store.maxWidgets) {
      store._refuse("the store already holds " + store.widgets.length + " widgets, the limit is " + store.maxWidgets)
      return ""
    }
    opts = opts || {}
    var floor = store._sizeFloor(type)
    var x = opts.x !== undefined ? store._numberArg(opts.x, 0, store.maxCoord) : 120
    var y = opts.y !== undefined ? store._numberArg(opts.y, 0, store.maxCoord) : 120
    var w = store._numberArg(opts.w !== undefined ? opts.w : 300, floor.width, store.maxSize)
    var h = store._numberArg(opts.h !== undefined ? opts.h : 300, floor.height, store.maxSize)
    if (x === null || y === null || w === null || h === null) {
      store._refuse("position and size must be finite numbers")
      return ""
    }
    var settings = store._settingsArg(opts.settings)
    if (settings === null) {
      store._refuse("settings must be a plain JSON object of at most " + store.maxSettingsChars + " bytes")
      return ""
    }
    var id = store._genId(type)
    var entry = {
      id: id,
      type: String(type),
      screen: String(screen),
      x: x, y: y, w: w, h: h,
      settings: settings
    }
    var list = store.widgets.slice()
    list.push(entry)
    store.widgets = list
    store._scheduleWrite()
    return id
  }

  function remove(id) {
    if (!store._writable("remove")) return false
    var idx = store._rowAt(id)
    if (idx === -1) return false
    var list = store.widgets.slice()
    list.splice(idx, 1)
    store.widgets = list
    store._scheduleWrite()
    return true
  }

  // x/y: finite numbers, clamped to [0, maxCoord].
  function move(id, x, y) {
    if (!store._writable("move")) return false
    var nx = store._numberArg(x, 0, store.maxCoord)
    var ny = store._numberArg(y, 0, store.maxCoord)
    if (nx === null || ny === null) return store._refuse("x and y must be finite numbers")
    var idx = store._rowAt(id)
    if (idx === -1) return false
    var list = store.widgets.slice()
    var entry = store._copyRow(list[idx])
    entry.x = nx
    entry.y = ny
    list[idx] = entry
    store.widgets = list
    store._scheduleWrite()
    return true
  }

  // w/h: finite numbers, clamped to [the type's registry minimum, maxSize].
  function resize(id, w, h) {
    if (!store._writable("resize")) return false
    var idx = store._rowAt(id)
    if (idx === -1) return false
    var floor = store._sizeFloor(store.widgets[idx].type)
    var nw = store._numberArg(w, floor.width, store.maxSize)
    var nh = store._numberArg(h, floor.height, store.maxSize)
    if (nw === null || nh === null) return store._refuse("w and h must be finite numbers")
    var list = store.widgets.slice()
    var entry = store._copyRow(list[idx])
    entry.w = nw
    entry.h = nh
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

  // Any other key lands in the row's `settings`, refused when it is not a
  // plain data key (PlainData.isUnsafeKey), when the value is not plain JSON
  // data (PlainData.clean) or when the row's settings would outgrow maxSettingsChars.
  // Which keys a caller may set at all is the caller's business - the IPC
  // verb allows only real settings (Service.qml).
  function set(id, key, value) {
    if (!store._writable("set")) return false
    var k = String(key)
    var idx = store._rowAt(id)
    if (idx === -1) return false
    var list = store.widgets.slice()
    var entry = store._copyRow(list[idx])
    if (store._isReserved(k)) {
      var s = String(value || "")
      if (s.length > store.maxStyleChars)
        return store._refuse(k + " is longer than " + store.maxStyleChars + " characters")
      if (s === "") delete entry[k]
      else entry[k] = s
      list[idx] = entry
      store.widgets = list
      store._scheduleWrite()
      return true
    }
    if (plain.isUnsafeKey(k)) return store._refuse("'" + k + "' is not a settable key")
    var c = plain.clean(value)
    if (!c.ok) return store._refuse("the value of " + k + " is not plain JSON data (finite numbers only)")
    var settings = store._copyRow(entry.settings || {})
    settings[k] = c.value
    if (plain.exceedsBytes(JSON.stringify(settings), store.maxSettingsChars))
      return store._refuse("the settings of " + id + " would exceed " + store.maxSettingsChars + " bytes")
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
    var k = String(key)
    var idx = store._rowAt(id)
    if (idx === -1) return false
    if (store._isReserved(k)) return store.set(id, k, "")
    var prevSettings = store.widgets[idx].settings || {}
    if (!Object.prototype.hasOwnProperty.call(prevSettings, k)) return true
    var list = store.widgets.slice()
    var entry = store._copyRow(list[idx])
    var settings = {}
    var keys = Object.keys(prevSettings)
    for (var i = 0; i < keys.length; i++) if (keys[i] !== k) settings[keys[i]] = prevSettings[keys[i]]
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
