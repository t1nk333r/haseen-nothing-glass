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

    // Where nothing can mask the field - Qt's software scene graph runs no
    // MultiEffect - a frame that would have cut its corners asks for them
    // here instead: a dot whose centre falls outside a rounded rectangle of
    // this radius is not drawn. 0, the default, draws every dot.
    property real cornerRadius: 0

    function _inside(i) {
        var r = Math.min(field.cornerRadius, field.width / 2, field.height / 2)
        var cx = (i % field.cols) * field.spacing + field.dot / 2
        var cy = Math.floor(i / field.cols) * field.spacing + field.dot / 2
        var dx = Math.max(r - cx, 0, cx - (field.width - r))
        var dy = Math.max(r - cy, 0, cy - (field.height - r))
        return dx * dx + dy * dy <= r * r
    }

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
                required property int index
                width: field.dot
                height: field.dot
                radius: field.dot / 2
                color: field.color
                // Opacity, not `visible`: a Grid closes up after an invisible
                // child, and the dots past it would shift.
                opacity: field.cornerRadius > 0 && !field._inside(index) ? 0 : field.intensity
            }
        }
    }
}
