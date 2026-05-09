/// Bytes per vertex in the unskinned vertex layout: position (`vec3`),
/// normal (`vec3`), tex coords (`vec2`), color (`vec4`) — 12 floats.
///
/// Match this layout exactly when emitting unskinned vertex buffers.
const int kUnskinnedPerVertexSize = 48;

/// Bytes per vertex in the skinned vertex layout: the unskinned 12
/// floats plus 4 joint indices and 4 joint weights — 20 floats.
///
/// Match this layout exactly when emitting skinned vertex buffers.
const int kSkinnedPerVertexSize = 80;
