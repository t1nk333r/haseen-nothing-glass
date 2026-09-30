import QtQuick
import "../../components"
import "widget"

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

    FontLoader {
        id: barlowSemiBold
        source: Qt.resolvedUrl("../../fonts/barlow_semibold.ttf")
    }
    FontLoader {
        id: barlowMedium
        source: Qt.resolvedUrl("../../fonts/barlow_medium.ttf")
    }

    // --- Time state ---
    // City Digital shows a single configured city (1x1 only). The digital
    // readout reads hour12/minute from the world-clock model (updated once a
    // second); the second-hand sweep below reads Date.now() directly.
    WorldClockQs {
        id: world
        clocks: plugin.settings.clocks
        needsSeconds: false
    }
    readonly property var _e: world.entries.length ? world.entries[0] : null

    // The fallback clock. A `new Date()` read inside a binding has no
    // dependencies, so QML evaluates it once and the tile freezes at its load
    // minute - a city is what owns the TzClock that would wake it.
    property date _localNow: new Date()

    Timer {
        running: full._e === null      // only the fallback needs this
        interval: 1000
        repeat: true
        onTriggered: {
            const now = new Date()
            // A compare a second, a write a minute. A timer aligned to the
            // wall minute at load would drift; this cannot.
            if (now.getMinutes() !== full._localNow.getMinutes())
                full._localNow = now
        }
    }

    readonly property int hour12: _e ? _e.hour12 : ((full._localNow.getHours() + 11) % 12) + 1
    readonly property int minute: _e ? _e.minute : full._localNow.getMinutes()

    LiquidGlass {
        id: glass
        anchors.fill: parent
        wallpaperItem: backdrop.item
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
        realtimeRefraction: plugin.settings.realtimeRefraction
        fallbackOpacity: colors.glassFallbackOpacity
        solidMode: colors.isSolid
        solidColor: colors.solidBackground
    }

    TickRing {
        id: ticks
        anchors.fill: parent
        cornerRadius: glass.radius
        roundness: glass.roundness
        outerInset: 0.05
        tickLength: 0.026
        cornerOuterExtension: 0.012
        tickWidthPx: 2.2
        baseOpacity: colors.tickRingOpacity
        tickColor: colors.foreground
    }

    // Smoothly advance the second hand at ~60fps while visible.
    // Don't gate on application state — Plasma desktop widgets must
    // keep ticking even when no Qt window has keyboard focus.
    Timer {
        interval: 16
        repeat: true
        running: full.visible
        onTriggered: {
            const ms = Date.now() % 60000;
            ticks.secondHandAngle = (ms / 60000) * 360;
        }
    }

    DigitalTime {
        anchors.centerIn: parent
        fontFamily: barlowMedium.name
        // Generous target size; the component auto-shrinks if the
        // content would overflow `availableWidth`.
        fontPixelSize: Math.min(full.width, full.height) * 0.60
        // Usable interior: widget width minus the same visual gap
        // on both sides that the ticks leave to the edge (5% inset
        // + 5% tick length + 5% pad = 15% each side).
        availableWidth: Math.max(40, full.width - 2 * Math.min(full.width, full.height) * 0.15)
        hour12: full.hour12
        minute: full.minute
        digitOpacity: colors.readoutOpacity
        textColor: colors.foreground
    }

    // City code near the top edge, hour-diff near the bottom edge, with
    // equal margins so the two gaps are even. Smaller than the clock text.
    //
    // Opacity: one quiet step, not two. The annotation used to compound a
    // second 0.55 on top of the glass 0.55 (0.30) — below the documented
    // floor (MacOSColors.textQuiet), and measured at 1.5:1 against what is
    // behind it on a glass tile, so the code and the hour-diff were a ghost
    // beside the readout they annotate. City I/II/III's annotation is this
    // same call site and takes the same token; the solid-mode value is
    // unchanged, because textQuiet IS the 0.55 it already had.
    readonly property real _annoFont:   Math.max(8, Math.min(full.width, full.height) * 0.085)
    readonly property real _annoMargin: Math.min(full.width, full.height) * 0.13
    readonly property real _annoOpacity: colors.textQuiet

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: full._annoMargin
        text: full._e ? full._e.code : ""
        font.family: colors.uiFont
        font.pixelSize: full._annoFont
        font.weight: Font.Medium
        color: colors.foreground
        opacity: full._annoOpacity
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: full._annoMargin
        text: full._e ? full._e.offsetLabel : ""
        font.family: colors.uiFont
        font.pixelSize: full._annoFont
        font.weight: Font.Medium
        color: colors.foreground
        opacity: full._annoOpacity
    }
}
