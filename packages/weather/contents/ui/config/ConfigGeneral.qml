import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: root
    implicitWidth: content.implicitWidth + Kirigami.Units.largeSpacing * 4
    implicitHeight: content.implicitHeight + Kirigami.Units.largeSpacing * 4

    property string cfg_location: ""
    property double cfg_latitude: 0
    property double cfg_longitude: 0
    property int cfg_temperatureUnit: 0

    property int _reqId: 0
    property bool _suppressTextChange: false

    ListModel { id: suggestionsModel }

    Timer {
        id: searchDebounce
        interval: 250
        repeat: false
        onTriggered: root._search(locationField.text)
    }

    function _search(query) {
        var q = (query || "").trim()
        if (q.length < 2) {
            suggestionsModel.clear()
            suggestionsPopup.close()
            return
        }
        var reqId = ++_reqId
        var xhr = new XMLHttpRequest()
        var url = "https://geocoding-api.open-meteo.com/v1/search?name=" +
                  encodeURIComponent(q) + "&count=8&language=en&format=json"
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (reqId !== root._reqId) return
            if (xhr.status !== 200) return
            try {
                var resp = JSON.parse(xhr.responseText)
                suggestionsModel.clear()
                if (!resp.results || resp.results.length === 0) {
                    suggestionsPopup.close()
                    return
                }
                for (var i = 0; i < resp.results.length; i++) {
                    var r = resp.results[i]
                    var parts = [r.name]
                    if (r.admin1 && r.admin1.length > 0) parts.push(r.admin1)
                    if (r.country && r.country.length > 0) parts.push(r.country)
                    suggestionsModel.append({
                        display: parts.join(", "),
                        name: r.name || "",
                        latitude: r.latitude,
                        longitude: r.longitude
                    })
                }
                if (locationField.activeFocus)
                    suggestionsPopup.open()
            } catch (e) {}
        }
        xhr.open("GET", url)
        xhr.send()
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing * 2
        spacing: Kirigami.Units.largeSpacing

        Label {
            Layout.fillWidth: true
            text: i18n("Location")
            font.bold: true
        }

        Label {
            Layout.fillWidth: true
            text: i18n("Start typing a city name and pick a result to set your weather location.")
            wrapMode: Text.WordWrap
            opacity: 0.75
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        }

        TextField {
            id: locationField
            Layout.fillWidth: true
            placeholderText: i18n("City name (e.g. London)")

            Component.onCompleted: {
                root._suppressTextChange = true
                text = root.cfg_location
                root._suppressTextChange = false
            }

            onTextChanged: {
                if (root._suppressTextChange) return
                root.cfg_location = text
                searchDebounce.restart()
            }

            Popup {
                id: suggestionsPopup
                y: locationField.height
                x: 0
                width: locationField.width
                padding: 1
                closePolicy: Popup.CloseOnPressOutsideParent | Popup.CloseOnEscape

                contentItem: ListView {
                    id: suggestionsList
                    implicitHeight: Math.min(contentHeight, 240)
                    model: suggestionsModel
                    clip: true
                    delegate: ItemDelegate {
                        width: suggestionsList.width
                        text: model.display
                        onClicked: {
                            root._suppressTextChange = true
                            locationField.text = model.name
                            root._suppressTextChange = false
                            root.cfg_location = model.name
                            root.cfg_latitude = model.latitude
                            root.cfg_longitude = model.longitude
                            suggestionsPopup.close()
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.largeSpacing

            Label {
                text: i18n("Temperature unit:")
            }
            ComboBox {
                id: unitCombo
                Layout.fillWidth: true
                model: [i18n("Celsius (°C)"), i18n("Fahrenheit (°F)")]
                // Restore the saved index explicitly (a JS-array model resets
                // currentIndex to 0 on load). Write back using the activated
                // signal's `index` argument, not `currentIndex`, which is not
                // yet updated when onActivated fires (caused a one-step lag).
                Component.onCompleted: currentIndex = root.cfg_temperatureUnit
                onModelChanged: currentIndex = root.cfg_temperatureUnit
                onActivated: (index) => root.cfg_temperatureUnit = index
            }
        }

        Item { Layout.fillHeight: true }

        Label {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing
            text: i18n("Locations are resolved with the Open-Meteo Geocoding API (geocoding-api.open-meteo.com) and forecasts are fetched from Open-Meteo (api.open-meteo.com). No account or API key is required. Selecting a result stores its coordinates directly, so weather refreshes skip the geocoding step.")
            wrapMode: Text.WordWrap
            opacity: 0.6
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        }
    }
}
