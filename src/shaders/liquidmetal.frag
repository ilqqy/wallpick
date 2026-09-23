#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float pixelWidth;
    float pixelHeight;
    float time;
    float rimWidth;
    float prism;
    float hoverAmount;
    float sheenPhase;
    float pressedAmount;
};

const float TAU = 6.28318530718;

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise21(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x);
    float b = mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), u.x);
    return mix(a, b, u.y);
}

float turbulence(vec2 p) {
    return (noise21(p) + 0.5 * noise21(p * 2.0)) / 1.5;
}

float roundedBox(vec2 p, vec2 halfSize, float radius) {
    vec2 q = abs(p) - halfSize + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

vec3 metal(float t) {
    t = fract(t);
    if (t < 0.08) return mix(vec3(0.965, 0.973, 0.984), vec3(0.682, 0.714, 0.753), t / 0.08);
    if (t < 0.20) return mix(vec3(0.682, 0.714, 0.753), vec3(0.337, 0.365, 0.404), (t - 0.08) / 0.12);
    if (t < 0.30) return mix(vec3(0.337, 0.365, 0.404), vec3(0.804, 0.831, 0.863), (t - 0.20) / 0.10);
    if (t < 0.40) return mix(vec3(0.804, 0.831, 0.863), vec3(1.0), (t - 0.30) / 0.10);
    if (t < 0.52) return mix(vec3(1.0), vec3(0.600, 0.631, 0.671), (t - 0.40) / 0.12);
    if (t < 0.64) return mix(vec3(0.600, 0.631, 0.671), vec3(0.263, 0.290, 0.325), (t - 0.52) / 0.12);
    if (t < 0.74) return mix(vec3(0.263, 0.290, 0.325), vec3(0.776, 0.804, 0.839), (t - 0.64) / 0.10);
    if (t < 0.84) return mix(vec3(0.776, 0.804, 0.839), vec3(0.965, 0.973, 0.984), (t - 0.74) / 0.10);
    if (t < 0.92) return mix(vec3(0.965, 0.973, 0.984), vec3(0.545, 0.576, 0.616), (t - 0.84) / 0.08);
    return mix(vec3(0.545, 0.576, 0.616), vec3(0.965, 0.973, 0.984), (t - 0.92) / 0.08);
}

vec3 spectrum(float t) {
    t = fract(t) * 7.0;
    if (t < 1.0) return mix(vec3(1.0, 0.176, 0.333), vec3(1.0, 0.584, 0.0), t);
    if (t < 2.0) return mix(vec3(1.0, 0.584, 0.0), vec3(1.0, 0.839, 0.039), t - 1.0);
    if (t < 3.0) return mix(vec3(1.0, 0.839, 0.039), vec3(0.204, 0.780, 0.349), t - 2.0);
    if (t < 4.0) return mix(vec3(0.204, 0.780, 0.349), vec3(0.0, 0.780, 0.745), t - 3.0);
    if (t < 5.0) return mix(vec3(0.0, 0.780, 0.745), vec3(0.039, 0.518, 1.0), t - 4.0);
    if (t < 6.0) return mix(vec3(0.039, 0.518, 1.0), vec3(0.749, 0.353, 0.949), t - 5.0);
    return mix(vec3(0.749, 0.353, 0.949), vec3(1.0, 0.176, 0.333), t - 6.0);
}

void main() {
    vec2 size = vec2(pixelWidth, pixelHeight);
    vec2 uv = qt_TexCoord0;
    vec2 p = uv * size - size * 0.5;
    float d = roundedBox(p, size * 0.5, pixelHeight * 0.5);
    float outside = 1.0 - smoothstep(-0.5, 0.5, d);
    float inside = 1.0 - smoothstep(-0.5, 0.5, d + rimWidth);
    float rim = max(0.0, outside - inside);

    // The source displaces two conic layers with two-octave SVG turbulence.
    // Deform the sampling coordinates, leaving the rounded ring mask stable.
    float cycle = 0.5 + 0.5 * sin(time * TAU / 18.0);
    vec2 freq = mix(vec2(0.012, 0.018), vec2(0.018, 0.012), cycle);
    vec2 samplePoint = (p + size * 0.5) * freq + vec2(4.0, 7.0);
    vec2 displacement = vec2(
        turbulence(samplePoint),
        turbulence(samplePoint + vec2(17.2, 41.7))
    );
    vec2 liquidP = p + (displacement - 0.5) * 6.0;
    float angle = atan(liquidP.y, liquidP.x) / TAU + 0.5;
    float spin = time / 6.0;
    vec3 chrome = metal(angle - spin);
    vec3 chroma = spectrum(angle + spin * 1.5);
    vec3 ringColor = 1.0 - (1.0 - chrome) * (1.0 - chroma * prism);

    vec3 top = vec3(0.110, 0.110, 0.118);
    vec3 bottom = vec3(0.055, 0.055, 0.059);
    vec3 face = mix(top, bottom, uv.y);
    face += vec3(0.045) * exp(-abs(d + rimWidth + 1.0) * 1.8) * inside;
    face *= 1.0 - pressedAmount * 0.08;

    // A one-shot diagonal specular sweep on hover mirrors the CSS sheen.
    float sheenCenter = 1.5 - sheenPhase * 2.0;
    float sheenX = uv.x + (uv.y - 0.5) * 0.14;
    float sheen = 1.0 - smoothstep(0.0, 0.16, abs(sheenX - sheenCenter));
    sheen *= hoverAmount * 0.34;
    vec3 color = mix(face, ringColor, rim / max(outside, 0.0001));
    color = 1.0 - (1.0 - color) * (1.0 - vec3(sheen));

    fragColor = vec4(color * outside, outside) * qt_Opacity;
}
