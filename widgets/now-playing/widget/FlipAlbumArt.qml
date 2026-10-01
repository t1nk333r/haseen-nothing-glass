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
    property bool _hasPending: false
    property int _pendingDir: 1

    property string _faceACanonical: ""
    property string _faceBCanonical: ""

    // No cache-busting stamp: every cover arrives from CoverArt under a URL of
    // its own (a fresh `?g=` per copy), so the same string always means the
    // same picture. The stamp used to make "" into the relative URL "?_t=N"
    // and a `data:` URL into a corrupt one.
    Component.onCompleted: {
        if (artUrl !== "") {
            _faceACanonical = artUrl
            faceA.artUrl = artUrl
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

        // An empty URL is a state like any other, but the "already showing
        // that" shortcut must not swallow it while a flip is in flight: mid-
        // flip the face that is still front is the OUTGOING one, so its
        // canonical reads "" whenever the previous track had no art, while the
        // face about to come on screen carries the new art. Dropping the
        // change there is the stuck cover this state machine exists to
        // prevent. Non-empty URLs keep the shortcut exactly as it was.
        if (url === frontCanon && !(url === "" && _state !== 0))
            return

        if (_state !== 0) {
            _pending = url
            _pendingDir = dir
            _hasPending = true
            return
        }

        if (url === backCanon && backCanon !== "") {
            _startFlip(dir)
            return
        }

        // An empty URL is "no art", a state like any other, so it is assigned
        // straight to the incoming face. It must never go through _stamp():
        // "_t=N" appended to "" is a relative URL that would resolve against
        // this document. And there is no image to wait for, so the preload
        // step is skipped and the flip starts at once.
        //
        // `Qt.callLater` because this branch also runs from _onFlipComplete,
        // i.e. from inside the running flip's own ScriptAction; restarting the
        // animation from there sets the state but never advances the angle, so
        // the face would never come round and the widget would sit in the
        // flipping state. Deferring one event-loop turn lets the animation
        // stop first. The preloaded path below never hits this: it reaches
        // _startFlip from the preloader's asynchronous onStatusChanged.
        if (url === "") {
            if (_showingA) {
                _faceBCanonical = ""
                faceB.artUrl = ""
            } else {
                _faceACanonical = ""
                faceA.artUrl = ""
            }
            Qt.callLater(_startFlip, dir)
            return
        }

        if (_showingA) {
            _faceBCanonical = url
            faceB.artUrl = url
        } else {
            _faceACanonical = url
            faceA.artUrl = url
        }

        flipAnim.flipDir = dir
        _state = 1
        // Cleared first: an earlier load that failed leaves its URL here, and
        // assigning the same string again would change nothing and never
        // report a status - the wait below would then only end on the guard.
        preloader.source = ""
        preloader.source = url
        loadGuard.restart()

        if (preloader.status === Image.Ready)
            _startFlip(dir)
    }

    function _startFlip(dir) {
        loadGuard.stop()
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

        if (_hasPending) {
            var url = _pending
            var dir = _pendingDir
            _pending = ""
            _pendingDir = 1
            _hasPending = false
            _processChange(url, dir)
        }
    }

    // A load that never reports Ready or Error must not hold the face for
    // good: every later cover queues behind state 1. Settled as an error, so
    // the next pending URL - or "" - goes ahead. CoverArt hands over local
    // copies, which decode in milliseconds; the bound is for whatever does not.
    Timer {
        id: loadGuard
        interval: 4000
        repeat: false
        onTriggered: {
            if (flip._state !== 1) return
            preloader.source = ""
            flip._preloadFailed()
        }
    }

    function _preloadFailed() {
        loadGuard.stop()
        _state = 0
        if (_hasPending) {
            var url = _pending
            var dir = _pendingDir
            _pending = ""
            _pendingDir = 1
            _hasPending = false
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
                if (flip._hasPending) {
                    flip._state = 0
                    var url = flip._pending
                    var dir = flip._pendingDir
                    flip._pending = ""
                    flip._pendingDir = 1
                    flip._hasPending = false
                    flip._processChange(url, dir)
                } else {
                    flip._startFlip(flipAnim.flipDir)
                }
            } else if (status === Image.Error) {
                flip._preloadFailed()
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
