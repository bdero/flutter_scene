// Fragment shader for the camera depth prepass.
//
// Pairs with the engine's standard vertex shaders (UnskinnedVertex /
// SkinnedVertex), driven with the camera view-projection. Writes planar
// view-space depth (the distance from the camera plane along the view
// direction, in world units) into the red channel of a floating-point
// color target, so screen-space passes such as ambient occlusion can
// reconstruct view-space positions from it. A transient depth attachment
// backs the depth test; the other standard vertex outputs are unused.
//
// View-space depth is computed from the world-space view vector rather
// than by linearizing gl_FragCoord.z, so it does not depend on the
// backend's clip-space depth-range convention.

#include <material_varyings.glsl>

uniform DepthInfo {
  // xyz: normalized world-space camera forward (from the eye into the
  // scene). w: unused.
  vec4 camera_forward;
}
depth_info;

void main() {
  // v_viewvector is (camera_position - world_position), so negating it and
  // projecting onto the forward axis gives the planar view-space depth
  // (positive in front of the camera).
  float view_depth = -dot(v_viewvector, depth_info.camera_forward.xyz);
  frag_color = vec4(view_depth, 0.0, 0.0, 1.0);
}
