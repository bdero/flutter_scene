// Vertex shader for skinned moving objects rendering deformation velocity.
//
// Reads current joints texture and previous frame joints texture to compute
// current and previous deformed clip positions.

uniform VelocityFrameInfo {
  mat4 current_view_projection;
  mat4 previous_view_projection;
  vec4 current_previous_jitter; // xy: current jitter NDC, zw: previous jitter NDC
} frame_info;

uniform VelocitySkinnedModelInfo {
  mat4 current_model_transform;
  mat4 previous_model_transform;
  float current_joint_texture_size;
  float previous_joint_texture_size;
  float enable_skinning;
  float padding;
} model_info;

uniform sampler2D current_joints_texture;
uniform sampler2D previous_joints_texture;

in vec3 position;
in vec4 joints;
in vec4 weights;

out vec4 v_current_clip;
out vec4 v_previous_clip;
out vec4 v_static_clip;

const int kMatrixTexelStride = 4;

mat4 GetJoint(sampler2D tex, float tex_size, float joint_index) {
  float texel_size_uv = 1.0 / tex_size;
  float matrix_start = joint_index * float(kMatrixTexelStride);
  float x = mod(matrix_start, tex_size);
  float y = floor(matrix_start / tex_size);
  y = (y + 0.5) * texel_size_uv;
  return mat4(
    texture(tex, vec2((x + 0.5) * texel_size_uv, y)),
    texture(tex, vec2((x + 1.5) * texel_size_uv, y)),
    texture(tex, vec2((x + 2.5) * texel_size_uv, y)),
    texture(tex, vec2((x + 3.5) * texel_size_uv, y))
  );
}

void main() {
  vec4 pos = vec4(position, 1.0);
  vec4 cur_deformed = pos;
  vec4 prev_deformed = pos;

  if (model_info.enable_skinning > 0.5) {
    mat4 cur_skin =
      GetJoint(current_joints_texture, model_info.current_joint_texture_size, joints.x) * weights.x +
      GetJoint(current_joints_texture, model_info.current_joint_texture_size, joints.y) * weights.y +
      GetJoint(current_joints_texture, model_info.current_joint_texture_size, joints.z) * weights.z +
      GetJoint(current_joints_texture, model_info.current_joint_texture_size, joints.w) * weights.w;

    mat4 prev_skin =
      GetJoint(previous_joints_texture, model_info.previous_joint_texture_size, joints.x) * weights.x +
      GetJoint(previous_joints_texture, model_info.previous_joint_texture_size, joints.y) * weights.y +
      GetJoint(previous_joints_texture, model_info.previous_joint_texture_size, joints.z) * weights.z +
      GetJoint(previous_joints_texture, model_info.previous_joint_texture_size, joints.w) * weights.w;

    cur_deformed = cur_skin * pos;
    prev_deformed = prev_skin * pos;
  }

  vec4 cur_world = model_info.current_model_transform * cur_deformed;
  vec4 prev_world = model_info.previous_model_transform * prev_deformed;

  v_current_clip = frame_info.current_view_projection * cur_world;
  v_previous_clip = frame_info.previous_view_projection * prev_world;
  v_static_clip = frame_info.previous_view_projection * cur_world;

  gl_Position = v_current_clip;
}
