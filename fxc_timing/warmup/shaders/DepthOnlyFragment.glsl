#version 300 es
precision mediump float;
precision highp int;

layout(location = 0) out highp vec4 frag_color;

void main()
{
    frag_color = vec4(gl_FragCoord.z, 0.0, 0.0, 1.0);
}

