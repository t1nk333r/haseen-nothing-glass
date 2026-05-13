import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("Weather")
        icon: "weather-clear"
        source: "config/ConfigGeneral.qml"
    }
}
