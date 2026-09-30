import QtQuick

// The base surface every Nothing widget sits on: matte, hairline outline,
// restrained radius. No shadow, no gradient - the flatness is the style.
Rectangle {
    id: card

    required property var theme

    property bool outlined: true
    // 0 = the panel surface, 1 = one step out from it, 2 = two.
    property int level: 0

    // Frost is a level-0 material and ONLY that: a plate nested inside a frosted
    // card must stay opaque, or the step it is there to draw would show
    // wallpaper where the design means a step. It also needs a screen's blurred
    // wallpaper behind it (`theme.frostSource`), which a launcher preview and
    // the sweep harness deliberately do not have - there the card keeps its own
    // fill and reads exactly as it always has.
    //
    // The gate is `frost` and not the source alone, so the default setting costs
    // nothing at all: at 0 no shader is drawn, no blur is sampled, and the card
    // is the matte one the style has always drawn. `surfaceAlpha` is not part of
    // this gate - it decides how much of the card the surface colour covers, at
    // every frost value including 0, so a card whose frost is off still fades.
    readonly property bool frosted: card.level === 0 && card.theme.frost > 0
                                    && card.theme.frostSource !== null

    // While frosted the fill is handed to NFrost below, which draws the WHOLE
    // material in one pass and so has to own the surface colour as well: the
    // surface cannot be painted here and composited under the frost, because a
    // child draws over its parent - a translucent surface under an opaque blur
    // is the blur painted over the surface, which is exactly the material that
    // lost its opacity knob. `theme.surfaceAlpha` reaches the shader through
    // NFrost instead, where it is the surface's weight against the backdrop.
    //
    // A zero-alpha surface colour rather than the literal "transparent", which
    // renders identically: the Behavior animates the change as an alpha fade of
    // this card's own colour, instead of sliding through black on the way in or
    // out.
    color: card.frosted
         ? Qt.rgba(card.theme.surfaceSolid.r, card.theme.surfaceSolid.g,
                   card.theme.surfaceSolid.b, 0)
         : card.level >= 2 ? card.theme.surface3
         : card.level === 1 ? card.theme.surface2
         : card.theme.surface
    radius: card.theme.rCard
    border.width: card.outlined ? card.theme.hair : 0
    border.color: card.theme.outline
    antialiasing: true

    Behavior on color { ColorAnimation { duration: card.theme.fast } }

    // First child, so it sits under everything a body draws on the card - ink,
    // hairlines, dot matrices - which is what keeps those crisp over the frost
    // without a single widget file knowing this exists.
    //
    // It reads the card's knobs off `theme` rather than being handed them, so
    // the two materials cannot drift: `frost` is the same token this card gates
    // on, and `surfaceAlpha` is the same token the fill above fades by. Its
    // `surface` uniform is the level-0 base plus that alpha, i.e. the fill it
    // replaces, which is why a card crossing this boundary in either direction -
    // frost on, frost off, opacity dragged while frosted - moves by a fade and
    // never by a jump.
    //
    // `visible` follows the fade rather than `frost` alone: an invisible item is
    // not rendered, so a card with frost off costs nothing at all, while the
    // opacity behavior still gives the toggle a cross-fade in BOTH directions.
    // Nothing is sampled here where there is nothing to sample (no source), so
    // the shader never runs against a null backdrop either.
    NFrost {
        anchors.fill: parent
        theme: card.theme
        visible: opacity > 0 && card.theme.frostSource !== null
        opacity: card.frosted ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: card.theme.fast; easing.type: card.theme.ease }
        }
    }
}
