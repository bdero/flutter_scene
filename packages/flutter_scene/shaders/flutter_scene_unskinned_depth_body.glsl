// Shared body for the position-only depth vertex shader and for a `.fmat`'s
// generated depth variant. Requires VertexInputs and Vertex() to be declared
// first by including material_vertex.glsl.
//
// This variant reads only the position attribute (plus the instance-rate model
// transform), so normal/uv/color are not available and are passed to Vertex()
// as zero. A material that displaces geometry purely from world_position (the
// common case, e.g. a world-space curve) casts a matching shadow and reads
// matching depth because the same displacement runs here; a displacement that
// depends on normal/uv/color does not, which is documented.
//
// In the shadow pass camera_transform is the light-space matrix and
// camera_position is a placeholder, so a camera-relative displacement is only
// correct in the shadow map once the real camera position is plumbed here.

uniform FrameInfo {
  mat4 camera_transform;
  vec3 camera_position;
}
frame_info;

in vec3 position;

// Instance-rate model matrix columns (vertex buffer slot 1, advanced once per
// instance). Non-instanced draws bind a single-element buffer holding the
// node's world transform, matching the unskinned body.
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
  vertex.normal = vec3(0.0);
  vertex.world_position = model_position.xyz;
  vertex.world_normal = vec3(0.0);
  vertex.uv = vec2(0.0);
  vertex.color = vec4(0.0);
  vertex.camera_position = frame_info.camera_position;
  Vertex(vertex);

  v_position = vertex.world_position;
  gl_Position = frame_info.camera_transform * vec4(vertex.world_position, 1.0);
  v_viewvector = frame_info.camera_position - vertex.world_position;
  v_normal = vec3(0.0);
  v_texture_coords = vec2(0.0);
  v_color = vec4(0.0);

#ifdef HAS_MATERIAL_VERTEX
  // Keep the position input and the instance-rate model_transform columns
  // live so a hook that replaces world_position cannot strip them (see
  // VertexKeepAlive). Only position is fetched in the depth pass.
  gl_Position += vertex_keep_alive.keep_alive.x *
      vec4(position + model_transform_0.xyz + model_transform_1.xyz +
               model_transform_2.xyz + model_transform_3.xyz,
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
