// Morphed skinned vertex shader: the shared skinned body with morph target
// blending switched on, applied before the skin matrix. Without the define
// below, the body compiles byte-for-byte to the plain SkinnedVertex.
#define FLUTTER_SCENE_MORPH_TARGETS
#include <material_vertex.glsl>
#include <flutter_scene_skinned_body.glsl>
