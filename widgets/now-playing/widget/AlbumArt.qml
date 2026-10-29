import QtQuick
import QtQuick.Effects
import Quickshell
import "../../../components"

// Copied from packages/music/contents/ui/widget/AlbumArt.qml. One change: the
// no-art fallback was a `Kirigami.Icon`, which does not exist here. It is now
// a plain Image over the same freedesktop theme icon, resolved with
// `Quickshell.iconPath()` (the shell's own pattern —
// services/AppLibrary.qml:59) and tinted through MultiEffect colorization so
// the `fallbackIconColor` property keeps working.

Item {
    id: art

    property string artUrl: ""
    property real radius: 12
    property color fallbackIconColor: "#ffffff"

    // Qt's software scene graph, haseen's default, runs no MultiEffect: the
    // masked cover and the tinted glyph below composite to nothing there
    // (measured). There `softCover` and `softGlyph` paint them with QPainter
    // instead, and the Images below load nothing, so the cover is decoded
    // once. Unknown, the window not drawn yet, is not software.
    readonly property bool shadersRun: art.GraphicsInfo.api !== GraphicsInfo.Software

    Image {
        id: coverImage
        anchors.fill: parent
        source: art.shadersRun ? art.artUrl : ""
        fillMode: Image.PreserveAspectCrop
        smooth: true
        mipmap: true
        // Invisible by opacity, not by `visible: false`: a layer that is not
        // updated keeps whatever it held when it was first produced, and this
        // one is the effect's source. See SquareLayout's background layer and
        // the photo frame's mask for the measured shape of the defect.
        opacity: 0
        layer.enabled: art.shadersRun
        cache: false
        // Decode at the drawn size, not the file's: a 1500px cover decoded
        // for a 400px slot is ~9 MB of pixmap, and this widget holds one of
        // these per album-art face (seven once a couple of tracks have
        // played). Same bound as the Nothing tile's art
        // (widgets-nothing/now-playing/main.qml:458): 2x headroom for a
        // fractional scale, and a floor for the frame before layout has run.
        //
        // `cache: false` above stays: CoverArt hands every copy over under a
        // fresh URL (`?g=`), so a cache entry could never be hit.
        sourceSize.width: Math.max(1, Math.round(art.width * 2))
        sourceSize.height: Math.max(1, Math.round(art.height * 2))
    }

    // Invisible by opacity, not by `visible: false`: `visible: false` is the
    // one state that guarantees an item is not updated, and this item exists
    // only to be sampled. When the effect below samples the mask before the
    // mask's own layer has been produced, the mask reads as transparent and
    // the cover draws nothing - permanently, with nothing logged. The same
    // defect is on record for the photo frame's mask
    // (widgets/photos/main.qml, and its Nothing twin); this is the same shape,
    // and the fix the guest measured there. Opacity 0 is the idiom the glass
    // already uses for its own texture helpers (components/LiquidGlass.qml's
    // down/upTex); the opacity applies where the item is composited, not to
    // the layer it provides as a mask.
    Item {
        id: roundMask
        anchors.fill: parent
        layer.enabled: art.shadersRun
        opacity: 0

        Rectangle {
            anchors.fill: parent
            radius: art.radius
            color: "white"
        }
    }

    Rectangle {
        anchors.fill: parent
        color: art.fallbackIconColor
        radius: art.radius
        opacity: 0.08
    }

    MultiEffect {
        anchors.fill: parent
        source: coverImage
        maskEnabled: true
        maskSource: roundMask
        visible: art.shadersRun && art.artUrl !== ""
    }

    Loader {
        id: softCover
        anchors.fill: parent
        active: !art.shadersRun && art.artUrl !== ""
        sourceComponent: SoftwarePicture {
            source: art.artUrl
            radius: art.radius
        }
    }

    // The no-art fallback: the theme's optical-disc glyph over a faint plate
    // of the same tint the layouts pass in. It is reachable now that the tile
    // sends an empty URL for "no art" (main.qml's albumArt) instead of a grey
    // raster that drew over this branch.
    Image {
        id: fallbackIcon
        anchors.centerIn: parent
        width: Math.round(parent.width * 0.35)
        height: Math.round(parent.height * 0.35)
        source: art.shadersRun ? Quickshell.iconPath("media-optical-audio", true) : ""
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        opacity: 0
        layer.enabled: art.shadersRun
    }

    MultiEffect {
        anchors.fill: fallbackIcon
        source: fallbackIcon
        colorization: 1.0
        colorizationColor: art.fallbackIconColor
        opacity: 0.4
        // `status`, not Quickshell.hasThemeIcon: hasThemeIcon reports false for
        // "media-optical-audio" on this machine, yet the path iconPath returns
        // does load (Image.Ready), while a bogus name never leaves Image.Null.
        visible: art.shadersRun && art.artUrl === "" && fallbackIcon.status === Image.Ready
    }

    Loader {
        id: softGlyph
        anchors.fill: fallbackIcon
        active: !art.shadersRun && art.artUrl === ""
        sourceComponent: SoftwarePicture {
            source: Quickshell.iconPath("media-optical-audio", true)
            crop: false
            tint: art.fallbackIconColor
            opacity: 0.4
        }
    }
}
