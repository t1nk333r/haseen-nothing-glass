import QtQuick
import "dots.js" as Dots

// A glyph, or a string, drawn as a dot matrix - the style's basic
// vocabulary.
//
// Unlit dots keep their place rather than disappearing: the ghost grid is
// what makes the whole thing read as a display instead of a floating
// drawing. They are hidden with opacity, never `visible`, because a Grid
// repacks its columns around an invisible child and the glyph warps on
// every change.
Item {
    id: matrix
    required property var theme

    // Either give a ready pattern, or a string to lay out from dots.js.
    property var pattern: []
    property string text: ""

    // Dot size and spacing. Set them directly, OR give `fitWidth`/`fitHeight`
    // and let the component work them out from the glyph it is actually
    // drawing - which is the only way to get this right, because a call site
    // cannot know how many columns a string is without laying it out. A
    // clock guessing "HH:MM is about 12 columns" (it is 29) sized its dots
    // 2.4x too large and the digits ran off both edges of the tile.
    property real dot: matrix._fits ? matrix._fitDot : matrix.theme.px(3)
    property real gap: matrix._fits ? Math.max(1, matrix._fitDot * matrix.gapRatio)
                                    : matrix.theme.px(2)

    // Box to fit inside. 0 (the default) means "use dot/gap as given".
    property real fitWidth: 0
    property real fitHeight: 0
    // Spacing as a fraction of the dot, used only in fit mode.
    property real gapRatio: 0.34

    readonly property bool _fits: matrix.fitWidth > 0 && matrix.fitHeight > 0
        && matrix.colCount > 0 && matrix.rowCount > 0

    // width = c*d + (c-1)*d*r  ->  d = width / (c + (c-1)*r), and the same
    // for height; the smaller of the two keeps the glyph inside the box.
    //
    // That holds while the gap can honour the ratio, which it cannot below
    // d*r == 1: `gap` floors at 1 px there, so the drawn box is c*d + (c-1)*1
    // and the ratio solution overshoots - a 14 px fit drew 16.84 px of glyph,
    // 20% over the tile edge. Two regimes, crossing exactly where d*r == 1,
    // so solving each and taking the smaller is exact; a glyph whose dot is
    // above 1/r keeps the answer it always had.
    readonly property real _fitDot: {
        if (!matrix._fits) return 0
        var r = Math.max(0, matrix.gapRatio)
        var g = 1   // the same floor `gap` applies below
        var c = matrix.colCount, n = matrix.rowCount
        var byWr = matrix.fitWidth / (c + (c - 1) * r)
        var byHr = matrix.fitHeight / (n + (n - 1) * r)
        var byWf = (matrix.fitWidth - (c - 1) * g) / c
        var byHf = (matrix.fitHeight - (n - 1) * g) / n
        // The trailing 1 is the last resort for a box too small to hold the
        // glyph even at a 1 px dot - 7 rows in a box under 13 px tall. Below
        // it the glyph overflows rather than shrinking to nothing.
        return Math.max(1, Math.min(byWr, byHr, byWf, byHf))
    }

    property color onColor: matrix.theme.on
    property color offColor: matrix.theme.onFaint
    // Fraction of dots lit, in reading order: animate 0 -> 1 to reveal a
    // glyph dot by dot.
    property real reveal: 1.0

    readonly property var _rows: matrix.text !== ""
        ? Dots.text(matrix.text) : matrix.pattern
    readonly property int rowCount: matrix._rows.length
    readonly property int colCount:
        matrix.rowCount > 0 ? String(matrix._rows[0]).length : 0
    readonly property int total: matrix.rowCount * matrix.colCount

    implicitWidth: matrix.colCount > 0
        ? matrix.colCount * matrix.dot + (matrix.colCount - 1) * matrix.gap : 0
    implicitHeight: matrix.rowCount > 0
        ? matrix.rowCount * matrix.dot + (matrix.rowCount - 1) * matrix.gap : 0

    Grid {
        anchors.centerIn: parent
        columns: matrix.colCount
        rowSpacing: matrix.gap
        columnSpacing: matrix.gap

        Repeater {
            model: matrix.total

            Rectangle {
                required property int index

                readonly property bool lit: {
                    var row = String(matrix._rows[Math.floor(index / matrix.colCount)] || "")
                    var ch = row[index % matrix.colCount] || "0"
                    return ch !== "0" && ch !== " " && ch !== "."
                }
                readonly property bool shown: matrix.total > 0
                    && (index + 1) / matrix.total <= matrix.reveal + 0.0001

                width: matrix.dot
                height: matrix.dot
                radius: matrix.dot / 2
                color: lit ? matrix.onColor : matrix.offColor
                opacity: shown ? 1 : 0

                Behavior on color { ColorAnimation { duration: matrix.theme.fast } }
                Behavior on opacity { NumberAnimation { duration: matrix.theme.fast } }
            }
        }
    }
}
