// Shared body for the unskinned vertex shader and for a `.fmat`'s generated
// unskinned vertex variant. Requires VertexInputs and Vertex() to be declared
// first by including material_vertex.glsl (the engine shader includes it with
// the no-op hook; a material variant includes it after defining
// HAS_MATERIAL_VERTEX and its own Vertex()).

uniform FrameInfo {
  mat4 camera_transform;
  vec3 camera_position;
}
frame_info;

// This attribute layout is expected to be identical to that within
// `impeller/scene/importer/scene.fbs`.
in vec3 position;
in vec3 normal;
in vec2 texture_coords;
in vec4 color;

// Instance-rate model matrix columns (vertex buffer slot 1, advanced once
// per instance). Non-instanced draws bind a single-element buffer holding
// the node's world transform.
in vec4 model_transform_0;
in vec4 model_transform_1;
in vec4 model_transform_2;
in vec4 model_transform_3;

// The v_* outputs are declared in material_vertex.glsl (included first), so a
// material's custom varyings can follow them with matching interpolant slots.

void main() {
  mat4 model_transform = mat4(model_transform_0, model_transform_1,
                              model_transform_2, model_transform_3);
  vec4 model_position = model_transform * vec4(position, 1.0);

  VertexInputs vertex;
  vertex.position = position;
  vertex.normal = normal;
  vertex.world_position = model_position.xyz;
  vertex.world_normal = mat3(model_transform) * normal;
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

#ifdef HAS_MATERIAL_VERTEX
  // Reference the mesh inputs behind a runtime-zero (see VertexKeepAlive) so a
  // Vertex() hook that fully replaces the outputs cannot let the optimizer
  // strip a declared attribute, which would break shader reflection. The
  // instance-rate model_transform columns are included because a hook that
  // overwrites world_position without reading it leaves them dead too.
  // Compiled only into a .fmat's vertex variants, never the engine's base
  // shaders.
  gl_Position += vertex_keep_alive.keep_alive.x *
      vec4(position + normal + vec3(texture_coords, 0.0) + color.xyz +
               model_transform_0.xyz + model_transform_1.xyz +
               model_transform_2.xyz + model_transform_3.xyz,
           0.0);
#ifdef MATERIAL_PARAMS_KEEP_ALIVE
  // Keep MaterialParams live even when Vertex() reads no parameter; the
  // runtime binds the block to the vertex stage unconditionally.
  gl_Position.x += vertex_keep_alive.keep_alive.x * MATERIAL_PARAMS_KEEP_ALIVE;
#endif
#endif
}
