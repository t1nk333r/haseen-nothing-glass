#version 440

// The Nothing style's one GPU pass: a card's own silhouette, filled with the
// style's surface colour over the host's blurred wallpaper.
//
// Both of the style's material knobs land here, and the material is COMPOSED
// from them rather than one being chosen over the other:
//
//   backdrop = mix(nothing, blurred wallpaper, frost)
//   material = mix(backdrop, surface, surface.a)
//
// `surface.a` is NTheme.surfaceAlpha - how much of the card's backdrop the
// surface colour covers - and `frost` is NTheme.frost, how much of that backdrop
// the blurred wallpaper is. Neither can annihilate the other: the surface covers
// its share at every frost value, the wallpaper is behind it at every
// surfaceAlpha, and `frost` 0 leaves the wallpaper out of the material entirely
// (the pass is not even instantiated then - NCard.qml - so the matte card is the
// card, byte for byte).
//
// Nothing-owned, and deliberately small. It shares the two Kawase kernels with
// the glass pipeline (they are pure GLSL and carry no glass semantics), copies
// crop.frag's mapping rather than importing it (this pass also masks), and
// takes nothing else from liquidglass.frag: no refraction or IOR, no
// chromaStrength, no specular pair, no `roundness` 7.5 squircle - the Nothing
// silhouette is a plain rounded rectangle at NTheme.rCard - and above all no
// tint/tintAlpha, whose meaning belongs to the glass material alone. The surface
// colour here is the style's own fill, and the fraction over it is this pass's
// own `surface.a`, not the glass pair. See PORTING.md item 20.
//
// qt_TexCoord0 is card-local UV (0..1); uvOffset/uvScale map card UV to the
// screen's blurred wallpaper UV, exactly as crop.frag maps to the wallpaper.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    vec2  uvOffset;
    vec2  uvScale;
    vec2  size;      // card size in px
    float radius;    // corner radius in px
    float frost;     // how much of the backdrop is the blurred wallpaper
    vec4  surface;   // rgb = the surface colour the card is filled with,
                     // a   = how much of the backdrop that colour covers
};

layout(binding = 1) uniform sampler2D source;

// Signed distance to the rounded rectangle, negative inside. The plain form
// deliberately: a card is a rounded rect, not a squircle, so the glass style's
// superellipse SDF and its analytic gradient stay in liquidglass.frag.
float cardSDF(vec2 p, vec2 halfSize, float r) {
    vec2 q = abs(p) - halfSize + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 wpUV = clamp(uvOffset + uv * uvScale, vec2(0.0), vec2(1.0));
    vec3 blurred = texture(source, wpUV).rgb;

    // The card's backdrop: `frost` of the blurred wallpaper, premultiplied,
    // mixed from nothing at all. At 0 this is zero in every channel whatever the
    // source holds, which is what makes frost 0 the pre-frost card rather than a
    // card that merely looks like one.
    vec4 backdrop = vec4(blurred, 1.0) * frost;

    // The material: the surface colour over the backdrop, the surface's own
    // weight being how much of the backdrop it covers. Written as the mix above;
    // in premultiplied space it is the same expression as
    // `surface + backdrop * (1 - surface.a)`, since the surface colour's own
    // alpha is the 1.0 here.
    vec4 material = mix(backdrop, vec4(surface.rgb, 1.0), surface.a);

    vec2 halfSize = size * 0.5;
    float d = cardSDF(uv * size - halfSize, halfSize,
                      clamp(radius, 0.0, min(halfSize.x, halfSize.y)));
    // 1 px feather centred on the edge, the same form liquidglass.frag uses,
    // and the reason a frosted card must not be rounded by clip:true - a
    // rectangular clip cannot round a corner.
    float mask = 1.0 - smoothstep(-0.5, 0.5, d);

    // Qt Quick blends ShaderEffect output as premultiplied alpha, and the
    // material now carries its own coverage as well as a feathered edge, so the
    // mask scales RGB and alpha together: a fractional-alpha edge pixel carrying
    // full material would blend as a fringe against the wallpaper.
    fragColor = material * mask * qt_Opacity;
}
