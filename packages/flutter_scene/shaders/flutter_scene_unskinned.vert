uniform FrameInfo {
  mat4 camera_transform;
  vec3 camera_position;
}
frame_info;

// This attribute layout is expected to be identical to that within
// `impeller/scene/importer/scene.fbs`.
in vec3 position;
in vec3 normal;
in vec2 texture_coords;
in vec4 color;

// Instance-rate model matrix columns (vertex buffer slot 1, advanced once
// per instance). Non-instanced draws bind a single-element buffer holding
// the node's world transform.
in vec4 model_transform_0;
in vec4 model_transform_1;
in vec4 model_transform_2;
in vec4 model_transform_3;

out vec3 v_position;
out vec3 v_normal;
out vec3 v_viewvector; // camera_position - vertex_position
out vec2 v_texture_coords;
out vec4 v_color;

void main() {
  mat4 model_transform = mat4(model_transform_0, model_transform_1,
                              model_transform_2, model_transform_3);
  vec4 model_position = model_transform * vec4(position, 1.0);
  v_position = model_position.xyz;
  gl_Position = frame_info.camera_transform * model_position;
  v_viewvector = frame_info.camera_position - v_position;
  v_normal = (mat3(model_transform) * normal).xyz;
  v_texture_coords = texture_coords;
  v_color = color;
}
