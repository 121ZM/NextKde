// Cast from the orbiting camera toward the nearest visible depth surface.
// A far hit inside the subject's original footprint is a newly uncovered
// background pixel, so it must sample the reconstructed background.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D depthMap;
layout(binding = 3) uniform sampler2D background;
layout(binding = 4) uniform sampler2D matte;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 pointer;
    vec2 cropScale;
    vec2 aspectFov;
    vec2 orbitAngles;
    float hasBackground;
} ubuf;

const float farDistance = 3.3;
const float depthSpan = 1.3;
const float cropMargin = 0.05;
const int marchSteps = 12;

vec2 croppedUv(vec2 uv)
{
    return vec2(0.5) + (uv - vec2(0.5))
        * ubuf.cropScale * (1.0 - 2.0 * cropMargin);
}

vec2 projectToImage(vec3 point)
{
    float distance = max(0.01, -point.z);
    float halfWidth = distance * ubuf.aspectFov.y * ubuf.aspectFov.x;
    float halfHeight = distance * ubuf.aspectFov.y;
    return vec2(0.5 + point.x / (2.0 * halfWidth),
                0.5 - point.y / (2.0 * halfHeight));
}

float surfaceZ(vec2 uv)
{
    vec2 textureUv = croppedUv(uv);
    float depth = texture(depthMap, textureUv).r;
    // The depth model smooths silhouettes. A valid subject matte keeps those
    // pixels in front of the reconstructed background at the boundary.
    if (ubuf.hasBackground > 0.5)
        depth = max(depth, texture(matte, textureUv).r * 0.72);
    return -(farDistance - clamp(depth, 0.0, 1.0) * depthSpan);
}

bool insideImage(vec2 uv)
{
    return all(greaterThanEqual(uv, vec2(0.0)))
        && all(lessThanEqual(uv, vec2(1.0)));
}

void main()
{
    vec2 screen = qt_TexCoord0 * 2.0 - vec2(1.0);
    screen.y = -screen.y;
    float centerDepth = texture(depthMap, croppedUv(vec2(0.5))).r;
    float focusDistance = farDistance - centerDepth * depthSpan;
    vec3 focus = vec3(0.0, 0.0, -focusDistance);

    vec2 pointer = clamp(ubuf.pointer, vec2(-1.0), vec2(1.0));
    if (length(pointer) > 1.0)
        pointer = normalize(pointer);
    float yaw = pointer.x * ubuf.orbitAngles.x;
    float pitch = -pointer.y * ubuf.orbitAngles.y;
    vec3 eye = vec3(sin(yaw) * cos(pitch) * focusDistance,
                    sin(pitch) * focusDistance,
                    -focusDistance + cos(yaw) * cos(pitch) * focusDistance);
    vec3 forward = normalize(focus - eye);
    vec3 right = normalize(cross(forward, vec3(0.0, 1.0, 0.0)));
    vec3 up = normalize(cross(right, forward));
    vec3 ray = normalize(forward
        + right * (screen.x * ubuf.aspectFov.x * ubuf.aspectFov.y)
        + up * (screen.y * ubuf.aspectFov.y));

    float rayZ = min(-0.05, ray.z);
    float nearZ = -(farDistance - depthSpan) + 0.04;
    float farZ = -farDistance - 0.04;
    float clearZ = nearZ;
    float hitZ = farZ;
    vec2 imageUv = vec2(0.5);
    bool hitSource = false;
    // Stop at the first intersection. Fixed-point iteration can converge on
    // the far surface across a depth jump and expose a second silhouette.
    for (int iteration = 0; iteration <= marchSteps; ++iteration) {
        float z = mix(nearZ, farZ, float(iteration) / float(marchSteps));
        vec3 point = eye + ray * ((z - eye.z) / rayZ);
        vec2 uv = projectToImage(point);
        if (!insideImage(uv))
            continue;
        if (z <= surfaceZ(uv)) {
            hitZ = z;
            imageUv = uv;
            hitSource = true;
            break;
        }
        clearZ = z;
    }
    if (hitSource) {
        // Refine the frontmost crossing without jumping to a farther layer.
        for (int iteration = 0; iteration < 3; ++iteration) {
            float z = (clearZ + hitZ) * 0.5;
            vec2 uv = projectToImage(eye + ray * ((z - eye.z) / rayZ));
            if (insideImage(uv) && z <= surfaceZ(uv))
                hitZ = z;
            else
                clearZ = z;
        }
        imageUv = projectToImage(eye + ray * ((hitZ - eye.z) / rayZ));
    }

    vec3 color;
    if (hitSource && insideImage(imageUv)) {
        vec2 textureUv = croppedUv(imageUv);
        float matteValue = ubuf.hasBackground > 0.5
            ? texture(matte, textureUv).r : 0.0;
        float surfaceDistance = abs(hitZ - surfaceZ(imageUv));
        if (ubuf.hasBackground > 0.5 && matteValue > 0.2
            && surfaceDistance > 0.15)
            color = texture(background, textureUv).rgb;
        else
            color = texture(source, textureUv).rgb;
    } else if (ubuf.hasBackground > 0.5) {
        float backgroundDistance = max(0.01,
            (-farDistance - eye.z) / rayZ);
        vec2 backgroundUv = projectToImage(eye + ray * backgroundDistance);
        color = texture(background, croppedUv(clamp(backgroundUv,
            vec2(0.001), vec2(0.999)))).rgb;
    } else {
        color = texture(source, croppedUv(clamp(imageUv,
            vec2(0.001), vec2(0.999)))).rgb;
    }
    fragColor = vec4(color, 1.0) * ubuf.qt_Opacity;
}
