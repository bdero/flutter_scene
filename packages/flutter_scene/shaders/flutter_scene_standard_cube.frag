// The standard lit fragment shader for backends whose prefiltered radiance is
// a roughness-mip cubemap. Same body as flutter_scene_standard.frag; the
// define picks the cube sampler so the 2D one is never declared and costs no
// texture unit.
#define FLUTTER_SCENE_RADIANCE_CUBE
#include <flutter_scene_standard.frag>
