import QtQuick
import QtQuick.Effects
import "../../../components"

Item {
    id: btn

    property string iconSource: ""
    property color iconColor: "#ffffff"
    property real iconSize: 24

    // Qt's software scene graph, haseen's default, runs no MultiEffect, and
    // the colourised layer below composites to nothing there (measured): the
    // controls vanished. There the glyph is painted in its colour by a
    // SoftwarePicture instead. Unknown, the window not drawn yet, is not
    // software.
    readonly property bool shadersRun: btn.GraphicsInfo.api !== GraphicsInfo.Software

    signal clicked()

    implicitWidth: iconSize * 1.6
    implicitHeight: iconSize * 1.6

    Item {
        id: iconItem
        anchors.centerIn: parent
        width: btn.iconSize
        height: btn.iconSize
        scale: 1.0

        layer.enabled: btn.shadersRun
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: btn.iconColor
        }

        Image {
            anchors.fill: parent
            visible: btn.shadersRun
            source: btn.shadersRun ? btn.iconSource : ""
            sourceSize: Qt.size(btn.iconSize, btn.iconSize)
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        Loader {
            anchors.fill: parent
            active: !btn.shadersRun && btn.iconSource !== ""
            sourceComponent: SoftwarePicture {
                source: btn.iconSource
                sourceSize: Qt.size(btn.iconSize, btn.iconSize)
                crop: false
                tint: btn.iconColor
            }
        }

        SequentialAnimation {
            id: bounceAnim
            NumberAnimation {
                target: iconItem; property: "scale"
                to: 0.7; duration: 100
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: iconItem; property: "scale"
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
