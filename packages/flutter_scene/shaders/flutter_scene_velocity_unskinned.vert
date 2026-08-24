// Vertex shader for unskinned moving objects rendering velocity.
//
// Computes current NDC position, previous NDC position under previous world
// transform and camera projection, and static previous NDC position under
// current world transform and previous camera projection.

uniform VelocityFrameInfo {
  mat4 current_view_projection;
  mat4 previous_view_projection;
  vec4 current_previous_jitter; // xy: current jitter NDC, zw: previous jitter NDC
} frame_info;

uniform VelocityModelInfo {
  mat4 current_model_transform;
  mat4 previous_model_transform;
} model_info;

in vec3 position;

in vec4 model_transform_0;
in vec4 model_transform_1;
in vec4 model_transform_2;
in vec4 model_transform_3;

out vec4 v_current_clip;
out vec4 v_previous_clip;
out vec4 v_static_clip;

void main() {
  mat4 cur_model = mat4(model_transform_0, model_transform_1,
                        model_transform_2, model_transform_3);
  vec4 cur_world = cur_model * vec4(position, 1.0);
  vec4 prev_world = model_info.previous_model_transform * vec4(position, 1.0);

  v_current_clip = frame_info.current_view_projection * cur_world;
  v_previous_clip = frame_info.previous_view_projection * prev_world;
  v_static_clip = frame_info.previous_view_projection * cur_world;

  gl_Position = v_current_clip;
}

