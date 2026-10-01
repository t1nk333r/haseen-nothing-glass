import QtQuick

// The weather header: where, how warm, what it looks like, and the day's
// range.
//
// It is a component because it used to be three copies - one per grid preset
// - and the copies had already drifted: the city was x1.1 in one and x1.15 in
// the others, the hero temperature x4 in one and x3.5 in the others, and the
// same high/low pair drawn two different ways. None of that was chosen, it is
// what three copies do, and it made every future change to the family three
// edits that keep diverging.
//
// The sizes arrive from `GlassScale`, so one tile of one size reads the same
// whichever layout draws it: `label` is the layout's role (the preset's own
// scale value, or the dense step-down for the big square), and the three
// proportions below are the header's own - they are the relationship between
// its parts, not a tile measurement, so they live here and only here.
//
// The one difference between the presets worth keeping is `compact`: the
// small square stacks the high/low pair under the icon and dims the low
// reading, the larger presets put the pair on one line under the condition.
Item {
    id: hdr

    property var weatherData
    property var colors
    // The family every line here is set in, passed in as a name by the
    // body. It used to arrive twice - `lightFontFamily` carried the SF Pro
    // Display Light cut for the temperature - and both were the same
    // family name even then; with the Apple faces gone (fonts/
    // LICENSES.md) the pair is one property. The weight the hero reads is
    // `font.weight: Font.Thin` at its own call site.
    property string fontFamily: ""

    property real label: 13
    property real body: Math.round(hdr.label * 1.15)
    property real hero: Math.round(hdr.label * 3.5)
    property real iconSize: Math.round(hdr.label * 3)

    property bool compact: false

    // The place name is the one string this header cannot size: it arrives
    // from the geocoder or the shared weather file, and Open-Meteo returns
    // "San Fernando del Valle de Catamarca" as readily as "Riyadh". With no
    // width and no elide it ran straight off the card - measured 201.3 px of
    // ink in a 160 px small square in the bundled face, and 1.55x that in the
    // system face the desktop's own font draws at. The icon owns the
    // right-hand end of the top row, so the name gets the room between them
    // and elides inside it; a name that already fits keeps `implicitWidth` and
    // renders exactly as before. Same rule as the footer (PORTING.md item 9)
    // and the Nothing twin's own header.
    readonly property real cityRoom: Math.max(0, hdr.width - hdr.iconSize
        - Math.round(hdr.label * 0.4)
        - (hdr.compact
            ? Math.round(hdr.label * 0.85) + Math.round(hdr.label * 0.25) : 0))

    // ── Where, and how warm ─────────────────────────────────────────────
    Row {
        id: cityRow
        anchors.top: parent.top
        anchors.left: parent.left
        spacing: Math.round(hdr.label * 0.25)

        Text {
            width: Math.min(implicitWidth, hdr.cityRoom)
            elide: Text.ElideRight
            // The name comes from a web service (the geocoder, or wttr.in for
            // the IP's city). Plain text, so markup in it is shown, never
            // obeyed - AutoText would load an <img> it named.
            textFormat: Text.PlainText
            text: hdr.weatherData.cityName
            color: hdr.colors.weatherForeground
            font.family: hdr.fontFamily
            font.pixelSize: hdr.body
            font.weight: Font.Medium
        }

        // The compact preset has no room for the condition line, so the
        // place is badged with its glyph instead.
        Image {
            visible: hdr.compact
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(hdr.label * 0.85)
            height: width
            source: Qt.resolvedUrl("../../../icons/location.png")
            smooth: true
            mipmap: true
        }
    }

    Text {
        id: heroTemp
        anchors.top: cityRow.bottom
        anchors.left: parent.left
        text: hdr.weatherData.currentTemp + hdr.weatherData.tempSymbol
        color: hdr.colors.weatherForeground
        font.family: hdr.fontFamily
        font.pixelSize: hdr.hero
        font.weight: Font.Thin
    }

    // ── What it looks like ──────────────────────────────────────────────
    WeatherIcon {
        id: icon
        anchors.top: parent.top
        anchors.right: parent.right
        iconName: hdr.weatherData.iconNameForCode(hdr.weatherData.weatherCode, hdr.weatherData.isNight)
        iconSet: hdr.colors.weatherIconSet
        iconSize: hdr.iconSize
    }

    // Everything under the icon: the condition and the range on one line for
    // the larger presets, the stacked pair for the compact one. Positioners
    // skip hidden items, so only one shape is ever laid out.
    Column {
        id: underIcon
        anchors.top: icon.bottom
        anchors.topMargin: Math.round(hdr.label * 0.3)
        anchors.right: parent.right
        spacing: hdr.compact
            ? Math.round(hdr.label * 0.15)
            : Math.round(hdr.label * 0.3)

        Text {
            visible: !hdr.compact
            anchors.right: parent.right
            textFormat: Text.PlainText
            text: hdr.weatherData.condition
            color: hdr.colors.weatherForeground
            font.family: hdr.fontFamily
            font.pixelSize: hdr.label
            font.weight: Font.Medium
        }

        Text {
            visible: !hdr.compact
            anchors.right: parent.right
            text: "H:" + hdr.weatherData.highTemp + "°  L:" + hdr.weatherData.lowTemp + "°"
            color: hdr.colors.weatherForeground
            opacity: 0.70
            font.family: hdr.fontFamily
            font.pixelSize: hdr.label
            font.weight: Font.Medium
        }

        Row {
            visible: hdr.compact
            spacing: Math.round(hdr.label * 0.15)

            Text {
                text: "↑"
                color: hdr.colors.weatherForeground
                font.family: hdr.fontFamily
                font.pixelSize: hdr.label
            }
            Text {
                text: hdr.weatherData.highTemp + "°"
                color: hdr.colors.weatherForeground
                font.family: hdr.fontFamily
                font.pixelSize: hdr.label
                font.weight: Font.Normal
            }
        }

        Row {
            visible: hdr.compact
            spacing: Math.round(hdr.label * 0.15)

            Text {
                text: "↓"
                color: hdr.colors.weatherForeground
                opacity: 0.70
                font.family: hdr.fontFamily
                font.pixelSize: hdr.label
            }
            Text {
                text: hdr.weatherData.lowTemp + "°"
                color: hdr.colors.weatherForeground
                opacity: 0.70
                font.family: hdr.fontFamily
                font.pixelSize: hdr.label
                font.weight: Font.Normal
            }
        }
    }
}
