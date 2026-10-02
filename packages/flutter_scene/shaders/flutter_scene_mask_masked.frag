// Alpha-masked variant of the object mask fragment shader (see
// flutter_scene_mask.frag): discards fragments the material's MASK coverage
// rejects, so a mask drawn through the full vertex stage covers a cutout
// surface only where the color pass shows it.
//
// Pairs with the engine's full vertex shaders, which supply the
// texture-coordinate and vertex-color varyings the mask needs.

// Varyings only; nothing here reads the view axis.
#define FLUTTER_SCENE_NO_VIEW_INFO
#include <material_varyings.glsl>
#include <material_inputs.glsl>
#include <depth_mask.glsl>

uniform MaskColor {
  // rgb: the fill color (linear); a: coverage (always 1).
  vec4 color;
}
mask_color;

void main() {
  ApplyDepthAlphaMask();
  frag_color = mask_color.color;
}
