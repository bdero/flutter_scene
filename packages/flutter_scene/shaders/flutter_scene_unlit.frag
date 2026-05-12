uniform FragInfo {
  vec4 color;
  float vertex_color_weight;
}
frag_info;

uniform sampler2D base_color_texture;

in vec3 v_position;
in vec3 v_normal;
in vec3 v_viewvector; // camera_position - vertex_position
in vec2 v_texture_coords;
in vec4 v_color;

out vec4 frag_color;

const float kGamma = 2.2;
vec3 SRGBToLinear(vec3 color) { return pow(color, vec3(kGamma)); }

void main() {
  vec4 vertex_color = mix(vec4(1), v_color, frag_info.vertex_color_weight);
  vec4 base = texture(base_color_texture, v_texture_coords);
  // Linearize the sRGB-encoded base color so what we write to the
  // floating-point scene-color target is linear; the tone-mapping resolve
  // pass re-applies the display EOTF. Output is premultiplied by alpha.
  vec3 rgb = SRGBToLinear(base.rgb) * vertex_color.rgb * frag_info.color.rgb;
  float alpha = base.a * vertex_color.a * frag_info.color.a;
  frag_color = vec4(rgb, 1.0) * alpha;
}
