#version 440
layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;
layout(std140,binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 viewport;
    float time;
    float front;
    vec4 orbitGeometry;
} u;
void main() {
    // Identical projection and phase on both desktop surfaces. Depth fades at
    // the two crossings, so a luminous arc passes smoothly behind the cards.
    vec2 p=qt_TexCoord0*u.viewport-u.orbitGeometry.xy;
    p=mat2(0.951,0.309,-0.309,0.951)*p;
    vec2 axes=u.orbitGeometry.zw;
    vec2 q=p/axes;
    float angle=atan(q.y,q.x);
    float distance=(length(q)-1.0)*min(axes.x,axes.y);
    float depth=smoothstep(-0.12,0.12,sin(angle));
    float layer=u.front>0.5 ? depth : 1.0-depth;
    float travel=atan(sin(angle-u.time*0.48),cos(angle-u.time*0.48));
    float pulse=exp(-travel*travel*5.0);
    float strands=0.65+0.35*sin(angle*47.0-u.time*3.0);
    float core=exp(-distance*distance/2.4);
    float halo=exp(-distance*distance/120.0);
    float a=(core*0.42+halo*0.08)*(0.12+pulse*0.88)*layer*strands*u.qt_Opacity;
    vec3 color=mix(vec3(1.0,0.43,0.15),vec3(1.0,0.88,0.73),core);
    fragColor=vec4(color*a,a);
}
