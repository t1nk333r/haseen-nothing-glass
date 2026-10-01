import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "../../components"

// Photos, Liquid Glass - the glass twin of widgets-nothing/photos/main.qml.
//
// The folder, the shuffle and the interval all live on PhotoData, which owns
// the one `find` per folder change and the one timer that advances the frame.
// This file adds no scan, no timer and no cache of its own, and reads the same
// three per-instance settings as the Nothing drawing (`photoFolder`,
// `photoIntervalSec`, `photoShuffle`) - one schema, two drawings (item 20).
//
// The picture sits inside the glass card like a mat, and its corners follow
// the card's: the frame is a layer with a `MultiEffect` mask over a hidden
// superellipse drawn by `Shape`, whose radius is the card's less the inset
// - the concentric radius, so the two curves stay parallel (item 24). `clip`
// cannot do this (Item clipping is rectangular), and the mask covers the
// caption scrim too, so its bottom corners follow the same curve.
//
// The mask is the shader's own superellipse (exponent `roundness`, radius
// clamped to min side / 2 exactly as liquidglass.frag clamps it) and not a
// `Rectangle { radius }`: at this family's corner radius a circular mask
// clamped to half the frame is a disc, and it cut the caption off the small
// and medium tiles. See `frameMask` below.
//
// What differs from the Nothing drawing, and only this: the surface is the
// glass card rather than an NCard; the empty state is a faint foreground wash
// instead of NDotField (that dot field is a Nothing tell, and glass has no
// counterpart); the caption's caps words are set in the glass face's own case
// ("No pictures", not "NO PICTURES" - NLabel uppercases, this face does not);
// and the position-in-folder readout is a continuous capsule instead of
// segments, which is the only bar shape this style draws.
//
// The reader is a photograph, so the caption is a scrim over its bottom edge
// and not a card: the photo is the surface there. The scrim is `glassTint`,
// the same token the shader tints the card with - black in plain glass, the
// theme's own background in styleMode 3 - and the words are
// `colors.foreground`, so light-on-dark and dark-on-light both fall out of
// the tokens with no branch here (item 15.3).
Item {
    id: full
    anchors.fill: parent

    MacOSColors {
        id: colors
        styleMode: plugin.settings.styleMode
        appearance: plugin.settings.appearance
        systemBackground: theme.systemBackground
        themePalette: theme.palette
    }

    PhotoData {
        id: photos
        folder: plugin.settings.photoFolder
        intervalSec: plugin.settings.photoIntervalSec
        shuffle: plugin.settings.photoShuffle
        // Stop scanning and stop advancing while the tile is off-screen.
        active: full.visible
    }

    // The family's one type and margin scale - see components/GlassScale.qml.
    // `isWide` (1.6) and `isBig` (minSide >= 300) are the same two branches
    // the Nothing drawing derives from `nothing`, so both tiles name the same
    // three presets wide, big and small (item 15.1).
    GlassScale {
        id: gscale
        tileWidth: full.width
        tileHeight: full.height
    }

    LiquidGlass {
        id: glass
        anchors.fill: parent
        wallpaperItem: backdrop.item
        radius: plugin.settings.cornerRadius
        roundness: plugin.settings.roundness
        refractThickness: plugin.settings.refractThickness
        refractIOR: plugin.settings.refractIOR
        refractScale: plugin.settings.refractScale
        tint: colors.glassTint
        tintAlpha: plugin.settings.tintAlpha
        chromaStrength: plugin.settings.chromaStrength
        specStrength: plugin.settings.specStrength
        blurRadius: plugin.settings.blurRadiusPx
        realtimeRefraction: plugin.settings.realtimeRefraction
        fallbackOpacity: colors.glassFallbackOpacity
        solidMode: colors.isSolid && plugin.settings.opaqueBackground
        solidColor: colors.solidBackground
    }

    // ── Layout state ─────────────────────────────────────────────────────
    readonly property bool isWide: gscale.isWide
    readonly property bool isBig: gscale.isBig

    readonly property bool hasPicture: photos.count > 0 && photos.current !== ""

    // The mat: the gap between the card's edge and the picture.
    readonly property real frameInset: gscale.pad

    // The radius the shader gives the card: liquidglass.frag clamps the
    // setting to min(w, h) / 2, so a 192 px tile at the default 100 is 96.
    readonly property real cardRadius: Math.min(glass.radius, Math.min(full.width, full.height) / 2)

    // The mat's radius: the card's less the inset, which is the concentric
    // radius of item 24, clamped exactly as the card's is.
    readonly property real frameRadius: Math.max(0,
        Math.min(full.cardRadius - full.frameInset,
                 Math.min(full.width, full.height) / 2 - full.frameInset))

    // The mask's exponent - the shader's `roundness`, mirrored into a local
    // property so the mask's outline is a binding of the same value the card
    // is drawn with.
    readonly property real maskRoundness: Math.max(plugin.settings.roundness, 2.0)

    // Caption padding. Two `gap`, and not the one-and-a-bit the eye suggests:
    // the frame's corner curve reaches in far enough on a 400x192 tile that a
    // tighter inset leaves the counter inside it by about a pixel, which shows
    // up only as a shaved glyph.
    readonly property real captionPad: Math.round(gscale.gap * 2)

    // The mask's outline: the same parametric superellipse the shader draws
    // for the card - the exponent `roundness` and the radius `frameRadius`,
    // both clamped the way the SDF clamps - as a polyline the scene graph
    // draws directly.
    //
    // Not a `Canvas`, deliberately. A Canvas owns a texture of its own, filled
    // by a deferred `onPaint`, and that deferred paint is what the guest
    // measured: in every blank instance the canvas had never painted
    // (`paints=0` for the rest of the session) while the photo under it was
    // ready and visible. The frame below samples this mask in the same frame,
    // and a mask that is not there yet reads as transparent, so the whole
    // layer drew nothing - photo, caption and empty state alike - permanently
    // and with nothing logged. `Canvas.Immediate` did not help, and a
    // `requestPaint()` retry repainted the mask but never re-rendered the
    // layer that had already sampled it. Geometry the scene graph draws has no
    // second texture to wait for.
    //
    // Guest, 400x192, 24 store writes x 4 tiles (2 glass, 2 Nothing), fresh
    // ids per write: the Canvas mask blanked 9 of 48 glass tiles across 8 of
    // the 24 writes; this drawing has blanked 1 of 88 tiles since. That
    // residue is the rarer hazard the Nothing drawing's plain `Rectangle` mask
    // still shows (1 of 88 there) - a mask source's layer texture not being
    // produced before the effect samples it. It is shared, unfixed, with
    // widgets/now-playing's AlbumArt and SquareLayout, which use the same
    // hidden-layer mask idiom.
    readonly property var maskPoints: {
        var w = frameMask.width, h = frameMask.height
        var r = Math.max(0, Math.min(full.frameRadius, w / 2, h / 2))
        var n = full.maskRoundness
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

    // The mask itself: never drawn, only sampled. It traces the SAME
    // superellipse the shader draws for the card - the exponent `roundness`
    // and the radius `frameRadius`, both clamped the way the SDF clamps -
    // because a plain `Rectangle { radius }` mask is not concentric with it:
    // at this family's radius (100 on a 192 px tile, where the shader clamps
    // to 96) a circular mask clamped to half the frame IS a disc - it
    // swallowed the caption strip whole on the small tile and cut the
    // filename down to its last characters on the medium one. The corner
    // trace is the one widgets/now-playing/widget/SquareLayout.qml already
    // uses for the same job: a rounded picture inside a glass card.
    Item {
        id: frameMask
        anchors.fill: parent
        anchors.margins: full.frameInset
        // Invisible by opacity, not by `visible: false`: `visible: false` is
        // the one state that guarantees an item is not updated, and this item
        // exists only to be sampled - seeing it rendered or not is not a choice
        // to leave to whichever code path happens to ask for its layer first.
        // Opacity 0 is the idiom the glass itself already uses for its own
        // texture helpers (components/LiquidGlass.qml's down/upTex), and the
        // opacity is applied where the item is composited, not to the layer it
        // provides as a mask.
        opacity: 0
        layer.enabled: true

        Shape {
            anchors.fill: parent
            antialiasing: true

            ShapePath {
                fillColor: "white"
                strokeColor: "transparent"
                strokeWidth: 0
                PathPolyline { path: full.maskPoints }
            }
        }
    }

    Item {
        id: frame
        anchors.fill: parent
        anchors.margins: full.frameInset
        clip: true

        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: frameMask
            // Needed, and not optional: MultiEffect thresholds the mask's
            // alpha, and its default spread of 0 turns the trace's
            // antialiased edge into a hard 0.5 cut - the curve then renders
            // visibly stair-stepped against the card. The spread lets the
            // mask's own coverage through, which is the only antialiasing
            // this edge gets. The Nothing drawing carries the same pair for
            // the same reason (there over a plain `Rectangle` mask).
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        Image {
            id: picture
            anchors.fill: parent
            visible: full.hasPicture && picture.status === Image.Ready
            source: photos.current
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            // A decode bound, not a size: with both dimensions set the aspect
            // ratio is preserved, and a 6000 px JPEG is not kept at full
            // resolution for a 400 px tile.
            sourceSize.width: Math.max(1, Math.round(frame.width * 2))
            sourceSize.height: Math.max(1, Math.round(frame.height * 2))
        }

        // ── Empty / loading state ────────────────────────────────────────
        // No picture: a faint wash of the foreground, which is this style's
        // way of saying "frame, no image" without an icon - the Nothing
        // drawing answers the same state with its dot field. No radius of its
        // own: the frame's mask is what cuts it to the card's curve, and a
        // `radius` here would not - where the card's radius is clamped (the
        // small and medium tiles) a circular radius of half the frame is a
        // disc, which is not the curve the picture gets.
        Rectangle {
            anchors.fill: parent
            color: colors.foreground
            opacity: 0.08
            visible: !picture.visible
        }

        Column {
            anchors.centerIn: parent
            width: Math.max(0, parent.width - 2 * full.captionPad)
            spacing: gscale.gap
            visible: !picture.visible

            Text {
                textFormat: Text.PlainText
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: photos.loaded
                    ? (photos.count > 0 ? "Loading" : "No pictures")
                    : "Scanning"
                color: colors.foreground
                font.family: colors.uiFont
                font.pixelSize: gscale.body
                font.weight: Font.DemiBold
            }

            // Which folder came up empty - worth the two lines, since the fix
            // is always "point it somewhere else".
            Text {
                textFormat: Text.PlainText
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: (full.isWide || full.isBig) && photos.errorMessage !== ""
                text: photos.errorMessage
                color: colors.foreground
                opacity: colors.textQuiet
                font.family: colors.uiFont
                font.pixelSize: gscale.micro
                elide: Text.ElideMiddle
            }
        }

        // ── Caption ─────────────────────────────────────────────────────
        // A scrim strip, not a card: the picture is the surface here, and the
        // caption is laid over its bottom edge. The gradient is the tint at
        // zero alpha at the top so the photograph is never cut by a hard line.
        Item {
            id: strip
            visible: picture.visible
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: captionColumn.height + full.captionPad * 2

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(colors.glassTint.r, colors.glassTint.g, colors.glassTint.b, 0.0) }
                    GradientStop { position: 1.0; color: Qt.rgba(colors.glassTint.r, colors.glassTint.g, colors.glassTint.b, 0.70) }
                }
            }

            Column {
                id: captionColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: full.captionPad
                spacing: gscale.gap

                Item {
                    width: parent.width
                    height: Math.max(nameText.implicitHeight, counterText.implicitHeight)

                    // 192 px of tile is not enough for a filename, so the
                    // small square keeps the counter only - the one thing
                    // that says where you are in the folder.
                    Text {
                        id: nameText
                        textFormat: Text.PlainText
                        visible: full.isWide || full.isBig
                        anchors.left: parent.left
                        anchors.right: counterText.left
                        anchors.rightMargin: gscale.gap
                        anchors.verticalCenter: parent.verticalCenter
                        text: photos.currentName
                        color: colors.foreground
                        font.family: colors.uiFont
                        font.pixelSize: gscale.micro
                        font.weight: Font.DemiBold
                        elide: Text.ElideMiddle
                    }

                    Text {
                        id: counterText
                        textFormat: Text.PlainText
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: (photos.index + 1) + "/" + photos.count
                        color: colors.foreground
                        font.family: colors.uiFont
                        font.pixelSize: gscale.micro
                    }
                }

                // Position in the folder, as a capsule. Only the large square
                // has the height to spend on it. No accent: position in a
                // folder is not a state that changed on its own.
                Item {
                    id: setBar
                    visible: full.isBig && photos.count > 1
                    width: parent.width
                    height: Math.round(gscale.gap * 1.2)

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: colors.foreground
                        opacity: 0.25
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * (photos.count > 0 ? (photos.index + 1) / photos.count : 0)
                        height: parent.height
                        radius: height / 2
                        color: colors.foreground
                        opacity: 0.85

                        Behavior on width {
                            NumberAnimation { duration: 200 }
                        }
                    }
                }
            }
        }

        // Hairline frame over the picture, so the outline reads at the same
        // weight whatever the photograph does at its edges. Shaped by the
        // same mask, for the same reason as the wash above.
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: 1
            border.color: colors.separator
        }
    }

    // Click advances. LEFT button only, deliberately: the host reserves the
    // right button for move-and-settings (Placement.qml), so a widget
    // that accepted it would eat the settings gesture. A rescan instead of an
    // advance when the folder came up empty - that is the only useful thing a
    // click can do there.
    MouseArea {
        anchors.fill: parent
        cursorShape: photos.count > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (photos.count === 0) photos.refresh()
            else photos.next()
        }
    }
}
