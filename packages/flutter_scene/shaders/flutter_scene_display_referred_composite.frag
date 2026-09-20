#version 460 core

// Composites the display-referred layer over the resolved image.
//
// Both inputs are display-encoded and premultiplied by alpha, so this is a
// plain source-over. The layer is drawn past the tone curve precisely so its
// colors are not transformed again here.

precision highp float;

uniform sampler2D display_color;
uniform sampler2D display_referred_color;

in vec2 v_uv;

out vec4 frag_color;

void main() {
  vec4 base = texture(display_color, v_uv);
  vec4 layer = texture(display_referred_color, v_uv);
  frag_color = layer + base * (1.0 - layer.a);
}
