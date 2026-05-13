import QtQuick
import QtQuick.Layouts

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

    readonly property real _m: Math.round(height * 0.08)
    readonly property real _s: height

    Item {
        id: content
        anchors.fill: parent
        anchors.margins: layout._m

        AlbumArt {
            id: albumArtItem
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            width: height
            artUrl: layout.albumArt
            radius: Math.round(height * 0.08)
            fallbackIconColor: layout.colors.foreground
        }

        Item {
            id: rightSection
            anchors.top: parent.top
            anchors.left: albumArtItem.right
            anchors.leftMargin: layout._m
            anchors.right: parent.right
            anchors.bottom: parent.bottom

            Column {
                id: infoCol
                anchors.top: parent.top
                anchors.topMargin: Math.round(rightSection.height * 0.08)
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 2

                MarqueeText {
                    width: parent.width
                    height: Math.round(layout._s * 0.08) + 4
                    text: layout.track || "Not Playing"
                    fontSize: Math.max(10, Math.round(layout._s * 0.075))
                    fontWeight: Font.DemiBold
                    fontFamily: layout.fontFamily
                    textColor: layout.colors.foreground
                }

                Text {
                    width: parent.width
                    text: layout.artist || "—"
                    font.pixelSize: Math.max(8, Math.round(layout._s * 0.055))
                    font.family: layout.fontFamily
                    color: layout.colors.musicSecondary
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            Row {
                id: controls
                anchors.verticalCenter: parent.verticalCenter
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Math.round(layout._s * 0.12)

                readonly property real _playSize: Math.max(22, Math.round(layout._s * 0.14))
                readonly property real _skipSize: Math.max(16, Math.round(layout._s * 0.09))
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

            MusicSlider {
                id: slider
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Math.round(rightSection.height * 0.05)
                position: layout.position
                length: layout.length
                fillColor: layout.colors.foreground
                trackColor: layout.colors.foreground
                timeLabelColor: layout.colors.foreground
                fontFamily: layout.fontFamily
                fontSize: Math.max(8, Math.round(layout._s * 0.04))
                formatTime: layout.formatTime
                onSeek: function(pos) { layout.seek(pos) }
            }
        }
    }
}
