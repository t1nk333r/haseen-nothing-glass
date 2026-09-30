import QtQuick

// A Nothing card's material: the card's own rounded rectangle, filled with the
// surface colour over the screen's blurred wallpaper - `theme.surfaceAlpha` of
// the colour, `theme.frost` of the wallpaper.
//
// The two knobs are INDEPENDENT, and this item is where that is true (the
// fragment shader's header has the algebra, NTheme's the control story): the
// surface covers its share of the card at every frost, and the blurred wallpaper
// is behind it at every surfaceAlpha. So `frost` 0 is the matte card, and
// `surfaceAlpha` still moves the card at `frost` 1 - the case where the two used
// to be one mutually exclusive material and the opacity knob did nothing.
//
// A visible ShaderEffect on purpose - no ShaderEffectSource, no per-card FBO, no
// capture. Per frame this is one texture tap into the screen's half-res blur
// (FrostLayer's output, shared by every card on that screen) plus a rounded-rect
// SDF for the silhouette; the blur itself is built once per wallpaper change,
// not per card and not per frame.
//
// Nothing-owned: it reads `theme` (NTheme) and nothing else - no MacOSColors, no
// LiquidGlass, no `qs.Ui` - and nfrost.frag takes none of the glass material
// with it. See PORTING.md item 20.
ShaderEffect {
  id: frostEffect

  required property var theme

  // What a card samples: the screen's blurred wallpaper, which is a
  // ShaderEffectSource in another item (NTheme.frostSource <- WidgetHost <-
  // GlassSurface's FrostLayer). Null on a surface with no screen behind it -
  // a launcher preview, the sweep harness - and a null source is never reached:
  // NCard only instantiates this when there is one.
  property Item blurSource: frostEffect.theme ? frostEffect.theme.frostSource : null

  fragmentShader: Qt.resolvedUrl("../shaders/nfrost.frag.qsb")

  property variant source: frostEffect.blurSource

  // The card's screen position in the blur's UV space: this pass crops the
  // screen-sized blur exactly the way crop.frag crops the wallpaper.
  //
  // mapToItem() is a function, so QML re-runs this binding only when something
  // it reads notifies - `frostEpoch`, which the host bumps on every x/y/width/
  // height change (WidgetHost.qml). The host is the only moving ancestor a card
  // has, so a drag or a resize is exact, and no 16 ms timer is involved.
  readonly property vector2d _uvOffset: {
    var src = frostEffect.blurSource
    if (frostEffect.theme) frostEffect.theme.frostEpoch
    if (!src || src.width <= 0 || src.height <= 0) return Qt.vector2d(0, 0)
    var p = frostEffect.mapToItem(src, 0, 0)
    return Qt.vector2d(p.x / src.width, p.y / src.height)
  }
  readonly property vector2d _uvScale: {
    var src = frostEffect.blurSource
    if (!src || src.width <= 0 || src.height <= 0) return Qt.vector2d(1, 1)
    return Qt.vector2d(frostEffect.width / src.width, frostEffect.height / src.height)
  }

  property vector2d uvOffset: frostEffect._uvOffset
  property vector2d uvScale: frostEffect._uvScale
  property size size: Qt.size(frostEffect.width, frostEffect.height)

  // The style's own silhouette: a plain rounded rect at NTheme.rCard. The glass
  // style's squircle exponent, refraction, specular and its tint/tintAlpha pair
  // are deliberately absent (see nfrost.frag's header).
  property real radius: frostEffect.theme ? frostEffect.theme.rCard : 0

  // The two material knobs, each carried to the shader under its own name, and
  // the surface colour itself in `surface`:
  //
  //   * `frost` - how much of the card's backdrop is the blurred wallpaper.
  //   * `surface.a` - how much of the backdrop the surface colour covers.
  //
  // Multiplied by the surface token's own alpha, so the shader's surface is
  // exactly the fill NTheme.surface hands the matte card - the two paths stay
  // the same colour at the same knob position, which is what makes the
  // pre-frost case reproducible and the cross-fade between them a fade.
  property real frost: frostEffect.theme ? frostEffect.theme.frost : 0
  property real surfaceAlpha: frostEffect.theme
    ? frostEffect.theme.surfaceAlpha * frostEffect.theme.surfaceSolid.a : 1
  property vector4d surface: frostEffect.theme
    ? Qt.vector4d(frostEffect.theme.surfaceSolid.r, frostEffect.theme.surfaceSolid.g,
                  frostEffect.theme.surfaceSolid.b, frostEffect.surfaceAlpha)
    : Qt.vector4d(0, 0, 0, 0)
}
