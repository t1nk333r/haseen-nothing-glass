import QtQuick

Flipable {
    id: flip

    property string artUrl: ""
    property real radius: 12
    property color fallbackIconColor: "#ffffff"
    property int direction: 1

    property bool _showingA: true
    property real _angle: 0
    property int _state: 0 // 0=idle, 1=loading, 2=flipping
    property string _pending: ""
    property int _pendingDir: 1
    property int _stampCounter: 0

    property string _faceACanonical: ""
    property string _faceBCanonical: ""

    function _stamp(url) {
        _stampCounter++
        if (url.indexOf("?") >= 0)
            return url + "&_t=" + _stampCounter
        return url + "?_t=" + _stampCounter
    }

    Component.onCompleted: {
        if (artUrl !== "") {
            _faceACanonical = artUrl
            faceA.artUrl = _stamp(artUrl)
        }
    }

    front: AlbumArt {
        id: faceA
        anchors.fill: parent
        radius: flip.radius
        fallbackIconColor: flip.fallbackIconColor
    }

    back: AlbumArt {
        id: faceB
        anchors.fill: parent
        radius: flip.radius
        fallbackIconColor: flip.fallbackIconColor
    }

    transform: Rotation {
        origin.x: flip.width / 2
        origin.y: flip.height / 2
        axis { x: 0; y: 1; z: 0 }
        angle: flip._angle
    }

    onArtUrlChanged: _processChange(artUrl, direction)

    function _processChange(url, dir) {
        var frontCanon = _showingA ? _faceACanonical : _faceBCanonical
        var backCanon  = _showingA ? _faceBCanonical : _faceACanonical

        if (url === "" || url === frontCanon)
            return

        if (_state !== 0) {
            _pending = url
            _pendingDir = dir
            return
        }

        if (url === backCanon && backCanon !== "") {
            _startFlip(dir)
            return
        }

        var stamped = _stamp(url)
        if (_showingA) {
            _faceBCanonical = url
            faceB.artUrl = stamped
        } else {
            _faceACanonical = url
            faceA.artUrl = stamped
        }

        flipAnim.flipDir = dir
        _state = 1
        preloader.source = stamped

        if (preloader.status === Image.Ready)
            _startFlip(dir)
    }

    function _startFlip(dir) {
        _state = 2
        flipAnim.flipDir = dir
        flipAnim.fromAngle = _angle
        flipAnim.toAngle = _angle + 180 * dir
        flipAnim.start()
    }

    function _onFlipComplete() {
        _showingA = !_showingA
        _state = 0
        preloader.source = ""

        if (_pending !== "") {
            var url = _pending
            var dir = _pendingDir
            _pending = ""
            _pendingDir = 1
            _processChange(url, dir)
        }
    }

    Image {
        id: preloader
        visible: false
        source: ""
        asynchronous: true
        cache: false
        sourceSize.width: flip.width > 0 ? flip.width : 200
        sourceSize.height: flip.height > 0 ? flip.height : 200
        onStatusChanged: {
            if (flip._state !== 1) return

            if (status === Image.Ready) {
                if (flip._pending !== "") {
                    flip._state = 0
                    var url = flip._pending
                    var dir = flip._pendingDir
                    flip._pending = ""
                    flip._pendingDir = 1
                    flip._processChange(url, dir)
                } else {
                    flip._startFlip(flipAnim.flipDir)
                }
            } else if (status === Image.Error) {
                flip._state = 0
                if (flip._pending !== "") {
                    var url = flip._pending
                    var dir = flip._pendingDir
                    flip._pending = ""
                    flip._pendingDir = 1
                    flip._processChange(url, dir)
                }
            }
        }
    }

    SequentialAnimation {
        id: flipAnim
        property int flipDir: 1
        property real fromAngle: 0
        property real toAngle: 180

        NumberAnimation {
            target: flip; property: "_angle"
            from: flipAnim.fromAngle; to: flipAnim.toAngle
            duration: 400; easing.type: Easing.InOutQuad
        }

        ScriptAction {
            script: flip._onFlipComplete()
        }
    }
}
