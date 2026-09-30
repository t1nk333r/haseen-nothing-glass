import QtQuick

// Maps a widget `type` string (as stored in nothing-glass.json) to its QML
// entry point, its minimum size and the words the catalogue shows for it.
//
// Stateless and dependency-free (no shell, no manifest), so it is safe to
// instantiate wherever it is needed rather than threading a single shared
// instance through every file — GlassSurface.qml and Service.qml each hold
// their own, and everything else is handed one of those.
QtObject {
  id: registry

  // type -> { path: relative to THIS file's own directory (the plugin root),
  //           so it resolves the same way whether this file is loaded from
  //           the checkout or from the deployed
  //           ~/.config/omarchy/plugins/t1nk33r.nothing-glass/. The strings
  //           themselves carry no "..": the standalone `qs -p` dev harness
  //           refuses any import or URL that textually leaves the entry file's
  //           directory — see glass-dev.qml's header.
  //           minWidth/minHeight mirror the ported widget's own
  //           Layout.minimumWidth/Height (PORTING.md item 6) and are
  //           enforced by Placement.qml's resize clamp.
  // `nothing: true` means `widgets-nothing/<type>/main.qml` exists as a
  // SECOND presentation of the same widget. The Liquid Glass file under
  // `widgets/` is untouched by that flag; `urlFor()` falls back to it for any
  // type that has no Nothing view yet, so a half-finished style still runs.
  //
  // `label`/`group`/`hint` are catalogue data for the launcher. They live
  // here because the launcher, the bar panel and the settings sheet all need
  // the same words, and three copies drift.
  readonly property var _entries: ({
    placeholder: { path: "widgets/placeholder/main.qml", minWidth: 120, minHeight: 120,
      dev: true, label: "Placeholder", group: "Dev", hint: "Plain glass, no content" },
    "test-glass": { path: "widgets/test-glass/main.qml", minWidth: 160, minHeight: 160,
      dev: true, label: "Glass test", group: "Dev", hint: "Shader knobs, visible" },
    "test-timer": { path: "widgets/test-timer/main.qml", minWidth: 120, minHeight: 120,
      dev: true, label: "Timer test", group: "Dev", hint: "Rolling digits" },

    "clock-digital": { path: "widgets/clock-digital/main.qml", minWidth: 160, minHeight: 160,
      nothing: true, label: "Digital", group: "Time", hint: "Hours and minutes, with a tick ring" },
    "clock-analog": { path: "widgets/clock-analog/main.qml", minWidth: 160, minHeight: 160,
      nothing: true, label: "Analog — Classic", group: "Time", hint: "A face with hands" },
    "clock-analog-2": { path: "widgets/clock-analog-2/main.qml", minWidth: 160, minHeight: 160,
      nothing: true, label: "Analog — Markers", group: "Time", hint: "The same face, heavier marks" },
    "clock-analog-3": { path: "widgets/clock-analog-3/main.qml", minWidth: 160, minHeight: 160,
      nothing: true, label: "Analog — Numerals", group: "Time", hint: "Four numerals only" },

    "city-1": { path: "widgets/city-1/main.qml", minWidth: 160, minHeight: 160,
      nothing: true, label: "Cities, bold", group: "World", hint: "Up to four analog faces" },
    "city-2": { path: "widgets/city-2/main.qml", minWidth: 160, minHeight: 160,
      nothing: true, label: "Cities, precision", group: "World", hint: "The same, alternate face" },
    "city-3": { path: "widgets/city-3/main.qml", minWidth: 160, minHeight: 160,
      nothing: true, label: "City, dial", group: "World", hint: "One city, one face" },
    "city-digital": { path: "widgets/city-digital/main.qml", minWidth: 160, minHeight: 160,
      nothing: true, label: "City, digital", group: "World", hint: "One city, numerals and offset" },

    weather: { path: "widgets/weather/main.qml", minWidth: 160, minHeight: 160,
      nothing: true, label: "Weather", group: "Weather", hint: "Now, hourly and the week" },
    sunrise: { path: "widgets/sunrise/main.qml", minWidth: 160, minHeight: 120,
      nothing: true, label: "Sunrise", group: "Weather", hint: "The sun's arc, with sunset" },

    calendar: { path: "widgets/calendar/main.qml", minWidth: 160, minHeight: 160,
      nothing: true, label: "Calendar", group: "Date", hint: "The month, with today badged" },
    prayer: { path: "widgets/prayer/main.qml", minWidth: 160, minHeight: 160,
      nothing: true, label: "Prayer", group: "Date", hint: "Next athan, countdown and the day" },

    timer: { path: "widgets/timer/main.qml", minWidth: 160, minHeight: 160,
      nothing: true, label: "Timer", group: "Timer", hint: "Countdown with presets" },
    // `now-playing`, not `music`: the source is the MPRIS service, which
    // reports whatever player is on the bus - a podcast, a video, a browser
    // tab - so the old name promised less than the widget draws. Renamed from
    // `music`; Store.qml's `_legacyTypes` absorbs an instance still carrying
    // the old name.
    "now-playing": { path: "widgets/now-playing/main.qml", minWidth: 80, minHeight: 60,
      nothing: true, label: "Now Playing", group: "Media",
      hint: "Whatever player is playing — a track, a podcast, a video — with controls" },

    codeburn: { path: "widgets/codeburn/main.qml", minWidth: 160, minHeight: 120,
      nothing: true, label: "Codeburn", group: "System",
      hint: "AI spend today, tokens and the last two weeks" },

    omarr: { path: "widgets/omarr/main.qml", minWidth: 160, minHeight: 120,
      nothing: true, label: "Media server", group: "Media",
      hint: "Fleet health and the download queue" },

    "claude-usage": { path: "widgets/claude-usage/main.qml", minWidth: 160, minHeight: 120,
      nothing: true, label: "Claude", group: "System",
      hint: "Session, week and model windows" },

    deepseek: { path: "widgets/deepseek/main.qml", minWidth: 160, minHeight: 120,
      nothing: true, label: "DeepSeek", group: "System",
      hint: "Credit left, spent and the day's ledger" },

    perf: { path: "widgets/perf/main.qml", minWidth: 160, minHeight: 120,
      nothing: true, label: "Performance", group: "System",
      hint: "Load, memory and temperatures" },

    tailscale: { path: "widgets/tailscale/main.qml", minWidth: 160, minHeight: 120,
      nothing: true, label: "Tailscale", group: "System",
      hint: "Tailnet status, path, address and the node web" },

    battery: { path: "widgets/battery/main.qml", minWidth: 160, minHeight: 120,
      nothing: true, label: "Battery", group: "System",
      hint: "Charge, state and time remaining" },
    network: { path: "widgets/network/main.qml", minWidth: 160, minHeight: 120,
      nothing: true, label: "Network", group: "System",
      hint: "Link, signal and address" },
    storage: { path: "widgets/storage/main.qml", minWidth: 160, minHeight: 120,
      nothing: true, label: "Storage", group: "System",
      hint: "Filesystem use, per mount" },
    photos: { path: "widgets/photos/main.qml", minWidth: 160, minHeight: 160,
      nothing: true, label: "Photos", group: "Media",
      hint: "A frame from a folder of pictures" }
  })

  function listTypes() {
    return Object.keys(registry._entries)
  }

  function hasType(type) {
    return Object.prototype.hasOwnProperty.call(registry._entries, String(type || ""))
  }

  // `style` is "liquid-glass" (default) or "nothing". One plugin draws both,
  // so the file is chosen per WIDGET. A type with no drawing in the asked-for
  // style falls back to the one it does have rather than failing to load: the
  // style is a preference, not a contract, and a desktop must not lose a
  // widget because a second look has not been drawn yet.
  function urlFor(type, style) {
    var key = String(type || "")
    var entry = registry._entries[key]
    if (!entry) return ""
    var want = String(style || "liquid-glass")
    if (want === "nothing" && entry.nothing === true)
      return Qt.resolvedUrl("widgets-nothing/" + key + "/main.qml")
    if (entry.nothingOnly === true)
      return Qt.resolvedUrl("widgets-nothing/" + key + "/main.qml")
    return Qt.resolvedUrl(entry.path)
  }

  // Which styles this type can actually be drawn in, in menu order.
  function stylesFor(type) {
    var entry = registry._entries[String(type || "")]
    if (!entry) return []
    if (entry.nothingOnly === true) return ["nothing"]
    return entry.nothing === true ? ["liquid-glass", "nothing"] : ["liquid-glass"]
  }

  function isDev(type) {
    var entry = registry._entries[String(type || "")]
    return !!(entry && entry.dev === true)
  }

  function label(type) {
    var entry = registry._entries[String(type || "")]
    return (entry && entry.label) ? entry.label : String(type || "")
  }

  function group(type) {
    var entry = registry._entries[String(type || "")]
    return (entry && entry.group) ? entry.group : "Other"
  }

  function hint(type) {
    var entry = registry._entries[String(type || "")]
    return (entry && entry.hint) ? entry.hint : ""
  }

  // Catalogue order for the launcher rail. Spelled out so a new group lands
  // where it belongs rather than wherever the table happened to put it.
  readonly property var groups: ["Time", "World", "Weather", "Date", "Timer", "Media", "System"]

  function typesInGroup(name) {
    var out = []
    var keys = Object.keys(registry._entries)
    for (var i = 0; i < keys.length; i++) {
      var e = registry._entries[keys[i]]
      if (e.dev === true) continue
      if ((e.group || "Other") === String(name)) out.push(keys[i])
    }
    return out
  }

  function minSize(type) {
    var entry = registry._entries[String(type || "")]
    return entry ? { width: entry.minWidth, height: entry.minHeight } : { width: 0, height: 0 }
  }

  // --- Home-screen grid, iOS-style ------------------------------------
  //
  // Widgets no longer free-transform. There is one grid, and three tile
  // sizes on it: small (2×2 cells), medium (4×2) and large (4×4) - the
  // iPhone set. A cell is 88 px with a 16 px gutter, so the pitch is 104 px
  // and the tiles come out 192×192, 400×192 and 400×400.
  //
  // The cell is 88 and not something rounder because 2 cells (192 px) must
  // clear the largest `minWidth` in the table above (160, the size every
  // clock, city and weather tile asks for) - a small tile that cannot
  // legally exist for some type would leave that type with two sizes,
  // silently.
  //
  // The three sizes also land on the aspect ratios every ported widget
  // already branches on: medium is 2.08:1, so `isWide`/`_wide`/`_ar >= 1.6`
  // all flip, and small is under the weather widget's 350 px `isSmall`
  // threshold while large is over it. No widget needed a layout change.
  readonly property int gridCell: 88
  readonly property int gridGap: 16
  readonly property int gridPitch: registry.gridCell + registry.gridGap

  readonly property var _sizeUnits: [
    { id: "small",  label: "Small",  w: 2, h: 2 },
    { id: "medium", label: "Medium", w: 4, h: 2 },
    { id: "large",  label: "Large",  w: 4, h: 4 }
  ]

  // n cells span n*cell + (n-1)*gap: the gutters live BETWEEN cells, so a
  // tile edge is always on a pitch boundary and two adjacent tiles are one
  // gutter apart.
  function gridSpan(cells) {
    return cells * registry.gridCell + (cells - 1) * registry.gridGap
  }

  // Presets a given type may actually take: one that would violate the
  // type's minimum is dropped rather than silently clamped to a
  // non-grid size.
  function sizes(type) {
    var min = registry.minSize(type)
    var out = []
    for (var i = 0; i < registry._sizeUnits.length; i++) {
      var u = registry._sizeUnits[i]
      var w = registry.gridSpan(u.w)
      var h = registry.gridSpan(u.h)
      if (w < min.width || h < min.height) continue
      out.push({ id: u.id, label: u.label, width: w, height: h })
    }
    return out
  }

  function defaultSize(type) {
    var list = registry.sizes(type)
    return list.length ? list[0] : registry.minSize(type)
  }

  // Which preset a free w×h is closest to. Used by the resize drag (it
  // snaps through the presets instead of following the pointer) and by the
  // control panel to show which size a tile currently is.
  function nearestSize(type, w, h, maxW, maxH) {
    var list = registry.sizes(type)
    if (!list.length) return null
    var best = null
    var bestD = Infinity
    for (var i = 0; i < list.length; i++) {
      var s = list[i]
      // A preset that does not fit in the space left on screen is not a
      // candidate - otherwise dragging near the right edge would snap to a
      // size that immediately gets clamped back off-grid.
      if (maxW !== undefined && s.width > maxW && i > 0) continue
      if (maxH !== undefined && s.height > maxH && i > 0) continue
      var d = Math.abs(s.width - w) + Math.abs(s.height - h)
      if (d < bestD) { bestD = d; best = s }
    }
    return best || list[0]
  }

  // Tile origins sit at inset + gap + n*pitch, so a widget dropped anywhere
  // lands in the same lattice its neighbours are on - and the lattice starts
  // below the bar, not under it (`inset` is the screen's reserved edge, see
  // ScreenInsets.qml). `inset` defaults to 0 for callers on an axis with no
  // exclusive zone.
  function snapCoord(v, inset) {
    var base = registry.gridGap + (inset || 0)
    var n = Math.round((v - base) / registry.gridPitch)
    return Math.max(inset || 0, base + n * registry.gridPitch)
  }

  // Where a fresh or reset widget goes: the first cell of the visible grid.
  function originX(insetLeft) { return registry.gridGap + (insetLeft || 0) }
  function originY(insetTop) { return registry.gridGap + (insetTop || 0) }
}
