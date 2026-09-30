import QtQuick
import "../../components"
import "widget"

// Port of packages/test-timer/contents/ui/main.qml, per PORTING.md: the
// PlasmoidItem wrapper becomes this Item + anchors.fill, Plasma imports and
// Layout.* are dropped, PlasmaBackdrop is dropped (WidgetHost.qml supplies the
// `backdrop` id), and Kirigami.Theme.backgroundColor becomes
// theme.systemBackground. Nothing else changed.
//
// The 1-second Timer is deliberately NOT gated on Qt.application.state (see
// AGENTS.md's timer conventions): a layer-shell surface is never the focused
// application, so such a gate would stop the digit dead.

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

    property int secondsDigit: new Date().getSeconds() % 10

    Timer {
        interval: 1000 - (new Date().getMilliseconds())
        repeat: true
        running: full.visible
        triggeredOnStart: false
        onTriggered: {
            full.secondsDigit = new Date().getSeconds() % 10
            interval = 1000 - (new Date().getMilliseconds())
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

    Item {
        id: digitViewport
        anchors.centerIn: parent
        width: Math.min(full.width, full.height) * 0.64
        height: Math.min(full.width, full.height) * 0.94
        clip: true

        RollingDigit {
            anchors.fill: parent
            value: String(full.secondsDigit)
            fontFamily: colors.uiFont
            fontPixelSize: Math.min(full.width, full.height) * 0.62
            textColor: colors.foreground
            digitOpacity: colors.rollingReadoutOpacity
        }
    }
}
