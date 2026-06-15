// Selection mask fragment shader.
//
// Draws a highlighted object's silhouette as a flat color into an offscreen
// mask target, which the selection-outline pass edge-detects. Pairs with the
// engine's standard vertex shaders (UnskinnedVertex / SkinnedVertex), like the
// depth prepass; the per-vertex varyings are unused.

#include <material_varyings.glsl>

uniform MaskInfo {
  // rgb: the node's highlight color (linear); a: coverage (always 1).
  vec4 color;
}
mask_info;

void main() {
  frag_color = mask_info.color;
}
