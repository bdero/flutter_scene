// Skinned vertex shader. The body lives in a shared include so a `.fmat` with a
// `vertex { }` block can reuse it with its own Vertex() hook spliced in; here
// Vertex() is the no-op from material_vertex.glsl, so the output is identical to
// the pre-hook shader.
#include <material_vertex.glsl>
#include <flutter_scene_skinned_body.glsl>
