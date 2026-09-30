import QtQuick

// Copied from packages/music/contents/ui/widget/MarqueeText.qml, except
// `Font.Regular` -> `Font.Normal`: Qt 6 has no Font.Regular, so the default
// weight evaluated to `undefined` (logged "Unable to assign [undefined] to
// int" on every repaint) -- in the Plasma original too. The two scroll
// durations are also clamped with Math.max(0, ...): while the layout settles,
// `needsScrolling` can be true for a frame where implicitWidth < width, and
// Qt logs "Cannot set a duration of < 0" for each such frame (eight lines per
// widget instantiation here). Same latent bug upstream; the clamp changes no
// visible behaviour.

Item {
    id: marquee

    property string text: ""
    property real fontSize: 14
    property bool bold: false
    property int fontWeight: bold ? Font.DemiBold : Font.Normal
    property color textColor: "#ffffff"
    property string fontFamily: ""
    property real textOpacity: 1.0
    property int scrollSpeed: 45
    property int initialPause: 5000
    property int endPause: 3000
    property int maxLoops: 2
    property bool scrollEnabled: true
    property int horizontalAlignment: Text.AlignLeft

    clip: true

    Text {
        id: label
        text: marquee.text
        textFormat: Text.PlainText
        font.pixelSize: marquee.fontSize
        font.weight: marquee.fontWeight
        font.family: marquee.fontFamily
        color: marquee.textColor
        opacity: marquee.textOpacity
        elide: needsScrolling ? Text.ElideNone : Text.ElideRight
        width: needsScrolling ? implicitWidth : parent.width
        // Alignment only applies when the text fits; while scrolling, x is animated.
        horizontalAlignment: needsScrolling ? Text.AlignLeft : marquee.horizontalAlignment

        property bool needsScrolling: marquee.scrollEnabled && implicitWidth > marquee.width

        x: 0

        SequentialAnimation on x {
            id: scrollAnim
            running: label.needsScrolling
            loops: marquee.maxLoops

            PauseAnimation { duration: marquee.initialPause }

            NumberAnimation {
                from: 0
                to: -(label.implicitWidth - marquee.width)
                duration: label.needsScrolling
                    ? Math.max(0, (label.implicitWidth - marquee.width) * marquee.scrollSpeed)
                    : 0
                easing.type: Easing.Linear
            }

            PauseAnimation { duration: marquee.endPause }

            NumberAnimation {
                from: -(label.implicitWidth - marquee.width)
                to: 0
                duration: label.needsScrolling
                    ? Math.max(0, (label.implicitWidth - marquee.width) * marquee.scrollSpeed)
                    : 0
                easing.type: Easing.Linear
            }

            PauseAnimation { duration: marquee.endPause }
        }

        Connections {
            target: marquee
            function onTextChanged() {
                scrollAnim.stop()
                label.x = 0
                if (label.needsScrolling) scrollAnim.restart()
            }
            function onVisibleChanged() {
                if (marquee.visible) {
                    scrollAnim.stop()
                    label.x = 0
                    if (label.needsScrolling) scrollAnim.restart()
                }
            }
            function onWidthChanged() {
                scrollAnim.stop()
                label.x = 0
                if (label.needsScrolling) scrollAnim.restart()
            }
        }
    }
}
