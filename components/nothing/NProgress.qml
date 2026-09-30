import QtQuick

// A segmented bar, not a smooth one: the segments are the Nothing tell, and
// they also make a value readable at a glance without a number beside it.
Item {
    id: bar
    required property var theme

    property real value: 0        // 0..1
    property int segments: 24
    property bool accent: false

    implicitHeight: bar.theme.px(6)

    Row {
        anchors.fill: parent
        spacing: bar.theme.px(2)

        Repeater {
            model: bar.segments

            Rectangle {
                required property int index
                readonly property real threshold: (index + 1) / bar.segments

                width: (bar.width - (bar.segments - 1) * bar.theme.px(2)) / bar.segments
                height: parent.height
                radius: bar.theme.rDot
                color: threshold <= bar.value + 0.0001
                    ? (bar.accent ? bar.theme.red : bar.theme.on)
                    : bar.theme.onFaint

                Behavior on color { ColorAnimation { duration: bar.theme.fast } }
            }
        }
    }
}
