import QtQuick

// A flat control. No fill until hovered; red only when it is the active
// choice, which is the one place a button earns the accent.
Rectangle {
    id: button
    required property var theme

    property string label: ""
    property bool active: false
    property bool enabled: true
    readonly property bool hovered: area.containsMouse

    signal clicked()

    implicitWidth: text.implicitWidth + button.theme.px(22)
    implicitHeight: button.theme.px(30)
    radius: button.theme.rChip

    color: button.active
        ? button.theme.red
        : (button.hovered ? button.theme.surface3 : "transparent")
    border.width: button.active ? 0 : button.theme.hair
    border.color: button.theme.outline
    opacity: button.enabled ? 1 : 0.4

    Behavior on color { ColorAnimation { duration: button.theme.fast } }

    Text {
        id: text
        anchors.centerIn: parent
        text: button.label
        color: button.active ? button.theme.redInk : button.theme.on
        font.family: button.theme.sans
        font.pixelSize: button.theme.fLabel
        font.letterSpacing: button.theme.trackLabel
        font.capitalization: Font.AllUppercase
        textFormat: Text.PlainText
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: button.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}
