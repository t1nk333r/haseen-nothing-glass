import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

Item {
    id: layout

    required property QtObject colors
    property string fontFamily: ""
    property string fontFamilyThin: ""
    property string track: ""
    property string artist: ""
    property string albumArt: ""
    property bool isPlaying: false
    property bool canGoPrevious: false
    property bool canGoNext: false
    property bool canPlay: false
    property bool canPause: false
    property real position: 0
    property real length: 0
    property var formatTime: function(us) { return "" }

    signal togglePlaying()
    signal nextTrack()
    signal previousTrack()
    signal seek(real positionUs)

    readonly property real _m: Math.round(Math.min(width, height) * 0.08)
    readonly property real _s: Math.min(width, height)

    // Album art as full background with gradient fade-out toward bottom
    Item {
        id: bgArtContainer
        anchors.fill: parent
        visible: layout.albumArt !== ""
        layer.enabled: true

        Image {
            anchors.fill: parent
            source: layout.albumArt
            fillMode: Image.PreserveAspectCrop
            smooth: true
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0;  color: "transparent" }
                GradientStop { position: 0.35; color: "transparent" }
                GradientStop { position: 0.85; color: Qt.rgba(0, 0, 0, 0.85) }
                GradientStop { position: 1.0;  color: Qt.rgba(0, 0, 0, 0.95) }
            }
        }
    }

    // Fallback icon when no album art
    Item {
        anchors.fill: parent
        visible: layout.albumArt === ""

        Rectangle {
            anchors.centerIn: parent
            width: layout._s * 0.3
            height: width
            radius: width * 0.15
            color: layout.colors.foreground
            opacity: 0.08
        }
    }

    // Content overlay
    Item {
        id: content
        anchors.fill: parent
        anchors.margins: layout._m

        Column {
            id: infoCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: slider.top
            anchors.bottomMargin: Math.round(layout._s * 0.03)
            spacing: 2

            MarqueeText {
                width: parent.width
                height: Math.round(layout._s * 0.06) + 4
                text: layout.track || "Not Playing"
                fontSize: Math.max(10, Math.round(layout._s * 0.055))
                fontWeight: Font.DemiBold
                fontFamily: layout.fontFamily
                textColor: layout.colors.foreground
            }

            Text {
                width: parent.width
                text: layout.artist || "—"
                font.pixelSize: Math.max(8, Math.round(layout._s * 0.04))
                font.family: layout.fontFamily
                color: layout.colors.musicSecondary
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        MusicSlider {
            id: slider
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: controls.top
            anchors.bottomMargin: Math.round(layout._s * 0.01)
            position: layout.position
            length: layout.length
            fillColor: layout.colors.foreground
            trackColor: layout.colors.foreground
            timeLabelColor: layout.colors.foreground
            fontFamily: layout.fontFamily
            fontSize: Math.max(8, Math.round(layout._s * 0.033))
            formatTime: layout.formatTime
            onSeek: function(pos) { layout.seek(pos) }
        }

        Row {
            id: controls
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(layout._s * 0.08)

            readonly property real _playSize: Math.max(18, Math.round(layout._s * 0.10))
            readonly property real _skipSize: Math.max(14, Math.round(layout._s * 0.07))
            readonly property real _rowH: _playSize * 1.6

            ControlButton {
                iconSource: "media-skip-backward"
                iconColor: layout.colors.foreground
                iconSize: controls._skipSize
                height: controls._rowH
                opacity: layout.canGoPrevious ? 1.0 : 0.3
                onClicked: layout.previousTrack()
            }

            ControlButton {
                iconSource: layout.isPlaying ? "media-playback-pause" : "media-playback-start"
                iconColor: layout.colors.foreground
                iconSize: controls._playSize
                height: controls._rowH
                opacity: (layout.canPlay || layout.canPause) ? 1.0 : 0.3
                onClicked: layout.togglePlaying()
            }

            ControlButton {
                iconSource: "media-skip-forward"
                iconColor: layout.colors.foreground
                iconSize: controls._skipSize
                height: controls._rowH
                opacity: layout.canGoNext ? 1.0 : 0.3
                onClicked: layout.nextTrack()
            }
        }
    }
}
