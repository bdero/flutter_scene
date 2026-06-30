// Fragment shader for the camera depth prepass when a consumer also needs
// per-pixel normals (screen-space reflections).
//
// Like LinearDepthFragment it writes planar view-space depth into the red
// channel, but it also writes the smooth, interpolated view-space normal
// into the green/blue/alpha channels of the same floating-point target (the
// depth uses only red, so the normal rides along at no extra attachment
// cost). Reflections need the shaded vertex normal, not a face normal
// reconstructed from depth, so that curved surfaces reflect smoothly rather
// than per-triangle.
//
// Pairs with the engine's full vertex shaders (UnskinnedVertex /
// SkinnedVertex), which provide the world-space v_normal and v_viewvector.
// The world normal is rotated into view space with the camera basis passed
// in, matching the lookAt view matrix (+X right, +Y up, +Z forward).

#include <material_varyings.glsl>

uniform DepthNormalInfo {
  // xyz: normalized world-space camera forward (eye into the scene).
  vec4 camera_forward;
  // xyz: world-space camera right axis.
  vec4 camera_right;
  // xyz: world-space camera up axis.
  vec4 camera_up;
}
info;

void main() {
  // v_viewvector is (camera_position - world_position); negating it and
  // projecting onto the forward axis gives planar view-space depth.
  float view_depth = -dot(v_viewvector, info.camera_forward.xyz);

  // Rotate the interpolated world normal into view space (eye looking down
  // +Z), the space the reflection trace works in.
  vec3 n = normalize(v_normal);
  vec3 view_normal = normalize(vec3(dot(n, info.camera_right.xyz),
                                    dot(n, info.camera_up.xyz),
                                    dot(n, info.camera_forward.xyz)));

  frag_color = vec4(view_depth, view_normal);
}
