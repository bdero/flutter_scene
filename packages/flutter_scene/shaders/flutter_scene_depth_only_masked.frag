// Alpha-masked variant of the shadow-pass fragment shader (see
// flutter_scene_depth_only.frag): discards fragments the material's MASK
// coverage rejects so cutout surfaces cast shadows only where opaque.
//
// Pairs with the engine's full vertex shaders (UnskinnedVertex /
// SkinnedVertex), not the position-only depth vertex path, because the mask
// needs the texture-coordinate and vertex-color varyings.

#include <material_varyings.glsl>
#include <depth_mask.glsl>

void main() {
  ApplyDepthAlphaMask();
  frag_color = vec4(gl_FragCoord.z, 0.0, 0.0, 1.0);
}
