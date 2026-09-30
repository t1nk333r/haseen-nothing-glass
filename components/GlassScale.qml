import QtQuick

// The Liquid Glass twin of NTheme's token block: one tile of one size draws
// the same type and the same margins whichever glass widget it is.
//
// It exists because the family had already drifted. The weather tile derived
// its label as `min(height, 350) * 0.065` and called a tile wide at
// `width >= height * 2`; the sunrise tile derived the same label as
// `minSide * (isWide ? 0.085 : 0.075)` and called it wide at *1.6. Two
// spellings of one decision, so the two tiles disagreed about what a label
// was by 7 px on the same 400x400 tile - and the weather body, which wrote
// its header three times, disagreed with itself inside one file.
//
// The three presets WidgetRegistry hands out are 192x192, 400x192 and
// 400x400 (PORTING.md item 15). Any `isWide` threshold between 1.0 and 2.083
// classifies all three identically, so `1.6` is that one decision written
// once, and a role below is read, never re-derived:
//
//   role    | 192x192 | 400x192 | 400x400
//   --------+---------+---------+--------
//   pad     |      16 |      16 |      34
//   gap     |       5 |       5 |       8
//   label   |      13 |      13 |      25
//   micro   |      12 |      12 |      23
//   body    |      15 |      15 |      29
//   hero    |      46 |      46 |      88
//   tight   |       7 |       7 |      13
//
// A dense layout (the big square's header and forecast rows) takes `tight`,
// the step-down the table above exists for, rather than inventing a second
// scale - or, worse, a literal.
//
// A widget body sets the two tile properties once and reads the roles from
// there; a new *role* belongs in this file and NTheme or in neither.
QtObject {
    id: s

    // Set once by the body, from its own width/height.
    property real tileWidth: 0
    property real tileHeight: 0

    readonly property real minSide: Math.min(s.tileWidth, s.tileHeight)
    readonly property bool isWide: s.tileWidth >= s.tileHeight * 1.6
    readonly property bool isBig: !s.isWide && s.minSide >= 300
    readonly property bool isSmall: !s.isWide && !s.isBig

    readonly property real pad:   Math.round(s.minSide * 0.085)
    readonly property real gap:   Math.round(s.label * 0.35)
    readonly property real label: Math.max(10, Math.round(Math.min(s.minSide, 350) * 0.070))
    readonly property real micro: Math.max(9, Math.round(s.label * 0.90))
    readonly property real body:  Math.round(s.label * 1.15)
    readonly property real hero:  Math.round(s.label * 3.5)
    readonly property real tight: Math.round(s.label * 0.52)
}
