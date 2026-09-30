import QtQuick

// The per-instance settings a widget type exposes, in one place.
//
// Three UIs edit them - the bar control panel (BarWidget.qml), the sheet a
// right-click on the widget opens (WidgetSettingsWindow.qml) and the browser's
// own pane (WidgetInspector.qml) - and they must agree on the key names, the
// types and what an empty value means, or one of them will write a string
// where another wrote a number and the widget will quietly stop matching its
// own comparisons.
//
// Stateless, so every consumer instantiates its own (same reasoning as
// WidgetRegistry.qml's header).
QtObject {
  id: fields

  // `kind` drives both the editor control and the coercion on save:
  //   string -> plain text
  //   number -> Number(), rejected if NaN, stored as a number
  //   bool   -> stored as a real boolean
  function forType(type) {
    var t = String(type || "")
    if (t === "weather") return [
      { key: "location", label: "Location", kind: "string",
        hint: "Empty follows Omarchy's own city (`omarchy-weather-location`), then IP auto-detect. Type a city to pin this widget to it" },
      { key: "unit", label: "Unit", kind: "string",
        hint: "metric = °C/km-h, imperial = °F/mph, empty picks by country then locale" },
      { key: "refreshMinutes", label: "Refresh", kind: "number",
        hint: "Minutes between updates, at least 1" }
    ]
    if (t === "city-1" || t === "city-2" || t === "city-3" || t === "city-digital") return [
      { key: "clocks", label: "Cities", kind: "string",
        hint: "Area/Zone|Label, comma-separated, up to 4 shown" }
    ]
    if (t === "calendar") return [
      { key: "firstDayOfWeek", label: "Week starts", kind: "number",
        hint: "0 = Sunday, 1 = Monday" },
      { key: "eventLookaheadDays", label: "Lookahead", kind: "number",
        hint: "0 = 7 days, 1 = 14, 2 = 30, 3 = 60 (wide layout's event list)" }
    ]
    if (t === "sunrise") return [
      { key: "useGeoclue", label: "GeoClue (opt-in)", kind: "bool",
        hint: "Off by default. Asks GeoClue2 for coordinates, as Firefox, before the prayer settings / Omarchy weather location / manual values - a network provider may be sent nearby Wi-Fi" },
      { key: "latitude", label: "Latitude", kind: "number",
        hint: "Used only when no other source resolves" },
      { key: "longitude", label: "Longitude", kind: "number",
        hint: "Used only when no other source resolves" }
    ]
    if (t === "network") return [
      { key: "networkInterface", label: "Interface", kind: "string",
        hint: "Pin to one interface and show its name, e.g. wlan0 - empty follows the live link and shows the SSID, or just Ethernet" }
    ]
    if (t === "storage") return [
      { key: "storageMounts", label: "Mounts", kind: "string",
        hint: "Comma-separated mount points, e.g. /, /home - empty lists every filesystem, and that list is where the exact names are" }
    ]
    if (t === "photos") return [
      { key: "photoFolder", label: "Folder", kind: "string",
        hint: "Absolute path or ~/… ; empty = $XDG_PICTURES_DIR, else ~/Pictures" },
      { key: "photoIntervalSec", label: "Every", kind: "number",
        hint: "Seconds between pictures; 0 stays on the current one" },
      { key: "photoShuffle", label: "Shuffle", kind: "bool",
        hint: "Random order instead of by filename" }
    ]
    if (t === "now-playing") return [
      { key: "playerFilter", label: "Players", kind: "string",
        hint: "Comma-separated MPRIS player names; empty = any player" },
      { key: "autoHideEnabled", label: "Hide when idle", kind: "bool",
        hint: "Hide this widget while nothing is playing" }
    ]
    if (t === "clock-analog") return [
      { key: "analogSecondSweep", label: "Sweep second hand", kind: "bool",
        hint: "Off ticks once a second, like a quartz movement; on sweeps continuously" }
    ]
    return []
  }

  function isOverridden(entry, key) {
    return !!(entry && entry.settings && (key in entry.settings))
  }

  // The value the widget is actually using: its own override first, then
  // whatever the plugin-wide configuration resolved to.
  function effective(entry, key, pluginConfig) {
    if (fields.isOverridden(entry, key)) return String(entry.settings[key])
    var v = pluginConfig ? pluginConfig[key] : undefined
    return (v === undefined || v === null) ? "" : String(v)
  }

  // The sentence under a field. An overridden field has to say how to get
  // back to the plugin-wide value; the right-click sheet and the browser's
  // inspector both print it, so it is worded in one place. (The bar panel
  // words it differently on purpose - it has a Save button to mention.)
  function hintFor(entry, field) {
    if (fields.isOverridden(entry, field.key))
      return "Set for this widget only. Clear the field to follow the plugin-wide value."
    return String(field.hint || "")
  }

  function isTrue(value) {
    var s = String(value).toLowerCase()
    return s === "true" || s === "1" || s === "yes"
  }

  // Empty text clears the override so the plugin-wide value applies again -
  // the only way back, since there is no separate "unset" control.
  function save(store, id, field, value) {
    if (!store) return false
    if (field.kind === "bool") return store.set(id, field.key, !!value)
    var t = String(value).trim()
    if (t === "") return store.unset(id, field.key)
    if (field.kind === "number") {
      var n = Number(t)
      if (isNaN(n)) return false
      return store.set(id, field.key, n)
    }
    return store.set(id, field.key, t)
  }
}
