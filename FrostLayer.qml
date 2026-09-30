import QtQuick

// The screen's wallpaper, blurred once per wallpaper change - the producer half
// of the Nothing style's frost. One instance per PanelWindow, beside Wallpaper
// (GlassSurface.qml), because that Image is the only blurrable backdrop there
// is: the compositor's wallpaper lives in another window and ShaderEffectSource
// cannot sample across windows (Wallpaper.qml's header), so there is no
// MultiEffect / layer.effect / compositor shortcut either.
//
// Nothing-owned. It reads an Item and shares only the two Kawase kernels, which
// are pure GLSL with no glass semantics - no MacOSColors, no LiquidGlass, and
// nothing of liquidglass.frag. See PORTING.md item 20.
//
// Shape: Dual Kawase, four downsamples from half resolution and three
// upsamples back to half - seven passes, the same pyramid LiquidGlass.qml
// builds, minus the crop (a card crops; the screen does not). The output is
// HALF resolution on purpose: the result is blurred, so the ~33 MB a
// full-resolution copy would cost per screen buys nothing.
//
// Timing: every layer is `live: false` and nothing here runs per frame. The
// chain re-captures on a new wallpaper file (Image.Ready), on resize, and when
// it is switched on - which is all `realtimeRefraction`'s finding amounts to
// (PORTING.md item 10): the backdrop is a still Image, so re-running this
// against unchanged pixels is pure GPU cost with zero visual difference.
Item {
  id: frost

  // The screen-sized wallpaper Image (Wallpaper.qml). An Image is a texture
  // provider, so the first pass samples it directly: there is no
  // full-resolution capture FBO in front of the chain.
  property Item wallpaper: null

  // Off means off. With this false no layer holds a sourceItem, so no FBO is
  // allocated and no pass runs - the key is off by default and must cost
  // nothing while it is (NTheme.qml's frost comment has the control story).
  // Named `active` rather than `enabled` because Qt's own Item.enabled now
  // means input handling, and a property here would shadow it.
  property bool active: false

  // The half-resolution blurred screen, or null while disabled. This is the
  // item a card samples as its material (NTheme.frostSource), so it must stay a
  // screen-sized item at the window origin: the card maps its own geometry into
  // it with mapToItem (NFrost.qml).
  readonly property Item output: frost.live ? up2Tex : null

  readonly property bool live: frost.active && frost.wallpaper !== null
                               && frost.width > 0 && frost.height > 0

  // The wallpaper in texels. It is normally the same size as this item; reading
  // the Image's own size keeps the first pass's taps right if it is not (a
  // partially decoded image, a differently sized source).
  readonly property real _srcW: (frost.wallpaper && frost.wallpaper.width > 0)
    ? frost.wallpaper.width : Math.max(1, frost.width)
  readonly property real _srcH: (frost.wallpaper && frost.wallpaper.height > 0)
    ? frost.wallpaper.height : Math.max(1, frost.height)

  // Level sizes. Half of the surface, then halved three more times: at 4K that
  // is 1920x1080 down to 240x135, so the coarsest level is wallpaper/16 and the
  // blur reads as frost rather than as a smudge.
  readonly property size _half: Qt.size(Math.max(1, Math.round(frost.width / 2)),
                                        Math.max(1, Math.round(frost.height / 2)))
  readonly property size _quarter: Qt.size(Math.max(1, Math.round(frost.width / 4)),
                                           Math.max(1, Math.round(frost.height / 4)))
  readonly property size _eighth: Qt.size(Math.max(1, Math.round(frost.width / 8)),
                                          Math.max(1, Math.round(frost.height / 8)))
  readonly property size _sixteenth: Qt.size(Math.max(1, Math.round(frost.width / 16)),
                                             Math.max(1, Math.round(frost.height / 16)))

  // Seven passes, once. The order is load-bearing: a ShaderEffectSource with
  // `live: false` re-captures only when asked, each pass reads the one above it,
  // and Qt renders layers in declaration order within a frame - so marking them
  // all dirty re-renders the chain top-down, exactly as LiquidGlass.qml's does.
  function recapture() {
    down1Tex.scheduleUpdate()
    down2Tex.scheduleUpdate()
    down3Tex.scheduleUpdate()
    down4Tex.scheduleUpdate()
    up4Tex.scheduleUpdate()
    up3Tex.scheduleUpdate()
    up2Tex.scheduleUpdate()
  }

  // A wallpaper file switch. WidgetHost's null-toggle trick (PORTING.md item 5)
  // is for ShaderEffectSources that hold `sourceItem` identity; this chain is
  // re-captured explicitly instead, which is the same trigger without the
  // binding dance.
  Connections {
    target: frost.wallpaper
    function onStatusChanged() { if (frost.live) frost.recapture() }
  }
  onWallpaperChanged: if (frost.live) frost.recapture()
  onLiveChanged: if (frost.live) frost.recapture()
  onWidthChanged: if (frost.live) frost.recapture()
  onHeightChanged: if (frost.live) frost.recapture()
  Component.onCompleted: if (frost.live) frost.recapture()

  // ── Downsample: full → half → quarter → eighth → sixteenth ──────────────
  //
  // `halfpixel` is half a texel of the texture being SAMPLED, which is the
  // convention LiquidGlass.qml uses: the kernel's five taps then straddle the
  // 2x2 block the pass collapses, and each level doubles the reach.
  ShaderEffect {
    id: down1
    anchors.fill: parent
    visible: false
    fragmentShader: Qt.resolvedUrl("components/shaders/kawase_down.frag.qsb")
    property variant source: frost.wallpaper
    property vector2d halfpixel: Qt.vector2d(0.5 / frost._srcW, 0.5 / frost._srcH)
  }
  ShaderEffectSource {
    id: down1Tex
    anchors.fill: parent
    opacity: 0                 // drawn, never seen: capturing is the point
    sourceItem: frost.live ? down1 : null
    live: false
    hideSource: true
    smooth: true
    textureSize: frost._half
    // The one case the explicit recapture above cannot see: the chain being
    // switched on, where the source appears without the wallpaper moving.
    onSourceItemChanged: if (sourceItem !== null) scheduleUpdate()
  }

  ShaderEffect {
    id: down2
    anchors.fill: parent
    visible: false
    fragmentShader: Qt.resolvedUrl("components/shaders/kawase_down.frag.qsb")
    property variant source: down1Tex
    property vector2d halfpixel: Qt.vector2d(0.5 / Math.max(1, down1Tex.textureSize.width),
                                             0.5 / Math.max(1, down1Tex.textureSize.height))
  }
  ShaderEffectSource {
    id: down2Tex
    anchors.fill: parent
    opacity: 0
    sourceItem: frost.live ? down2 : null
    live: false
    hideSource: true
    smooth: true
    textureSize: frost._quarter
    onSourceItemChanged: if (sourceItem !== null) scheduleUpdate()
  }

  ShaderEffect {
    id: down3
    anchors.fill: parent
    visible: false
    fragmentShader: Qt.resolvedUrl("components/shaders/kawase_down.frag.qsb")
    property variant source: down2Tex
    property vector2d halfpixel: Qt.vector2d(0.5 / Math.max(1, down2Tex.textureSize.width),
                                             0.5 / Math.max(1, down2Tex.textureSize.height))
  }
  ShaderEffectSource {
    id: down3Tex
    anchors.fill: parent
    opacity: 0
    sourceItem: frost.live ? down3 : null
    live: false
    hideSource: true
    smooth: true
    textureSize: frost._eighth
    onSourceItemChanged: if (sourceItem !== null) scheduleUpdate()
  }

  ShaderEffect {
    id: down4
    anchors.fill: parent
    visible: false
    fragmentShader: Qt.resolvedUrl("components/shaders/kawase_down.frag.qsb")
    property variant source: down3Tex
    property vector2d halfpixel: Qt.vector2d(0.5 / Math.max(1, down3Tex.textureSize.width),
                                             0.5 / Math.max(1, down3Tex.textureSize.height))
  }
  ShaderEffectSource {
    id: down4Tex
    anchors.fill: parent
    opacity: 0
    sourceItem: frost.live ? down4 : null
    live: false
    hideSource: true
    smooth: true
    textureSize: frost._sixteenth
    onSourceItemChanged: if (sourceItem !== null) scheduleUpdate()
  }

  // ── Upsample: sixteenth → eighth → quarter → half ──────────────────────
  //
  // The up chain's taps are half a texel of the DESTINATION, which is what
  // makes it an upsample rather than a second blur (LiquidGlass.qml's up chain
  // carries the same convention).
  ShaderEffect {
    id: up4
    anchors.fill: parent
    visible: false
    fragmentShader: Qt.resolvedUrl("components/shaders/kawase_up.frag.qsb")
    property variant source: down4Tex
    property vector2d halfpixel: Qt.vector2d(0.5 / frost._eighth.width, 0.5 / frost._eighth.height)
  }
  ShaderEffectSource {
    id: up4Tex
    anchors.fill: parent
    opacity: 0
    sourceItem: frost.live ? up4 : null
    live: false
    hideSource: true
    smooth: true
    textureSize: frost._eighth
    onSourceItemChanged: if (sourceItem !== null) scheduleUpdate()
  }

  ShaderEffect {
    id: up3
    anchors.fill: parent
    visible: false
    fragmentShader: Qt.resolvedUrl("components/shaders/kawase_up.frag.qsb")
    property variant source: up4Tex
    property vector2d halfpixel: Qt.vector2d(0.5 / frost._quarter.width, 0.5 / frost._quarter.height)
  }
  ShaderEffectSource {
    id: up3Tex
    anchors.fill: parent
    opacity: 0
    sourceItem: frost.live ? up3 : null
    live: false
    hideSource: true
    smooth: true
    textureSize: frost._quarter
    onSourceItemChanged: if (sourceItem !== null) scheduleUpdate()
  }

  ShaderEffect {
    id: up2
    anchors.fill: parent
    visible: false
    fragmentShader: Qt.resolvedUrl("components/shaders/kawase_up.frag.qsb")
    property variant source: up3Tex
    property vector2d halfpixel: Qt.vector2d(0.5 / frost._half.width, 0.5 / frost._half.height)
  }
  // The output. Half resolution, screen-sized, and the only texture a card ever
  // samples.
  ShaderEffectSource {
    id: up2Tex
    anchors.fill: parent
    opacity: 0
    sourceItem: frost.live ? up2 : null
    live: false
    hideSource: true
    smooth: true
    textureSize: frost._half
    onSourceItemChanged: if (sourceItem !== null) scheduleUpdate()
  }
}
