uniform VertexInfo {
  mat4 mvp;
} vertex_info;

in vec3 position;
in vec2 texture_coords;
in vec4 color;
out vec2 v_texture_coords;
out vec4 v_color;

void main() {
  v_texture_coords = texture_coords;
  v_color = color;
  gl_Position = vertex_info.mvp * vec4(position, 1.0);
}
