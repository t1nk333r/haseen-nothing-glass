import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

Item {
    id: layout

    required property QtObject colors
    property real cornerRadius: 24
    property real roundness: 7.5
    property string fontFamily: ""
    property string fontFamilyThin: ""
    property string track: ""
    property string artist: ""
    property string albumArt: ""
    // See main.qml's hasRealArt: the full-bleed background waits for art a
    // player actually provided, so an idle widget stays glass.
    property bool hasRealArt: false
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

    clip: true

    // The mask's outline: the same parametric superellipse the shader draws
    // for the card - the exponent `roundness` and the radius `cornerRadius`,
    // both clamped the way the SDF clamps - as a polyline the scene graph
    // draws directly.
    //
    // Not a `Canvas`, deliberately. A Canvas owns a texture of its own, filled
    // by a deferred `onPaint`, and that deferred paint is what the guest
    // measured on the photos frame: in every blank instance the canvas had
    // never painted (`paints=0` for the rest of the session) while the picture
    // under it was ready and visible. This mask is sampled by the MultiEffect
    // below in the same frame, and a mask that is not there yet reads as
    // transparent, so the whole background layer drew nothing - cover and
    // gradient alike - permanently and with nothing logged. A `requestPaint()`
    // repaint did not bring the layer back. Geometry the scene graph draws has
    // no second texture to wait for.
    readonly property var maskPoints: {
        var w = bgArtMask.width, h = bgArtMask.height
        var r = Math.max(0, Math.min(layout.cornerRadius, w / 2, h / 2))
        var n = Math.max(layout.roundness, 2.0)
        var steps = 32
        var pts = []

        // Corner boundary of the shader's SDF: q = abs(p) - b + r, and
        // (qx^n + qy^n)^(1/n) = r, so parametrically
        // qx = r*cos(t)^(2/n), qy = r*sin(t)^(2/n).
        function cornerX(t) { return r * Math.pow(Math.abs(Math.cos(t)), 2.0 / n) }
        function cornerY(t) { return r * Math.pow(Math.abs(Math.sin(t)), 2.0 / n) }

        pts.push(Qt.point(r, 0))
        pts.push(Qt.point(w - r, 0))
        for (var i = 1; i <= steps; i++) {
            var t = (1 - i / steps) * Math.PI / 2
            pts.push(Qt.point(w - r + cornerX(t), r - cornerY(t)))
        }
        pts.push(Qt.point(w, h - r))
        for (var j = 1; j <= steps; j++) {
            var t2 = (1 - j / steps) * Math.PI / 2
            pts.push(Qt.point(w - r + cornerY(t2), h - r + cornerX(t2)))
        }
        pts.push(Qt.point(r, h))
        for (var k = 1; k <= steps; k++) {
            var t3 = (1 - k / steps) * Math.PI / 2
            pts.push(Qt.point(r - cornerX(t3), h - r + cornerY(t3)))
        }
        pts.push(Qt.point(0, r))
        for (var m = 1; m <= steps; m++) {
            var t4 = (1 - m / steps) * Math.PI / 2
            pts.push(Qt.point(r - cornerY(t4), r - cornerX(t4)))
        }
        pts.push(Qt.point(r, 0))
        return pts
    }

    // Album art as full background with gradient fade-out toward bottom
    Item {
        id: bgArtContainer
        anchors.fill: parent
        visible: layout.hasRealArt

        Item {
            id: bgArtSource
            anchors.fill: parent
            // Invisible by opacity, not by `visible: false` - the same reason
            // stated for the mask below, and measured on the guest: a store
            // write that re-creates this layout left the background layer
            // sampling a gradient that had been captured before the anchors
            // resolved (13 of 72 400x400 tiles rendered a stretched, or absent,
            // darkening). `visible: false` is the one state that guarantees an
            // item is not updated, and a layer that is not updated is a layer
            // that keeps whatever it held on the frame it was first produced.
            // `opacity: 0` is applied where the item is composited, not to the
            // layer texture the effect below reads.
            opacity: 0
            layer.enabled: true

            Image {
                anchors.fill: parent
                source: layout.albumArt
                fillMode: Image.PreserveAspectCrop
                smooth: true
                mipmap: true
                // Same bound as AlbumArt.qml's cover: this is the copy the
                // selected layout actually draws full-bleed, so a 1500px
                // cover would otherwise hold a ~9 MB pixmap for a 400px slot.
                sourceSize.width: Math.max(1, Math.round(layout.width * 2))
                sourceSize.height: Math.max(1, Math.round(layout.height * 2))
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0;  color: Qt.rgba(0, 0, 0, 0.35) }
                    GradientStop { position: 0.35; color: Qt.rgba(0, 0, 0, 0.45) }
                    GradientStop { position: 0.85; color: Qt.rgba(0, 0, 0, 0.90) }
                    GradientStop { position: 1.0;  color: Qt.rgba(0, 0, 0, 0.97) }
                }
            }
        }

        // The mask itself: never drawn, only sampled. Invisible by opacity,
        // not by `visible: false`: `visible: false` is the one state that
        // guarantees an item is not updated, and this item exists only to be
        // sampled - seeing it rendered or not is not a choice to leave to
        // whichever code path happens to ask for its layer first. Opacity 0 is
        // the idiom the glass itself already uses for its own texture helpers
        // (components/LiquidGlass.qml's down/upTex), and the opacity is applied
        // where the item is composited, not to the layer it provides as a mask.
        Item {
            id: bgArtMask
            anchors.fill: parent
            opacity: 0
            layer.enabled: true

            Shape {
                anchors.fill: parent
                antialiasing: true

                ShapePath {
                    fillColor: "white"
                    strokeColor: "transparent"
                    strokeWidth: 0
                    PathPolyline { path: layout.maskPoints }
                }
            }
        }

        MultiEffect {
            anchors.fill: parent
            source: bgArtSource
            maskEnabled: true
            maskSource: bgArtMask
            // Needed, and not optional: MultiEffect thresholds the mask's
            // alpha, and its default spread of 0 turns the trace's antialiased
            // edge into a hard 0.5 cut - the curve then renders visibly
            // stair-stepped against the card. The spread lets the mask's own
            // coverage through, which is the only antialiasing this edge gets.
            // The Nothing photo frame carries the same pair for the same
            // reason.
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
            visible: layout.hasRealArt
        }
    }

    // The idle wash, not a cover fallback. This is the full-bleed BACKGROUND
    // sitting behind everything, and it is kept this faint on purpose: a
    // widget with no art has to keep reading as a glass card rather than the
    // opaque plate with a big note on it that main.qml's hasRealArt records
    // the operator rejecting. The cover fallback - the glyph on a plate -
    // belongs to AlbumArt.qml, and only the bar, wide and tallwide layouts
    // mount it; this layout never does.
    Item {
        anchors.fill: parent
        visible: !layout.hasRealArt

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
            anchors.bottom: controls.top
            anchors.bottomMargin: Math.round(layout._s * 0.04)
            spacing: 2

            MarqueeText {
                width: parent.width
                height: Math.round(layout._s * 0.0735) + 4
                text: layout.track || "Not Playing"
                fontSize: Math.max(13, Math.round(layout._s * 0.0683))
                fontWeight: Font.DemiBold
                fontFamily: layout.fontFamily
                textColor: layout.colors.foreground
                horizontalAlignment: Text.AlignHCenter
            }

            MarqueeText {
                width: parent.width
                height: Math.max(13, Math.round(layout._s * 0.0504)) + 4
                text: layout.artist || "—"
                fontSize: Math.max(9, Math.round(layout._s * 0.0494))
                fontWeight: Font.Medium
                fontFamily: layout.fontFamily
                textColor: layout.colors.foreground
                textOpacity: 0.55
                horizontalAlignment: Text.AlignHCenter
            }
        }

        Row {
            id: controls
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(layout._s * 0.08)

            readonly property real _iconSize: Math.max(20, Math.round(layout._s * 0.11))
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
