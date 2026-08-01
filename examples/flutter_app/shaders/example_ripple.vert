// Example raw vertex shader, driven by ShaderMaterial. Displaces the mesh
// along its normal with a travelling ripple and hands the fragment stage the
// displacement it applied.
//
// This is the whole engine contract for an unskinned mesh. FrameInfo and the
// instance-rate model_transform columns are bound by the engine; RippleInfo is
// bound from Dart with setUniformBlock(..., stage: ShaderStage.vertex).

uniform FrameInfo {
  mat4 camera_transform;
  vec3 camera_position;
}
frame_info;

uniform RippleInfo {
  float time;
  float amplitude;
  float wavelength;
  float speed;
}
ripple;

in vec3 position;
in vec3 normal;
in vec2 texture_coords;
in vec4 color;

// Instance-rate model matrix columns, bound in the slot after the vertex
// streams. A non-instanced draw gets a single-element buffer.
in vec4 model_transform_0;
in vec4 model_transform_1;
in vec4 model_transform_2;
in vec4 model_transform_3;
in vec4 instance_color;

out vec3 v_position;
out vec3 v_normal;
out vec3 v_viewvector;
out vec2 v_texture_coords;
out vec4 v_color;
out float v_ripple;

void main() {
  mat4 model_transform = mat4(model_transform_0, model_transform_1,
                              model_transform_2, model_transform_3);
  vec4 world_position = model_transform * vec4(position, 1.0);

  float phase = length(world_position.xz) / max(ripple.wavelength, 0.001);
  float wave = sin(phase - ripple.time * ripple.speed);
  vec3 world_normal = normalize(mat3(model_transform) * normal);
  world_position.xyz += world_normal * wave * ripple.amplitude;

  v_position = world_position.xyz;
  v_normal = world_normal;
  v_viewvector = frame_info.camera_position - world_position.xyz;
  v_texture_coords = texture_coords;
  v_color = color * instance_color;
  v_ripple = wave * 0.5 + 0.5;

  gl_Position = frame_info.camera_transform * world_position;
}
