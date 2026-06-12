import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("Clocks")
        icon: "preferences-system-time"
        source: "config/ConfigGeneral.qml"
    }
    ConfigCategory {
        name: i18n("Appearance")
        icon: "preferences-desktop-theme"
        source: "config/ConfigAppearance.qml"
    }
}
