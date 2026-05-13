import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: btn

    property string iconSource: ""
    property color iconColor: "#ffffff"
    property real iconSize: 24

    signal clicked()

    implicitWidth: iconSize * 1.6
    implicitHeight: iconSize * 1.6

    Kirigami.Icon {
        id: icon
        anchors.centerIn: parent
        width: btn.iconSize
        height: btn.iconSize
        source: btn.iconSource
        color: btn.iconColor

        scale: 1.0

        SequentialAnimation {
            id: bounceAnim
            NumberAnimation {
                target: icon; property: "scale"
                to: 0.7; duration: 100
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: icon; property: "scale"
                to: 1.0; duration: 300
                easing.type: Easing.OutBack
                easing.overshoot: 2.5
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            bounceAnim.restart()
            btn.clicked()
        }
    }
}
