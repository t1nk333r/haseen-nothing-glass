import QtQuick
import "../../../components/nothing"

// The Nothing weather header: the city, the tile's unit badge (or the
// condition glyph on the small square), and the line under it.
//
// It is a component because it used to be three copies - one per grid preset,
// at lines 154, 237 and 396 of main.qml - and three copies of one header is
// how a style drifts apart from itself.
//
// It takes no sizes. The sidebar already has a scale (`theme`), and the
// Nothing vocabulary is absolute: `theme.fLabel` and `theme.fMicro` are what
// every other NLabel and NMono in this tree draws at, so a layout asks for a
// ROLE - `compact`, the badge, the sub-line - and never for a number.
Item {
    id: hdr

    required property var theme

    property string city: ""
    property string chipLabel: ""
    property string subLine: ""
    // The condition, as the small square's right-hand marker. Five-by-five
    // dot patterns, the same vocabulary the hero number is drawn in.
    property var glyph: []

    // The small square: no chip, the glyph instead, and the city on the top
    // edge. That is the one shape the presets genuinely disagree about.
    property bool compact: false
    property bool showChip: true
    property bool showSub: false

    // The next section anchors to this header's bottom edge, so the header is
    // exactly as tall as what it drew. The extent is measured as y + height,
    // never as `.bottom`: on an item here that is an anchor LINE
    // (QQuickAnchorLine), and arithmetic on one is NaN - a NaN height would
    // silently collapse the stage the layout hangs under it.
    implicitHeight: {
        var low = Math.max(cityLabel.y + cityLabel.height,
                           hdr.badgeSlot.y + hdr.badgeSlot.height)
        if (subLine.visible) low = Math.max(low, subLine.y + subLine.height)
        return low
    }

    // Whichever marker this preset uses; the city reserves room against it.
    readonly property Item badgeSlot: hdr.showChip ? chip : conditionGlyph

    NDotMatrix {
        id: conditionGlyph
        visible: !hdr.showChip
        theme: hdr.theme
        pattern: hdr.glyph
        dot: hdr.theme.px(3)
        gap: hdr.theme.px(1.5)
        onColor: hdr.theme.on
        offColor: "transparent"
        anchors.top: parent.top
        anchors.right: parent.right
    }

    NBadge {
        id: chip
        visible: hdr.showChip
        theme: hdr.theme
        active: true
        label: hdr.chipLabel
        anchors.top: parent.top
        anchors.right: parent.right
    }

    NLabel {
        id: cityLabel
        theme: hdr.theme
        text: hdr.city
        loud: true
        elide: Text.ElideRight
        anchors.left: parent.left
        anchors.right: hdr.badgeSlot.left
        anchors.rightMargin: hdr.theme.gap
        // The compact preset has no chip to centre against: the city sits on
        // the top edge beside the glyph. Same rule as the glass twin's
        // sunrise arc, which also switches an anchor on the preset.
        anchors.top: hdr.compact ? parent.top : undefined
        anchors.verticalCenter: hdr.compact ? undefined : hdr.badgeSlot.verticalCenter
    }

    NLabel {
        id: subLine
        visible: hdr.showSub
        theme: hdr.theme
        text: hdr.subLine
        elide: Text.ElideRight
        anchors.top: hdr.badgeSlot.bottom
        anchors.topMargin: hdr.theme.px(4)
        anchors.left: parent.left
        anchors.right: parent.right
    }
}
