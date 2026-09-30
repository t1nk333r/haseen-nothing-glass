import QtQuick
import QtQuick.Effects
import "../../components"
import "../../components/nothing"

// Photos - a frame from a folder of pictures. Nothing-only: there is no
// Liquid Glass twin, and no glass would help a photograph anyway.
//
// The folder, the shuffle and the interval all live on PhotoData, which owns
// the one `find` per folder change and the one timer that advances the frame.
// This file adds no scan, no timer and no cache of its own.
//
// Three per-instance settings, so two photo tiles can show two folders:
// `photoFolder` (absolute or ~/…, empty = $XDG_PICTURES_DIR then ~/Pictures),
// `photoIntervalSec` (0 parks on the current picture) and `photoShuffle`.
// Editable from the widget's right-click sheet and the bar panel; declared in
// WidgetFields.forType("photos") and defaulted in manifest.json.
Item {
    id: root
    anchors.fill: parent

    PhotoData {
        id: photos
        folder: plugin.settings.photoFolder
        intervalSec: plugin.settings.photoIntervalSec
        shuffle: plugin.settings.photoShuffle
        // Stop scanning and stop advancing while the tile is off-screen.
        active: root.visible
    }

    // The three grid presets: 192x192, 400x192, 400x400.
    readonly property bool isWide: root.width >= root.height * 1.6
    readonly property bool isBig: !root.isWide && Math.min(root.width, root.height) >= 300

    readonly property bool hasPicture: photos.count > 0 && photos.current !== ""

    // The mask itself: never drawn, only sampled. Its radius is the card's
    // less the inset, so the two curves are concentric.
    //
    // Invisible by opacity, not by `visible: false`: `visible: false` is the
    // one state that guarantees an item is not updated, and this item exists
    // only to be sampled. The defect it guards against is real on this drawing
    // too - the frame's layer can sample the mask before the mask's own layer
    // has been produced, and then the whole frame draws nothing (photo,
    // caption and empty state alike), permanently and with nothing logged.
    // Measured in the guest at 400x192 over 24 writes x 4 tiles: 1 of 88
    // Nothing tiles blanked, the same rare residue the Liquid Glass drawing
    // still has after its Canvas mask was replaced by geometry. Opacity 0 is
    // the idiom the glass already uses for its own texture helpers
    // (components/LiquidGlass.qml's down/upTex); the opacity applies where the
    // item is composited, not to the layer it provides as a mask.
    Rectangle {
        id: frameMask
        anchors.fill: parent
        anchors.margins: nothing.gap
        radius: Math.max(0, card.radius - nothing.gap)
        color: "white"
        antialiasing: true
        opacity: 0
        layer.enabled: true
    }

    NCard {
        id: card
        theme: nothing
        anchors.fill: parent

        // The picture sits inside the card like a mat, and its corners follow
        // the card's: the frame is masked by a rounded rectangle whose radius
        // is the card's minus the inset, which is the concentric radius - a
        // square-cornered picture inside a rounded card reads as a bug, and a
        // picture sharing the card's radius exactly reads as a sticker.
        //
        // `clip` alone cannot do this: Item clipping is rectangular. The mask
        // covers everything in the frame, the caption strip included, so the
        // strip's bottom corners follow the same curve.
        Item {
            id: frame
            anchors.fill: parent
            anchors.margins: nothing.gap
            clip: true

            layer.enabled: true
            layer.smooth: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: frameMask
                // Without a threshold pair the mask's antialiased edge is
                // treated as partial coverage twice over and the corners come
                // out chewed; this keeps the curve clean.
                maskSpreadAtMin: 1.0
                maskThresholdMin: 0.5
            }

            Image {
                id: picture
                anchors.fill: parent
                visible: root.hasPicture && picture.status === Image.Ready
                source: photos.current
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                // A decode bound, not a size: with both dimensions set the
                // aspect ratio is preserved, and a 6000 px JPEG is not kept
                // at full resolution for a 400 px tile.
                sourceSize.width: Math.max(1, Math.round(frame.width * 2))
                sourceSize.height: Math.max(1, Math.round(frame.height * 2))
            }

            // ── Empty / loading state ─────────────────────────────────────
            // No picture: the dot grid stands in for one, which is the
            // style's way of saying "frame, no image" without an icon.
            NDotField {
                theme: nothing
                anchors.fill: parent
                visible: !picture.visible
                spacing: nothing.px(12)
                intensity: 0.8
            }

            Column {
                anchors.centerIn: parent
                width: parent.width - nothing.pad * 2
                spacing: nothing.px(4)
                visible: !picture.visible

                NLabel {
                    theme: nothing
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    loud: true
                    text: photos.loaded
                        ? (photos.count > 0 ? "LOADING" : "NO PICTURES")
                        : "SCANNING"
                }

                // Which folder came up empty - worth the two lines, since the
                // fix is always "point it somewhere else".
                NMono {
                    theme: nothing
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: (root.isWide || root.isBig) && photos.errorMessage !== ""
                    text: photos.errorMessage
                    color: nothing.onDim
                    font.pixelSize: nothing.fMicro
                    elide: Text.ElideMiddle
                }
            }

            // ── Caption ───────────────────────────────────────────────────
            // A scrim strip, not a card: the picture is the surface here, and
            // the caption is laid over its bottom edge.
            Rectangle {
                id: strip
                visible: picture.visible
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                color: nothing.scrim
                height: caption.height + nothing.px(10) * 2
                     + (setBar.visible ? setBar.height + nothing.px(8) : 0)

                Item {
                    id: caption
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: nothing.px(10)
                    anchors.rightMargin: nothing.px(10)
                    anchors.topMargin: nothing.px(10)
                    height: Math.max(name.implicitHeight, counter.implicitHeight)

                    // 192 px of tile is not enough for a filename, so the
                    // small square keeps the counter only - the one thing
                    // that says where you are in the folder.
                    NLabel {
                        id: name
                        theme: nothing
                        visible: root.isWide || root.isBig
                        loud: true
                        anchors.left: parent.left
                        anchors.right: counter.left
                        anchors.rightMargin: nothing.gap
                        anchors.verticalCenter: parent.verticalCenter
                        text: photos.currentName
                        font.pixelSize: nothing.fMicro
                        elide: Text.ElideMiddle
                    }

                    NMono {
                        id: counter
                        theme: nothing
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: (photos.index + 1) + "/" + photos.count
                        color: nothing.on
                        font.pixelSize: nothing.fMicro
                    }
                }

                // Position in the folder, as segments. Only the large square
                // has the height to spend on it.
                NProgress {
                    id: setBar
                    theme: nothing
                    visible: root.isBig && photos.count > 1
                    anchors.left: caption.left
                    anchors.right: caption.right
                    anchors.top: caption.bottom
                    anchors.topMargin: nothing.px(8)
                    height: nothing.px(4)
                    segments: Math.max(4, Math.min(photos.count, 40))
                    // Position in a folder is not a state worth the accent:
                    // the red stays for things that changed on their own.
                    accent: false
                    value: photos.count > 0 ? (photos.index + 1) / photos.count : 0
                }
            }

            // Hairline frame over the picture, so the outline reads at the
            // same weight whatever the photograph does at its edges.
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                radius: nothing.rDot
                border.width: nothing.hair
                border.color: nothing.outline
            }
        }

        // Click advances. LEFT button only, deliberately: the host reserves
        // the right button for move-and-settings (Placement.qml), so a
        // widget that accepted it would eat the settings gesture. A rescan
        // instead of an advance when the folder came up empty - that is the
        // only useful thing a click can do there.
        MouseArea {
            anchors.fill: parent
            cursorShape: photos.count > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (photos.count === 0) photos.refresh()
                else photos.next()
            }
        }
    }
}
