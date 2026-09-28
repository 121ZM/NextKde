#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D depthMap;
layout(location = 1) in float relativeDepth;

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

void main()
{
    float sampledDepth = texture(depthMap, qt_TexCoord0).r;
    if (abs(sampledDepth - relativeDepth) > 0.12)
        discard;
    fragColor = texture(source, clamp(qt_TexCoord0, vec2(0.0), vec2(1.0)))
        * ubuf.qt_Opacity;
}
