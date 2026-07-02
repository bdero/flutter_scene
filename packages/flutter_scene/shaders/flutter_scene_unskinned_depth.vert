// Position-only vertex shader for the depth-style passes (directional-light
// shadow map, camera depth prepass, and the object-selection mask).
//
// It reads only the position attribute and the instance-rate model transform,
// so a pipeline built with it can bind a layout that omits normal, texture
// coordinates, and color, and the input assembler fetches only position per
// vertex. The full UnskinnedVertex shader reads all four attributes, so it
// could not be paired with such a trimmed layout.
//
// The paired fragment shaders (DepthOnlyFragment, LinearDepthFragment,
// MaskFragment) include material_varyings.glsl, which declares the full set of
// per-vertex inputs. The body writes every one of those varyings to keep the
// vertex/fragment varying interface matched, but only v_position and
// v_viewvector carry real data; the rest are zero because no consumer reads
// them.
//
// The body lives in a shared include so a `.fmat` with a `vertex { }` block can
// reuse it with its own Vertex() hook spliced in; here Vertex() is the no-op
// from material_vertex.glsl, so the output is identical to the pre-hook shader.
#include <material_vertex.glsl>
#include <flutter_scene_unskinned_depth_body.glsl>
