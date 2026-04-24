#version 440

// Liquid-glass fragment shader — Snell-on-a-dome refraction + corner specular.
//
// Ported from iyinchao/liquid-glass-studio's fragment-main.glsl with extras.
// Key ideas:
//   * Edge refraction uses Snell's law through a dome-shaped bevel:
//         sinθI = (1 - t)^2      where t = 0..1 across the edge band
//         θT    = asin(sinθI / IOR)
//         mag   = tan(θI - θT)   // lateral shift of the refracted ray
//   * SDF gradient is kept UNNORMALIZED and its magnitude is reused as a
//     corner-AA gate.
//   * Chromatic dispersion: R/B sampled at an extra offset along the
//     refraction direction, scaled by how deep we are in the edge band.
//   * Corner specular: on hover, the two corners on the diagonal nearest
//     the cursor light up; brightness tapers exponentially along the
//     border from each apex; applied on the outer lip only.
//
// qt_TexCoord0 is widget-local UV (0..1).
// uvOffset/uvScale map widget UV -> wallpaper UV.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    vec2  size;              // widget size in px
    float radius;            // corner radius in px
    float roundness;         // superellipse exponent; 2 = circle, 5 ≈ iOS squircle
    float refractThickness;  // edge band width in px
    float refractIOR;
    float refractScale;
    float chromaStrength;    // 0..1 chromatic aberration
    vec4  tint;
    vec2  uvOffset;
    vec2  uvScale;
    vec2  mousePos;          // widget-local UV (0..1); (-1,-1) = no mouse
    float mouseFade;         // 0..1 hover fade
    float specRadiusPx;      // corner specular arc-length taper in px
    float specStrength;      // 0..1 intensity
};

layout(binding = 1) uniform sampler2D backdrop;

// --- Shape SDF: superellipse-cornered rounded rect (squircle) ---

float superellipseCorner(vec2 p, float r, float n) {
    p = abs(p);
    float v = pow(pow(p.x, n) + pow(p.y, n), 1.0 / n);
    return v - r;
}

float sceneSDF(vec2 p) {
    vec2 b = size * 0.5;
    float r = radius;
    vec2 d = abs(p) - b;
    if (d.x > -r && d.y > -r) {
        vec2 cornerCenter = sign(p) * (b - vec2(r));
        vec2 cp = p - cornerCenter;
        return superellipseCorner(cp, r, roundness);
    }
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2(0.0)));
}

vec2 sceneGradient(vec2 p) {
    float dx = sceneSDF(p + vec2(1.0, 0.0)) - sceneSDF(p - vec2(1.0, 0.0));
    float dy = sceneSDF(p + vec2(0.0, 1.0)) - sceneSDF(p - vec2(0.0, 1.0));
    return vec2(dx, dy);
}

vec3 sampleBackdrop(vec2 localUV) {
    vec2 wpUV = clamp(uvOffset + localUV * uvScale, vec2(0.0), vec2(1.0));
    return texture(backdrop, wpUV).rgb;
}

