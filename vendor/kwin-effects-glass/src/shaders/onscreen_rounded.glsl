#include "sdf.glsl"

uniform sampler2D texUnit;
uniform mat4 colorMatrix;
uniform float offset;
uniform vec2 halfpixel;
uniform vec4 box;
uniform vec4 cornerRadius;
uniform float opacity;
uniform int glassEnabled;
uniform int scrimMode;
uniform float scrimCap;
uniform float scrimDecay;
uniform sampler2D scrimLumaTex;
uniform int scrimLumaValid;

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
        // Contrast scrim: a black or white fill whose opacity rises with the
        // backdrop's proximity to the opposite extreme, so light-on-light and
        // dark-on-dark content both stay legible. Only the extreme ramps:
        // curveLo/Hi sit near the top of the range, so nothing happens across
        // mid-tones. The scale happens toward the danger end:
        //   black tint -> brighter backdrop darkens,
        //   white tint -> darker backdrop lifts.
        // cap is an absolute ceiling, decay a per-surface scaler on top.
        if (scrimMode > 0) {
            // One value for the whole surface: the compositor reduces the
            // backdrop to a 1x1 average and feeds it here, so every fragment
            // of the surface shares the same scrim tone. Per-pixel backdrop
            // luminance made a variegated wallpaper band a panel into uneven
            // light/dark blocks; a single average keeps it uniform.
            float lum = 0.5;
            if (scrimLumaValid == 1)
                lum = dot(texture(scrimLumaTex, vec2(0.5)).rgb,
                          vec3(0.299, 0.587, 0.114));
            float damage = (scrimMode == 2) ? (1.0 - lum) : lum;
            float amount = smoothstep(0.40, 0.85, damage);
            // A floor of a small fraction of cap keeps the scrim from
            // collapsing fully to invisible on a backdrop that already matches
            // the tint; scaling with cap means see-through levels still stay
            // nearly transparent while readable ones hold a faint presence.
            float scrimAlpha = clamp(max(amount * scrimDecay, 0.06 * scrimCap),
                                     0.0, scrimCap);
            vec3 tint = (scrimMode == 2) ? vec3(1.0) : vec3(0.0);
            sum.rgb = mix(sum.rgb, tint, scrimAlpha);
        }
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
