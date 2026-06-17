import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami

Item {
    id: art

    property string artUrl: ""
    property real radius: 12
    property color fallbackColor: "#2c2c2e"
    property color fallbackIconColor: "#ffffff"

    Image {
        id: coverImage
        anchors.fill: parent
        source: art.artUrl
        fillMode: Image.PreserveAspectCrop
        smooth: true
        mipmap: true
        visible: false
        layer.enabled: true
        cache: false
    }

    Item {
        id: roundMask
        anchors.fill: parent
        layer.enabled: true
        visible: false

        Rectangle {
            anchors.fill: parent
            radius: art.radius
            color: "white"
        }
    }

    Rectangle {
        anchors.fill: parent
        color: art.fallbackColor
        radius: art.radius
        opacity: 0.3
    }

    MultiEffect {
        anchors.fill: parent
        source: coverImage
        maskEnabled: true
        maskSource: roundMask
        visible: art.artUrl !== ""
    }

    Kirigami.Icon {
        anchors.centerIn: parent
        width: parent.width * 0.35
        height: parent.height * 0.35
        source: "media-optical-audio"
        color: art.fallbackIconColor
        opacity: 0.4
        visible: art.artUrl === ""
    }
}
