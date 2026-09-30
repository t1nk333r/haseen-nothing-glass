import QtQuick

// A small state marker. Red when `active`, otherwise a faint outline - the
// only place the accent appears in most widgets.
Rectangle {
    id: badge
    required property var theme

    property bool active: false
    property string label: ""

    implicitWidth: badge.label === ""
        ? badge.theme.px(8)
        : text.implicitWidth + badge.theme.px(12)
    implicitHeight: badge.label === "" ? badge.theme.px(8) : badge.theme.px(18)
    radius: badge.label === "" ? height / 2 : badge.theme.rChip

    color: badge.active ? badge.theme.red : "transparent"
    border.width: badge.active ? 0 : badge.theme.hair
    border.color: badge.theme.outline

    Behavior on color { ColorAnimation { duration: badge.theme.fast } }

    Text {
        id: text
        anchors.centerIn: parent
        visible: badge.label !== ""
        text: badge.label
        color: badge.active ? badge.theme.redInk : badge.theme.onDim
        font.family: badge.theme.sans
        font.pixelSize: badge.theme.fMicro
        font.letterSpacing: badge.theme.trackLabel
        font.capitalization: Font.AllUppercase
        textFormat: Text.PlainText
    }
}
