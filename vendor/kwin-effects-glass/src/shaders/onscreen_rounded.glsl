#include "sdf.glsl"

uniform sampler2D texUnit;
uniform mat4 colorMatrix;
uniform float offset;
uniform vec2 halfpixel;
uniform vec4 box;
uniform vec4 cornerRadius;
uniform float opacity;
uniform int glassEnabled;

in vec2 uv;
in vec2 vertex;
#include "glass.glsl"
#include "oklab.glsl"

void main(void)
{
    // Same field as the cut below, evaluated from the fragment's own position
    // relative to the box centre. It used to be reconstructed as
    // "uv * blurSize - blurSize * 0.5", which is a rounded rectangle centred on
    // the *texture* and mirrored in y; that only agreed with the box when the
    // box was the whole texture, so any other stage -- and every protocol shape
    // but the first -- would have gate and cut disagreeing.
    // KWin's vertex space and the sampled texture have opposite Y axes.
    // Keep the material field in texture orientation, so the deliberately
    // stronger top glint is actually painted at the visual top.
    vec2 position = vec2(vertex.x - box.x, box.y - vertex.y);
    float dist = roundedRectangleDist(position, box.zw, cornerRadius);

    vec4 sum = vec4(0);
    if (dist <= 0.0) {
        sum = texture(texUnit, uv + vec2(-halfpixel.x * 2.0, 0.0) * offset);
        sum += texture(texUnit, uv + vec2(-halfpixel.x, halfpixel.y) * offset) * 2.0;
        sum += texture(texUnit, uv + vec2(0.0, halfpixel.y * 2.0) * offset);
        sum += texture(texUnit, uv + vec2(halfpixel.x, halfpixel.y) * offset) * 2.0;
        sum += texture(texUnit, uv + vec2(halfpixel.x * 2.0, 0.0) * offset);
        sum += texture(texUnit, uv + vec2(halfpixel.x, -halfpixel.y) * offset) * 2.0;
        sum += texture(texUnit, uv + vec2(0.0, -halfpixel.y * 2.0) * offset);
        sum += texture(texUnit, uv + vec2(-halfpixel.x, -halfpixel.y) * offset) * 2.0;
        sum /= 12.0;
    }

    if (glassEnabled == 1) {
        sum = glass(sum, cornerRadius, position, box.zw);
        // One field, one cut: reusing dist is not a shortcut but the point --
        // gate and cut can no longer drift apart per stage.
        float df = fwidth(dist);
        sum *= 1.0 - clamp(0.5 + dist / df, 0.0, 1.0);
    }

    if (glassEnabled == 1 && useOklabSaturation == 1) {
        sum.rgb = oklabSaturate(sum.rgb, saturation);
    }

    fragColor = glassEnabled == 1
        ? sum * colorMatrix * opacity
        : sum * opacity;
}
