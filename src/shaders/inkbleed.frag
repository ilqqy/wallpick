#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float blurPixels;
    float roughness;
    float pixelWidth;
    float pixelHeight;
    vec4 inkColor;
    vec4 accentColor;
};

layout(binding = 1) uniform sampler2D source;

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise21(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
        mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
        u.y
    );
}

float fibre(vec2 p) {
    return (noise21(p * 0.9) + 0.5 * noise21(p * 1.8 + vec2(4.0, 17.0))) / 1.5;
}

float glyphAlpha(vec2 uv) {
    return texture(source, uv).a;
}

void main() {
    vec2 size = vec2(pixelWidth, pixelHeight);
    vec2 p = qt_TexCoord0 * size;
    float wet = 1.0 - clamp(progress, 0.0, 1.0);

    // The original's word-level turbulence displaces the ink by about 1.6px.
    vec2 fibreOffset = vec2(fibre(p + vec2(4.0, 11.0)), fibre(p + vec2(31.0, 7.0))) - 0.5;
    vec2 uv = qt_TexCoord0 + fibreOffset * roughness * wet / size;
    vec2 stepUv = vec2(blurPixels) / size * 0.54;

    float core = glyphAlpha(uv);
    float diffuse = (
        core * 4.0
        + glyphAlpha(uv + vec2(stepUv.x, 0.0)) * 2.0
        + glyphAlpha(uv - vec2(stepUv.x, 0.0)) * 2.0
        + glyphAlpha(uv + vec2(0.0, stepUv.y)) * 2.0
        + glyphAlpha(uv - vec2(0.0, stepUv.y)) * 2.0
        + glyphAlpha(uv + stepUv)
        + glyphAlpha(uv - stepUv)
        + glyphAlpha(uv + vec2(stepUv.x, -stepUv.y))
        + glyphAlpha(uv + vec2(-stepUv.x, stepUv.y))
    ) / 16.0;

    float body = mix(diffuse, core, progress);
    float bleed = diffuse * wet * 0.50;
    float alpha = clamp((body + bleed) * progress, 0.0, 1.0);
    vec3 color = mix(accentColor.rgb, inkColor.rgb, progress);
    fragColor = vec4(color * alpha, alpha) * qt_Opacity;
}
