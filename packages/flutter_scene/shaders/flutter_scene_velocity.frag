// Fragment shader for VelocityPass.
//
// Outputs object-space motion delta beyond camera motion in RG, and 1.0 mask in B.

uniform VelocityFrameInfo {
  mat4 current_view_projection;
  mat4 previous_view_projection;
  vec4 current_previous_jitter; // xy: current jitter NDC, zw: previous jitter NDC
} frame_info;

in vec4 v_current_clip;
in vec4 v_previous_clip;
in vec4 v_static_clip;

out vec4 frag_color;

void main() {
  vec2 cur_ndc = (v_current_clip.xy / max(v_current_clip.w, 1e-6)) - frame_info.current_previous_jitter.xy;
  vec2 prev_ndc = (v_previous_clip.xy / max(v_previous_clip.w, 1e-6)) - frame_info.current_previous_jitter.zw;
  vec2 static_ndc = (v_static_clip.xy / max(v_static_clip.w, 1e-6)) - frame_info.current_previous_jitter.zw;

  // Object motion delta in UV:
  // In UV space, delta_uv.x = delta_ndc.x * 0.5, delta_uv.y = -delta_ndc.y * 0.5
  vec2 object_delta_uv = vec2((static_ndc.x - prev_ndc.x) * 0.5, -(static_ndc.y - prev_ndc.y) * 0.5);

  frag_color = vec4(object_delta_uv, 1.0, 1.0);
}
