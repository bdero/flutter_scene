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

void main() {
  vec4 vertex_color = mix(vec4(1), v_color, frag_info.vertex_color_weight);
  frag_color = texture(base_color_texture, v_texture_coords) * vertex_color *
               frag_info.color;
}
