import QtQuick
import org.hyprland.style.impl

// The compositor's "less animation" preference: Hyprland's Qt Quick Control
// style exposes it; Quickshell has no equivalent (checked against
// quickshell-core.qmltypes). Load this through a Loader, never by
// instantiating it: it is an impl module of a compositor-shipped style, and a
// missing import fails the *importing* document. Behind a Loader that failure
// is one warning and a null item, which the clocks read as "animate".
QtObject { readonly property bool reduceMotion: HyprlandStyle.reduceMotion }
