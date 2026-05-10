import QtQuick
import QtQuick.Layouts

Item {
    id: hf

    property var slots: []
    property string iconSet: "default"
    property color textColor: "#ffffff"
    property color secondaryTextColor: "#ffffff"
    property real secondaryOpacity: 0.65
    property string fontFamily: ""
    property real baseFontSize: 12

    readonly property real _fontSize: baseFontSize * 0.85

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Repeater {
            model: hf.slots.length

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                readonly property var slot: index < hf.slots.length ? hf.slots[index] : null

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Math.round(hf.height * 0.04)

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: slot ? slot.displayTime : "--"
                        color: hf.secondaryTextColor
                        opacity: hf.secondaryOpacity
                        font.family: hf.fontFamily
                        font.pixelSize: hf._fontSize
                        font.weight: Font.Regular
                    }

                    WeatherIcon {
                        Layout.alignment: Qt.AlignHCenter
                        iconName: slot ? slot.iconName : "sunny"
                        iconSet: hf.iconSet
                        iconSize: Math.round(hf.height * 0.36)
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: {
                            if (!slot) return "--"
                            if (slot.isSunEvent) return slot.sunEventType
                            return slot.temp + "°"
                        }
                        color: hf.textColor
                        opacity: slot && slot.isSunEvent ? hf.secondaryOpacity : 1.0
                        font.family: hf.fontFamily
                        font.pixelSize: hf._fontSize
                        font.weight: Font.Regular
                    }
                }
            }
        }
    }
}
