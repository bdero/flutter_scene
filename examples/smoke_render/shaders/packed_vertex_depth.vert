// The position-only twin of packed_vertex.vert, assigned with
// Geometry.setDepthOnlyVertex. The depth-style passes bind only the first
// stream (slot 0) and a 64-byte model transform record (slot 1). The
// varyings are written to match the depth fragment shaders' interface; only
// the position ones carry data.

uniform FrameInfo {
  mat4 camera_transform;
  vec3 camera_position;
}
frame_info;

in vec3 position;

in vec4 model_transform_0;
in vec4 model_transform_1;
in vec4 model_transform_2;
in vec4 model_transform_3;

out vec3 v_position;
out vec3 v_normal;
out vec3 v_viewvector;
out vec2 v_texture_coords;
out vec2 v_texture_coords_1;
out vec4 v_color;
out vec4 v_tangent;

void main() {
  mat4 model_transform = mat4(model_transform_0, model_transform_1,
                              model_transform_2, model_transform_3);
  vec4 world_position = model_transform * vec4(position, 1.0);
  v_position = world_position.xyz;
  v_normal = vec3(0.0);
  v_viewvector = frame_info.camera_position - world_position.xyz;
  v_texture_coords = vec2(0.0);
  v_texture_coords_1 = vec2(0.0);
  v_color = vec4(0.0);
  v_tangent = vec4(0.0);
  gl_Position = frame_info.camera_transform * world_position;
}
