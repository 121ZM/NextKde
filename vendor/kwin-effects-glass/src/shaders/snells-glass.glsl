vec4 processSnellSample(sampler2D tex, vec2 baseUv, vec3 glassNormal,
    float ior, float dispersion, float magnitude, vec2 uvScale,
    vec2 lensShift)
{
    vec3 viewRay = vec3(0.0, 0.0, -1.0);
    vec3 refracted = refract(viewRay, glassNormal, 1.0 / ior);
    vec2 direction = length(refracted.xy) > 0.001
        ? normalize(refracted.xy) : vec2(0.0);
    // Keep the refraction local to the glass edge. The shape's edge width
    // controls where this is visible, not how far the backdrop can be pulled.
    // Clamp every channel after combining the optical and positional shifts so
    // a large panel or a high offset-strength setting cannot create a repeated
    // wallpaper-sized smear.
    vec2 maxShift = uvScale * 12.0;
    vec2 shiftG = clamp(direction * magnitude * uvScale + lensShift,
                         -maxShift, maxShift);
    vec4 sampleG = texture(tex, clamp(baseUv + shiftG, 0.0, 1.0));

    if (dispersion > 0.001) {
        float fringe = clamp(dispersion, 0.0, 1.0) * 0.3;
        vec2 shiftR = clamp(direction * (magnitude * (1.0 + fringe)) * uvScale
                            + lensShift, -maxShift, maxShift);
        vec2 shiftB = clamp(direction * (magnitude * (1.0 - fringe)) * uvScale
                            + lensShift, -maxShift, maxShift);
        float red = texture(tex, clamp(baseUv + shiftR, 0.0, 1.0)).r;
        float blue = texture(tex, clamp(baseUv + shiftB, 0.0, 1.0)).b;
        return vec4(red, sampleG.g, blue, sampleG.a);
    }
    return sampleG;
}

GlassFragment snellsRefraction(vec2 position, vec2 halfShapeSize,
    vec4 cornerRadius, float minHalfSize, float dist, float edgeFactor,
    float concaveFactor)
{
    float bandWidth = clamp(edgeSizePixels, 0.1, minHalfSize * 0.9);
    float ior = 1.0 + refractionStrength;

    float minRadius = min(min(cornerRadius.x, cornerRadius.y),
        min(cornerRadius.z, cornerRadius.w));
    float epsilon = min(bandWidth * 0.75, minRadius * 0.6);
    float dxp = roundedRectangleDist(position + vec2(epsilon, 0.0),
        halfShapeSize, cornerRadius);
    float dxn = roundedRectangleDist(position - vec2(epsilon, 0.0),
        halfShapeSize, cornerRadius);
    float dyp = roundedRectangleDist(position + vec2(0.0, epsilon),
        halfShapeSize, cornerRadius);
    float dyn = roundedRectangleDist(position - vec2(0.0, epsilon),
        halfShapeSize, cornerRadius);
    vec2 smoothGradient = vec2(dxp - dxn, dyp - dyn);
    float gradientLength = length(smoothGradient);

    float normalHeight = concaveFactor * refractionBevelIntensity;
    vec2 normalXY = gradientLength > 0.001
        ? (smoothGradient / gradientLength) * normalHeight : vec2(0.0);
    vec3 glassNormal = normalize(vec3(normalXY, 1.0));

    // `bandWidth` is solely the width of the liquid edge. It used to multiply
    // the displacement as well, so widening an edge could turn into hundreds
    // of pixels of refraction. Keep the lens visible but strictly local.
    float lensMagnitude = min(concaveFactor * refractionBevelIntensity * 6.0,
        10.0);
    vec2 surfaceNormal = gradientLength > 0.001
        ? smoothGradient / gradientLength : vec2(1.0, 0.0);

    // The lens field belongs to this protocol shape, while UV conversion
    // belongs to the shared offscreen texture. Main used one blurSize for
    // both because it could only draw one window-wide shape.
    vec2 normalizedPosition = position / max(halfShapeSize * 2.0, vec2(1.0));
    float cornerWeight = dot(normalizedPosition, normalizedPosition)
        * refractionOffsetStrength;
    surfaceNormal += normalizedPosition * concaveFactor * cornerWeight;

    // halfpixel is 0.5 / textureSize in the KWin pass.
    vec2 pixelUv = halfpixel * 2.0;
    vec2 lensDirection = length(surfaceNormal) > 0.001
        ? normalize(surfaceNormal) : vec2(0.0);
    vec2 lensShift = -lensDirection * lensMagnitude * pixelUv;
    float refractionMagnitude = lensMagnitude * refractionStrength;
    vec4 color = processSnellSample(texUnit, uv, glassNormal, ior,
        refractionRGBFringing, refractionMagnitude, pixelUv, lensShift);

    return GlassFragment(color, dist, edgeFactor, concaveFactor,
        glassNormal, ior);
}
