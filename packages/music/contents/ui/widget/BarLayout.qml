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
    property color accentColor: "#ffffff"
    property real cornerRadius: 24
    property var formatTime: function(us) { return "" }

    signal togglePlaying()
    signal nextTrack()
    signal previousTrack()
    signal seek(real positionUs)

    readonly property real _h: height
    readonly property real _pad: Math.round(_h * 0.12)

    // Album art with equal margins
    AlbumArt {
        id: artItem
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: layout._pad
        width: height
        artUrl: layout.albumArt
        radius: Math.round(height * 0.12)
        fallbackIconColor: layout.colors.foreground
    }

    // Info section: text + slider
    Item {
        id: infoSection
        anchors.left: artItem.right
        anchors.leftMargin: layout._pad
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: controls.left
        anchors.rightMargin: Math.round(layout._pad * 0.5)
        anchors.topMargin: layout._pad
        anchors.bottomMargin: layout._pad

        Column {
            id: textCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 1

            MarqueeText {
                width: parent.width
                height: Math.round(layout._h * 0.26) + 2
                text: layout.track || "Not Playing"
                fontSize: Math.max(8, Math.round(layout._h * 0.19))
                fontWeight: Font.DemiBold
                fontFamily: layout.fontFamily
                textColor: layout.colors.foreground
                scrollEnabled: false
            }

            MarqueeText {
                width: parent.width
                height: Math.max(8, Math.round(layout._h * 0.15)) + 2
                text: layout.artist || "—"
                fontSize: Math.max(6, Math.round(layout._h * 0.14))
                fontWeight: Font.Medium
                fontFamily: layout.fontFamily
                textColor: layout.colors.foreground
                textOpacity: 0.55
                scrollEnabled: false
            }
        }

        // Progress bar at bottom of info section
        Rectangle {
            id: progressLine
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 3
            radius: 1.5
            color: "transparent"

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: layout.length > 0
                    ? parent.width * Math.min(1, layout.position / layout.length)
                    : 0
                radius: parent.radius
                color: layout.accentColor
                opacity: 0.8

                Behavior on width {
                    NumberAnimation { duration: 200 }
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: layout.colors.foreground
                opacity: 0.15
            }
        }
    }

    // Controls pushed to the right
    Row {
        id: controls
        anchors.right: parent.right
        anchors.rightMargin: layout._pad
        anchors.verticalCenter: parent.verticalCenter
        spacing: Math.round(layout._h * 0.08)

        readonly property real _iconSize: Math.max(14, Math.round(layout._h * 0.28))
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
