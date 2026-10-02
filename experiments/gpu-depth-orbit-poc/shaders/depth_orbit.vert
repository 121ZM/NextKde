#version 440

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 qt_TexCoord0;
layout(binding = 2) uniform sampler2D depthMap;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 pointer;
    vec2 viewSize;
    float depthSpan;
    float farDistance;
    float orbitYaw;
    float orbitPitch;
} ubuf;
layout(location = 1) out float relativeDepth;

void main()
{
    const float overscan = 0.06;
    const float halfFov = radians(42.0) * 0.5;
    vec2 uv = qt_MultiTexCoord0 * (1.0 + 2.0 * overscan)
        - vec2(overscan);
    vec2 ndc = uv * 2.0 - 1.0;
    vec2 textureUv = vec2(uv.x, 1.0 - uv.y);
    float depth = textureLod(depthMap, clamp(textureUv, vec2(0.0), vec2(1.0)), 0.0).r;
    float pivotDepth = textureLod(depthMap, vec2(0.5), 0.0).r;
    float pivotZ = ubuf.farDistance - pivotDepth * ubuf.depthSpan;
    float z = ubuf.farDistance - depth * ubuf.depthSpan;
    float aspect = ubuf.viewSize.x / max(ubuf.viewSize.y, 1.0);
    float tangent = tan(halfFov);
    vec3 point = vec3(ndc.x * z * tangent * aspect,
                      ndc.y * z * tangent,
                      z);
    vec2 tilt = ubuf.pointer / max(1.0, length(ubuf.pointer));
    float yaw = tilt.x * radians(ubuf.orbitYaw);
    float pitch = -tilt.y * radians(ubuf.orbitPitch);
    float radius = pivotZ;
    vec3 focus = vec3(0.0, 0.0, pivotZ);
    vec3 eye = vec3(sin(yaw) * cos(pitch) * radius,
                    sin(pitch) * radius,
                    pivotZ - cos(yaw) * cos(pitch) * radius);
    vec3 forward = normalize(focus - eye);
    vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), forward));
    vec3 cameraUp = normalize(cross(forward, right));
    vec3 relative = point - eye;
    float cameraZ = max(dot(relative, forward), 0.001);
    float focal = ubuf.viewSize.y / (2.0 * tangent);
    vec2 screen = ubuf.viewSize * 0.5
        + vec2(focal * dot(relative, right) / cameraZ,
               -focal * dot(relative, cameraUp) / cameraZ);
    gl_Position = ubuf.qt_Matrix * vec4(screen, 0.0, 1.0);
    qt_TexCoord0 = textureUv;
    relativeDepth = depth;
}
