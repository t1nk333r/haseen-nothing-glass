import QtQuick

Item {
    id: iconItem

    property string iconName: "sunny"
    property string iconSet: "default"
    property real iconSize: 48

    implicitWidth: iconSize
    implicitHeight: iconSize
    width: iconSize
    height: iconSize

    Image {
        anchors.fill: parent
        source: Qt.resolvedUrl("../icons/weather/" + iconItem.iconSet + "/" + iconItem.iconName + ".png")
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
    }
}
