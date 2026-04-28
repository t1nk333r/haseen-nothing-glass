import QtQuick

Item {
    id: root

    property int minutes: 0
    property int seconds: 0
    property string fontFamily: ""
    property color textColor: "#ffffff"
    property real digitOpacity: 0.7
    property bool flashing: false

    readonly property real _minSide: Math.min(width, height)
    readonly property real _fontSize: _minSide * 0.48
    readonly property real _digitW: _fontSize * 0.72
    readonly property real _digitH: _fontSize * 1.7
    readonly property real _colonW: _fontSize * 0.28
    readonly property real _gap: _fontSize * 0.02
    readonly property real _totalW: _digitW * 4 + _colonW + _gap * 4

    readonly property string _m1: String(Math.floor(minutes / 10))
    readonly property string _m0: String(minutes % 10)
    readonly property string _s1: String(Math.floor(seconds / 10))
    readonly property string _s0: String(seconds % 10)

    opacity: 1.0
    SequentialAnimation on opacity {
        id: flashAnim
        running: root.flashing
        loops: Animation.Infinite
        NumberAnimation { to: 0.3; duration: 500; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 1.0; duration: 500; easing.type: Easing.InOutQuad }
        onRunningChanged: if (!running) root.opacity = 1.0
    }

    Row {
        anchors.centerIn: parent
        spacing: root._gap

        Item {
            width: root._digitW; height: root._digitH; clip: true
            RollingDigit {
                anchors.fill: parent
                value: root._m1
                fontFamily: root.fontFamily
                fontPixelSize: root._fontSize
                textColor: root.textColor
                digitOpacity: root.digitOpacity
            }
        }

        Item {
            width: root._digitW; height: root._digitH; clip: true
            RollingDigit {
                anchors.fill: parent
                value: root._m0
                fontFamily: root.fontFamily
                fontPixelSize: root._fontSize
                textColor: root.textColor
                digitOpacity: root.digitOpacity
            }
        }

        Item {
            width: root._colonW
            height: root._digitH

            readonly property real _dotSize: root._fontSize * 0.08
            readonly property real _dotSpacing: _dotSize * 1.6

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height / 2 - parent._dotSpacing / 2 - height
                width: parent._dotSize; height: parent._dotSize
                radius: parent._dotSize / 2
                color: root.textColor
                opacity: root.digitOpacity * 0.8
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height / 2 + parent._dotSpacing / 2
                width: parent._dotSize; height: parent._dotSize
                radius: parent._dotSize / 2
                color: root.textColor
                opacity: root.digitOpacity * 0.8
            }
        }

        Item {
            width: root._digitW; height: root._digitH; clip: true
            RollingDigit {
                anchors.fill: parent
                value: root._s1
                fontFamily: root.fontFamily
                fontPixelSize: root._fontSize
                textColor: root.textColor
                digitOpacity: root.digitOpacity
            }
        }

        Item {
            width: root._digitW; height: root._digitH; clip: true
            RollingDigit {
                anchors.fill: parent
                value: root._s0
                fontFamily: root.fontFamily
                fontPixelSize: root._fontSize
                textColor: root.textColor
                digitOpacity: root.digitOpacity
            }
        }
    }
}
