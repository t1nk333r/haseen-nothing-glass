import QtQuick
import "../../components"

// Trivial widget type used to exercise the runtime (instances, placement,
// persistence, IPC) without porting a real widget — it exists so that a
// runtime failure and a widget-port failure stay distinguishable.
//
// Shaped like a real ported widget so it doubles as a worked example for
// PORTING.md: a plain `Item { anchors.fill: parent }` root (item 3), a
// locally-declared `MacOSColors { id: colors }` (per AGENTS.md's per-widget
// QML conventions), and the glass binding block copied verbatim (item 10).
// The one thing a real port has that this deliberately skips is sampling
// the wallpaper — `LiquidGlass.wallpaperItem` is left at its `null` default,
// so this always renders the flat fallback rect. See GlassSurface.qml's
// comment on `backdrop` for why that's this plan's scope, not an oversight.
Item {
    id: full
    anchors.fill: parent

    MacOSColors {
        id: colors
        styleMode: plugin.settings.styleMode
        appearance: plugin.settings.appearance
        systemBackground: theme.systemBackground
        themePalette: theme.palette
    }

    LiquidGlass {
        id: glass
        anchors.fill: parent
        radius: plugin.settings.cornerRadius
        roundness: plugin.settings.roundness
        refractThickness: plugin.settings.refractThickness
        refractIOR: plugin.settings.refractIOR
        refractScale: plugin.settings.refractScale
        tint: colors.glassTint
        tintAlpha: plugin.settings.tintAlpha
        chromaStrength: plugin.settings.chromaStrength
        specStrength: plugin.settings.specStrength
        blurRadius: plugin.settings.blurRadiusPx
        realtimeRefraction: false
        fallbackOpacity: colors.glassFallbackOpacity
        solidMode: colors.isSolid
        solidColor: colors.solidBackground
    }

    Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: "placeholder"
        color: colors.foreground
        font.pixelSize: Math.max(10, Math.min(full.width, full.height) * 0.12)
    }
}
