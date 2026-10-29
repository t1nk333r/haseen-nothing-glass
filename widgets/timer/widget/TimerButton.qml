import QtQuick
import QtQuick.Effects
import "../../../components"

Item {
    id: btn

    property real diameter: 64
    property url iconSource: ""
    property color iconColor: "#ffffff"
    property color backgroundColor: Qt.rgba(1, 1, 1, 0.18)

    // Qt's software scene graph, haseen's default, runs no MultiEffect, and
    // the colourised glyph below composites to nothing there (measured): the
    // button was an empty disc. There the glyph is painted in its colour by
    // a SoftwarePicture instead - colourised, then brightened to full, the
    // effect's output is `iconColor` wherever the glyph is. Unknown, the
    // window not drawn yet, is not software.
    readonly property bool shadersRun: btn.GraphicsInfo.api !== GraphicsInfo.Software

    signal clicked()

    width: diameter
    height: diameter

    Rectangle {
        anchors.fill: parent
        radius: btn.diameter / 2
        color: btn.backgroundColor
        opacity: mouseArea.pressed ? 0.5 : 1.0
        Behavior on opacity { NumberAnimation { duration: 80 } }
    }

    Image {
        id: iconImage
        anchors.centerIn: parent
        width: btn.diameter * 0.42
        height: btn.diameter * 0.42
        visible: btn.shadersRun
        source: btn.shadersRun ? btn.iconSource : ""
        sourceSize.width: 96
        sourceSize.height: 96
        fillMode: Image.PreserveAspectFit
        smooth: true

        layer.enabled: btn.shadersRun
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: btn.iconColor
            brightness: 1.0
        }
    }

    Loader {
        anchors.fill: iconImage
        active: !btn.shadersRun && String(btn.iconSource) !== ""
        sourceComponent: SoftwarePicture {
            source: btn.iconSource
            sourceSize: Qt.size(96, 96)
            crop: false
            tint: btn.iconColor
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        onClicked: btn.clicked()
    }
}