// Corner border specular. Thin stroke on the silhouette with per-corner
// prominence: dominant corner (nearest cursor) full, diagonal opposite
// half, the other two minimal. Slight feather.
vec3 cornerSpec(vec2 p, float depthPx) {
    if (mouseFade <= 0.0 || specStrength <= 0.0) return vec3(0.0);
    if (mousePos.x < 0.0 || mousePos.y < 0.0) return vec3(0.0);

    // Hard cap on stroke thickness at the dominant apex, in px.
    const float MAX_STROKE_PX = 3.0;
    const float DOMINANT     = 1.0;  // the single nearest corner
    const float DIAGONAL     = 0.5;  // its diagonal opposite
    const float OTHER        = 0.12; // the other two corners (thin)

    vec2 b = size * 0.5;
    vec2 mousePx = (mousePos - vec2(0.5)) * size;

    // Corner apexes (outer-rectangle corners).
    vec2 aTL = vec2(-b.x,  b.y);
    vec2 aTR = vec2( b.x,  b.y);
    vec2 aBL = vec2(-b.x, -b.y);
    vec2 aBR = vec2( b.x, -b.y);

    // Softmax over the four corners to pick the dominant one without a
    // hard pop when the cursor crosses an axis. The sharpness constant
    // determines how decisively the nearest corner wins; larger = harder.
    float sharp = 1.0 / (max(size.x, size.y) * 0.30);
    float dTL = distance(mousePx, aTL);
    float dTR = distance(mousePx, aTR);
    float dBL = distance(mousePx, aBL);
    float dBR = distance(mousePx, aBR);
    float wTL = exp(-dTL * sharp);
    float wTR = exp(-dTR * sharp);
    float wBL = exp(-dBL * sharp);
    float wBR = exp(-dBR * sharp);
    float wSum = wTL + wTR + wBL + wBR + 1e-6;
    wTL /= wSum; wTR /= wSum; wBL /= wSum; wBR /= wSum;

    // Per-corner prominence is a softmax-weighted blend of the three
    // roles (dominant / diagonal / other). Each corner sees itself as
    // dominant with weight w_self, the opposite diagonal as diagonal
    // with weight w_opp, and the other two as "other".
    float promTL = wTL*DOMINANT + wBR*DIAGONAL + (wTR + wBL)*OTHER;
    float promTR = wTR*DOMINANT + wBL*DIAGONAL + (wTL + wBR)*OTHER;
    float promBL = wBL*DOMINANT + wTR*DIAGONAL + (wTL + wBR)*OTHER;
    float promBR = wBR*DOMINANT + wTL*DIAGONAL + (wTR + wBL)*OTHER;

    // Arc-length attenuation along the border from each apex.
    float taper = max(1.0, specRadiusPx);
    float aTLa = exp(-distance(p, aTL) / taper);
    float aTRa = exp(-distance(p, aTR) / taper);
    float aBLa = exp(-distance(p, aBL) / taper);
    float aBRa = exp(-distance(p, aBR) / taper);

    // Effective stroke thickness at this fragment. Take the max so
    // contributions don't double up.
    float tPx = 0.0;
    tPx = max(tPx, promTL * aTLa * MAX_STROKE_PX);
    tPx = max(tPx, promTR * aTRa * MAX_STROKE_PX);
    tPx = max(tPx, promBL * aBLa * MAX_STROKE_PX);
    tPx = max(tPx, promBR * aBRa * MAX_STROKE_PX);

    // Render the stroke with a 2px feather on the inner lip so it
    // reads as a softened hairline rather than a hard slab.
    const float FEATHER_PX = 2.0;
    float stroke = 1.0 - smoothstep(tPx - FEATHER_PX, tPx, depthPx);

    // Global tone-down multiplier so the effect stays subtle even at
    // specStrength = 1.0.
    float I = stroke * specStrength * mouseFade * 0.55;
    return vec3(1.0, 0.98, 0.94) * I;
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 p  = (uv - vec2(0.5)) * size;
    float d = sceneSDF(p);

    // Outside the shape: fully transparent.
    if (d > 0.5) {
        fragColor = vec4(0.0);
        return;
    }

    vec3 col;
    float depthPx = -d;

    if (depthPx >= refractThickness) {
        // Interior: flat glass (pass-through + tint), no refraction.
        col = sampleBackdrop(uv);
        col = mix(col, tint.rgb, tint.a);
    } else {
        // --- Edge band: Snell on a dome ---
        float t = depthPx / refractThickness;
        float sinThetaI = (1.0 - t) * (1.0 - t);
        float thetaI = asin(clamp(sinThetaI, 0.0, 1.0));
        float sinThetaT = sinThetaI / refractIOR;
        float thetaT = asin(clamp(sinThetaT, 0.0, 1.0));
        float edgeMag = tan(thetaI - thetaT);

        vec2 grad = sceneGradient(p);
        float gradLen = length(grad);
        vec2 ndir = gradLen > 1e-4 ? grad / gradLen : vec2(0.0);

        vec2 displacePx = -ndir * edgeMag * refractScale;
        vec2 displaceUV = displacePx / size;

        float edgeWeight = 1.0 - t;
        float chromaPx = chromaStrength * refractThickness * 0.35 * edgeWeight;
        vec2 chromaUV = -ndir * chromaPx / size;

        col.r = sampleBackdrop(uv + displaceUV + chromaUV).r;
        col.g = sampleBackdrop(uv + displaceUV).g;
        col.b = sampleBackdrop(uv + displaceUV - chromaUV).b;

        col = mix(col, tint.rgb, tint.a);

        // Corner specular — hairline stroke on the silhouette (self-gated
        // by its own stroke-thickness test in depthPx).
        col += cornerSpec(p, depthPx);
    }

    // Final AA mask at the silhouette.
    float mask = 1.0 - smoothstep(-1.0, 0.0, d);
    fragColor = vec4(col, mask) * qt_Opacity;
}
