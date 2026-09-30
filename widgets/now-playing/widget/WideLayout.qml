import QtQuick

// Lyrics removed on the operator's request: no SyncedLyricsView, no Lyrics
// toggle, no lyrics-* properties. What remains is the layout that used to
// live under the lyrics overlay — album art, track/artist, transport,
// slider.

Item {
    id: layout

    required property QtObject colors
    property string fontFamily: ""
    property string fontFamilyThin: ""
    property string track: ""
    property string artist: ""
    property string albumArt: ""
    property bool hasRealArt: false
    property bool isPlaying: false
    property bool canGoPrevious: false
    property bool canGoNext: false
    property bool canPlay: false
    property bool canPause: false
    property real position: 0
    property real length: 0
    property color accentColor: "#ffffff"
    property int flipDirection: 1
    property var formatTime: function(us) { return "" }

    signal togglePlaying()
    signal nextTrack()
    signal previousTrack()
    signal seek(real positionUs)

    readonly property real _m: Math.round(height * 0.08)
    readonly property real _s: height

    Item {
        id: normalContent
        anchors.fill: parent


        Item {
            id: content
            anchors.fill: parent
            anchors.margins: layout._m

            MusicSlider {
                id: slider
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                position: layout.position
                length: layout.length
                fillColor: layout.accentColor
                trackColor: layout.colors.foreground
                timeLabelColor: layout.colors.foreground
                fontFamily: layout.fontFamily
                fontSize: Math.max(9, Math.round(layout._s * 0.046))
                formatTime: layout.formatTime
                onSeek: function(pos) { layout.seek(pos) }
            }

            Item {
                id: topRow
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: slider.top
                anchors.bottomMargin: Math.round(layout._s * 0.03)

                FlipAlbumArt {
                    id: albumArtItem
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    width: height
                    artUrl: layout.albumArt
                    radius: Math.round(height * 0.08)
                    fallbackIconColor: layout.colors.foreground
                    direction: layout.flipDirection
                }

                Item {
                    id: rightSection
                    anchors.top: parent.top
                    anchors.left: albumArtItem.right
                    anchors.leftMargin: layout._m
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom

                    Column {
                        id: centerGroup
                        anchors.centerIn: parent
                        width: parent.width
                        spacing: Math.round(layout._s * 0.03)

                        Column {
                            id: infoCol
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width
                            spacing: 2

                            MarqueeText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width
                                height: Math.round(layout._s * 0.09) + 4
                                text: layout.track || "Not Playing"
                                fontSize: Math.max(11, Math.round(layout._s * 0.081))
                                fontWeight: Font.DemiBold
                                fontFamily: layout.fontFamily
                                textColor: layout.colors.foreground
                                horizontalAlignment: Text.AlignHCenter
                            }

                            MarqueeText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width
                                height: Math.max(11, Math.round(layout._s * 0.059)) + 4
                                text: layout.artist || "—"
                                fontSize: Math.max(9, Math.round(layout._s * 0.059))
                                fontWeight: Font.Medium
                                fontFamily: layout.fontFamily
                                textColor: layout.colors.foreground
                                textOpacity: 0.55
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        Row {
                            id: controls
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: Math.round(layout._s * 0.06)

                            readonly property real _iconSize: Math.max(20, Math.round(layout._s * 0.136))
                            readonly property real _rowH: _iconSize * 1.6

                            ControlButton {
                                iconSource: Qt.resolvedUrl("../icons/previous.svg")
                                iconColor: layout.colors.foreground
                                iconSize: controls._iconSize
                                height: controls._rowH
                                opacity: layout.canGoPrevious ? 1.0 : 0.3
                                onClicked: layout.previousTrack()
                            }

                            ControlButton {
                                iconSource: layout.isPlaying ? Qt.resolvedUrl("../icons/pause.svg") : Qt.resolvedUrl("../icons/play.svg")
                                iconColor: layout.colors.foreground
                                iconSize: controls._iconSize
                                height: controls._rowH
                                opacity: (layout.canPlay || layout.canPause) ? 1.0 : 0.3
                                onClicked: layout.togglePlaying()
                            }

                            ControlButton {
                                iconSource: Qt.resolvedUrl("../icons/next.svg")
                                iconColor: layout.colors.foreground
                                iconSize: controls._iconSize
                                height: controls._rowH
                                opacity: layout.canGoNext ? 1.0 : 0.3
                                onClicked: layout.nextTrack()
                            }
                        }
                    }
                }
            }
        }
    }
}
