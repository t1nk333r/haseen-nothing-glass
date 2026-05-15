import QtQuick

Item {
    id: slider

    property real position: 0
    property real length: 0
    property color fillColor: "#ffffff"
    property color trackColor: "#ffffff"
    property real trackOpacity: 0.20
    property color timeLabelColor: "#ffffff"
    property real timeLabelOpacity: 0.50
    property string fontFamily: ""
    property real fontSize: 10
    property bool showTimeLabels: true
    property var formatTime: function(us) { return "" }

    signal seek(real positionUs)

    implicitHeight: showTimeLabels ? (barArea.height + timeRow.height + 2) : barArea.height

    property bool _active: barMouse.containsMouse || barMouse.pressed

    Item {
        id: barArea
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 14

        Rectangle {
            id: track
            anchors.centerIn: parent
            width: parent.width
            height: slider._active ? 8 : 3
            radius: height / 2
            color: slider.trackColor
            opacity: slider.trackOpacity

            Behavior on height {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
        }

        Rectangle {
            id: fill
            anchors.verticalCenter: track.verticalCenter
            anchors.left: track.left
            width: slider.length > 0 ? (track.width * Math.min(1, slider.position / slider.length)) : 0
            height: track.height
            radius: height / 2
            color: slider.fillColor

            Behavior on width {
                enabled: !barMouse.pressed
                NumberAnimation { duration: 200 }
            }
        }

        MouseArea {
            id: barMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onPressed: function(mouse) { _seekTo(mouse.x) }
            onPositionChanged: function(mouse) {
                if (pressed) _seekTo(mouse.x)
            }

            function _seekTo(mx) {
                var ratio = Math.max(0, Math.min(1, mx / width))
                slider.seek(ratio * slider.length)
            }
        }
    }

    Item {
        id: timeRow
        visible: slider.showTimeLabels
        anchors.top: barArea.bottom
        anchors.topMargin: 2
        anchors.left: parent.left
        anchors.right: parent.right
        height: currentLabel.height

        Text {
            id: currentLabel
            anchors.left: parent.left
            text: slider.formatTime(slider.position)
            color: slider.timeLabelColor
            opacity: slider.timeLabelOpacity
            font.family: slider.fontFamily
            font.pixelSize: slider.fontSize
        }

        Text {
            id: totalLabel
            anchors.right: parent.right
            text: slider.formatTime(slider.length)
            color: slider.timeLabelColor
            opacity: slider.timeLabelOpacity
            font.family: slider.fontFamily
            font.pixelSize: slider.fontSize
        }
    }
}
