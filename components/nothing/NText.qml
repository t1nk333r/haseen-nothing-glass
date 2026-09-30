import QtQuick

// Body text with the style's defaults already applied, so a call site only
// states what makes it different. Every Nothing widget uses this rather
// than a bare Text, which is what keeps a typeface change to one file.
Text {
    id: t
    required property var theme

    color: t.theme.on
    font.family: t.theme.sans
    font.pixelSize: t.theme.fBody
    renderType: Text.NativeRendering
    textFormat: Text.PlainText
}
