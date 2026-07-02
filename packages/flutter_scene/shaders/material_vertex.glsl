// The per-vertex data a material's Vertex() hook reads and writes, plus the
// default no-op hook. This mirrors material_inputs.glsl on the fragment side:
// every engine vertex shader builds a VertexInputs from the mesh attributes,
// calls Vertex(), and writes its stage outputs from the (possibly modified)
// struct.
//
// A `.fmat` with a `vertex { }` block defines HAS_MATERIAL_VERTEX before
// including this file and supplies its own Vertex(); every other vertex shader
// includes this file without that define and gets the no-op below, so its
// output is byte-for-byte unchanged from the pre-hook shader.
//
// This file declares only the struct and the default hook and has no
// dependencies. The per-variant body includes (flutter_scene_*_body.glsl)
// require it to be included first.

struct VertexInputs {
  // Object-space position and normal. On a skinned mesh these are already
  // transformed by the blended skin matrix (so they mean the same thing in the
  // skinned and unskinned variants).
  vec3 position;
  vec3 normal;
  // World-space position and normal, after the model (and skin) transform.
  // Writing world_position is how a material displaces geometry; the engine
  // projects it to clip space after Vertex() returns.
  vec3 world_position;
  vec3 world_normal;
  vec2 uv;
  vec4 color;
  // Read-only frame data the engine fills in before calling Vertex(). The
  // world-space camera position is available in every variant.
  vec3 camera_position;
};

// The engine's standard vertex outputs, consumed by the fragment stage's
// material_varyings.glsl in this same order. Declared here (before a material's
// custom varyings, which the emitter appends after including this file) so the
// vertex and fragment stages assign matching interpolant locations. The body
// includes (flutter_scene_*_body.glsl) write these in main().
out vec3 v_position; // world-space position
out vec3 v_normal; // world-space normal, not normalized
out vec3 v_viewvector; // camera_position - vertex_position (world space)
out vec2 v_texture_coords;
out vec4 v_color;

#ifndef HAS_MATERIAL_VERTEX
// The default hook: leave every vertex unchanged.
void Vertex(inout VertexInputs vertex) {}
#endif
