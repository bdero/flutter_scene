// The no-shadow standard shader for backends whose prefiltered radiance is
// a roughness-mip cubemap. Both defines, one body.
#define FLUTTER_SCENE_SKIP_SHADOWS
#define FLUTTER_SCENE_RADIANCE_CUBE
#include <flutter_scene_standard.frag>
