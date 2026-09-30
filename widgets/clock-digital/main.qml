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
    // `now` is the minute-level clock used to drive digital display +
    // hour label. Bumped once per minute by minuteWatchdog. The
    // second-hand sweep does NOT read `now` — it reads Date.now()
    // directly every frame (avoids per-frame property churn).
    property date now: new Date()
    readonly property int hour12: ((now.getHours() + 11) % 12) + 1
    readonly property int minute: now.getMinutes()

    Timer {
        id: minuteWatchdog
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            const n = new Date();
            if (n.getMinutes() !== full.now.getMinutes() || n.getHours() !== full.now.getHours() || n.getDate() !== full.now.getDate()) {
                full.now = n;
            }
        }
    }

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
}
