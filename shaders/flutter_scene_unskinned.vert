uniform FrameInfo {
  mat4 mvp;
  vec3 camera_position;
}
frame_info;

// This attribute layout is expected to be identical to that within
// `impeller/scene/importer/scene.fbs`.
in vec3 position;
in vec3 normal;
in vec2 texture_coords;
in vec4 color;

out vec3 v_position;
out vec3 v_normal;
out vec3 v_viewvector; // camera pos - vertex pos
out vec2 v_texture_coords;
out vec4 v_color;

void main() {
  gl_Position = frame_info.mvp * vec4(position, 1.0);
  v_position = gl_Position.xyz;
  v_normal = normal;
  v_viewvector = frame_info.camera_position - v_position;
  v_texture_coords = texture_coords;
  v_color = color;
}
