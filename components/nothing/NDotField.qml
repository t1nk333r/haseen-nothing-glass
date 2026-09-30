import QtQuick

// The decorative dot grid that fills empty corners of a card. Purely
// atmospheric, so it stays faint and never carries information - a field
// that meant something would be a chart, and a chart should say so.
Item {
    id: field
    required property var theme

    property real dot: field.theme.px(2)
    property real spacing: field.theme.px(9)
    property color color: field.theme.onFaint
    property real intensity: 1.0

    readonly property int cols: Math.max(0, Math.floor(width / field.spacing))
    readonly property int rows: Math.max(0, Math.floor(height / field.spacing))

    // An invisible Item still instantiates its children, so the presets that
    // hide this field were building 1,681 Rectangles for a grid nobody draws.
    // The Repeater's model is the only thing that decides that, so it is
    // gated on `visible`; a field that IS drawn counts exactly as before.
    readonly property int dotCount: field.visible ? field.cols * field.rows : 0

    clip: true

    Grid {
        columns: field.cols
        rowSpacing: field.spacing - field.dot
        columnSpacing: field.spacing - field.dot

        Repeater {
            model: field.dotCount

            Rectangle {
                width: field.dot
                height: field.dot
                radius: field.dot / 2
                color: field.color
                opacity: field.intensity
            }
        }
    }
}
