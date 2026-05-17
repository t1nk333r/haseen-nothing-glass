import QtQuick

Item {
    id: lv

    required property QtObject colors
    property var syncedLyrics: []
    property string plainLyrics: ""
    property int lyricsState: 0
    property real currentPositionMs: 0
    property string fontFamily: ""
    property string lyricsFontFamily: ""
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
    property bool _hasInitialScrolled: false

    on_CurrentIndexChanged: {
        if (_currentIndex === _previousIndex) return
        _previousIndex = _currentIndex

        if (_currentIndex < 0) return

        if (!_hasInitialScrolled) {
            _hasInitialScrolled = true
            lyricsList.positionViewAtIndex(_currentIndex, ListView.Center)
            return
        }

        lyricsList.currentIndex = _currentIndex
    }

    onSyncedLyricsChanged: {
        _previousIndex = -2
        _hasInitialScrolled = false
    }

    // ── Synced lyrics ─────────────────────────────────────────────────────
    ListView {
        id: lyricsList
        anchors.fill: parent
        visible: lv.lyricsState === 2 && lv.syncedLyrics.length > 0
        clip: true
        spacing: Math.round(lv.baseFontSize * 0.15)
        topMargin: Math.round(height * 0.08)
        bottomMargin: Math.round(height * 0.6)
        model: lv.syncedLyrics.length
        cacheBuffer: 400
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 600
        highlightMoveVelocity: -1
        preferredHighlightBegin: Math.round(height * 0.08)
        preferredHighlightEnd: Math.round(height * 0.35)
        highlightRangeMode: ListView.ApplyRange
        highlightFollowsCurrentItem: true
        highlight: Item {}

        delegate: Item {
            id: del
            width: lyricsList.width
            height: bg.height

            readonly property bool _isActive: index === lv._currentIndex
            readonly property bool _isInstrumental:
                (lv.syncedLyrics[index] ? lv.syncedLyrics[index].text : "") === ""

            Rectangle {
                id: bg
                width: parent.width
                height: lineText.implicitHeight + _vPad * 2
                radius: Math.round(height * 0.22)
                color: hoverArea.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                Behavior on color { ColorAnimation { duration: 150 } }

                scale: hoverArea.pressed ? 0.97 : 1.0
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                readonly property real _vPad: Math.round(lv.baseFontSize * 0.45)
                readonly property real _hPad: Math.round(lv.baseFontSize * 0.6)

                Text {
                    id: lineText
                    x: bg._hPad
                    y: bg._vPad
                    width: bg.width - bg._hPad * 2
                    text: del._isInstrumental ? "♪  ♪  ♪" : lv.syncedLyrics[index].text
                    color: "#ffffff"
                    font.pixelSize: lv.baseFontSize
                    font.family: lv.lyricsFontFamily !== "" ? lv.lyricsFontFamily : lv.fontFamily
                    font.italic: del._isInstrumental
                    wrapMode: Text.WordWrap
                }
            }

            opacity: del._isActive ? 1.0 : 0.35
            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

            MouseArea {
                id: hoverArea
                anchors.fill: parent
                hoverEnabled: true
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
        anchors.fill: parent
        visible: lv.lyricsState === 2 && lv.syncedLyrics.length === 0 && lv.plainLyrics !== ""
        clip: true
        contentHeight: plainText.implicitHeight + 32
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds

        Text {
            id: plainText
            x: 16; y: 16
            width: parent.width - 32
            text: lv.plainLyrics
            color: "#ffffff"
            opacity: 0.85
            font.pixelSize: Math.round(lv.baseFontSize * 0.75)
            font.family: lv.lyricsFontFamily !== "" ? lv.lyricsFontFamily : lv.fontFamily
            wrapMode: Text.WordWrap
            lineHeight: 1.6
        }
    }

    // ── Loading ───────────────────────────────────────────────────────────
    Text {
        anchors.centerIn: parent
        visible: lv.lyricsState === 1
        text: "Loading lyrics…"
        color: "#ffffff"
        font.pixelSize: Math.max(12, Math.round(lv.baseFontSize * 0.8))
        font.weight: Font.Medium
        font.family: lv.fontFamily

        SequentialAnimation on opacity {
            running: lv.lyricsState === 1
            loops: Animation.Infinite
            NumberAnimation { from: 0.45; to: 0.15; duration: 800; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 0.15; to: 0.45; duration: 800; easing.type: Easing.InOutQuad }
        }
    }

    // ── Not found / error ─────────────────────────────────────────────────
    Text {
        anchors.centerIn: parent
        visible: lv.lyricsState >= 3 || (lv.lyricsState === 2 && lv.syncedLyrics.length === 0 && lv.plainLyrics === "")
        text: "No lyrics available"
        color: "#ffffff"
        opacity: 0.45
        font.pixelSize: Math.max(12, Math.round(lv.baseFontSize * 0.8))
        font.weight: Font.Medium
        font.family: lv.fontFamily
    }
}
