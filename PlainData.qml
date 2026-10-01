import QtQuick

// What may be stored in the files this plugin owns, in one place: the widget
// store's rows and per-instance settings (Store.qml), the plugin-wide options
// file (Options.qml) and the values the IPC verbs accept (Service.qml,
// GlassSurface.setPluginSetting). Stateless, so every user instantiates its
// own (same reasoning as WidgetRegistry.qml's header).
QtObject {
  id: plain

  // A key that is not plain data: `__proto__` (a JSON document can carry it
  // as an own key, and a `for...in` copy then ASSIGNS it - replacing the
  // copy's prototype instead of adding a field), `constructor`, `prototype`,
  // the empty key, and anything else Object.prototype already answers to
  // (`toString`, `hasOwnProperty`), which an `in` test reports as set.
  function isUnsafeKey(key) {
    var k = String(key)
    return k === "" || k === "__proto__" || k === "constructor" || k === "prototype" ||
           (k in Object.prototype)
  }

  // Count UTF-8 bytes without allocating an encoded copy. Stop as soon as
  // the cap is crossed; surrogate pairs encode as four bytes.
  function exceedsBytes(text, cap) {
    if (text.length > cap) return true
    var bytes = 0
    for (var i = 0; i < text.length; i++) {
      var c = text.charCodeAt(i)
      if (c < 128) bytes++
      else if (c < 2048) bytes += 2
      else if (c >= 0xd800 && c <= 0xdbff && i + 1 < text.length &&
               text.charCodeAt(i + 1) >= 0xdc00 && text.charCodeAt(i + 1) <= 0xdfff) {
        bytes += 4
        i++
      } else bytes += 3
      if (bytes > cap) return true
    }
    return false
  }

  // A JSON-shaped copy of `value`: finite numbers, strings, booleans, null,
  // and arrays/objects of those, own safe keys only, nested at most 8 deep.
  // Returns { ok, value }; `ok` is false for anything else (NaN, Infinity,
  // undefined, a function, an unsafe key, a cycle).
  function clean(value) {
    return plain._clean(value, 0)
  }

  function _clean(v, depth) {
    if (v === null || typeof v === "string" || typeof v === "boolean") return { ok: true, value: v }
    if (typeof v === "number") return isFinite(v) ? { ok: true, value: v } : { ok: false }
    if (typeof v !== "object" || depth >= 8) return { ok: false }
    var list = Array.isArray(v)
    var out = list ? [] : {}
    var keys = Object.keys(v)
    for (var i = 0; i < keys.length; i++) {
      if (!list && plain.isUnsafeKey(keys[i])) return { ok: false }
      var c = plain._clean(v[keys[i]], depth + 1)
      if (!c.ok) return { ok: false }
      if (list) out.push(c.value)
      else out[keys[i]] = c.value
    }
    return { ok: true, value: out }
  }

  // An object read from disk, kept to what `clean` accepts key by key: an
  // unsafe key or an unclean value is left out, everything else is copied
  // exactly. Anything that is not a plain object gives {}.
  function cleanObject(obj) {
    var out = {}
    if (!obj || typeof obj !== "object" || Array.isArray(obj)) return out
    var keys = Object.keys(obj)
    for (var i = 0; i < keys.length; i++) {
      if (plain.isUnsafeKey(keys[i])) continue
      var c = plain.clean(obj[keys[i]])
      if (c.ok) out[keys[i]] = c.value
    }
    return out
  }
}
