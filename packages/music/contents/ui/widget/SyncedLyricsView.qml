import QtQuick
import QtQuick.Effects

Item {
    id: lv

    required property QtObject colors
    property var syncedLyrics: []
    property string plainLyrics: ""
    property int lyricsState: 0
    property real currentPositionMs: 0
    property string fontFamily: ""
    property real baseFontSize: 20
    property bool blurEnabled: true

    signal seekTo(real positionUs)

    readonly property int _currentIndex: {
        var adj = currentPositionMs + 200
        var idx = -1
        for (var i = 0; i < syncedLyrics.length; i++) {
            if (syncedLyrics[i].timestamp <= adj) idx = i
            else break
        }
        return idx
    }

    property int _previousIndex: -2
    property bool _isUserScrolling: false
    property bool _isProgrammaticScroll: false
    property bool _isFocusedOnActive: true
    property bool _hasInitialScrolled: false

    readonly property int _visibleBelowActive: {
        var estLineH = baseFontSize * 2.1 + baseFontSize * 1.1
        var count = Math.max(3, Math.floor(height / estLineH))
        return count
    }

    on_CurrentIndexChanged: {
        if (_currentIndex === _previousIndex) return

        if (!_hasInitialScrolled && _currentIndex >= 0) {
            _hasInitialScrolled = true
            _isProgrammaticScroll = true
            lyricsList.positionViewAtIndex(_currentIndex, ListView.Beginning)
            _isProgrammaticScroll = false
            _previousIndex = _currentIndex
            return
        }

        if (_isUserScrolling) {
            _previousIndex = _currentIndex
            return
        }

        var oldY = lyricsList.contentY
        _isProgrammaticScroll = true
        if (_currentIndex >= 0)
            lyricsList.positionViewAtIndex(_currentIndex, ListView.Beginning)
        _isProgrammaticScroll = false
        _isFocusedOnActive = true
        var scrollDelta = oldY - lyricsList.contentY

        for (var i = 0; i < lyricsList.contentItem.children.length; i++) {
            var child = lyricsList.contentItem.children[i]
            if (child && child.hasOwnProperty("_waveY"))
                child._waveY = scrollDelta
        }

        _previousIndex = _currentIndex
    }

    onSyncedLyricsChanged: {
        _previousIndex = -2
        _hasInitialScrolled = false
        _isFocusedOnActive = true
        _isUserScrolling = false
    }

    Timer {
        id: snapBackTimer
        interval: 1500
        onTriggered: {
            lv._isUserScrolling = false
            if (lv._currentIndex >= 0) {
                lv._isProgrammaticScroll = true
                lyricsList.positionViewAtIndex(lv._currentIndex, ListView.Beginning)
                lv._isProgrammaticScroll = false
                lv._isFocusedOnActive = true
            }
        }
    }

    // ── Synced lyrics view ────────────────────────────────────────────────
    ListView {
        id: lyricsList
        anchors.fill: parent
        visible: lv.lyricsState === 2 && lv.syncedLyrics.length > 0
        clip: true
        spacing: 0
        topMargin: Math.round(height * 0.05)
        bottomMargin: Math.round(height * 0.7)
        model: lv.syncedLyrics.length
        cacheBuffer: 600
        boundsBehavior: Flickable.StopAtBounds

        onMovementStarted: {
            if (!lv._isProgrammaticScroll) {
                lv._isUserScrolling = true
                lv._isFocusedOnActive = false
                for (var i = 0; i < contentItem.children.length; i++) {
                    var child = contentItem.children[i]
                    if (child && child.hasOwnProperty("_waveY"))
                        child._waveY = 0
                }
            }
        }
        onMovementEnded: {
            if (lv._isUserScrolling)
                snapBackTimer.restart()
        }

        delegate: Item {
            id: del
            width: lyricsList.width
            height: lineText.implicitHeight + _vPad * 2
            clip: false

            property real _waveY: 0
            readonly property real _vPad: Math.round(lv.baseFontSize * 0.55)
            readonly property real _hPad: Math.round(lv.baseFontSize * 0.9)

            readonly property bool _isActive: lv._currentIndex >= 0 && index === lv._currentIndex
            readonly property bool _isPast: lv._currentIndex >= 0 && index < lv._currentIndex
            readonly property int _distFromActive: lv._currentIndex >= 0 ? index - lv._currentIndex : index + 1

            readonly property real _fraction: lv._visibleBelowActive > 1
                ? Math.min(1, Math.max(0, _distFromActive / lv._visibleBelowActive))
                : 1

            readonly property real _targetOpacity: {
                if (lv._isUserScrolling || !lv._isFocusedOnActive)
                    return _isActive ? 1.0 : 0.25
                if (_isActive) return 1.0
                if (_isPast) return 0.0
                return (0.35 * (1 - _fraction) + 0.05)
            }

            readonly property real _targetBlur: {
                if (!lv.blurEnabled) return 0
                if (lv._isUserScrolling || !lv._isFocusedOnActive || _distFromActive <= 0) return 0
                if (_distFromActive === 1) return 0.045
                var maxBlur = 0.3
                var blurFrac = Math.min(1, Math.max(0, (_distFromActive - 1) / Math.max(1, lv._visibleBelowActive - 1)))
                return maxBlur * blurFrac
            }

            transform: Translate { id: waveTranslate; y: del._waveY }

            on_WaveYChanged: {
                waveAnim.stop()
                if (Math.abs(_waveY) < 1) return
                var dist = _distFromActive
                if (dist < 0) {
                    waveAnim._delay = 0
                    waveAnim._target = -25
                } else if (dist === 0) {
                    waveAnim._delay = 0
                    waveAnim._target = 0
                } else {
                    waveAnim._delay = 120 + (dist - 1) * 150
                    waveAnim._target = 0
                }
                waveAnim.start()
            }

            SequentialAnimation {
                id: waveAnim
                property int _delay: 0
                property real _target: 0
                PauseAnimation { duration: waveAnim._delay }
                NumberAnimation {
                    target: del; property: "_waveY"
                    to: waveAnim._target
                    duration: 600; easing.type: Easing.OutQuart
                }
            }

            opacity: _targetOpacity
            Behavior on opacity { NumberAnimation { duration: 1400; easing.type: Easing.OutCubic } }

            Item {
                id: textContainer
                anchors.fill: parent

                layer.enabled: del._targetBlur > 0.01
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: del._targetBlur
                    blurMax: 32
                }

                Text {
                    id: lineText
                    x: del._hPad
                    y: del._vPad
                    width: del.width - del._hPad * 2
                    text: {
                        var t = lv.syncedLyrics[index] ? lv.syncedLyrics[index].text : ""
                        return t === "" ? "♪  ♪  ♪" : t
                    }
                    color: lv.colors.foreground
                    font.pixelSize: lv.baseFontSize
                    font.weight: Font.Bold
                    font.family: lv.fontFamily
                    font.italic: (lv.syncedLyrics[index] ? lv.syncedLyrics[index].text : "") === ""
                    wrapMode: Text.WordWrap
                    opacity: (lv.syncedLyrics[index] ? lv.syncedLyrics[index].text : "") === "" ? 0.5 : 1.0
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    var ts = lv.syncedLyrics[index] ? lv.syncedLyrics[index].timestamp : 0
                    lv.seekTo(ts * 1000)
                }
            }
        }
    }

    // ── Plain lyrics fallback ─────────────────────────────────────────────
    Flickable {
        id: plainView
        anchors.fill: parent
        visible: lv.lyricsState === 2 && lv.syncedLyrics.length === 0 && lv.plainLyrics !== ""
        clip: true
        contentHeight: plainText.implicitHeight + 32
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds

        Text {
            id: plainText
            x: 16; y: 16
            width: plainView.width - 32
            text: lv.plainLyrics
            color: lv.colors.foreground
            opacity: 0.85
            font.pixelSize: Math.round(lv.baseFontSize * 0.75)
            font.weight: Font.Bold
            font.family: lv.fontFamily
            wrapMode: Text.WordWrap
            lineHeight: 1.6
        }
    }

    // ── Loading state ─────────────────────────────────────────────────────
    Text {
        anchors.centerIn: parent
        visible: lv.lyricsState === 1
        text: "Loading lyrics…"
        color: lv.colors.foreground
        opacity: _loadingPulse.running ? 0.45 : 0.45
        font.pixelSize: Math.max(12, Math.round(lv.baseFontSize * 0.8))
        font.weight: Font.Medium
        font.family: lv.fontFamily

        SequentialAnimation on opacity {
            id: _loadingPulse
            running: lv.lyricsState === 1
            loops: Animation.Infinite
            NumberAnimation { from: 0.45; to: 0.15; duration: 800; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 0.15; to: 0.45; duration: 800; easing.type: Easing.InOutQuad }
        }
    }

    // ── Error / not found state ───────────────────────────────────────────
    Text {
        anchors.centerIn: parent
        visible: lv.lyricsState >= 3 || (lv.lyricsState === 2 && lv.syncedLyrics.length === 0 && lv.plainLyrics === "")
        text: "No lyrics available"
        color: lv.colors.foreground
        opacity: 0.45
        font.pixelSize: Math.max(12, Math.round(lv.baseFontSize * 0.8))
        font.weight: Font.Medium
        font.family: lv.fontFamily
    }
}
