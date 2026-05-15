import QtQuick

Item {
    id: flip

    property string artUrl: ""
    property real radius: 12
    property color fallbackIconColor: "#ffffff"
    property int direction: 1

    property bool _showingA: true
    property real _angle: 0
    property bool _flipping: false

    Component.onCompleted: {
        faceA.artUrl = artUrl
    }

    onArtUrlChanged: {
        if (_flipping) return

        var currentUrl = _showingA ? faceA.artUrl : faceB.artUrl
        if (artUrl === currentUrl || artUrl === "") return

        if (_showingA) {
            faceB.artUrl = artUrl
        } else {
            faceA.artUrl = artUrl
        }

        _flipping = true
        preloader.source = artUrl

        if (preloader.status === Image.Ready) {
            flipAnim.start()
        }
    }

    Image {
        id: preloader
        visible: false
        source: ""
        asynchronous: true
        sourceSize.width: flip.width > 0 ? flip.width : 200
        sourceSize.height: flip.height > 0 ? flip.height : 200
        onStatusChanged: {
            if (status === Image.Ready && flip._flipping && !flipAnim.running) {
                flipAnim.start()
            }
        }
    }

    SequentialAnimation {
        id: flipAnim

        NumberAnimation {
            target: flip; property: "_angle"
            from: 0; to: 180 * flip.direction
            duration: 400; easing.type: Easing.InOutQuad
        }

        ScriptAction {
            script: {
                flip._showingA = !flip._showingA
                flip._angle = 0
                flip._flipping = false
                preloader.source = ""
            }
        }
    }

    transform: Rotation {
        origin.x: flip.width / 2
        origin.y: flip.height / 2
        axis { x: 0; y: 1; z: 0 }
        angle: flip._angle
    }

    AlbumArt {
        id: faceA
        anchors.fill: parent
        radius: flip.radius
        fallbackIconColor: flip.fallbackIconColor
        visible: {
            var a = Math.abs(flip._angle) % 360
            return a < 90 || a > 270
        }
    }

    AlbumArt {
        id: faceB
        anchors.fill: parent
        radius: flip.radius
        fallbackIconColor: flip.fallbackIconColor
        visible: !faceA.visible

        transform: Rotation {
            origin.x: faceB.width / 2
            origin.y: faceB.height / 2
            axis { x: 0; y: 1; z: 0 }
            angle: 180
        }
    }
}
