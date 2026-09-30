import QtQuick

// The Nothing OS visual language, as tokens.
//
// This is the second presentation style, beside Liquid Glass. It does NOT
// replace MacOSColors: a Liquid Glass widget never sees this object, and a
// Nothing widget never reads MacOSColors. Both read the same data
// components, which is the whole point of the split.
//
// Matte near-black, charcoal surfaces, hairline grey outlines, one red used
// sparingly, tight radii, small type. Everything scales through px() so a
// single `scale` setting resizes the entire style without touching a widget.
QtObject {
    id: theme

    // Injected by WidgetHost from the plugin configuration.
    property real scale: 1.0
    property color accent: "#D71921"
    // Optional Omarchy palette ({background, foreground, accent, urgent,
    // surface}). Null keeps the stock Nothing palette; set it and the style
    // follows the desktop theme the same way MacOSColors' modes 2/3 do.
    property var themePalette: null
    property bool followTheme: false

    function px(v) { return Math.round(v * theme.scale) }

    function _t(key, fallback) {
        if (!theme.followTheme || !theme.themePalette) return fallback
        var v = theme.themePalette[key]
        return (v === undefined || v === null || v === "") ? fallback : v
    }

    // ── Surfaces ─────────────────────────────────────────────────────
    // Numbered by how far a surface stands out from what it sits on, so a
    // call site keeps its meaning if the palette is swapped.
    //
    // Each level is a pair, and the split is the whole mechanism behind
    // `surfaceAlpha`: the `*Solid` token is the declared opaque base, and the
    // plain token is that base with the multiplier in its alpha channel. A
    // colour's alpha is the one thing a call site cannot add for itself
    // without also fading the ink drawn on top of it, and a card whose fill
    // fades must keep its type, its hairlines and its dot matrices at full
    // strength - fading those is the compositor look (`NCard.opacity`), not a
    // translucent material.
    //
    // Both bases are declared as `color` properties rather than passed
    // straight into `Qt.rgba`/`Qt.lighter`: `_t()` hands back the palette's
    // *string*, and a string has no `.r` - see the note on `redInk` below,
    // which is what that costs when it goes wrong. Only the level-0 base is
    // `surfaceSolid` and public, because only it has call sites that must stay
    // opaque at every multiplier: the six dial hub discs, whose backdrop is
    // the ink cap they sit inside rather than the material over the wallpaper.
    readonly property color surfaceSolid:  _t("background", "#0B0B0B")
    // Qt.lighter() carries alpha through untouched, but the stock branch is a
    // literal, so the multiply happens once, at the end, for all three levels
    // and both branches - doing it on the base instead would apply it twice
    // on the followed-theme path and lose it on the stock one.
    readonly property color surface2Solid: theme.followTheme
        ? Qt.lighter(theme.surfaceSolid, 1.35) : "#161616"
    readonly property color surface3Solid: theme.followTheme
        ? Qt.lighter(theme.surfaceSolid, 1.7) : "#212121"

    // Injected by WidgetHost from the plugin configuration. 0..1; 1 is the
    // matte card the style has always drawn, i.e. the default leaves every
    // pixel where it was. It multiplies the alpha of the three surface fills
    // and nothing else: `on`/`onDim`/`onQuiet`/`onFaint`, `outline`, `scrim`,
    // `red`, `NButton`'s disabled-state opacity, `NDotField.intensity` and
    // `NDotMatrix.reveal` all keep their present values, so a translucent card
    // still reads. `onDim`/`onQuiet` stay calibrated to the *matte* surface -
    // `_over()` reads only r/g/b, and what is behind a real card is the
    // compositor's wallpaper, which nothing here can measure.
    //
    // What shows through is the wallpaper, crisp: a desktop widget sits on a
    // transparent layer. There is no blur and no refraction back there unless
    // `frost` below puts them there - and the pair is not a choice between the
    // two: this knob is how much of a level-0 card the surface colour covers,
    // `frost` is what the card's backdrop is made of. Neither is a gate on the
    // other.
    //
    // This is the multiplier the level-0 card shares with NFrost, where it
    // weights the surface colour against that backdrop (nfrost.frag): the same
    // number, the same token, so a card crossing the frost threshold in either
    // direction fades between one material and the other instead of jumping.
    //
    // One consequence to know: the daylight plates (`city-1`, `city-2`) and
    // `NButton`'s hover fill are drawn *inside* the level-0 card, so their area
    // carries two translucent layers and measures 1-(1-a)^2 - 0.75 at a = 0.5,
    // visibly denser than the card.
    property real surfaceAlpha: 1.0

    // ── Frost ────────────────────────────────────────────────────────
    // The second knob, and INDEPENDENT of `surfaceAlpha` rather than an
    // alternative material to it. The two compose into one material, which is
    // the whole of nfrost.frag:
    //
    //   backdrop = mix(nothing, blurred wallpaper, frost)
    //   material = mix(backdrop, surface, surfaceAlpha)
    //
    // so this fraction is how much of a level-0 card's backdrop is the blurred
    // wallpaper, and `surfaceAlpha` is how much of that backdrop the surface
    // colour covers. Each one still moves the card while the other is anywhere
    // in 0..1 - at `frost` 1 the surface is still a weight against the blur, and
    // at `surfaceAlpha` 1 nothing behind the surface can show, which is what
    // "covers its backdrop" has always meant. Neither can annihilate the other,
    // and they are not multiplied together either.
    //
    // The trap this replaces: with the mix factor carried by the frost, the card
    // at `frost` 1 was the blurred wallpaper outright, so the surface - and with
    // it the opacity knob - was multiplied out of the picture and the slider did
    // nothing at the value the pane's other knob was set to. The composition
    // above is what keeps both knobs live.
    //
    // At `frost` 0 the backdrop is nothing at all, no shader is instantiated
    // anywhere (NCard.qml), and every card is the matte one it has always been
    // at any `surfaceAlpha`.
    //
    // One state to know about, and it is documented rather than clamped:
    // `frost` 0 with `surfaceAlpha` 0 is a card with no backdrop and no surface,
    // i.e. an invisible one. That is the honest reading of both knobs at their
    // floor, it is a state only two deliberate drags reach, and the default
    // `surfaceAlpha` of 1 never reaches it; clamping the surface would take the
    // knob's own meaning away (a card may legitimately be drawn at zero) and
    // would make the pre-frost card a different card. Turning frost up is the
    // way out of it - a frosted card is visible again at `surfaceAlpha` 0.
    //
    // Only `NCard` reads this, and only at `level === 0`: a plate nested inside
    // a frosted card stays opaque, or the step it is there to draw would show
    // wallpaper instead. See NCard.qml and PORTING.md item 20.
    property real frost: 0.0
    // The screen's blurred wallpaper (the host binds it from
    // GlassSurface's FrostLayer), and null wherever there is no screen behind
    // the widget - a launcher preview, the sweep harness, the launcher's own
    // sheet. A null source is a matte card, never a hole: see NCard.
    property Item frostSource: null
    // Bumped by the host on every geometry change. A card's crop of the source
    // above is a mapToItem() call, which notifies nothing on its own, so this is
    // what re-runs it while a widget is dragged or resized.
    property int frostEpoch: 0

    readonly property color surface: Qt.rgba(theme.surfaceSolid.r, theme.surfaceSolid.g,
        theme.surfaceSolid.b, theme.surfaceAlpha * theme.surfaceSolid.a)
    readonly property color surface2: Qt.rgba(theme.surface2Solid.r, theme.surface2Solid.g,
        theme.surface2Solid.b, theme.surfaceAlpha * theme.surface2Solid.a)
    readonly property color surface3: Qt.rgba(theme.surface3Solid.r, theme.surface3Solid.g,
        theme.surface3Solid.b, theme.surfaceAlpha * theme.surface3Solid.a)

    // ── Ink ──────────────────────────────────────────────────────────
    readonly property color on:      _t("foreground", "#FFFFFF")

    // Contrast, in the WCAG form the 4.5:1 floor is defined in: sRGB
    // channel -> linear -> 0.2126/0.7152/0.0722. This is NOT the
    // 0.299/0.587/0.114 expression used elsewhere in the tree, which is a
    // polarity test between two inks rather than a ratio between two
    // surfaces, and is not linearised.
    function _linear(c) {
        return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
    }
    function _luminance(c) {
        return 0.2126 * theme._linear(c.r)
             + 0.7152 * theme._linear(c.g)
             + 0.0722 * theme._linear(c.b)
    }
    function _contrast(a, b) {
        var la = theme._luminance(a)
        var lb = theme._luminance(b)
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
    }
    // `ink` laid over `bg` at `alpha`, composited the way the scene graph
    // composites a translucent colour: the channels blend in sRGB, so the
    // transfer function applies to the blend, not to each end of it.
    function _over(ink, bg, alpha) {
        return Qt.rgba(alpha * ink.r + (1 - alpha) * bg.r,
                       alpha * ink.g + (1 - alpha) * bg.g,
                       alpha * ink.b + (1 - alpha) * bg.b, 1)
    }

    // `onDim`/`onQuiet` are an alpha over `surface`, and the alpha comes from
    // the pair in play rather than from a constant. A constant is calibrated
    // to one pair - the stock #FFFFFF on #0B0B0B - and a followed theme
    // supplies its own: at the fixed 0.55/0.48 the same two inks composite to
    // 2.47:1 and 2.16:1 on rose-pine, 2.53:1 and 2.21:1 on catppuccin-latte,
    // and fail 4.5:1 in 15 and 19 of the 22 installed themes.
    //
    // These two floors are what those fixed alphas already measure on the
    // stock pair, so the stock surface keeps exactly the step it has today
    // while any other surface gets the alpha that reaches the same ratio on
    // *it*. `onFaint` is deliberately not one of them: it is drawn, not read.
    readonly property real dimFloor: 6.261
    readonly property real quietFloor: 4.992

    // The alpha whose composite over `bg` measures `floor`. The composite
    // runs monotonically from `bg` at alpha 0 to `ink` at 1, so bisection
    // lands on it; when `ink` alone cannot reach `floor` it returns 1, the
    // loudest that ink can be. Twenty halvings is a 1e-6 step, far past the
    // 1/255 the renderer resolves, and this re-runs only when the palette
    // does.
    function _inkAlpha(ink, bg, floor) {
        var lo = 0.0, hi = 1.0
        for (var i = 0; i < 20; i++) {
            var mid = (lo + hi) / 2
            if (theme._contrast(theme._over(ink, bg, mid), bg) < floor) lo = mid
            else hi = mid
        }
        return hi
    }

    readonly property color onDim: Qt.rgba(theme.on.r, theme.on.g, theme.on.b,
        theme._inkAlpha(theme.on, theme.surface, theme.dimFloor))
    readonly property color onQuiet: Qt.rgba(theme.on.r, theme.on.g, theme.on.b,
        theme._inkAlpha(theme.on, theme.surface, theme.quietFloor))
    // 0.22 composites to 1.93:1 on the stock surface: decoration, for what is
    // drawn and meant to be unlit. No Text may read it.
    readonly property color onFaint: Qt.rgba(theme.on.r, theme.on.g, theme.on.b, 0.22)

    // ── Accent ───────────────────────────────────────────────────────
    // Restraint is the rule: the red marks state, never decoration. One red
    // thing per widget is usually one too many already.
    readonly property color red: theme.followTheme
        ? _t("accent", theme.accent) : theme.accent
    // The ink drawn on the accent fill.
    //
    // The name is `redInk` and not `onRed` for a hard reason. QML reads
    // `on` + a capital as a *signal handler*, and there is a `red` here for
    // `onRed` to be read as a handler of, so `property color onRed` never
    // became a property: it silently kept QML's default #000000 at every
    // call site, which drew the badge label at 4.05:1 where the intended
    // white is 5.18:1 (plan 040's number). Silent, and no linter flags it -
    // the linter is clean on the dead form.
    //
    // The pick is a measurement rather than a polarity guess. The
    // 0.299/0.587/0.114 rule it used to carry chose white for rose-pine's
    // #56949f (3.42:1) and ethereal's #7d82d9 (3.46:1); taking the better of
    // the two inks never falls below 4.77:1 across the 22 installed themes,
    // and on the stock #D71921 it still picks white, at 5.18:1.
    //
    // The two inks are declared as colours rather than passed as literals: a
    // string handed into a JS helper stays a string, `c.r` on it is
    // undefined, and every comparison against NaN is false - which would
    // quietly pick the light ink for every accent.
    readonly property color _inkDark: "#0B0B0B"
    readonly property color _inkLight: "#FFFFFF"

    readonly property color redInk: theme._contrast(theme._inkDark, theme.red)
                                  >= theme._contrast(theme._inkLight, theme.red)
        ? theme._inkDark : theme._inkLight

    readonly property color outline: theme.followTheme
        ? Qt.rgba(theme.on.r, theme.on.g, theme.on.b, 0.14) : "#2A2A2A"
    readonly property color scrim: Qt.rgba(0, 0, 0, 0.72)

    // ── Geometry ─────────────────────────────────────────────────────
    // Restrained radii: Nothing's cards are rounded, not pill-shaped, and
    // the small elements are nearly square.
    readonly property int rCard: theme.px(22)
    readonly property int rChip: theme.px(10)
    readonly property int rDot: theme.px(2)

    readonly property int gap: theme.px(8)
    readonly property int pad: theme.px(14)
    readonly property int hair: 1

    // ── Type ─────────────────────────────────────────────────────────
    // Deliberately small, with the spacing doing the work. `mono` is the
    // technical readout face; `sans` carries labels and titles.
    // Inter is the reference project's face and is not installed here, so
    // the style ships its own: Barlow, the low-contrast grotesk in the root
    // fonts/ directory, for words; the Nerd Font mono that Omarchy's own bar
    // uses for readouts, so a number in a widget matches a number in the bar.
    property FontLoader _sans: FontLoader { source: Qt.resolvedUrl("../../fonts/barlow_medium.ttf") }
    property FontLoader _sansBold: FontLoader { source: Qt.resolvedUrl("../../fonts/barlow_semibold.ttf") }

    // Off: the bundled Barlow those loaders register. On: the desktop's own
    // font, by the same fontconfig alias the bar itself binds to - a generic
    // name, so `omarchy font set` keeps working with no change here. The
    // loaders stay loaded either way: they are what makes the family name
    // resolvable in the default mode.
    property bool systemFont: false

    readonly property string sans: theme.systemFont
      ? "sans-serif"
      : (theme._sans.status === FontLoader.Ready ? theme._sans.name : "Noto Sans")
    readonly property string sansBold: theme.systemFont
      ? "sans-serif"
      : (theme._sansBold.status === FontLoader.Ready ? theme._sansBold.name : theme.sans)
    // Readouts follow the system face only in system mode. The stock token
    // stays the bar's Nerd Font Mono, so the default look does not move.
    readonly property string mono: theme.systemFont ? "monospace" : "JetBrainsMono Nerd Font"

    readonly property int fMicro: theme.px(9)
    readonly property int fLabel: theme.px(11)
    readonly property int fBody:  theme.px(13)
    readonly property int fTitle: theme.px(18)
    readonly property int fHuge:  theme.px(44)

    // Uppercase metadata is spaced out; body text is not.
    readonly property real trackLabel: theme.px(1.4)

    // ── Motion ───────────────────────────────────────────────────────
    readonly property int fast: 120
    readonly property int med: 220
    readonly property int ease: Easing.OutCubic
}
