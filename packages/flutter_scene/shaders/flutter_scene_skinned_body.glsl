// Shared body for the skinned vertex shader and for a `.fmat`'s generated
// skinned vertex variant. Requires VertexInputs and Vertex() to be declared
// first by including material_vertex.glsl.
//
// The blended skin matrix is applied before Vertex() runs, so vertex.position
// and vertex.world_position mean the same thing here as in the unskinned body
// and a material's Vertex() never has to know whether the mesh is skinned.

uniform FrameInfo {
  mat4 model_transform;
  mat4 camera_transform;
  vec3 camera_position;
  float enable_skinning;
  float joint_texture_size;
}
frame_info;

uniform sampler2D joints_texture;

// This attribute layout is expected to be identical to `SkinnedVertex` within
// `impeller/scene/importer/scene.fbs`.
in vec3 position;
in vec3 normal;
in vec2 texture_coords;
in vec4 color;
in vec4 joints;
in vec4 weights;

// The v_* outputs are declared in material_vertex.glsl (included first), so a
// material's custom varyings can follow them with matching interpolant slots.

const int kMatrixTexelStride = 4;

mat4 GetJoint(float joint_index) {
  // The size of one texel in UV space. The joint texture should always be
  // square, so the answer is the same in both dimensions.
  float texel_size_uv = 1 / frame_info.joint_texture_size;

  // Each joint matrix takes up 4 pixels (16 floats), so we jump 4 pixels per
  // joint matrix.
  float matrix_start = joint_index * kMatrixTexelStride;

  // The texture space coordinates at the start of the matrix.
  float x = mod(matrix_start, frame_info.joint_texture_size);
  float y = floor(matrix_start / frame_info.joint_texture_size);

  // Nearest sample the middle of each the texel by adding `0.5 * texel_size_uv`
  // to both dimensions.
  y = (y + 0.5) * texel_size_uv;
  mat4 joint =
      mat4(texture(joints_texture, vec2((x + 0.5) * texel_size_uv, y)),
           texture(joints_texture, vec2((x + 1.5) * texel_size_uv, y)),
           texture(joints_texture, vec2((x + 2.5) * texel_size_uv, y)),
           texture(joints_texture, vec2((x + 3.5) * texel_size_uv, y)));

  return joint;
}

void main() {
  mat4 skin_matrix;
  if (frame_info.enable_skinning == 1) {
    skin_matrix =
        GetJoint(joints.x) * weights.x + GetJoint(joints.y) * weights.y +
        GetJoint(joints.z) * weights.z + GetJoint(joints.w) * weights.w;
  } else {
    skin_matrix = mat4(1); // Identity matrix.
  }

  vec4 skinned_position = skin_matrix * vec4(position, 1.0);
  vec3 skinned_normal = mat3(skin_matrix) * normal;
  vec4 model_position = frame_info.model_transform * skinned_position;

  VertexInputs vertex;
  vertex.position = skinned_position.xyz;
  vertex.normal = skinned_normal;
  vertex.world_position = model_position.xyz;
  vertex.world_normal = mat3(frame_info.model_transform) * skinned_normal;
  vertex.uv = texture_coords;
  vertex.color = color;
  vertex.camera_position = frame_info.camera_position;
  Vertex(vertex);

  v_position = vertex.world_position;
  gl_Position = frame_info.camera_transform * vec4(vertex.world_position, 1.0);
  v_viewvector = frame_info.camera_position - vertex.world_position;
  v_normal = vertex.world_normal;
  v_texture_coords = vertex.uv;
  v_color = vertex.color;
}
