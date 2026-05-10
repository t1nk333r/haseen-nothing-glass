import QtQuick
import org.kde.plasma.plasmoid

// Reusable frosted/liquid-glass background.
// Place inside a PlasmoidItem, anchors.fill: parent.
//
// Pipeline:
//   wallpaperTex -> crop (extract widget region) -> blurH1 -> blurV1
//     -> blurH2 -> blurV2 -> glassShader (refraction + chroma + tint)
//
// The crop shader maps wallpaper UV to widget-local UV so the blur
// passes operate in widget pixel space. The glass shader then applies
// refraction on the blurred result with identity UV mapping. When
// blurRadius <= 0 the crop/blur chain is inert and the glass shader
// samples wallpaperTex directly with uvOffset/uvScale.
//
// Falls back to a flat translucent rounded rect when wallpaperGraphicsObject
// is null or zero-size (panels, plasmoidviewer).
Item {
    id: glass

    // Shape
    property real radius: 100
    // Superellipse exponent: 2 = plain rounded rect, 5.5 ≈ iOS squircle
    property real roundness: 7.5

    // Glass effect — Snell-on-a-dome refraction through an edge band.
    // refractThickness is the width of that band in pixels. refractIOR is
    // the glass index of refraction (1.0 = none, 1.4 ≈ real glass, higher
    // exaggerates). refractScale is a user-facing strength multiplier on
    // top of Snell — cranked up vs. the reference because our coordinates
    // are widget pixels, not normalized units.
    property real refractThickness: 30
    property real refractIOR: 1.6
    property real refractScale: 65
    property color tint: "#ffffff"
    property real tintAlpha: 0.25
    property real chromaStrength: 0.20

    // Blur spread in widget pixels; 0 = disabled.
    property real blurRadius: 8

    // Border specular (free-following primary + antipodal secondary).
    property bool specEnabled: true
    property real specStrength: 0.70

    // When false, the wallpaper is only re-captured on geometry changes
    // (recommended for static wallpapers — saves GPU per frame). Turn on
    // for animated / video wallpapers that need continuous updates.
    property bool realtimeRefraction: false

    property real fallbackOpacity: 0.55

    // Solid mode: skip wallpaper capture and refraction; render an opaque
    // squircle filled with `solidColor`. The squircle silhouette + corner
    // specular still render via the same shader (tint forced opaque), so
    // the macOS material feel is preserved.
    property bool solidMode: false
    property color solidColor: "#1A1B1E"
    property color solidColorBottom: "transparent"

    readonly property var wallpaperItem: {
        const c = Plasmoid.containment
        if (!c) return null
        const w = c.wallpaperGraphicsObject
        if (!w) return null
        return findRenderableSource(w)
    }

    readonly property bool active: wallpaperItem !== null
                                   && wallpaperItem.width > 0
                                   && wallpaperItem.height > 0

    function isLoader(n) {
        return n && n.sourceComponent !== undefined && n.item !== undefined
    }
    function findRenderableSource(node) {
        if (!node) return null
        if (isLoader(node)) return findRenderableSource(node.item)
        if (node.children && node.children.length > 0) {
            for (var i = 0; i < node.children.length; i++) {
                const inner = findRenderableSource(node.children[i])
                if (inner) return inner
            }
        }
        if (node.width > 0 && node.height > 0) return node
        return null
    }

    property real _offX: 0
    property real _offY: 0
    function updateGeometry() {
        if (!wallpaperItem) return
        const p = glass.mapToItem(wallpaperItem, 0, 0)
        let moved = false
        if (p.x !== _offX) { _offX = p.x; moved = true }
        if (p.y !== _offY) { _offY = p.y; moved = true }
        // If realtime is off, force a one-shot backdrop recapture so the
        // sampled wallpaper stays aligned after the widget moves.
        if (moved && !realtimeRefraction) wallpaperTex.scheduleUpdate()
    }

    // --- Mouse tracking for specular highlight ---
    // _mouseU/_mouseV are in widget-local UV (0..1). (-1,-1) means no hover.
    property real _mouseU: -1
    property real _mouseV: -1
    property real _mouseFade: 0

    Behavior on _mouseFade {
        NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: glass.specEnabled
        acceptedButtons: Qt.NoButton   // never consume clicks
        propagateComposedEvents: true

        onPositionChanged: (mouse) => {
            glass._mouseU = mouse.x / Math.max(1, glass.width)
            glass._mouseV = mouse.y / Math.max(1, glass.height)
            glass._mouseFade = 1
        }
        onEntered: glass._mouseFade = 1
        onExited: {
            glass._mouseFade = 0
            glass._mouseU = -1
            glass._mouseV = -1
        }
    }
    Timer {
        interval: 16
        repeat: true
        // Solid mode doesn't need geometry updates (no wallpaper sample),
        // but we still want the timer disabled until the widget has size.
        running: !glass.solidMode && glass.active
                 && glass.visible && glass.width > 0 && glass.height > 0
        onTriggered: glass.updateGeometry()
    }
    Component.onCompleted: updateGeometry()

    // --- Wallpaper capture ---

    ShaderEffectSource {
        id: wallpaperTex
        anchors.fill: parent
        opacity: 0
        sourceItem: glass.solidMode ? null : glass.wallpaperItem
        live: !glass.solidMode && glass.realtimeRefraction
        hideSource: false
        recursive: false
        smooth: true
        mipmap: false
        textureMirroring: ShaderEffectSource.MirrorVertically

        onSourceItemChanged: scheduleUpdate()
        Connections {
            target: glass
            function onWidthChanged()  { if (!glass.solidMode && !glass.realtimeRefraction) wallpaperTex.scheduleUpdate() }
            function onHeightChanged() { if (!glass.solidMode && !glass.realtimeRefraction) wallpaperTex.scheduleUpdate() }
        }
    }

    // --- Frosted-glass blur pipeline ---
    //
    // crop → blurH1 → blurV1 → blurH2 → blurV2
    //
    // The crop shader extracts the widget's wallpaper region into a
    // widget-sized texture (widget-local UV space). The four separable
    // Gaussian passes (17-tap each, two full H+V iterations) then blur
    // in that local space — no wallpaper-vs-widget UV mismatch.
    //
    // The glass shader receives the blurred crop with identity UV
    // mapping (uvOffset=0, uvScale=1) and applies refraction + chroma
    // on top of the already-blurred image.
    //
    // When blurRadius <= 0 or in solid mode, the crop/blur chain is
    // inert and the glass shader samples wallpaperTex directly with
    // the standard uvOffset/uvScale.

    readonly property bool _blurActive: !glass.solidMode && glass.blurRadius > 0 && glass.active

    readonly property vector2d _uvOff: glass.active
        ? Qt.vector2d(glass._offX / glass.wallpaperItem.width,
                      glass._offY / glass.wallpaperItem.height)
        : Qt.vector2d(0, 0)
    readonly property vector2d _uvSc: glass.active
        ? Qt.vector2d(glass.width  / glass.wallpaperItem.width,
                      glass.height / glass.wallpaperItem.height)
        : Qt.vector2d(1, 1)

    readonly property real _widgetW: Math.max(1, glass.width)
    readonly property real _widgetH: Math.max(1, glass.height)

    ShaderEffect {
        id: cropPass
        anchors.fill: parent
        visible: false
        fragmentShader: Qt.resolvedUrl("shaders/crop.frag.qsb")
        property variant source: wallpaperTex
        property vector2d uvOffset: glass._uvOff
        property vector2d uvScale: glass._uvSc
    }
    ShaderEffectSource {
        id: cropTex
        anchors.fill: parent
        opacity: 0
        sourceItem: glass._blurActive ? cropPass : null
        live: glass._blurActive
        hideSource: true
        smooth: true
    }

    ShaderEffect {
        id: blurH1
        anchors.fill: parent
        visible: false
        fragmentShader: Qt.resolvedUrl("shaders/blur_h.frag.qsb")
        property variant source: cropTex
        property real radiusPx: glass.blurRadius
        property vector2d sourceSizePx: Qt.vector2d(glass._widgetW, glass._widgetH)
    }
    ShaderEffectSource {
        id: blurH1Tex
        anchors.fill: parent
        opacity: 0
        sourceItem: glass._blurActive ? blurH1 : null
        live: glass._blurActive
        hideSource: true
        smooth: true
    }

    ShaderEffect {
        id: blurV1
        anchors.fill: parent
        visible: false
        fragmentShader: Qt.resolvedUrl("shaders/blur_v.frag.qsb")
        property variant source: blurH1Tex
        property real radiusPx: glass.blurRadius
        property vector2d sourceSizePx: Qt.vector2d(glass._widgetW, glass._widgetH)
    }
    ShaderEffectSource {
        id: blurV1Tex
        anchors.fill: parent
        opacity: 0
        sourceItem: glass._blurActive ? blurV1 : null
        live: glass._blurActive
        hideSource: true
        smooth: true
    }

    ShaderEffect {
        id: blurH2
        anchors.fill: parent
        visible: false
        fragmentShader: Qt.resolvedUrl("shaders/blur_h.frag.qsb")
        property variant source: blurV1Tex
        property real radiusPx: glass.blurRadius
        property vector2d sourceSizePx: Qt.vector2d(glass._widgetW, glass._widgetH)
    }
    ShaderEffectSource {
        id: blurH2Tex
        anchors.fill: parent
        opacity: 0
        sourceItem: glass._blurActive ? blurH2 : null
        live: glass._blurActive
        hideSource: true
        smooth: true
    }

    ShaderEffect {
        id: blurV2
        anchors.fill: parent
        visible: false
        fragmentShader: Qt.resolvedUrl("shaders/blur_v.frag.qsb")
        property variant source: blurH2Tex
        property real radiusPx: glass.blurRadius
        property vector2d sourceSizePx: Qt.vector2d(glass._widgetW, glass._widgetH)
    }
    ShaderEffectSource {
        id: blurV2Tex
        anchors.fill: parent
        opacity: 0
        sourceItem: glass._blurActive ? blurV2 : null
        live: glass._blurActive
        hideSource: true
        smooth: true
    }

    // --- Glass shader (refraction + chroma + tint + specular + mask) ---
    //
    // When blur is active, backdrop is the blurred crop in widget-local
    // UV (uvOffset=0, uvScale=1). Refraction displaces into the blurred
    // image. When blur is off, falls back to wallpaperTex with the
    // standard offset/scale mapping.

    ShaderEffect {
        id: glassShader
        anchors.fill: parent
        visible: glass.solidMode || glass.active
        fragmentShader: Qt.resolvedUrl("shaders/liquidglass.frag.qsb")

        property variant backdrop: glass._blurActive ? blurV2Tex : wallpaperTex
        property size size: Qt.size(glass._widgetW, glass._widgetH)
        property real radius: glass.radius
        property real roundness: glass.roundness
        property real refractThickness: glass.solidMode ? 0.0 : glass.refractThickness
        property real refractIOR: glass.refractIOR
        property real refractScale: glass.solidMode ? 0.0 : glass.refractScale
        property real chromaStrength: glass.solidMode ? 0.0 : glass.chromaStrength
        property vector4d tint: glass.solidMode
            ? Qt.vector4d(glass.solidColor.r, glass.solidColor.g, glass.solidColor.b, 1.0)
            : Qt.vector4d(glass.tint.r, glass.tint.g, glass.tint.b, glass.tintAlpha)
        property vector4d tintBottom: glass.solidMode && glass.solidColorBottom.a > 0
            ? Qt.vector4d(glass.solidColorBottom.r, glass.solidColorBottom.g, glass.solidColorBottom.b, 1.0)
            : Qt.vector4d(0, 0, 0, 0)

        property vector2d mousePos: Qt.vector2d(glass._mouseU, glass._mouseV)
        property real mouseFade: glass._mouseFade
        property real specStrength: glass.specEnabled ? glass.specStrength : 0.0

        property vector2d uvOffset: glass._blurActive
            ? Qt.vector2d(0, 0) : glass._uvOff
        property vector2d uvScale: glass._blurActive
            ? Qt.vector2d(1, 1) : glass._uvSc
    }

    // --- Fallback ---
    // Used when the wallpaper containment is unavailable (panels,
    // plasmoidviewer) AND we're in glass mode. In solid mode the shader
    // above already renders an opaque tinted squircle, so no fallback
    // needed.

    Rectangle {
        id: fallback
        anchors.fill: parent
        visible: !glass.solidMode && !glass.active
        color: glass.tint
        opacity: glass.fallbackOpacity
        radius: glass.radius
    }
}
