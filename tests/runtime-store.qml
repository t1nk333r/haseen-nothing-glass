import QtQuick
import Quickshell
import Quickshell.Io
import "plugin"

// NOTE: `qs` refuses to load a QML module path outside the config folder, so
// run.sh copies this file into a scratch directory that also carries a
// `plugin` symlink to the runtime under test - hence the plain
// `import "plugin"`.
//
// Headless check of Store.qml's public surface: the mutations every writer
// goes through, the reserved `style` column, the one-time migration from the
// retired store names, the corrupt-file path, and the fact that a mutation
// actually reaches the disk. It exists because two data-loss defects shipped
// through this gap - a migration that could rename away a widget the user can
// see, and a store document that was only ever checked by reading the code
// that wrote it.
//
// HOME points at a scratch directory for this process (run.sh sets it), so
// nothing here can touch the user's own layout, with one deliberate
// exception: Store._mayAbsorb only lets a store at its DEFAULT path absorb a
// retired file, so the migration case leaves `path` alone and migrates the
// fixtures run.sh wrote into the scratch HOME.
ShellRoot {
  Item {
    id: host

    readonly property string home: Quickshell.env("HOME")

    // The store under test. Its file does not exist yet: a first run.
    Store { id: scratchStore; path: host.home + "/scratch/store.json" }
    // `path` deliberately left at its default - see the header.
    Store { id: migratorStore }
    // Fed a truncated document by run.sh.
    Store { id: corruptStore; path: host.home + "/scratch/corrupt.json" }
    // Fed a document that carries a retired widget type (and one the registry
    // never had). Its path is a scratch one, so `_mayAbsorb` is false here:
    // the type mapping must not be gated on the real store the way the
    // retired-file absorb is.
    Store { id: typeStore; path: host.home + "/scratch/renamed-type.json" }
    // 37 ordinary rows shaped like a real desktop: must load exactly as written.
    Store { id: legitStore; path: host.home + "/scratch/legit.json" }
    // Rows no writer produces: clamped on load, every one kept.
    Store { id: hostileStore; path: host.home + "/scratch/hostile.json" }
    // A well-formed document past the parse cap: the corrupt-file path.
    Store { id: hugeStore; path: host.home + "/scratch/huge.json" }
    // 300 ordinary rows: all load, and no further add is accepted.
    Store { id: crowdStore; path: host.home + "/scratch/crowd.json" }
    // Starts empty; filled by add() until the row cap refuses.
    Store { id: limitStore; path: host.home + "/scratch/limit.json" }
    // A later start of the shell: a fresh Store at the default path, created
    // once the first one has written, the way a restart reads the file.
    Component { id: restartComponent; Store {} }
    property var restartStore: null
    property int restartRound: 0
    property int settle: 0

    // Read back what the stores wrote, rather than trusting the in-memory
    // array: "the layout survives" is a claim about bytes on disk.
    FileView { id: storeFile; path: scratchStore.path; printErrors: false }
    // The corrupt document as it still sits on disk, and the backup the store
    // is supposed to have made of it.
    FileView { id: corruptOriginal; path: corruptStore.path; printErrors: false }
    FileView { id: corruptBackup; path: corruptStore.path + ".bak"; printErrors: false }
    FileView { id: realStoreFile; path: migratorStore.path; printErrors: false }
    FileView { id: legitFile; path: legitStore.path; printErrors: false }
    FileView { id: hugeOriginal; path: hugeStore.path; printErrors: false }
    FileView { id: hugeBackup; path: hugeStore.path + ".bak"; printErrors: false }

    // The mode of the files a store wrote, read with stat(1).
    Process {
      id: modeProbe
      property string out: ""
      property bool done: false
      stdout: StdioCollector { onStreamFinished: { modeProbe.out = String(this.text || ""); modeProbe.done = true } }
    }

    property int failures: 0
    property int checks: 0
    property int phase: 0
    property int waited: 0
    property string waitingFor: "the store to finish loading"
    // The ids of the two rows the mutation phase creates, so the persistence
    // phase can look them up in the document it reads back.
    property string firstId: ""
    property string secondId: ""

    function check(label, ok, detail) {
      host.checks++
      if (!ok) {
        host.failures++
        console.log("FAIL " + label + (detail ? "  (" + detail + ")" : ""))
      }
    }

    function fail(message) {
      console.log("FAIL " + message)
      Qt.exit(1)
    }

    function rowOf(store, id) {
      var list = store.widgets || []
      for (var i = 0; i < list.length; i++)
        if (list[i] && list[i].id === id) return list[i]
      return null
    }

    function idsOf(store) {
      var out = []
      var list = store.widgets || []
      for (var i = 0; i < list.length; i++) out.push(String(list[i].id))
      return out
    }

    function uniqueCount(list) {
      var seen = {}
      var n = 0
      for (var i = 0; i < list.length; i++) {
        if (seen[list[i]] === true) continue
        seen[list[i]] = true
        n++
      }
      return n
    }

    Timer {
      id: driver
      interval: 100
      repeat: true
      running: true

      onTriggered: {
        host.waited++
        if (host.waited > 100) host.fail("timed out waiting for " + host.waitingFor)
        host.step()
      }
    }

    // Each phase waits for one asynchronous thing and resets the budget, so a
    // stuck phase names itself rather than reporting a bare timeout.
    function next(phase, message) {
      host.phase = phase
      host.waitingFor = message
      host.waited = 0
    }

    function step() {
      switch (host.phase) {
      case 0: host.phaseLoaded(); break
      case 1: host.phaseMutate(); break
      case 2: host.phaseMigration(); break
      case 3: host.phaseCorruption(); break
      case 4: host.phasePersistence(); break
      case 5: host.phaseRestart(); break
      case 6: host.phaseWriterBounds(); break
      case 7: host.phaseLoadBounds(); break
      case 8: host.phaseLegitWrite(); break
      case 9: host.phaseModes(); break
      }
    }

    function phaseLoaded() {
      // `loaded` is the gate: a store that never settles fails this phase's
      // timeout by name rather than being asserted twice here.
      if (!scratchStore.loaded) return
      // A store file that is not there is a first run, not corruption.
      host.check("a missing store file settles to an empty layout",
                 scratchStore.widgets.length === 0, "widgets=" + scratchStore.widgets.length)

      // A widget `type` is also the directory its QML comes from, so a row
      // left on a retired name has no drawing at all - the failure this
      // mapping exists to stop. Only the retired name may change: the row
      // already on the living name and the name no table knows both come
      // through as they were.
      if (!typeStore.loaded) return
      var retired = host.rowOf(typeStore, "music-1")
      host.check("an instance carrying a retired type arrives on the living one",
                 !!retired && retired.type === "now-playing",
                 "row=" + JSON.stringify(retired))
      host.check("the renamed row keeps its own id, geometry and settings",
                 !!retired && retired.x === 16 && retired.w === 192 &&
                 !!retired.settings && retired.settings.playerFilter === "spotify",
                 "row=" + JSON.stringify(retired))
      var living = host.rowOf(typeStore, "now-playing-4")
      host.check("an instance already on the living type is untouched",
                 !!living && living.type === "now-playing",
                 "row=" + JSON.stringify(living))
      var unknown = host.rowOf(typeStore, "no-such-type-1")
      host.check("a type the mapping does not know is left exactly as it was",
                 !!unknown && unknown.type === "no-such-type",
                 "row=" + JSON.stringify(unknown))

      host.next(1, "the mutations to be visible in memory")
    }

    function phaseMutate() {
      // Sizes at or above each type's registry minimum: a writer floors a
      // size there (see phaseWriterBounds).
      var a = scratchStore.add("clock-digital", "TEST-1", { x: 10, y: 20, w: 400, h: 192 })
      var b = scratchStore.add("weather", "TEST-1", { x: 1, y: 2, w: 192, h: 192 })
      host.firstId = a
      host.secondId = b

      var first = host.rowOf(scratchStore, a)
      host.check("add() returns the id of the row it created",
                 a !== "" && !!first, "id=" + JSON.stringify(a))
      host.check("the added row carries the type and screen it was given",
                 !!first && first.type === "clock-digital" && first.screen === "TEST-1",
                 "row=" + JSON.stringify(first))
      host.check("add() honours the geometry it was handed",
                 !!first && first.x === 10 && first.y === 20 && first.w === 400 && first.h === 192,
                 "row=" + JSON.stringify(first))

      // A second row, so "leaves the others alone" has something to leave.
      var secondBefore = JSON.stringify(host.rowOf(scratchStore, b))
      scratchStore.move(a, 300, 400)
      var moved = host.rowOf(scratchStore, a)
      host.check("move() rewrites the named row's position only",
                 !!moved && moved.x === 300 && moved.y === 400 && moved.w === 400 && moved.h === 192,
                 "row=" + JSON.stringify(moved))
      scratchStore.resize(a, 500, 600)
      var resized = host.rowOf(scratchStore, a)
      host.check("resize() rewrites the named row's size only",
                 !!resized && resized.w === 500 && resized.h === 600 &&
                 resized.x === 300 && resized.y === 400,
                 "row=" + JSON.stringify(resized))
      host.check("move and resize leave the other rows untouched",
                 JSON.stringify(host.rowOf(scratchStore, b)) === secondBefore,
                 "was " + secondBefore + " now " + JSON.stringify(host.rowOf(scratchStore, b)))

      // The reserved column. `style` is resolved into a drawing before a host
      // is ever built, so it has to live on the row; routed through `settings`
      // instead it would sit somewhere nothing reads, which is a defect that
      // actually shipped.
      scratchStore.set(a, "style", "nothing")
      var styled = host.rowOf(scratchStore, a)
      host.check("set('style') writes the row's own column, not its settings",
                 !!styled && styled.style === "nothing" &&
                 !!styled.settings && !("style" in styled.settings),
                 "row=" + JSON.stringify(styled))
      scratchStore.set(a, "style", "")
      var unstyled = host.rowOf(scratchStore, a)
      host.check("set('style', '') removes the column instead of storing it blank",
                 !!unstyled && !("style" in unstyled), "row=" + JSON.stringify(unstyled))

      // Any other key is the instance's own setting value.
      scratchStore.set(a, "textColor", "#123456")
      var setting = host.rowOf(scratchStore, a)
      host.check("set(<any other key>) lands in the row's settings object",
                 !!setting && setting.textColor === undefined &&
                 !!setting.settings && setting.settings.textColor === "#123456",
                 "row=" + JSON.stringify(setting))

      // unset() is the "cleared field" path: the plugin-wide value applies
      // again, and only that one key is dropped.
      scratchStore.set(a, "unit", "metric")
      scratchStore.unset(a, "unit")
      var cleared = host.rowOf(scratchStore, a)
      host.check("unset() drops the per-instance override again",
                 !!cleared && !!cleared.settings && !("unit" in cleared.settings) &&
                 cleared.settings.textColor === "#123456",
                 "row=" + JSON.stringify(cleared))

      host.next(2, "the retired store's widgets to arrive")
    }

    function phaseMigration() {
      // The retired file arrives on its own FileView's schedule, and the store
      // retries the absorb once its own load settles, so wait for the count
      // rather than for a fixed delay.
      if (!migratorStore.loaded || migratorStore.widgets.length !== 6) return

      var ids = host.idsOf(migratorStore)
      host.check("the retired store's rows are absorbed into this one",
                 ids.length === 6, "ids=" + ids.join(","))
      host.check("every id in the store is still unique after the absorb",
                 host.uniqueCount(ids) === 6, "ids=" + ids.join(","))

      // liquidglass.json: its `.migrated` name was already taken, so the
      // rename cannot happen - the absorb itself still must, once.
      var battery = host.rowOf(migratorStore, "battery-1")
      host.check("a retired file whose .migrated name is taken is still absorbed",
                 !!battery && battery.x === 21 && battery.y === 22 && battery.w === 192 &&
                 !("style" in battery), "row=" + JSON.stringify(battery))

      // The colliding row keeps the geometry the user can see; the incoming
      // one is renamed and keeps its own.
      var kept = host.rowOf(migratorStore, "clock-digital-1")
      host.check("the id that was already taken is not overwritten",
                 !!kept && kept.x === 10 && kept.y === 20 && kept.w === 30 && kept.h === 40,
                 "row=" + JSON.stringify(kept))

      var renamed = null
      var rows = migratorStore.widgets || []
      for (var i = 0; i < rows.length; i++)
        if (rows[i].type === "clock-digital" && rows[i].id !== "clock-digital-1") renamed = rows[i]
      host.check("the renamed row kept the incoming widget's own geometry",
                 !!renamed && renamed.x === 1 && renamed.y === 2 && renamed.screen === "TEST-1",
                 "row=" + JSON.stringify(renamed))

      var free = host.rowOf(migratorStore, "weather-1")
      host.check("a free id is kept, with screen, position, size and settings",
                 !!free && free.screen === "TEST-1" && free.x === 5 && free.y === 6 &&
                 free.w === 7 && free.h === 8 &&
                 !!free.settings && free.settings.textColor === "#abcdef",
                 "row=" + JSON.stringify(free))
      host.check("absorbed rows from the retired Nothing plugin keep its style",
                 !!renamed && renamed.style === "nothing" &&
                 !!free && free.style === "nothing",
                 "renamed=" + JSON.stringify(renamed) + " free=" + JSON.stringify(free))

      // The file this plugin kept before plan 053 renamed it. These rows are
      // this plugin's own, so they keep the style they were drawn with - and a
      // row that carried none must not come back pinned to Nothing, which is
      // what absorbing them through the Nothing reader would do.
      var styled = host.rowOf(migratorStore, "timer-1")
      host.check("a row from the store's previous name keeps the style it carried",
                 !!styled && styled.style === "liquid-glass" &&
                 styled.x === 9 && styled.y === 8 && styled.w === 7 && styled.h === 6 &&
                 !!styled.settings && styled.settings.durationSec === 300,
                 "row=" + JSON.stringify(styled))

      var plain = host.rowOf(migratorStore, "perf-1")
      host.check("a row from the store's previous name is not pinned to a style",
                 !!plain && plain.x === 11 && plain.y === 12 && !("style" in plain),
                 "row=" + JSON.stringify(plain))

      host.next(3, "the corrupt document to be backed up")
    }

    function phaseCorruption() {
      if (!corruptStore.loaded) return
      // The backup is a FileView write, so it lands after the load failure,
      // and the path did not exist when this reader was created - ask for the
      // file again every tick instead of trusting a watch on it.
      corruptBackup.reload()
      corruptOriginal.reload()
      var backup = String(corruptBackup.text() || "")
      if (backup === "") return

      host.check("an unparseable store document renders no widgets",
                 corruptStore.widgets.length === 0, "widgets=" + corruptStore.widgets.length)
      host.check("the unreadable bytes are copied to a .bak beside it, unchanged",
                 backup === String(corruptOriginal.text() || ""),
                 "backup=" + JSON.stringify(backup) +
                 " original=" + JSON.stringify(String(corruptOriginal.text() || "")))
      host.next(4, "the layout to reach the disk")
    }

    function phasePersistence() {
      storeFile.reload()
      var text = String(storeFile.text() || "")
      if (text === "") return
      var doc = null
      try { doc = JSON.parse(text) } catch (e) { return }
      // The first mutation writes immediately and the rest coalesce into a
      // trailing write, so the document only carries two rows once the burst
      // has landed.
      if (!doc || !Array.isArray(doc.widgets) || doc.widgets.length !== 2) return

      var first = null
      for (var i = 0; i < doc.widgets.length; i++)
        if (doc.widgets[i].id === host.firstId) first = doc.widgets[i]

      host.check("both rows reach the file", doc.widgets.length === 2,
                 "widgets=" + doc.widgets.length)
      host.check("the file carries the geometry the mutations set",
                 !!first && first.x === 300 && first.y === 400 && first.w === 500 && first.h === 600,
                 "row=" + JSON.stringify(first))
      host.check("the file carries the settings write and neither removed key",
                 !!first && !!first.settings && first.settings.textColor === "#123456" &&
                 !("style" in first) && !("unit" in first.settings),
                 "row=" + JSON.stringify(first))

      // remove() is the other half of add(): it must drop the row it was given
      // and nothing else, and refuse an id it does not hold.
      host.check("remove() drops the row it was given",
                 scratchStore.remove(host.secondId) === true &&
                 host.rowOf(scratchStore, host.secondId) === null &&
                 host.rowOf(scratchStore, host.firstId) !== null)
      host.check("remove() refuses an id it does not hold",
                 scratchStore.remove("no-such-widget") === false)

      host.next(5, "a restarted store to settle")
    }

    function countAt(list, x, y) {
      var n = 0
      for (var i = 0; i < list.length; i++)
        if (list[i] && list[i].x === x && list[i].y === y) n++
      return n
    }

    // Two more starts of the real store after the first one absorbed the
    // retired files. liquidglass.json is still on disk (its `.migrated` name
    // was taken), so a start that only trusts the rename absorbs it again -
    // one more copy of that widget per restart.
    function phaseRestart() {
      if (host.restartStore === null) {
        realStoreFile.reload()
        var doc = null
        try { doc = JSON.parse(String(realStoreFile.text() || "")) } catch (e) { return }
        if (!doc || !Array.isArray(doc.widgets) || doc.widgets.length < 6) return
        host.restartStore = restartComponent.createObject(host)
        host.settle = 0
        return
      }
      var s = host.restartStore
      if (!s.loaded || !s._legacyGlassDone || !s._legacyNothingDone || !s._legacyLiquidNothingDone) return
      // A few ticks for anything the start decided to write.
      if (++host.settle < 4) return
      host.restartRound++
      host.check("restart " + host.restartRound + " keeps one copy of every absorbed widget",
                 s.widgets.length === 6 && host.countAt(s.widgets, 21, 22) === 1,
                 "widgets=" + s.widgets.length + " battery copies=" + host.countAt(s.widgets, 21, 22))
      s.destroy()
      host.restartStore = null
      if (host.restartRound < 2) return
      realStoreFile.reload()
      var onDisk = null
      try { onDisk = JSON.parse(String(realStoreFile.text() || "")) } catch (e) { onDisk = null }
      var rows = onDisk && Array.isArray(onDisk.widgets) ? onDisk.widgets : []
      host.check("after the restarts the file still holds one copy of every widget",
                 rows.length === 6 && host.countAt(rows, 21, 22) === 1,
                 "widgets=" + rows.length + " battery copies=" + host.countAt(rows, 21, 22))
      host.next(6, "the writer bounds")
    }

    // The single writer refuses what no UI produces and clamps the absurd.
    function phaseWriterBounds() {
      var a = host.firstId
      var before = JSON.stringify(host.rowOf(scratchStore, a))
      host.check("move() refuses NaN",
                 scratchStore.move(a, NaN, 5) === false && scratchStore.lastError !== "" &&
                 JSON.stringify(host.rowOf(scratchStore, a)) === before,
                 "row=" + JSON.stringify(host.rowOf(scratchStore, a)))
      host.check("move() refuses Infinity and strings",
                 scratchStore.move(a, Infinity, 5) === false &&
                 scratchStore.move(a, "100", 5) === false &&
                 JSON.stringify(host.rowOf(scratchStore, a)) === before,
                 "row=" + JSON.stringify(host.rowOf(scratchStore, a)))
      scratchStore.move(a, 1e308, -50)
      var moved = host.rowOf(scratchStore, a)
      host.check("move() clamps an absurd position into range",
                 !!moved && moved.x === scratchStore.maxCoord && moved.y === 0,
                 "row=" + JSON.stringify(moved))
      scratchStore.resize(a, -5, 1e308)
      var sized = host.rowOf(scratchStore, a)
      host.check("resize() floors at the type's minimum and caps at the maximum",
                 !!sized && sized.w === 160 && sized.h === scratchStore.maxSize,
                 "row=" + JSON.stringify(sized))
      host.check("resize() refuses NaN",
                 scratchStore.resize(a, NaN, 200) === false && host.rowOf(scratchStore, a).w === 160)

      var proto = JSON.parse('{"__proto__": {"polluted": true}}')
      host.check("set() refuses __proto__, constructor and inherited names",
                 scratchStore.set(a, "__proto__", { polluted: true }) === false &&
                 scratchStore.set(a, "constructor", 1) === false &&
                 scratchStore.set(a, "toString", "x") === false &&
                 scratchStore.set(a, "prototype", 1) === false)
      host.check("set() refuses a value carrying an own __proto__ key, and NaN",
                 scratchStore.set(a, "nested", proto) === false &&
                 scratchStore.set(a, "ratio", NaN) === false)
      var settings = host.rowOf(scratchStore, a).settings
      var copy = {}
      for (var k in settings) copy[k] = settings[k]
      host.check("no refused key reaches the row, and a copy of it is not polluted",
                 Object.getPrototypeOf(settings) === Object.prototype &&
                 copy.polluted === undefined && !("nested" in settings) && !("ratio" in settings),
                 "settings=" + JSON.stringify(settings))
      var big = new Array(2 * 1024 * 1024 + 1).join("x")
      host.check("set() refuses a value past the per-row settings cap",
                 scratchStore.set(a, "big", big) === false && !("big" in host.rowOf(scratchStore, a).settings))
      host.check("set() still takes an ordinary value",
                 scratchStore.set(a, "location", "Oslo") === true &&
                 host.rowOf(scratchStore, a).settings.location === "Oslo")

      var added = 0
      var refusal = ""
      for (var i = 0; i < 300; i++) {
        var id = limitStore.add("perf", "TEST-1", { x: 16, y: 16, w: 192, h: 192 })
        if (id !== "") added++
        else if (refusal === "") refusal = String(limitStore.lastError)
      }
      host.check("add() stops at the row cap with an error",
                 added === limitStore.maxWidgets && limitStore.widgets.length === limitStore.maxWidgets &&
                 refusal !== "",
                 "added=" + added + " error=" + JSON.stringify(refusal))
      host.next(7, "the bounded stores to load")
    }

    function phaseLoadBounds() {
      if (!hostileStore.loaded || !legitStore.loaded || !hugeStore.loaded || !crowdStore.loaded) return

      // Every hostile row kept, each clamped to something drawable.
      host.check("a hostile document keeps every row",
                 host.idsOf(hostileStore).join(",") === "inf-1,huge-1,proto-1",
                 "ids=" + host.idsOf(hostileStore).join(","))
      var inf = host.rowOf(hostileStore, "inf-1")
      host.check("non-finite and negative geometry is clamped on load",
                 !!inf && inf.x === 0 && inf.y === 0 && inf.w === 192 && inf.h === 192,
                 "row=" + JSON.stringify(inf))
      var copy = {}
      for (var k in (inf ? inf.settings : {})) copy[k] = inf.settings[k]
      host.check("a __proto__ settings key is dropped on load, the rest kept",
                 !!inf && Object.getPrototypeOf(inf.settings) === Object.prototype &&
                 copy.polluted === undefined && inf.settings.location === "Paris" &&
                 Object.keys(inf.settings).length === 1,
                 "settings=" + JSON.stringify(inf ? inf.settings : null))
      var huge = host.rowOf(hostileStore, "huge-1")
      host.check("absurd and string geometry is clamped, oversized settings emptied",
                 !!huge && huge.x === hostileStore.maxCoord && huge.y === 12 && huge.w === 192 &&
                 huge.h === 192 && Object.keys(huge.settings).length === 0,
                 "row=" + JSON.stringify(huge).slice(0, 200))
      var proto = host.rowOf(hostileStore, "proto-1")
      host.check("a row-level __proto__, a constructor setting and a non-string style are dropped",
                 !!proto && Object.getPrototypeOf(proto) === Object.prototype && proto.polluted === undefined &&
                 !("style" in proto) && proto.settings.durationSec === 300 &&
                 !Object.prototype.hasOwnProperty.call(proto.settings, "constructor") && proto.x === 16,
                 "row=" + JSON.stringify(proto))

      // 37 ordinary rows: the load hands back exactly what the file says.
      legitFile.reload()
      var fixture = JSON.parse(String(legitFile.text()))
      host.check("a 37-widget layout loads unchanged",
                 legitStore.widgets.length === 37 &&
                 JSON.stringify(legitStore.widgets) === JSON.stringify(fixture.widgets),
                 "widgets=" + legitStore.widgets.length)

      // Past the parse cap: the corrupt-file path, not a load.
      host.check("a document past the parse cap is not loaded",
                 hugeStore.widgets.length === 0, "widgets=" + hugeStore.widgets.length)

      host.check("a store holding more rows than the cap keeps every one of them",
                 crowdStore.widgets.length === 300, "widgets=" + crowdStore.widgets.length)
      host.check("and accepts no further add()",
                 crowdStore.add("perf", "TEST-1") === "" && crowdStore.widgets.length === 300 &&
                 crowdStore.lastError !== "", "error=" + JSON.stringify(crowdStore.lastError))

      // The one mutation the next phase reads back from disk.
      legitStore.set("weather-1", "refreshMinutes", 45)
      host.next(8, "the oversized document's backup and the 37-widget write")
    }

    function phaseLegitWrite() {
      hugeBackup.reload()
      legitFile.reload()
      var backup = String(hugeBackup.text() || "")
      var doc = null
      try { doc = JSON.parse(String(legitFile.text() || "")) } catch (e) { return }
      var weather = null
      for (var i = 0; doc && i < doc.widgets.length; i++)
        if (doc.widgets[i].id === "weather-1") weather = doc.widgets[i]
      if (!weather || weather.settings.refreshMinutes !== 45) return
      // No backup is coming for a document that was loaded instead (that
      // already failed in the previous phase); do not wait for one.
      if (backup === "" && hugeStore.widgets.length === 0) return

      hugeOriginal.reload()
      host.check("the oversized document is backed up unchanged and left on disk",
                 backup.length > hugeStore.maxFileChars &&
                 backup === String(hugeOriginal.text() || ""),
                 "backup=" + backup.length + " original=" + String(hugeOriginal.text() || "").length)

      // A write of the 37-widget layout changes the one value it was asked to
      // and carries every other row through byte for byte.
      var fixture = JSON.parse(JSON.stringify(legitStore.widgets))
      var others = 0
      for (var j = 0; j < doc.widgets.length; j++) {
        if (doc.widgets[j].id === "weather-1") continue
        if (JSON.stringify(doc.widgets[j]) === JSON.stringify(fixture[j])) others++
      }
      host.check("writing one setting leaves the other 36 rows exactly as they were",
                 doc.widgets.length === 37 && others === 36 && !("absorbed" in doc) &&
                 weather.settings.location === "Lisbon" && weather.settings.unit === "metric",
                 "rows=" + doc.widgets.length + " unchanged=" + others)
      host.next(9, "the store's files to be owner-only (0600)")
    }

    function phaseModes() {
      if (modeProbe.running) return
      if (!modeProbe.done) {
        modeProbe.command = ["stat", "-c", "%a %n", scratchStore.path, corruptStore.path + ".bak",
                             legitStore.path, hugeStore.path + ".bak"]
        modeProbe.running = true
        return
      }
      var lines = modeProbe.out.trim().split("\n")
      var allPrivate = lines.length === 4
      for (var i = 0; i < lines.length; i++) if (lines[i].indexOf("600 ") !== 0) allPrivate = false
      if (!allPrivate) {
        // The chmod runs after the write lands; ask again next tick.
        host.waitingFor = "the store's files to be owner-only (0600), last seen: " + lines.join("; ")
        modeProbe.done = false
        return
      }
      host.check("the store, the files it wrote and its backups are mode 0600", allPrivate)

      driver.stop()
      console.log(host.failures === 0
        ? "OK: store round-trip and migration (" + host.checks + " checks)"
        : host.failures + " of " + host.checks + " store checks FAILED")
      Qt.exit(host.failures === 0 ? 0 : 1)
    }
  }
}
