import QtQuick

// The small uppercase metadata line - "CPU", "NEXT", "RIYADH". Tracked out
// and dimmed: it names the number beside it and must never compete with it.
Text {
    id: l
    required property var theme

    property bool loud: false

    text: ""
    color: l.loud ? l.theme.on : l.theme.onDim
    font.family: l.theme.sans
    font.pixelSize: l.theme.fLabel
    font.letterSpacing: l.theme.trackLabel
    font.capitalization: Font.AllUppercase
    renderType: Text.NativeRendering
    textFormat: Text.PlainText
}
