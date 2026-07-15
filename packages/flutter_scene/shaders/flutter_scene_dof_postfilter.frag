// Depth-of-field postfilter, a 3x3 tent over the half-res gather output.
// Smooths the residual undersampling noise of the fixed gather kernel (the
// engine has no temporal pass to hide it), at the cost of slightly softer
// bokeh edges.

precision highp float;

uniform sampler2D dof_texture;

uniform PostFilterInfo {
  // xy: half-res texel size   zw: unused
  vec4 params0;
}
postfilter_info;

in vec2 v_uv;

out vec4 frag_color;

void main() {
  vec2 t = postfilter_info.params0.xy;
  vec4 sum = vec4(0.0);
  sum += texture(dof_texture, v_uv + vec2(-t.x, -t.y));
  sum += texture(dof_texture, v_uv + vec2(0.0, -t.y)) * 2.0;
  sum += texture(dof_texture, v_uv + vec2(t.x, -t.y));
  sum += texture(dof_texture, v_uv + vec2(-t.x, 0.0)) * 2.0;
  sum += texture(dof_texture, v_uv) * 4.0;
  sum += texture(dof_texture, v_uv + vec2(t.x, 0.0)) * 2.0;
  sum += texture(dof_texture, v_uv + vec2(-t.x, t.y));
  sum += texture(dof_texture, v_uv + vec2(0.0, t.y)) * 2.0;
  sum += texture(dof_texture, v_uv + vec2(t.x, t.y));
  frag_color = sum / 16.0;
}
