library importer;

// position: 3, normal: 3, tangent: 4, textureCoords: 2, color: 4 :: 16 floats :: 64 bytes
const int kUnskinnedPerVertexSize = 64;

// vertex: 16, joints: 4, weights: 4 :: 24 floats :: 96 bytes
const int kSkinnedPerVertexSize = 96;
