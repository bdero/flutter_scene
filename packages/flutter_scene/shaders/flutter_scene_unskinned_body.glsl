// Shared body for the unskinned vertex shader and for a `.fmat`'s generated
// unskinned vertex variant. Requires VertexInputs and Vertex() to be declared
// first by including material_vertex.glsl (the engine shader includes it with
// the no-op hook; a material variant includes it after defining
// HAS_MATERIAL_VERTEX and its own Vertex()).

uniform FrameInfo {
  mat4 camera_transform;
  vec3 camera_position;
  float depth_bias;
}
frame_info;

#include <depth_bias.glsl>

// This attribute layout is expected to be identical to that within
// `impeller/scene/importer/scene.fbs`.
in vec3 position;
in vec3 normal;
in vec2 texture_coords;
in vec2 texture_coords_1;
in vec4 color;
in vec4 tangent;

// Instance-rate model matrix columns (vertex buffer slot 1, advanced once
// per instance). Non-instanced draws bind a single-element buffer holding
// the node's world transform.
in vec4 model_transform_0;
in vec4 model_transform_1;
in vec4 model_transform_2;
in vec4 model_transform_3;
in vec4 instance_color;

#ifdef FLUTTER_SCENE_MORPH_TARGETS
#include <flutter_scene_morph.glsl>
#endif

// The v_* outputs are declared in material_vertex.glsl (included first), so a
// material's custom varyings can follow them with matching interpolant slots.

void main() {
  // Morph targets blend the object-space position and normal before any
  // transform. The plain variant aliases the attributes through macros, so
  // its preprocessed body stays byte-identical to the pre-morph shader.
#ifdef FLUTTER_SCENE_MORPH_TARGETS
  vec3 in_position = MorphedPosition(position);
  vec3 in_normal = MorphedNormal(normal);
#else
#define in_position position
#define in_normal normal
#endif

  mat4 model_transform = mat4(model_transform_0, model_transform_1,
                              model_transform_2, model_transform_3);
  vec4 model_position = model_transform * vec4(in_position, 1.0);

  VertexInputs vertex;
  vertex.position = in_position;
  vertex.normal = in_normal;
  vertex.tangent = tangent;
  vertex.world_position = model_position.xyz;
  vertex.world_normal = mat3(model_transform) * in_normal;
  vec3 world_tangent = mat3(model_transform) * tangent.xyz;
  float tangent_length_squared = dot(world_tangent, world_tangent);
  float tangent_sign = determinant(mat3(model_transform)) < 0.0
      ? -tangent.w : tangent.w;
  vertex.world_tangent = tangent_length_squared > 1e-10
      ? vec4(world_tangent * inversesqrt(tangent_length_squared), tangent_sign)
      : vec4(0.0);
  vertex.uv = texture_coords;
  vertex.uv1 = texture_coords_1;
  vertex.color = color * instance_color;
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
  // Reference the mesh inputs behind a runtime-zero (see VertexKeepAlive) so a
  // Vertex() hook that fully replaces the outputs cannot let the optimizer
  // strip a declared attribute, which would break shader reflection. The
  // instance-rate model_transform columns are included because a hook that
  // overwrites world_position without reading it leaves them dead too.
  // Compiled only into a .fmat's vertex variants, never the engine's base
  // shaders.
  gl_Position += vertex_keep_alive.keep_alive.x *
      vec4(position + normal + vec3(texture_coords + texture_coords_1, 0.0) +
               color.xyz + tangent.xyz +
               model_transform_0.xyz + model_transform_1.xyz +
               model_transform_2.xyz + model_transform_3.xyz +
               instance_color.xyz,
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
