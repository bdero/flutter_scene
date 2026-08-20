// Morphed unskinned vertex shader: the shared unskinned body with morph
// target blending switched on. Without the define below, the body compiles
// byte-for-byte to the plain UnskinnedVertex, so unmorphed scenes never pay
// for (or change under) morph support.
#define FLUTTER_SCENE_MORPH_TARGETS
#include <material_vertex.glsl>
#include <flutter_scene_unskinned_body.glsl>
