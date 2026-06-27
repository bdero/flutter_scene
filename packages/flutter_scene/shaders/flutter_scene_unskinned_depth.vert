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
// per-vertex inputs. To keep the vertex/fragment varying interface matched,
// this shader writes every one of those varyings, but only v_position and
// v_viewvector carry real data (the prepass needs v_viewvector for view-space
// depth); the rest are zero because no consumer reads them.

uniform FrameInfo {
  mat4 camera_transform;
  vec3 camera_position;
}
frame_info;

in vec3 position;

// Instance-rate model matrix columns (vertex buffer slot 1, advanced once per
// instance). Non-instanced draws bind a single-element buffer holding the
// node's world transform, matching UnskinnedVertex.
in vec4 model_transform_0;
in vec4 model_transform_1;
in vec4 model_transform_2;
in vec4 model_transform_3;

out vec3 v_position;
out vec3 v_normal;
out vec3 v_viewvector; // camera_position - vertex_position
out vec2 v_texture_coords;
out vec4 v_color;

void main() {
  mat4 model_transform = mat4(model_transform_0, model_transform_1,
                              model_transform_2, model_transform_3);
  vec4 model_position = model_transform * vec4(position, 1.0);
  v_position = model_position.xyz;
  gl_Position = frame_info.camera_transform * model_position;
  v_viewvector = frame_info.camera_position - v_position;
  v_normal = vec3(0.0);
  v_texture_coords = vec2(0.0);
  v_color = vec4(0.0);
}
