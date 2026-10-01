// Vertex shader for unskinned moving objects rendering velocity.
//
// Computes current NDC position, previous NDC position under previous world
// transform and camera projection, and static previous NDC position under
// current world transform and previous camera projection.

uniform VelocityFrameInfo {
  mat4 current_view_projection;
  mat4 previous_view_projection;
  vec4 current_previous_jitter; // xy: current jitter NDC, zw: previous jitter NDC
  vec4 camera_position;         // xyz: world-space eye
} frame_info;

uniform VelocityModelInfo {
  mat4 current_model_transform;
  mat4 previous_model_transform;
  // The material's depth-layer offset, matching the depth prepass this pass
  // tests against with equal (see ApplyDepthOffset).
  vec4 depth_offset;
  vec4 depth_bias; // x: Material.depthBias
} model_info;

#include <depth_bias.glsl>

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

  // Rasterize exactly where the depth prepass did, so the equal test holds
  // for a biased or layered surface. Motion reads the unbiased clips above;
  // the bias moves along the eye ray and the layer touches only depth.
  vec3 draw_position = ApplyDepthBias(
      cur_world.xyz, frame_info.current_view_projection,
      frame_info.camera_position.xyz, model_info.depth_bias.x);
  vec4 clip_position =
      frame_info.current_view_projection * vec4(draw_position, 1.0);
  gl_Position = ApplyDepthOffset(
      clip_position, model_info.depth_offset,
      InstanceDepthRank(model_transform_3.xyz),
      DepthRoundingSteps(clip_position, frame_info.current_view_projection,
                         draw_position, frame_info.camera_position.xyz));
}

