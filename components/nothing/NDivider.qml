import QtQuick

// A hairline. Horizontal by default; set `vertical` for a column rule.
Rectangle {
    id: rule
    required property var theme

    property bool vertical: false

    color: rule.theme.outline
    implicitWidth: rule.vertical ? rule.theme.hair : 0
    implicitHeight: rule.vertical ? 0 : rule.theme.hair
    width: rule.vertical ? rule.theme.hair : undefined
    height: rule.vertical ? undefined : rule.theme.hair
}
