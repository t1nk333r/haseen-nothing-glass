#version 440

// Liquid-glass fragment shader — Snell-on-a-dome refraction + mouse specular.
//
// Ported from iyinchao/liquid-glass-studio's fragment-main.glsl with extras.
// Key ideas:
//   * Edge refraction uses Snell's law through a dome-shaped bevel:
//         sinθI = (1 - t)^2      where t = 0..1 across the edge band
//         θT    = asin(sinθI / IOR)
//         mag   = tan(θI - θT)   // lateral shift of the refracted ray
//   * SDF gradient is kept UNNORMALIZED and its magnitude is reused as a
//     corner-AA gate on the specular.
//   * Chromatic dispersion: R/B sampled at an extra offset along the
//     refraction direction, scaled by how deep we are in the edge band.
//   * Mouse specular: radial gaussian glow centered on mousePos (in
//     widget-local UV), boosted where the SDF gradient points toward the
//     mouse (fake "curvature facing the light").
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
    float specRadiusPx;      // radius of the specular glow in px
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

// Mouse specular: gaussian halo around mousePos, with a small anisotropic
// bump that leans the highlight toward the surface facing the mouse
// (dot product with the SDF normal direction).
vec3 mouseSpec(vec2 localUV, vec2 ndir) {
    if (mouseFade <= 0.0 || specStrength <= 0.0) return vec3(0.0);
    if (mousePos.x < 0.0 || mousePos.y < 0.0) return vec3(0.0);

    // Distance from this fragment to the mouse, in widget pixels.
    vec2 toMousePx = (mousePos - localUV) * size;
    float distPx = length(toMousePx);

    // Gaussian-ish falloff: exp(-x^2 / r^2). Half strength at ~0.6*radius.
    float r = max(1.0, specRadiusPx);
    float base = exp(-(distPx * distPx) / (r * r));

    // Directional lean: fragments whose outward normal points roughly
    // toward the mouse get a lightness boost, simulating a convex lens
    // reflecting the "light" positioned at the mouse. This is subtle on
    // the interior (normal is undefined there) and strongest at the lip.
    vec2 toMouseDir = distPx > 0.001 ? (toMousePx / distPx) : vec2(0.0);
    float facing = clamp(dot(ndir, -toMouseDir), 0.0, 1.0);
    float lean = pow(facing, 2.0) * 0.6;

    float intensity = base * (0.7 + lean) * specStrength * mouseFade;

    // Slightly warm white so it reads as "light" not "flash".
    return vec3(1.0, 0.98, 0.94) * intensity;
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
    vec2 ndir = vec2(0.0);
    float depthPx = -d;

    if (depthPx >= refractThickness) {
        // Interior: flat glass (pass-through + tint), no refraction.
        col = sampleBackdrop(uv);
        col = mix(col, tint.rgb, tint.a);

        // Normal direction is still useful for the spec lean; approximate
        // it from the gradient even though the gradient is ~0 in the deep
        // interior (lean term harmlessly goes to 0).
        vec2 grad = sceneGradient(p);
        float gradLen = length(grad);
        ndir = gradLen > 1e-4 ? grad / gradLen : vec2(0.0);
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
        ndir = gradLen > 1e-4 ? grad / gradLen : vec2(0.0);

        vec2 displacePx = -ndir * edgeMag * refractScale;
        vec2 displaceUV = displacePx / size;

        float edgeWeight = 1.0 - t;
        float chromaPx = chromaStrength * refractThickness * 0.35 * edgeWeight;
        vec2 chromaUV = -ndir * chromaPx / size;

        col.r = sampleBackdrop(uv + displaceUV + chromaUV).r;
        col.g = sampleBackdrop(uv + displaceUV).g;
        col.b = sampleBackdrop(uv + displaceUV - chromaUV).b;

        col = mix(col, tint.rgb, tint.a);
    }

    // Mouse specular — additive, applied to both interior and edge paths.
    col += mouseSpec(uv, ndir);

    // Final AA mask at the silhouette.
    float mask = 1.0 - smoothstep(-1.0, 0.0, d);
    fragColor = vec4(col, mask) * qt_Opacity;
}
