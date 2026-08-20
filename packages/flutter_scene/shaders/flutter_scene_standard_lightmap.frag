// The standard lit fragment shader for a material carrying a baked lightmap.
// Same body as flutter_scene_standard.frag; the define swaps the SH diffuse
// ambient for the sampled lightmap, so the lightmap sampler takes the texture
// unit sh_coefficients gives up.
#define FLUTTER_SCENE_LIGHTMAP
#include <flutter_scene_standard.frag>
