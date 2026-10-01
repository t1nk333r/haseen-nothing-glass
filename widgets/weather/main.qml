import QtQuick
import "../../components"
import "widget"

// Port of packages/weather/contents/ui/main.qml, per PORTING.md. Beyond the
// mechanical steps (PlasmoidItem wrapper -> this Item + anchors.fill, Plasma
// imports and Layout.* dropped, PlasmaBackdrop dropped, WeatherData ->
// WeatherDataQs, Kirigami.Theme.backgroundColor -> theme.systemBackground,
// i18n() stripped), one real fix: `Font.Regular` does not exist in Qt 6 --
// the four weight bindings that used it evaluated to `undefined` and logged
// "Unable to assign [undefined] to int" on every repaint, here AND on Plasma.
// They are `Font.Normal` now, which is the weight the undefined value fell
// back to anyway, so nothing renders differently. Same fix in
// widget/HourlyForecast.qml; worth reporting upstream.

Item {
    id: full
    anchors.fill: parent

    MacOSColors {
        id: colors
        styleMode: plugin.settings.styleMode
        appearance: plugin.settings.appearance
        systemBackground: theme.systemBackground
        themePalette: theme.palette
        weatherGradientCategory: weatherData.gradientCategory
    }

    // Where "here" is, and in what units, are both the engine's business now:
    // WeatherDataQs follows ~/.local/state/omarchy/settings/weather.json (the
    // file `omarchy-weather-location` owns, and the bar's own weather widget
    // reads) and falls back to IP auto-detection, exactly like the stock
    // Omarchy pill. `location` is a per-widget override for a second tile
    // pointed at another city; empty - the default - means "follow Omarchy".
    //
    // The plugin-wide `latitude`/`longitude`/`useGeoclue` keys are the sunrise
    // widget's, and weather deliberately ignores them: a GeoClue or
    // prayer-settings fix used to sit between the shared file and the network
    // and would now pre-empt the IP detection that replaced the old hard-coded
    // city.
    WeatherDataQs {
        id: weatherData
        location: plugin.settings.location
        unit: plugin.settings.unit
        refreshMinutes: plugin.settings.refreshMinutes
        // Same gate as every other engine in this plugin: off while the
        // screen is switched off, on whenever that is unknown.
        active: full.visible
    }

    // One scale for the four drawings. This file used to derive its own
    // label and its own wide threshold and the sunrise tile next door
    // derived two different ones, so the same size tile disagreed with
    // itself about what a label was. The roles live in
    // components/GlassScale.qml now and the layouts below read them.
    GlassScale {
        id: scale
        tileWidth: full.width
        tileHeight: full.height
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
        solidColor: colors.isSolid ? colors.weatherGradientTop : colors.solidBackground
        solidColorBottom: colors.isSolid ? colors.weatherGradientBottom : "transparent"
    }

    // ── Small Layout ─────────────────────────────────────────────
    Item {
        id: smallLayout
        visible: scale.isSmall
        anchors.fill: parent
        anchors.margins: scale.pad

        // The header, drawn once for all three presets - see
        // widget/WeatherHeader.qml. Nothing here knows a font size: the role
        // is the tile's, and `compact` is the small square's stacked pair.
        WeatherHeader {
            anchors.fill: parent
            compact: true
            weatherData: weatherData
            colors: colors
            fontFamily: colors.uiFont
            label: scale.label
        }

        // The footer is a prose column, not a hug-your-content column: it is
        // given the tile's own inner width so the two value lines below have
        // a box to elide inside. Without one, `width == implicitWidth ==
        // contentWidth` and `elide` never fires - in system-font mode the
        // precipitation sentence measures 1.55x the width it takes in the SF
        // Pro Display cut these drawings were made against, and simply ran off
        // the card. See PORTING.md item 9.
        Column {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            width: parent.width

            spacing: 0

            Text {
                textFormat: Text.PlainText
                text: "Precipitation"
                color: colors.weatherForeground
                font.family: colors.uiFont
                font.pixelSize: scale.micro
                font.weight: Font.Medium
            }
            Text {
                textFormat: Text.PlainText
                text: weatherData.precipitationSummary
                color: colors.weatherForeground
                opacity: 0.55
                font.family: colors.uiFont
                font.pixelSize: scale.micro
                font.weight: Font.Normal
                width: parent.width
                elide: Text.ElideRight
                visible: weatherData.precipitationSummary !== ""
            }

            Item { width: 1; height: scale.gap }

            Text {
                textFormat: Text.PlainText
                text: "Wind"
                color: colors.weatherForeground
                font.family: colors.uiFont
                font.pixelSize: scale.micro
                font.weight: Font.Medium
            }
            Text {
                textFormat: Text.PlainText
                text: weatherData.windSpeed + " " + weatherData.windUnit + " " + weatherData.windDirection
                color: colors.weatherForeground
                opacity: 0.55
                font.family: colors.uiFont
                font.pixelSize: scale.micro
                font.weight: Font.Normal
                width: parent.width
                elide: Text.ElideRight
            }
        }
    }

    // ── Big Square Layout ────────────────────────────────────────
    Item {
        id: bigLayout
        visible: scale.isBig
        anchors.fill: parent
        anchors.margins: scale.pad

        readonly property real topSectionH: height * 0.30
        readonly property real hourlyH: height * 0.22
        readonly property real _sepSpacing: Math.round(height * 0.02)

        Item {
            id: bigTop
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: bigLayout.topSectionH

            // The big square is dense by design: `tight` is the scale's
            // step-down, and it is the size this layout used to derive for
            // itself - so this preset keeps the drawing it had.
            WeatherHeader {
                anchors.fill: parent
                weatherData: weatherData
                colors: colors
                fontFamily: colors.uiFont
                label: scale.tight
            }
        }

        Rectangle {
            id: sep1
            anchors.top: bigTop.bottom
            anchors.topMargin: bigLayout._sepSpacing
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: colors.weatherSeparator
        }

        HourlyForecast {
            id: bigHourly
            anchors.top: sep1.bottom
            anchors.topMargin: bigLayout._sepSpacing
            anchors.left: parent.left
            anchors.right: parent.right
            height: bigLayout.hourlyH
            slots: weatherData.hourlySlots
            iconSet: colors.weatherIconSet
            textColor: colors.weatherForeground
            secondaryTextColor: colors.weatherForeground
            secondaryOpacity: 0.70
            fontFamily: colors.uiFont
            baseFontSize: scale.tight
        }

        Rectangle {
            id: sep2
            anchors.top: bigHourly.bottom
            anchors.topMargin: bigLayout._sepSpacing
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: colors.weatherSeparator
        }

        DailyForecast {
            anchors.top: sep2.bottom
            anchors.topMargin: bigLayout._sepSpacing
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            days: weatherData.dailyForecast
            overallLow: weatherData.overallLow
            overallHigh: weatherData.overallHigh
            iconSet: colors.weatherIconSet
            textColor: colors.weatherForeground
            secondaryColor: colors.weatherForeground
            secondaryOpacity: 0.70
            rangeBarBg: colors.weatherRangeBarBg
            rangeBarFill: colors.weatherRangeBarFill
            fontFamily: colors.uiFont
            fontSize: scale.tight
            iconNameForCode: function(code, night) { return weatherData.iconNameForCode(code, night) }
        }
    }

    // ── Wide Layout ──────────────────────────────────────────────
    Column {
        id: wideLayout
        visible: scale.isWide
        anchors.fill: parent
        anchors.margins: scale.pad
        spacing: 0

        Item {
            id: wideTop
            width: parent.width
            height: parent.height * 0.50

            WeatherHeader {
                anchors.fill: parent
                weatherData: weatherData
                colors: colors
                fontFamily: colors.uiFont
                label: scale.label
            }
        }

        HourlyForecast {
            width: parent.width
            height: parent.height - wideTop.height
            slots: weatherData.hourlySlots
            iconSet: colors.weatherIconSet
            textColor: colors.weatherForeground
            secondaryTextColor: colors.weatherForeground
            secondaryOpacity: 0.70
            fontFamily: colors.uiFont
            baseFontSize: scale.label
        }
    }

    MacSpinner {
        anchors.centerIn: parent
        width: Math.round(scale.minSide * 0.14)
        height: width
        running: weatherData.isLoading && weatherData.currentTemp === "--"
        visible: running
        z: 5
    }

    MouseArea {
        anchors.fill: parent
        z: 10
        acceptedButtons: Qt.LeftButton
        propagateComposedEvents: true
        onClicked: {
            weatherData.forceRefresh()
            mouse.accepted = false
        }
    }
}
