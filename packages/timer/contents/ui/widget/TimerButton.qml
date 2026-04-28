import QtQuick

Item {
    id: btn

    property real diameter: 64
    property string text: ""
    property color backgroundColor: "#333333"
    property color textColor: "#ffffff"
    property string fontFamily: ""
    property real fontSize: diameter * 0.24

    signal clicked()

    width: diameter
    height: diameter

    Rectangle {
        anchors.fill: parent
        radius: btn.diameter / 2
        color: btn.backgroundColor
        opacity: mouseArea.pressed ? 0.6 : 1.0
        Behavior on opacity { NumberAnimation { duration: 80 } }
    }

    Text {
        anchors.centerIn: parent
        text: btn.text
        color: btn.textColor
        font.family: btn.fontFamily
        font.pixelSize: btn.fontSize
        font.weight: Font.Medium
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        renderType: Text.NativeRendering
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        onClicked: btn.clicked()
    }
}
