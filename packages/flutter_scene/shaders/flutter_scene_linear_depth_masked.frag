// Alpha-masked variant of the camera depth prepass fragment shader (see
// flutter_scene_linear_depth.frag): discards fragments the material's MASK
// coverage rejects, so screen-space consumers (ambient occlusion, refraction,
// depth fade) see cutout surfaces only where they are actually opaque.
//
// Pairs with the engine's full vertex shaders, which supply the
// texture-coordinate and vertex-color varyings the mask needs.

#include <material_varyings.glsl>
#include <depth_mask.glsl>

uniform DepthInfo {
  // xyz: normalized world-space camera forward (from the eye into the
  // scene). w: unused.
  vec4 camera_forward;
}
depth_info;

void main() {
  ApplyDepthAlphaMask();
  float view_depth = -dot(v_viewvector, depth_info.camera_forward.xyz);
  frag_color = vec4(view_depth, 0.0, 0.0, 1.0);
}
