import QtQuick

QtObject {
    id: macColors

    // Two orthogonal axes:
    //   styleMode:  0 = Glass (translucent shader), 1 = Solid (opaque fill),
    //               2 = Solid, following the host theme's palette,
    //               3 = Glass, following the host theme's palette
    //   appearance: 0 = Dark, 1 = Light, 2 = Follow system
    //
    // The two "theme" modes keep the same geometry and the same shader as
    // 0/1 and only swap where the colours come from: instead of the fixed
    // macOS palette they read `themePalette` below. Light/dark stops being a
    // user choice there - the theme's own background decides.
    property int styleMode: 0
    property int appearance: 0

    readonly property bool useSystem: appearance === 2

    // Host-supplied background colour, used only to decide whether the system
    // theme is dark when `appearance` is "Follow system". Plasma passes
    // Kirigami.Theme.backgroundColor; Quickshell passes the Omarchy theme's
    // Color.background. Defaults to dark so an unset host still behaves.
    property color systemBackground: "#1c1c1e"

    readonly property bool systemIsDark: {
        var bg = systemBackground
        var luminance = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b
        return luminance < 0.5
    }
    // Host theme palette, optional. Quickshell passes the Omarchy theme's
    // Color tokens; Plasma passes nothing today, and a null palette makes the
    // theme modes fall back to the macOS palette, so a host that never sets
    // this behaves exactly as before.
    //
    // Shape: { background, foreground, accent, urgent, surface } - all
    // colour strings. Missing keys fall back per-token.
    property var themePalette: null

    readonly property bool isThemed: styleMode === 2 || styleMode === 3
    readonly property bool isGlass: styleMode === 0 || styleMode === 3
    readonly property bool isSolid: styleMode === 1 || styleMode === 2

    function _theme(key, fallback) {
        var p = macColors.themePalette
        if (!p) return fallback
        var v = p[key]
        return (v === undefined || v === null || v === "") ? fallback : v
    }

    readonly property color themeBackground: _theme("background", "#1c1c1e")
    readonly property color themeForeground: _theme("foreground", "#ffffff")
    readonly property color themeAccent:     _theme("accent", "#0a84ff")
    readonly property color themeUrgent:     _theme("urgent", "#FF3B30")
    readonly property color themeSurface:    _theme("surface", themeBackground)

    // A themed mode inherits the theme's own polarity: a light Omarchy theme
    // makes the widgets light, in glass as well as solid. That is the whole
    // point of "follow theme", and it is why isLight is no longer hard-false
    // for every glass mode.
    readonly property bool themeIsLight: {
        var bg = themeBackground
        return (0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b) >= 0.5
    }

    readonly property bool isLight: isThemed
        ? themeIsLight
        : (!isGlass && (appearance === 1 || (useSystem && !systemIsDark)))

    readonly property color background: isThemed ? themeBackground : (isLight ? "#f2f2f7" : "#1c1c1e")
    readonly property color surface:    isThemed ? themeSurface    : (isLight ? "#ffffff" : "#2c2c2e")
    readonly property color surfaceAlt: isThemed
        ? Qt.rgba(themeForeground.r, themeForeground.g, themeForeground.b, 0.12)
        : (isLight ? "#e5e5ea" : "#3a3a3c")

    readonly property color labelPrimary:    isLight ? "#000000" : "#ffffff"
    readonly property color labelSecondary:  isLight ? "#3c3c43" : "#ebebf5"
    readonly property color labelTertiary:   isLight ? "#3c3c4399" : "#ebebf599"
    readonly property color labelQuaternary: isLight ? "#3c3c432e" : "#ebebf52e"

    readonly property color accent: isThemed ? themeAccent : "#0a84ff"

    // The lowest opacity informative text may be drawn at - the 0.55 the
    // already readable widgets used. WCAG fixes no number for text over a
    // photograph, so this is a floor and anything dimmer is decoration, not a
    // value.
    readonly property real textQuiet: 0.55

    // How far a secondary annotation on the widget's own face is dimmed: the
    // quiet floor in glass, no dimming at all in solid, whose opaque face
    // carries full ink. A widget asks for this rather than branching on
    // `isGlass` itself (AGENTS.md's token rule) - a second copy of the pick
    // in the widget is what compounded the city annotations to a ghost.
    readonly property real annotationOpacity: isGlass ? textQuiet : 1.0

    // Ink a widget draws on its own face, one token per role. A glass face is
    // translucent and everything behind it shows through, so ink is drawn at
    // the role's own opacity; a solid face is opaque and takes the other arm.
    // One token per role rather than one token with parameters, because the
    // roles differ - most of them in BOTH arms - and one value would be wrong
    // for two of them. The dial's numerals and its hands are not the same
    // softening (0.85 against 0.92 in glass), and the city label's secondary
    // line is not a softening at all in solid: it takes a 0.6 step DOWN from
    // its 1.0 primary there, where the arm is a text hierarchy rather than the
    // glass face's wash.
    readonly property real dialNumeralOpacity:   isGlass ? 0.85 : 1.0
    readonly property real dialHandOpacity:      isGlass ? 0.92 : 1.0
    readonly property real citySecondaryOpacity: isGlass ? 0.85 : 0.6

    // The faint static marks a clock face draws its ink over. Two roles
    // because the glass arms differ by what sits among the marks: an analog
    // dial's perimeter ticks flank its hour marks and read as part of the dial
    // (0.24), where a digital clock's sixty-tick ring is texture under a comet
    // trail (0.18). Both go to 0.30 on the opaque face, where the wash that
    // dims them in glass is gone.
    readonly property real dialTickOpacity:      isGlass ? 0.24 : 0.30
    readonly property real tickRingOpacity:      isGlass ? 0.18 : 0.30

    // What a digital clock draws its own time in. `readoutOpacity` is the
    // quiet floor in glass, where the big type is meant to be read through,
    // and full ink on the opaque face - the same two arms `annotationOpacity`
    // takes, as its own token because this is the tile's content and not a
    // caption on it. The rolling seconds cylinder (`test-timer`) is one digit
    // and nothing else on the face, so it carries its own pair: a step
    // brighter in glass, and stopping at 0.92 rather than going to full ink on
    // the opaque face.
    readonly property real readoutOpacity:        isGlass ? textQuiet : 1.0
    readonly property real rollingReadoutOpacity: isGlass ? 0.62 : 0.92

    readonly property color separator: isLight ? "#3c3c4336" : "#54545899"

    // Glass mode tint — translucent overlay sampled by the shader. A themed
    // glass tints with the theme's own background instead of plain black or
    // white, which is what makes it read as the same desktop.
    readonly property color glassTint: isThemed
        ? themeBackground
        : (isLight ? "#ffffff" : "#000000")
    readonly property real  glassTintAlpha: isLight ? 0.60 : 0.32
    readonly property real  glassFallbackOpacity: isLight ? 0.72 : 0.55

    // Solid mode palette — opaque fill plus contrasting foreground.
    readonly property color solidBackground: isThemed ? themeBackground : (isLight ? "#ffffff" : "#1A1B1E")
    readonly property color solidForeground: isThemed ? themeForeground : (isLight ? "#1A1B1E" : "#ffffff")

    // Tuned reds for the today badge in Solid mode (Glass keeps it white).
    readonly property color accentRed: isThemed ? themeUrgent : (isLight ? "#D70015" : "#FF3B30")

    // The second alarm step, for a value that is a warning and not yet a
    // fault - the Claude usage tiles' `severity: "warning"` and their 50-79%
    // band, which the phone widget and the SwiftBar plugin both draw amber.
    // A token rather than a literal at the call site, like every colour here.
    //
    // It cannot follow the theme the way accentRed does: the Omarchy palette
    // carries `urgent` but nothing between it and the accent, and inventing a
    // second theme key for one widget would be a worse lie than a fixed amber.
    // Apple's own systemOrange, on the same light/dark pair the red above
    // uses, so the two alarms keep their relationship in either appearance.
    readonly property color accentAmber: isLight ? "#FF9500" : "#FF9F0A"

    // The headroom ink: a live figure well clear of its limit. The Claude
    // usage tiles draw each window's percentage in this, and only a window at
    // or over the warning band takes amber or red - so the colour of the
    // number is the state, at a glance, which is what the phone widget does
    // and what the desktop tile now mirrors.
    //
    // Apple's systemGreen in the dark appearance; deeper in the light one,
    // where #34C759 on a pale panel measures under 3:1 and stops reading as
    // a figure. Same treatment accentRed gets above, for the same reason.
    readonly property color accentGreen: isLight ? "#17803D" : "#30D158"

    // Per-widget override: set to true/false to force foreground polarity
    // independent of appearance. Null means use the normal isLight logic.
    property var foregroundDarkOverride: null

    // The family the widget's words are set in: the fontconfig alias the bar
    // binds to, so `omarchy font set` drives the glass widgets too. It used to
    // be a per-widget choice between that alias and the bundled SF Pro
    // Display, registered by a FontLoader in the widget body; the Apple faces
    // are gone (fonts/LICENSES.md), so there is no second face left to switch
    // to and no `systemFont` input here any more. The plugin-wide
    // `settings.systemFont` still selects a face for the Nothing style, which
    // has Barlow to fall back to. Weight is never encoded: the call sites ask
    // for it with font.weight.
    readonly property string uiFont: "sans-serif"

    readonly property bool effectiveLight: foregroundDarkOverride !== null
        ? !foregroundDarkOverride
        : isLight

    // Foreground used by widget content. Glass stays monochromatic white
    // so the translucent shader keeps its existing look regardless of
    // appearance; Solid follows light/dark inversion.
    readonly property color foreground: isThemed
        ? themeForeground
        : (isGlass ? "#ffffff" : (effectiveLight ? "#1A1B1E" : "#ffffff"))

    // Today/highlight accent: white in Glass (monochrome) and red in Solid.
    readonly property color todayAccent: isThemed ? themeAccent : (isGlass ? "#ffffff" : accentRed)

    // Badge punch-out: glass uses destination-out compositing, solid uses normal text.
    // Punch-out only works when the text is meant to be the backdrop showing
    // through, i.e. monochrome glass. A themed glass paints real colours.
    readonly property bool punchOutText: isGlass && !isThemed

    // Analog dial plate: the contrasting disc the marks and hands sit on.
    // Glass keeps a faint wash so the refraction still reads; solid needs a
    // real plate. Modes 0/1 reproduce the literals the ported clocks used to
    // carry (#ffffff / #343436), which is why this is a token and not a new
    // look. `dialPlateDay/Night` are the per-city day/night discs.
    //
    // A day/night disc is a POLARITY, not a lightness step on the page
    // background: the day disc is the theme's own light end, the night disc
    // its dark end, and the ink on each is the opposite end. Deriving both
    // ends from `themeSurface` alone lost exactly that on a dark theme —
    // `lighter(surface)` is still dark there, and `dialMarkDay` was the page
    // background — so a day dial was a dark disc with dark ink: measured on
    // tokyo-night, the day dial carried 222 ink px above luminance 90 against
    // the night dial's 1640 in the same frame, and the city code on it was
    // illegible. The non-themed literals are untouched, and `dialPlate` (the
    // 1x1 / clock-analog disc, which picks its end by `isLight` and so always
    // had a matching pair) is unchanged value-for-value in every mode.
    readonly property color _dialPlateLight: themeIsLight ? Qt.lighter(themeSurface, 1.30) : themeForeground
    readonly property color _dialPlateDark:  themeIsLight ? themeForeground : Qt.darker(themeSurface, 1.30)

    readonly property color dialPlateDay:   isThemed ? _dialPlateLight : "#ffffff"
    readonly property color dialPlateNight: isThemed ? _dialPlateDark  : "#343436"
    readonly property color dialPlate: isGlass
        ? (isThemed
            ? Qt.rgba(themeForeground.r, themeForeground.g, themeForeground.b, 0.20)
            : Qt.rgba(1, 1, 1, 0.20))
        : (isLight ? dialPlateDay : dialPlateNight)
    // Text drawn ON the dial plate, so it inverts with it.
    readonly property color dialMarkDay:   isThemed ? _dialPlateDark  : "#1A1B1E"
    readonly property color dialMarkNight: isThemed ? _dialPlateLight : "#ffffff"
    // The mark ink for a dial whose disc is `dialPlate`: the same `isLight`
    // pick made above, as one token. A widget that draws those marks must not
    // spell the pick out itself (AGENTS.md's token rule) - a second copy of it
    // is a second thing to forget the next time an end here changes.
    readonly property color dialMark: isLight ? dialMarkDay : dialMarkNight

    // Card backgrounds — white on dark modes, black on light solid mode.
    readonly property color cardBackground: isThemed ? themeForeground : (isLight ? "#000000" : "#ffffff")
    readonly property real  cardBackgroundOpacity: isLight ? 0.08 : 0.10
    readonly property real  cardHoverOpacity:      isLight ? 0.14 : 0.17
    readonly property real  cardPressOpacity:      isLight ? 0.20 : 0.22

    // Timer action colors — solid-filled in glass, tinted in solid.
    readonly property color countdownText: isThemed ? themeAccent : (isGlass ? "#ffffff" : "#FF8B00")
    readonly property color actionGreen:    "#00A832"
    readonly property color actionOrange:   "#FF8E00"
    readonly property color buttonIcon: isThemed ? themeForeground : (isGlass ? "#ffffff" : solidForeground)
    readonly property color cancelButtonBg: isThemed
        ? Qt.rgba(themeForeground.r, themeForeground.g, themeForeground.b, isGlass ? 0.25 : 0.12)
        : (isGlass
            ? Qt.rgba(1, 1, 1, 0.25)
            : Qt.rgba(solidForeground.r, solidForeground.g, solidForeground.b, 0.12))
    readonly property color actionGreenBg: isThemed
        ? Qt.rgba(themeAccent.r, themeAccent.g, themeAccent.b, isGlass ? 1.0 : 0.18)
        : (isGlass ? "#00A832" : Qt.rgba(0, 0.659, 0.196, 0.18))
    readonly property color actionOrangeBg: isThemed
        ? Qt.rgba(themeAccent.r, themeAccent.g, themeAccent.b, isGlass ? 0.75 : 0.14)
        : (isGlass ? "#FF8E00" : Qt.rgba(1, 0.557, 0, 0.18))

    // The ink for the icon on an action disc, i.e. on a fill of `actionGreenBg`
    // / `actionOrangeBg`: glass fills that disc with the action colour itself,
    // so the icon rides white on it; an opaque face fills it with an 18% wash
    // of the same colour, so the icon takes the colour at full strength and
    // stays legible against the wash. `stateColor` is the widget's own pick
    // between `actionGreen` and `actionOrange` (the timer's running and paused
    // states) - a function because the style arm is this file's and the state
    // arm is not, and a widget may not spell the style arm out itself.
    function actionIconInk(stateColor) {
        return isGlass ? "#ffffff" : stateColor
    }

    // ── Weather tokens ────────────────────────────────────────────────
    property string weatherGradientCategory: "clear"

    readonly property color weatherGradientTop: {
        if (isGlass) return "transparent"
        // A themed solid paints the sky from the theme, not from photographs
        // of one: the category still shifts it, but within the palette.
        if (isThemed) return Qt.lighter(themeBackground, 1.45)
        var cat = weatherGradientCategory
        if (cat === "clear")       return "#5188BD"
        if (cat === "cloudy")      return "#8E9EAF"
        if (cat === "rain")        return "#607B8A"
        if (cat === "storm")       return "#3A3A4A"
        if (cat === "snow")        return "#B0C4DE"
        if (cat === "fog")         return "#9CA3AF"
        if (cat === "nightclear")  return "#1A1A3E"
        if (cat === "nightcloudy") return "#2C3040"
        return "#5188BD"
    }

    readonly property color weatherGradientBottom: {
        if (isGlass) return "transparent"
        if (isThemed) return themeBackground
        var cat = weatherGradientCategory
        if (cat === "clear")       return "#194E84"
        if (cat === "cloudy")      return "#4A5568"
        if (cat === "rain")        return "#2C3E50"
        if (cat === "storm")       return "#1A1A2E"
        if (cat === "snow")        return "#708090"
        if (cat === "fog")         return "#6B7280"
        if (cat === "nightclear")  return "#0D0D2B"
        if (cat === "nightcloudy") return "#1A1E2A"
        return "#194E84"
    }

    // Music widget — secondary text (artist name, time labels)
    // Use explicit RGBA values here instead of deriving channels from another
    // color property; QML can coerce those through a string path and collapse
    // the channel reads to black in dark/glass modes.
    readonly property color musicSecondary: isThemed
        ? Qt.rgba(themeForeground.r, themeForeground.g, themeForeground.b, 0.55)
        : ((isGlass ? false : effectiveLight)
            ? Qt.rgba(0.102, 0.106, 0.118, 0.55)
            : Qt.rgba(1, 1, 1, 0.55))

    readonly property color weatherForeground: isThemed ? themeForeground : "#ffffff"
    readonly property string weatherIconSet: (isGlass && !isThemed) ? "mono-light" : "default"

    // Chrome that used to be hard white: in a themed mode it has to ride on
    // the theme's foreground, or a light theme paints white on white.
    readonly property color _weatherChrome: isThemed ? themeForeground : Qt.rgba(1, 1, 1, 1)
    readonly property color weatherSeparator: Qt.rgba(_weatherChrome.r, _weatherChrome.g, _weatherChrome.b, isGlass ? 0.15 : 0.20)
    readonly property color weatherRangeBarBg: Qt.rgba(_weatherChrome.r, _weatherChrome.g, _weatherChrome.b, isGlass ? 0.12 : 0.15)
    readonly property color weatherRangeBarFill: Qt.rgba(_weatherChrome.r, _weatherChrome.g, _weatherChrome.b, isGlass ? 0.50 : 0.60)
}
