uniform sampler2D tex;

in vec2 v_texture_coords;
in vec4 v_color;
out vec4 frag_color;

void main() {
  frag_color = v_color * texture(tex, v_texture_coords);
}
