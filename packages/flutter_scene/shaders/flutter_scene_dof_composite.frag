// Depth-of-field composite at full resolution: the half-res blurred fields
// (premultiplied by their coverage alpha) composite over the sharp scene
// color. In-focus pixels (coverage 0) take the sharp color untouched, so
// full-resolution focus survives the half-res round trip.

precision highp float;

uniform sampler2D scene_color;
uniform sampler2D dof_texture;

in vec2 v_uv;

out vec4 frag_color;

void main() {
  vec4 sharp = texture(scene_color, v_uv);
  vec4 dof = texture(dof_texture, v_uv);
  frag_color = vec4(dof.rgb + (1.0 - dof.a) * sharp.rgb, sharp.a);
}
