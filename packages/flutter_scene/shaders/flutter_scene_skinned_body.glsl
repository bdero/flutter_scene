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
  float depth_bias;
}
frame_info;

#include <depth_bias.glsl>
#include <normal_transform.glsl>

uniform sampler2D joints_texture;

#ifdef FLUTTER_SCENE_MORPH_TARGETS
#include <flutter_scene_morph.glsl>
#endif

// This attribute layout is expected to be identical to `SkinnedVertex` within
// `impeller/scene/importer/scene.fbs`.
in vec3 position;
in vec3 normal;
in vec2 texture_coords;
in vec2 texture_coords_1;
in vec4 color;
in vec4 tangent;
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
  // Morph before skinning: targets blend the object-space position and
  // normal, then the blended skin matrix deforms the morphed result. The
  // plain variant aliases the attributes through macros, so its preprocessed
  // body stays byte-identical to the pre-morph shader.
#ifdef FLUTTER_SCENE_MORPH_TARGETS
  vec3 in_position = MorphedPosition(position);
  vec3 in_normal = MorphedNormal(normal);
#else
#define in_position position
#define in_normal normal
#endif

  mat4 skin_matrix;
  if (frame_info.enable_skinning == 1) {
    skin_matrix =
        GetJoint(joints.x) * weights.x + GetJoint(joints.y) * weights.y +
        GetJoint(joints.z) * weights.z + GetJoint(joints.w) * weights.w;
  } else {
    skin_matrix = mat4(1); // Identity matrix.
  }

  vec4 skinned_position = skin_matrix * vec4(in_position, 1.0);
  vec3 skinned_normal = mat3(skin_matrix) * in_normal;
  mat4 combined_transform = frame_info.model_transform * skin_matrix;
  vec4 model_position = combined_transform * vec4(in_position, 1.0);

  VertexInputs vertex;
  vertex.position = skinned_position.xyz;
  vertex.normal = skinned_normal;
  vertex.tangent = vec4(mat3(skin_matrix) * tangent.xyz, tangent.w);
  vertex.world_position = model_position.xyz;
  vertex.world_normal =
      WorldNormalMatrix(mat3(combined_transform)) * in_normal;
  vec3 world_tangent = mat3(combined_transform) * tangent.xyz;
  float tangent_length_squared = dot(world_tangent, world_tangent);
  float tangent_sign = determinant(mat3(combined_transform)) < 0.0
      ? -tangent.w : tangent.w;
  vertex.world_tangent = tangent_length_squared > 1e-10
      ? vec4(world_tangent * inversesqrt(tangent_length_squared), tangent_sign)
      : vec4(0.0);
  vertex.uv = texture_coords;
  vertex.uv1 = texture_coords_1;
  vertex.color = color;
  vertex.camera_position = frame_info.camera_position;
  Vertex(vertex);

  v_position = vertex.world_position;
  vec3 draw_position = ApplyDepthBias(
      vertex.world_position, frame_info.camera_position, frame_info.depth_bias);
  gl_Position = frame_info.camera_transform * vec4(draw_position, 1.0);
  v_viewvector = frame_info.camera_position - vertex.world_position;
  v_normal = vertex.world_normal;
  v_texture_coords = vertex.uv;
  v_texture_coords_1 = vertex.uv1;
  v_color = vertex.color;
  v_tangent = vertex.world_tangent;

#ifdef MATERIAL_INSTANCE_VARYINGS
  // Forward the material's declared per-instance attributes to the fragment
  // stage (defined only when Surface() reads one through its accessor).
  MATERIAL_INSTANCE_VARYINGS
#endif

#ifdef HAS_MATERIAL_VERTEX
  // Keep the mesh inputs (including the skin attributes) live behind a
  // runtime-zero (see VertexKeepAlive) so a hook that fully replaces the
  // outputs cannot strip a declared attribute and break shader reflection.
  gl_Position += vertex_keep_alive.keep_alive.x *
      vec4(position + normal + vec3(texture_coords + texture_coords_1, 0.0) +
               color.xyz + tangent.xyz +
               joints.xyz + weights.xyz,
           0.0);
#ifdef MATERIAL_PARAMS_KEEP_ALIVE
  // Keep MaterialParams live even when Vertex() reads no parameter; the
  // runtime binds the block to the vertex stage unconditionally.
  gl_Position.x += vertex_keep_alive.keep_alive.x * MATERIAL_PARAMS_KEEP_ALIVE;
#endif
#ifdef MATERIAL_ATTRIBUTES_KEEP_ALIVE
  // Keep declared custom attributes live even when Vertex() reads none; a
  // stripped input breaks reflection and the pipeline's vertex layout.
  gl_Position.x +=
      vertex_keep_alive.keep_alive.x * MATERIAL_ATTRIBUTES_KEEP_ALIVE;
#endif
#endif
}
