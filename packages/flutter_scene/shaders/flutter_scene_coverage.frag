// The main pass's coverage pre-draw for an opaque surface that cuts itself
// out (an alpha mask or a level-of-detail cross-fade). It writes depth only
// where the surface is kept, and the color draw that follows shades with an
// equal depth test, so the lit shaders need no discard. A discard turns off
// early depth testing and hidden-surface removal for every draw of a shader
// on tiled GPUs; here it costs only the draws that cut out.
//
// Pairs with the color draw's own vertex shader, so both rasterize the same
// depth. The color it writes is overwritten by that draw.

#define FLUTTER_SCENE_NO_VIEW_INFO
#include <material_varyings.glsl>
#include <material_inputs.glsl>
#include <depth_mask.glsl>
#include <lod_fade.glsl>

uniform CoverageInfo {
  // Level-of-detail cross-fade coverage (see lod_fade.glsl).
  float fade;
}
coverage_info;

void main() {
  ApplyLodFade(coverage_info.fade);
  ApplyDepthAlphaMask();
  frag_color = vec4(0.0);
}
