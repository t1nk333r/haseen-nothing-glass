import QtQuick

// The technical readout: times, percentages, counters. Monospaced so digits
// do not shuffle the layout as they change - a clock whose colon moves is
// the fastest way to make a desktop feel cheap.
Text {
    id: m
    required property var theme

    color: m.theme.on
    font.family: m.theme.mono
    font.pixelSize: m.theme.fBody
    renderType: Text.NativeRendering
    textFormat: Text.PlainText
}
