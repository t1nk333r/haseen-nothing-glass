#version 440

// Horizontal Gaussian blur — 9 bilinear taps covering 17 texels.
//
// Sigma is derived from radiusPx (sigma = radiusPx / 3) so the kernel
// shape stays correct at any radius. Bilinear tap optimization merges
// adjacent texel pairs: each hardware read blends two texels, and the
// tap offset is placed between them weighted by their Gaussian values.
// This gives 17-texel coverage from only 9 texture reads.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float radiusPx;
    vec2  sourceSizePx;
};

layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 uv = qt_TexCoord0;
    float px = 1.0 / sourceSizePx.x;

    float sigma = max(radiusPx / 3.0, 0.001);
    float s2 = 2.0 * sigma * sigma;

    // Compute raw Gaussian weights at texel offsets 0..8
    float g0 = 1.0;
    float g1 = exp(-1.0  / s2);
    float g2 = exp(-4.0  / s2);
    float g3 = exp(-9.0  / s2);
    float g4 = exp(-16.0 / s2);
    float g5 = exp(-25.0 / s2);
    float g6 = exp(-36.0 / s2);
    float g7 = exp(-49.0 / s2);
    float g8 = exp(-64.0 / s2);

    // Bilinear merge: pair (1,2), (3,4), (5,6), (7,8)
    float w0 = g0;
    float w12 = g1 + g2;
    float w34 = g3 + g4;
    float w56 = g5 + g6;
    float w78 = g7 + g8;

    // Bilinear tap offsets (in texels): weighted average of pair positions
    float o12 = (1.0 * g1 + 2.0 * g2) / w12;
    float o34 = (3.0 * g3 + 4.0 * g4) / w34;
    float o56 = (5.0 * g5 + 6.0 * g6) / w56;
    float o78 = (7.0 * g7 + 8.0 * g8) / w78;

    vec4 c = texture(source, uv) * w0;

    c += texture(source, uv + vec2(o12 * px, 0.0)) * w12;
    c += texture(source, uv - vec2(o12 * px, 0.0)) * w12;

    c += texture(source, uv + vec2(o34 * px, 0.0)) * w34;
    c += texture(source, uv - vec2(o34 * px, 0.0)) * w34;

    c += texture(source, uv + vec2(o56 * px, 0.0)) * w56;
    c += texture(source, uv - vec2(o56 * px, 0.0)) * w56;

    c += texture(source, uv + vec2(o78 * px, 0.0)) * w78;
    c += texture(source, uv - vec2(o78 * px, 0.0)) * w78;

    c /= (w0 + 2.0 * (w12 + w34 + w56 + w78));

    fragColor = c * qt_Opacity;
}
