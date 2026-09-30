import QtQuick
import "../../components"
import "../../components/nothing"
import "widget"

// Weather, Nothing style.
//
// Same data wiring as the Liquid Glass weather tile next door - one
// WeatherDataQs instance (one HTTP fetch, one refresh timer) resolving the
// same shared-location -> IP-auto-detect chain, the same
// `plugin.settings` keys. Only the drawing differs: no PNG icon set,
// no glass, no gradient. The condition is a five-by-five dot glyph, the
// temperature is a dot-matrix number, the forecast is mono text and
// segmented bars.
Item {
    id: full
    anchors.fill: parent

    // The three grid presets: 192x192 (small), 400x192 (wide), 400x400 (big).
    readonly property bool isWide: full.width >= full.height * 1.6
    readonly property bool isBig: !full.isWide && Math.min(full.width, full.height) >= 300
    readonly property bool isSmall: !full.isWide && !full.isBig

    // ── Data: identical to widgets/weather/main.qml ──────────────────────
    // WeatherDataQs owns the location now: it follows
    // ~/.local/state/omarchy/settings/weather.json (what
    // `omarchy-weather-location` writes and the bar's weather reads) and falls
    // back to IP auto-detection. `location` is only a per-widget override, so
    // a second tile can sit on another city; empty means "follow Omarchy".
    WeatherDataQs {
        id: weatherData
        location: plugin.settings.location
        unit: plugin.settings.unit
        refreshMinutes: plugin.settings.refreshMinutes
        // Same gate as every other engine in this plugin: off while the
        // screen is switched off, on whenever that is unknown.
        active: full.visible
    }

    readonly property string cityLabel: weatherData.cityName
    readonly property string unitLabel: weatherData.tempSymbol
    readonly property string highLow:
        "H " + weatherData.highTemp + "°   L " + weatherData.lowTemp + "°"
    readonly property string windLine:
        weatherData.windSpeed + " " + weatherData.windUnit + " " + weatherData.windDirection

    // ── Condition as dots, not as an icon file ───────────────────────────
    // Five-by-five patterns, one per name WeatherDataQs.iconNameForCode can
    // return. NDotMatrix draws them with the same dots the temperature uses,
    // which is the whole point: one vocabulary, no bitmap art.
    readonly property var _glyphs: ({
        "sunny":              ["01110", "10001", "10001", "10001", "01110"],
        "clearnight":         ["01110", "11000", "10000", "11000", "01110"],
        "partlysunny":        ["01100", "10010", "01111", "11111", "00000"],
        "partlycloudynight":  ["11000", "01100", "00111", "11111", "00000"],
        "cloudy":             ["00000", "01110", "11111", "11111", "00000"],
        "fog":                ["01110", "00000", "11111", "00000", "01110"],
        "drizzle":            ["01110", "11111", "00000", "01010", "00000"],
        "nightdrizzle":       ["01110", "11111", "00000", "01010", "00000"],
        "rain":               ["01110", "11111", "00000", "10101", "01010"],
        "heavyrain":          ["01110", "11111", "10101", "01010", "10101"],
        "sleet":              ["01110", "11111", "00000", "10100", "00101"],
        "snow":               ["10101", "01110", "11111", "01110", "10101"],
        "scatteredsnow":      ["01110", "11111", "00000", "10001", "00100"],
        "thunderbolt":        ["00110", "01100", "11110", "00110", "01100"],
        "sunrise":            ["00100", "01010", "10001", "00000", "11111"],
        "sunset":             ["11111", "00000", "10001", "01010", "00100"]
    })

    function glyphFor(name) {
        var g = full._glyphs[name]
        return g ? g : full._glyphs["cloudy"]
    }

    readonly property var currentGlyph:
        full.glyphFor(weatherData.iconNameForCode(weatherData.weatherCode, weatherData.isNight))

    // Dot columns a string occupies in NDotMatrix: five per digit (and per
    // minus sign) with a one-dot gutter between them. Used to size the hero
    // from the tile instead of from a constant.
    function matrixCols(s) {
        var n = Math.max(1, String(s).length)
        return n * 6 - 1
    }

    // 24-hour label: the strip is monospaced and dense, so "15" beats "3 PM".
    function hourLabel(slot) {
        return slot && slot.time ? Qt.formatDateTime(slot.time, "HH") : "--"
    }

    // Where an hourly temperature sits inside the strip's own range, which
    // is what the dot columns read. Sun events carry no temperature.
    readonly property var _hourBounds: {
        var lo = Infinity
        var hi = -Infinity
        var s = weatherData.hourlySlots
        for (var i = 0; i < s.length; i++) {
            if (s[i].isSunEvent) continue
            var t = parseFloat(s[i].temp)
            if (isNaN(t)) continue
            if (t < lo) lo = t
            if (t > hi) hi = t
        }
        if (lo === Infinity) return { lo: 0, hi: 1 }
        if (hi - lo < 1) hi = lo + 1
        return { lo: lo, hi: hi }
    }

    function hourFrac(slot) {
        if (!slot || slot.isSunEvent) return 0
        var t = parseFloat(slot.temp)
        if (isNaN(t)) return 0
        var b = full._hourBounds
        return Math.max(0, Math.min(1, (t - b.lo) / (b.hi - b.lo)))
    }

    function dayFrac(v) {
        var span = weatherData.overallHigh - weatherData.overallLow
        if (span <= 0) return 0
        return Math.max(0, Math.min(1, (parseFloat(v) - weatherData.overallLow) / span))
    }

    // The one hot day of the week. Exactly one row gets the accent: ties on
    // the maximum go to the earliest, because two red bars would read as a
    // category rather than as "this is the peak".
    readonly property int hottestDay: {
        var days = weatherData.dailyForecast
        var best = -1
        var bestV = -Infinity
        for (var i = 0; i < days.length; i++) {
            var v = parseFloat(days[i].high)
            if (isNaN(v)) continue
            if (v > bestV) { bestV = v; best = i }
        }
        return best
    }

    readonly property string statusLine:
        weatherData.errorMessage !== "" ? weatherData.errorMessage : "Loading"

    NCard {
        id: card
        theme: nothing
        anchors.fill: parent
        clip: true

        // ── Small square: city, the number, the condition ────────────────
        Item {
            id: smallLayout
            visible: full.isSmall
            anchors.fill: parent
            anchors.margins: nothing.pad

            // The header, drawn once for all three presets - see
            // widget/WeatherHeader.qml. A role, never a size.
            WeatherHeader {
                id: sHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                theme: nothing
                compact: true
                showChip: false
                city: full.cityLabel
                glyph: full.currentGlyph
            }

            Item {
                id: sStage
                anchors.top: sHeader.bottom
                anchors.topMargin: nothing.gap
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: sFooter.top
                anchors.bottomMargin: nothing.gap

                readonly property real dotSize: {
                    var cols = full.matrixCols(weatherData.currentTemp)
                    var byW = (sStage.width - (cols - 1) * 2) / cols
                    var byH = (sStage.height - 6 * 2) / 7
                    // One fill factor for all three presets: the 0.82,
                    // 0.9 and 0.92 the three copies carried were three
                    // spellings of one decision.
                    return Math.max(2, Math.min(byW, byH) * 0.9)
                }

                NDotMatrix {
                    anchors.centerIn: parent
                    theme: nothing
                    text: weatherData.currentTemp
                    dot: sStage.dotSize
                    gap: Math.max(1, sStage.dotSize * 0.34)
                    onColor: nothing.on
                }
            }

            Column {
                id: sFooter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: nothing.px(3)

                NLabel {
                    theme: nothing
                    width: parent.width
                    text: weatherData.condition
                    loud: true
                    elide: Text.ElideRight
                }
                NMono {
                    theme: nothing
                    width: parent.width
                    text: full.highLow
                    color: nothing.onDim
                    font.pixelSize: nothing.fMicro
                    elide: Text.ElideRight
                }
            }
        }

        // ── Wide: the number on the left, the next four hours beside it ──
        Item {
            id: wideLayout
            visible: full.isWide
            anchors.fill: parent
            anchors.margins: nothing.pad

            readonly property var slots: weatherData.hourlySlots.slice(0, 4)

            WeatherHeader {
                id: wHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                theme: nothing
                showChip: true
                city: full.cityLabel
                chipLabel: full.unitLabel
            }

            Item {
                id: wLeft
                anchors.top: wHeader.bottom
                anchors.topMargin: nothing.gap
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                width: Math.round(parent.width * 0.46)

                readonly property real dotSize: {
                    var cols = full.matrixCols(weatherData.currentTemp)
                    var byW = (wLeft.width - (cols - 1) * 2) / cols
                    var byH = (wLeft.height - wText.height - nothing.gap - 6 * 2) / 7
                    return Math.max(2, Math.min(byW, byH) * 0.9)
                }

                NDotMatrix {
                    id: wTemp
                    theme: nothing
                    text: weatherData.currentTemp
                    dot: wLeft.dotSize
                    gap: Math.max(1, wLeft.dotSize * 0.34)
                    onColor: nothing.on
                    anchors.left: parent.left
                    anchors.top: parent.top
                }

                Column {
                    id: wText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    spacing: nothing.px(2)

                    NLabel {
                        theme: nothing
                        width: parent.width
                        text: weatherData.condition
                        loud: true
                        elide: Text.ElideRight
                    }
                    NMono {
                        theme: nothing
                        width: parent.width
                        text: full.highLow
                        color: nothing.onDim
                        font.pixelSize: nothing.fMicro
                        elide: Text.ElideRight
                    }
                }
            }

            NDivider {
                id: wRule
                theme: nothing
                vertical: true
                anchors.left: wLeft.right
                anchors.leftMargin: nothing.pad
                anchors.top: wLeft.top
                anchors.bottom: parent.bottom
            }

            Column {
                id: wHours
                anchors.left: wRule.right
                anchors.leftMargin: nothing.pad
                anchors.right: parent.right
                anchors.top: wLeft.top
                anchors.bottom: parent.bottom
                spacing: nothing.px(2)

                readonly property int rows: Math.max(1, wideLayout.slots.length)
                readonly property real rowH:
                    (wHours.height - (wHours.rows - 1) * wHours.spacing) / wHours.rows

                Repeater {
                    model: wideLayout.slots

                    Item {
                        id: wRow
                        required property var modelData
                        width: wHours.width
                        height: wHours.rowH

                        NMono {
                            id: wRowHour
                            theme: nothing
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: full.hourLabel(wRow.modelData)
                            color: nothing.onDim
                            font.pixelSize: nothing.fLabel
                        }

                        NDotMatrix {
                            theme: nothing
                            anchors.left: wRowHour.right
                            anchors.leftMargin: nothing.gap
                            anchors.verticalCenter: parent.verticalCenter
                            pattern: full.glyphFor(wRow.modelData.iconName)
                            dot: nothing.px(3)
                            gap: nothing.px(1)
                            onColor: wRow.modelData.isSunEvent ? nothing.red : nothing.on
                            offColor: "transparent"
                        }

                        NMono {
                            theme: nothing
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: wRow.modelData.isSunEvent
                                ? wRow.modelData.sunEventType.toUpperCase()
                                : wRow.modelData.temp + "°"
                            color: wRow.modelData.isSunEvent ? nothing.red : nothing.on
                            font.pixelSize: wRow.modelData.isSunEvent
                                ? nothing.fMicro : nothing.fLabel
                        }
                    }
                }
            }

            NLabel {
                theme: nothing
                anchors.centerIn: wHours
                width: wHours.width
                visible: wideLayout.slots.length === 0
                text: full.statusLine
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }

        // ── Big square: everything - hero, hourly strip, five-day rows ───
        Item {
            id: bigLayout
            visible: full.isBig
            anchors.fill: parent
            anchors.margins: nothing.pad

            WeatherHeader {
                id: bHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                theme: nothing
                showChip: true
                showSub: true
                city: full.cityLabel
                chipLabel: full.unitLabel
                subLine: weatherData.precipitationSummary !== ""
                    ? weatherData.precipitationSummary : full.windLine
            }

            // Hero: dot-matrix temperature, condition glyph and text beside it.
            Item {
                id: bHero
                anchors.top: bHeader.bottom
                anchors.topMargin: nothing.gap
                anchors.left: parent.left
                anchors.right: parent.right
                height: Math.round(full.height * 0.22)

                readonly property real dotSize: {
                    var cols = full.matrixCols(weatherData.currentTemp)
                    var byW = (bHero.width * 0.52 - (cols - 1) * 2) / cols
                    var byH = (bHero.height - 6 * 2) / 7
                    return Math.max(2, Math.min(byW, byH) * 0.9)
                }

                NDotMatrix {
                    theme: nothing
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: weatherData.currentTemp
                    dot: bHero.dotSize
                    gap: Math.max(1, bHero.dotSize * 0.34)
                    onColor: nothing.on
                }

                NDotMatrix {
                    id: bGlyph
                    theme: nothing
                    anchors.right: parent.right
                    anchors.top: parent.top
                    pattern: full.currentGlyph
                    dot: nothing.px(4)
                    gap: nothing.px(2)
                    onColor: nothing.on
                    offColor: "transparent"
                }

                Column {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.left: parent.horizontalCenter
                    spacing: nothing.px(2)

                    NLabel {
                        theme: nothing
                        width: parent.width
                        text: weatherData.condition
                        loud: true
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                    }
                    NMono {
                        theme: nothing
                        width: parent.width
                        text: full.highLow
                        color: nothing.onDim
                        font.pixelSize: nothing.fLabel
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                    }
                    NMono {
                        theme: nothing
                        width: parent.width
                        text: full.windLine
                        color: nothing.onDim
                        font.pixelSize: nothing.fMicro
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                    }
                }
            }

            NDivider {
                id: bRule1
                theme: nothing
                anchors.top: bHero.bottom
                anchors.topMargin: nothing.gap
                anchors.left: parent.left
                anchors.right: parent.right
            }

            // Hourly: one dot column per slot, height = temperature inside
            // the strip's own range. Sun events are the red columns.
            Row {
                id: bHours
                anchors.top: bRule1.bottom
                anchors.topMargin: nothing.gap
                anchors.left: parent.left
                anchors.right: parent.right
                height: Math.round(full.height * 0.19)
                spacing: nothing.px(6)

                readonly property int count: Math.max(1, weatherData.hourlySlots.length)
                readonly property real colW:
                    (bHours.width - (bHours.count - 1) * bHours.spacing) / bHours.count

                Repeater {
                    model: weatherData.hourlySlots

                    Item {
                        id: bCol
                        required property var modelData
                        width: bHours.colW
                        height: bHours.height

                        readonly property bool sun: bCol.modelData.isSunEvent
                        readonly property int lit: bCol.sun
                            ? 1 : Math.max(1, Math.round(full.hourFrac(bCol.modelData) * 5))

                        NMono {
                            id: bColHour
                            theme: nothing
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            text: full.hourLabel(bCol.modelData)
                            color: nothing.onDim
                            font.pixelSize: nothing.fMicro
                        }

                        Column {
                            id: bColDots
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: bColHour.bottom
                            anchors.topMargin: nothing.px(4)
                            spacing: nothing.px(2)

                            Repeater {
                                model: 5

                                Rectangle {
                                    required property int index
                                    width: nothing.px(4)
                                    height: nothing.px(4)
                                    radius: width / 2
                                    color: (5 - index) <= bCol.lit
                                        ? (bCol.sun ? nothing.red : nothing.on)
                                        : nothing.onFaint
                                }
                            }
                        }

                        NMono {
                            theme: nothing
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            text: bCol.sun
                                ? (bCol.modelData.sunEventType === "Sunrise" ? "RISE" : "SET")
                                : bCol.modelData.temp + "°"
                            color: bCol.sun ? nothing.red : nothing.on
                            font.pixelSize: bCol.sun ? nothing.fMicro : nothing.fLabel
                        }
                    }
                }
            }

            NLabel {
                theme: nothing
                anchors.centerIn: bHours
                width: bHours.width
                visible: weatherData.hourlySlots.length === 0
                text: full.statusLine
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            NDivider {
                id: bRule2
                theme: nothing
                anchors.top: bHours.bottom
                anchors.topMargin: nothing.gap
                anchors.left: parent.left
                anchors.right: parent.right
            }

            // Five days: label, glyph, low, the range as a segmented bar
            // between the week's extremes, high. The hottest day's bar is
            // the one red thing in the tile.
            Column {
                id: bDays
                anchors.top: bRule2.bottom
                anchors.topMargin: nothing.gap
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: nothing.px(2)

                readonly property int count: Math.max(1, weatherData.dailyForecast.length)
                readonly property real rowH:
                    (bDays.height - (bDays.count - 1) * bDays.spacing) / bDays.count

                Repeater {
                    model: weatherData.dailyForecast

                    Item {
                        id: bDay
                        required property var modelData
                        required property int index
                        width: bDays.width
                        height: bDays.rowH

                        readonly property bool peak: bDay.index === full.hottestDay

                        NLabel {
                            id: bDayName
                            theme: nothing
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.round(bDays.width * 0.13)
                            text: bDay.modelData.day
                            loud: true
                        }

                        NDotMatrix {
                            id: bDayGlyph
                            theme: nothing
                            anchors.left: bDayName.right
                            anchors.verticalCenter: parent.verticalCenter
                            pattern: full.glyphFor(
                                weatherData.iconNameForCode(bDay.modelData.weatherCode, false))
                            dot: nothing.px(3)
                            gap: nothing.px(1)
                            onColor: nothing.onDim
                            offColor: "transparent"
                        }

                        NMono {
                            id: bDayLow
                            theme: nothing
                            anchors.left: bDayGlyph.right
                            anchors.leftMargin: nothing.gap
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.round(bDays.width * 0.10)
                            horizontalAlignment: Text.AlignRight
                            text: bDay.modelData.low + "°"
                            color: nothing.onDim
                            font.pixelSize: nothing.fLabel
                        }

                        Row {
                            id: bDayBar
                            anchors.left: bDayLow.right
                            anchors.leftMargin: nothing.gap
                            anchors.right: bDayHigh.left
                            anchors.rightMargin: nothing.gap
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: nothing.px(2)

                            readonly property int segments: 16
                            readonly property real lo: full.dayFrac(bDay.modelData.low)
                            readonly property real hi: full.dayFrac(bDay.modelData.high)

                            Repeater {
                                model: bDayBar.segments

                                Rectangle {
                                    required property int index
                                    readonly property real at:
                                        (index + 0.5) / bDayBar.segments

                                    width: (bDayBar.width
                                        - (bDayBar.segments - 1) * nothing.px(2))
                                        / bDayBar.segments
                                    height: nothing.px(4)
                                    radius: nothing.rDot
                                    color: (at >= bDayBar.lo && at <= bDayBar.hi)
                                        ? (bDay.peak ? nothing.red : nothing.on)
                                        : nothing.onFaint
                                }
                            }
                        }

                        NMono {
                            id: bDayHigh
                            theme: nothing
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.round(bDays.width * 0.10)
                            horizontalAlignment: Text.AlignRight
                            text: bDay.modelData.high + "°"
                            color: nothing.on
                            font.pixelSize: nothing.fLabel
                        }
                    }
                }
            }

            NLabel {
                theme: nothing
                anchors.centerIn: bDays
                width: bDays.width
                visible: weatherData.dailyForecast.length === 0
                text: full.statusLine
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }
    }

    // Click to refetch, exactly as the Liquid Glass tile does.
    MouseArea {
        anchors.fill: parent
        z: 10
        acceptedButtons: Qt.LeftButton
        onClicked: weatherData.forceRefresh()
    }
}
