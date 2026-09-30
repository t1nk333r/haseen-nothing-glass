import QtQuick

// Who this plugin is.
//
// It draws BOTH styles. There was briefly a second plugin, `t1nk33r.nothing`,
// generated from the same runtime; it is gone. Two plugins meant two bar
// entries, two panels, two stores and two of every setting, to express what
// is really one axis on one widget - and Omarchy un-places a dual-kind
// plugin's bar entry on startup, so the second one could not even keep its
// icon. One plugin, one entry, one store, and the style chosen per widget or
// per category instead.
QtObject {
  id: identity

  readonly property string id: "t1nk33r.nothing-glass"
  readonly property string label: "Nothing Glass"

  // The widget browser's toplevel (Panel.qml) carries this as its window
  // title, and Hyprland's float/center/size rule for it
  // (`float_nothing_glass_browser` in ~/.config/hypr/rules.lua) matches on
  // exactly this string. The title is how the compositor identifies the
  // window - without a matching rule Hyprland tiles a toplevel - so it is
  // spelled here, once, and read from here by the QML.
  readonly property string browserTitle: "Nothing Glass"

  // The styles this plugin can draw. `liquid-glass` is the default for a
  // widget that says nothing; `nothing` is the Nothing OS drawing.
  readonly property var styles: ["liquid-glass", "nothing"]
  function styleLabel(style) {
    return String(style) === "nothing" ? "Nothing" : "Liquid Glass"
  }

  // ~/.config/omarchy/nothing-glass.json (widgets) and
  // ~/.config/omarchy/nothing-glass-options.json (plugin-wide settings).
  // Both derive from the id, so a rename moves them together - see
  // Store._absorbLegacyStore(), which carries an older name across.
  readonly property string storeName: {
    var parts = String(identity.id).split(".")
    return parts[parts.length - 1]
  }

  readonly property string namespace: String(identity.id).replace(/\./g, "-")
}
