import QtQuick

// The settings a widget body reads, as `plugin.settings.cornerRadius`.
//
// This has to be reachable as a bare `plugin` identifier from inside the
// loaded widget document, so the host declares it with a QML *id*: only ids
// and true context properties fall through a Loader's parent-context chain.
// A plain property would only be reachable as `host.plugin`, which widget
// bodies do not write.
QtObject {
  id: shim

  // Manifest defaults, the plugin's shell.json entry and its own options file
  // merged in that order, supplied by the host (GlassSurface.qml).
  // Per-instance overrides win over the plugin-wide value.
  property var settings: ({})
}
