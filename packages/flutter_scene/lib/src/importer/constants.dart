/// Bytes per vertex in the unskinned vertex layout: position (`vec3`),
/// normal (`vec3`), two tex coords (`vec2` each), color (`vec4`), and tangent
/// (`vec4`), 18 floats.
///
/// Match this layout exactly when emitting unskinned vertex buffers.
const int kUnskinnedPerVertexSize = 72;

/// Bytes per vertex in the skinned vertex layout: the unskinned 18
/// floats plus 4 joint indices and 4 joint weights, 26 floats.
///
/// Match this layout exactly when emitting skinned vertex buffers.
const int kSkinnedPerVertexSize = 104;
