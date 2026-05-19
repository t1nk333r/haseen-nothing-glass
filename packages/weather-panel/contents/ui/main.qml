import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "components"
import "widget"

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground

    FontLoader { id: sfLight;   source: Qt.resolvedUrl("../fonts/SF-Pro-Display-Light.otf") }
    FontLoader { id: sfRegular; source: Qt.resolvedUrl("../fonts/sf_pro_display_regular.otf") }

    WeatherData {
        id: weatherData
        location: plasmoid.configuration.location
        temperatureUnit: plasmoid.configuration.temperatureUnit
    }

    compactRepresentation: Item {
        id: compact

        readonly property bool isVertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

        states: [
            State {
                name: "horizontalPanel"
                when: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
                PropertyChanges {
                    compact.Layout.fillHeight: true
                    compact.Layout.fillWidth: false
                    compact.Layout.minimumWidth: compactRow.implicitWidth + compact.height * 0.3
                    compact.Layout.maximumWidth: compact.Layout.minimumWidth
                }
            },
            State {
                name: "verticalPanel"
                when: Plasmoid.formFactor === PlasmaCore.Types.Vertical
                PropertyChanges {
                    compact.Layout.fillHeight: false
                    compact.Layout.fillWidth: true
                    compact.Layout.minimumHeight: compactCol.implicitHeight + compact.width * 0.3
                    compact.Layout.maximumHeight: compact.Layout.minimumHeight
                }
            }
        ]

        Row {
            id: compactRow
            visible: !compact.isVertical
            anchors.centerIn: parent
            spacing: Math.round(compact.height * 0.15)

            WeatherIcon {
                anchors.verticalCenter: parent.verticalCenter
                iconName: weatherData.iconNameForCode(weatherData.weatherCode, weatherData.isNight)
                iconSet: "mono-light"
                iconSize: compact.height * 0.85
            }

            PlasmaComponents.Label {
                anchors.verticalCenter: parent.verticalCenter
                text: weatherData.currentTemp + "°"
                font.family: sfRegular.name
                font.pixelSize: compact.height * 0.55
                font.weight: Font.Medium
            }

            TextMetrics {
                id: compactMetrics
                font: compactRow.children[1].font
                text: "000°"
            }
        }

        Column {
            id: compactCol
            visible: compact.isVertical
            anchors.centerIn: parent
            spacing: Math.round(compact.width * 0.04)

            WeatherIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                iconName: weatherData.iconNameForCode(weatherData.weatherCode, weatherData.isNight)
                iconSet: "mono-light"
                iconSize: compact.width * 0.85
            }

            PlasmaComponents.Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: weatherData.currentTemp + "°"
                font.family: sfRegular.name
                font.pixelSize: compact.width * 0.48
                font.weight: Font.Medium
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: {
                if (mouse.button === Qt.RightButton)
                    weatherData.forceRefresh()
                else
                    root.expanded = !root.expanded
            }
        }
    }

    fullRepresentation: Item {
        id: full

        Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        Layout.preferredHeight: Kirigami.Units.gridUnit * 24
        Layout.minimumWidth: Kirigami.Units.gridUnit * 14
        Layout.minimumHeight: Kirigami.Units.gridUnit * 18

        readonly property real _labelSize: Math.max(10, Math.round(Math.min(full.height, 500) * 0.034))
        readonly property real _smallLabel: Math.max(9, Math.round(full._labelSize * 0.85))
        readonly property color _fg: Kirigami.Theme.textColor
        readonly property color _fgSec: Kirigami.Theme.disabledTextColor

        Item {
            id: content
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing

            readonly property real topSectionH: height * 0.22
            readonly property real hourlyH: height * 0.18
            readonly property real _sepSpacing: Math.round(height * 0.015)

            Item {
                id: topSection
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: content.topSectionH

                Column {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    spacing: 0

                    PlasmaComponents.Label {
                        text: weatherData.cityName || weatherData.location
                        font.family: sfRegular.name
                        font.pixelSize: Math.round(full._labelSize * 1.15)
                        font.weight: Font.Medium
                    }

                    PlasmaComponents.Label {
                        text: weatherData.currentTemp + "°"
                        font.family: sfLight.name
                        font.pixelSize: Math.round(full._labelSize * 3.5)
                        font.weight: Font.Thin
                    }
                }

                Column {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: Math.round(full._labelSize * 0.3)

                    WeatherIcon {
                        anchors.right: parent.right
                        iconName: weatherData.iconNameForCode(weatherData.weatherCode, weatherData.isNight)
                        iconSet: "mono-light"
                        iconSize: full._labelSize * 3
                    }

                    PlasmaComponents.Label {
                        anchors.right: parent.right
                        text: weatherData.condition
                        font.family: sfRegular.name
                        font.pixelSize: full._labelSize
                        font.weight: Font.Medium
                    }

                    PlasmaComponents.Label {
                        anchors.right: parent.right
                        text: "H:" + weatherData.highTemp + "°  L:" + weatherData.lowTemp + "°"
                        opacity: 0.60
                        font.family: sfRegular.name
                        font.pixelSize: full._labelSize
                        font.weight: Font.Medium
                    }
                }
            }

            Kirigami.Separator {
                id: sep1
                anchors.top: topSection.bottom
                anchors.topMargin: content._sepSpacing
                anchors.left: parent.left
                anchors.right: parent.right
            }

            HourlyForecast {
                id: hourly
                anchors.top: sep1.bottom
                anchors.topMargin: content._sepSpacing
                anchors.left: parent.left
                anchors.right: parent.right
                height: content.hourlyH
                slots: weatherData.hourlySlots
                iconSet: "mono-light"
                textColor: full._fg
                secondaryTextColor: full._fg
                secondaryOpacity: 0.60
                fontFamily: sfRegular.name
                baseFontSize: full._smallLabel
            }

            Kirigami.Separator {
                id: sep2
                anchors.top: hourly.bottom
                anchors.topMargin: content._sepSpacing
                anchors.left: parent.left
                anchors.right: parent.right
            }

            DailyForecast {
                anchors.top: sep2.bottom
                anchors.topMargin: content._sepSpacing
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                days: weatherData.dailyForecast
                overallLow: weatherData.overallLow
                overallHigh: weatherData.overallHigh
                iconSet: "mono-light"
                textColor: full._fg
                secondaryColor: full._fg
                secondaryOpacity: 0.60
                rangeBarBg: Qt.rgba(full._fgSec.r, full._fgSec.g, full._fgSec.b, 0.20)
                rangeBarFill: Qt.rgba(full._fg.r, full._fg.g, full._fg.b, 0.50)
                fontFamily: sfRegular.name
                fontSize: full._smallLabel
                iconNameForCode: function(code, night) { return weatherData.iconNameForCode(code, night) }
            }
        }

        MacSpinner {
            anchors.centerIn: parent
            width: 32
            height: 32
            color: full._fg
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
}
