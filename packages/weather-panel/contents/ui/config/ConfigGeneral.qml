import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root
    spacing: Kirigami.Units.largeSpacing

    property alias cfg_location: locationField.text
    property alias cfg_temperatureUnit: unitCombo.currentIndex

    Kirigami.FormLayout {
        Layout.fillWidth: true

        TextField {
            id: locationField
            Kirigami.FormData.label: i18n("Location:")
            placeholderText: i18n("City name (e.g. London)")
        }

        ComboBox {
            id: unitCombo
            Kirigami.FormData.label: i18n("Temperature unit:")
            model: [i18n("Celsius (°C)"), i18n("Fahrenheit (°F)")]
        }
    }
}
