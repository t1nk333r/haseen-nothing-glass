import QtQuick

// Feeds Omarchy's live theme into MacOSColors' one host input. MacOSColors owns
// the iOS palette itself — those literals are fixed brand colours, not theme
// colours, and stay put. The only thing the host decides is whether the system
// theme is light or dark, which is what `appearance: 2` ("Follow system") asks.
QtObject {
  id: theme

  // Injected by the host so this file carries no `qs.Commons` import: that
  // module only resolves inside the Omarchy shell, and the dev harness
  // (glass-dev.qml) runs outside it. Service.qml (which only ever loads
  // inside the shell) binds this to `Color.background`; GlassSurface.qml's
  // own default `Theme {}` instance — used verbatim by the dev harness,
  // which instantiates GlassSurface directly and never loads Service.qml —
  // keeps this fallback value instead.
  property color systemBackground: "#1c1c1e"

  // The rest of the Omarchy palette, for `styleMode` 2/3 ("follow theme").
  // Bound by Service.qml to the `Color` singleton's foundational tokens, so
  // they re-evaluate live when `shell.applyTheme` reassigns them; the dev
  // harness keeps these fallbacks.
  property color themeForeground: "#ffffff"
  property color themeAccent: "#0a84ff"
  property color themeUrgent: "#FF3B30"
  property color themeSurface: "#2c2c2e"

  // Handed to MacOSColors.themePalette as one object, so a widget passes a
  // single binding instead of five.
  readonly property var palette: ({
    background: theme.systemBackground,
    foreground: theme.themeForeground,
    accent: theme.themeAccent,
    urgent: theme.themeUrgent,
    surface: theme.themeSurface
  })
}
