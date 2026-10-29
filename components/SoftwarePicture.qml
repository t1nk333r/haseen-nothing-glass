import QtQuick

// One picture painted without a shader, for Qt's software scene graph.
//
// Every MultiEffect in this plugin - the photo and cover masks, the icon
// tints, the rolling digits' blur - draws nothing at all there: measured under
// QT_QUICK_BACKEND=software, a masked Image, a colourised icon and a blurred
// Text each composite to fully transparent pixels. haseen runs its shell on
// that scene graph unless told otherwise. This paints what the effects would
// have, with QPainter through a Canvas, in this order:
//
//   1. the picture, cropped like Image.PreserveAspectCrop or, with `crop`
//      false, fitted like PreserveAspectFit;
//   2. with a `tint` of non-zero alpha, the picture's colour replaced by it
//      and its alpha kept, which is what `colorization: 1.0` does to the
//      single-colour icons it is used on;
//   3. a vertical `overlayStops` band from `overlayTop` to the bottom - a
//      caption scrim, or the darkening laid over a cover;
//   4. with a `strokeWidth` above 0, a `strokeColor` hairline that far
//      inside the outline - a rectangle's border, but following the curve;
//   5. everything cut to `points` (a closed polyline in this item's
//      coordinates, Squircle.outline()'s shape) or else to a rounded rectangle
//      of `radius`, by an antialiased `destination-out` fill of what lies
//      outside it: a QPainter clip is aliased, and the masks it stands in for
//      are not;
//   6. a flat `fill` under the lot, inside the same outline.
//
// Only for where no shader runs. On the GPU path a Canvas used as a hidden
// mask was measured never to paint (widgets/photos/main.qml's mask comment);
// here the Canvas is what is drawn, not a texture something else samples, and
// `paints` lets a test prove it painted.
Canvas {
    id: pic

    property url source: ""
    // A decode bound: the picture is decoded to fit inside this, aspect kept,
    // so a 6000 px photograph is not held at full size for a 192 px tile.
    // Twice the item, the bound the shader paths give their Image.sourceSize.
    property size sourceSize: Qt.size(Math.max(1, Math.round(pic.width * 2)),
                                      Math.max(1, Math.round(pic.height * 2)))
    property bool crop: true
    property var points: null
    property real radius: 0
    property color fill: "transparent"
    property color tint: "transparent"
    property real overlayTop: 0
    // [{ position: 0..1, color: color }], positions over the band.
    property var overlayStops: []
    property color strokeColor: "transparent"
    property real strokeWidth: 0

    // True once the current `source` has been decoded and can be painted -
    // what Image.status === Image.Ready tells the shader path.
    readonly property bool ready: pic._ready
    property bool _ready: false

    // How many times onPaint has run: the tests require a painted picture,
    // since a Canvas that never paints draws nothing and logs nothing.
    readonly property int paints: pic._paints
    property int _paints: 0
    property url _loaded: ""

    antialiasing: true

    function _reload() {
        if (String(pic._loaded) !== "") pic.unloadImage(pic._loaded)
        pic._loaded = pic.source
        pic._ready = false
        if (String(pic.source) !== "") pic.loadImage(pic.source, pic.sourceSize)
        pic.requestPaint()
    }

    // Adds the outline to the current path as one closed subpath.
    function _outline(ctx) {
        var pts = pic.points
        if (pts && pts.length > 2) {
            ctx.moveTo(pts[0].x, pts[0].y)
            for (var i = 1; i < pts.length; i++) ctx.lineTo(pts[i].x, pts[i].y)
            ctx.closePath()
        } else {
            var r = Math.max(0, Math.min(pic.radius, pic.width / 2, pic.height / 2))
            ctx.roundedRect(0, 0, pic.width, pic.height, r, r)
        }
    }

    onSourceChanged: pic._reload()
    onSourceSizeChanged: pic._reload()
    onImageLoaded: {
        pic._ready = String(pic.source) !== "" && pic.isImageLoaded(String(pic.source))
        pic.requestPaint()
    }
    onPointsChanged: pic.requestPaint()
    onRadiusChanged: pic.requestPaint()
    onFillChanged: pic.requestPaint()
    onTintChanged: pic.requestPaint()
    onCropChanged: pic.requestPaint()
    onOverlayTopChanged: pic.requestPaint()
    onOverlayStopsChanged: pic.requestPaint()
    onStrokeColorChanged: pic.requestPaint()
    onStrokeWidthChanged: pic.requestPaint()
    onWidthChanged: pic.requestPaint()
    onHeightChanged: pic.requestPaint()
    Component.onCompleted: pic._reload()
    Component.onDestruction: if (String(pic._loaded) !== "") pic.unloadImage(pic._loaded)

    onPaint: {
        var ctx = pic.getContext("2d")
        ctx.reset()
        pic._paints++
        var w = pic.width, h = pic.height
        if (w <= 0 || h <= 0) return

        // createImageData() finds a loaded image only by its URL as a string:
        // given the url value it returns undefined (measured, Qt 6.12).
        var src = String(pic.source)
        pic._ready = src !== "" && pic.isImageLoaded(src)
        if (pic._ready) {
            var data = ctx.createImageData(src)
            var iw = data ? data.width : 0, ih = data ? data.height : 0
            if (iw > 0 && ih > 0) {
                var s = pic.crop ? Math.max(w / iw, h / ih) : Math.min(w / iw, h / ih)
                var dw = iw * s, dh = ih * s
                ctx.drawImage(src, (w - dw) / 2, (h - dh) / 2, dw, dh)
                if (pic.tint.a > 0) {
                    ctx.globalCompositeOperation = "source-in"
                    ctx.fillStyle = pic.tint
                    ctx.fillRect(0, 0, w, h)
                    ctx.globalCompositeOperation = "source-over"
                }
            }
        }

        var stops = pic.overlayStops || []
        if (stops.length > 0 && pic.overlayTop < h) {
            var band = ctx.createLinearGradient(0, pic.overlayTop, 0, h)
            for (var i = 0; i < stops.length; i++)
                band.addColorStop(stops[i].position, stops[i].color)
            ctx.fillStyle = band
            ctx.fillRect(0, pic.overlayTop, w, h - pic.overlayTop)
        }

        // Twice the width, centred on the outline: the cut below removes the
        // outer half.
        if (pic.strokeWidth > 0 && pic.strokeColor.a > 0) {
            ctx.strokeStyle = pic.strokeColor
            ctx.lineWidth = pic.strokeWidth * 2
            ctx.beginPath()
            pic._outline(ctx)
            ctx.stroke()
        }

        // QPainter composes only the pixels a fill covers, so `destination-in`
        // over the outline would keep the corners (measured): clear the
        // outside instead, the canvas rectangle with the outline cut out of it.
        ctx.globalCompositeOperation = "destination-out"
        ctx.fillStyle = "#ffffff"
        ctx.fillRule = Qt.OddEvenFill
        ctx.beginPath()
        ctx.rect(0, 0, w, h)
        pic._outline(ctx)
        ctx.fill()
        ctx.fillRule = Qt.WindingFill

        if (pic.fill.a > 0) {
            ctx.globalCompositeOperation = "destination-over"
            ctx.fillStyle = pic.fill
            ctx.beginPath()
            pic._outline(ctx)
            ctx.fill()
        }
        ctx.globalCompositeOperation = "source-over"
    }
}
