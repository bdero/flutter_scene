// The standard lit fragment shader for a draw with no shadow atlas bound.
// Same body as flutter_scene_standard.frag; the define compiles the cascade
// and spot shadow sampling out, dropping the shadow_map sampler and roughly
// halving the program, which matters most for register pressure on mobile
// GPUs. Selected exactly when Lighting.shadowMap is null.
#define FLUTTER_SCENE_SKIP_SHADOWS
#include <flutter_scene_standard.frag>
