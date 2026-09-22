// The engine-provided fragment inputs every flutter_scene material shader
// receives: the interpolated per-vertex outputs (world space) and the color
// output. Plus convenience accessors a material's Surface() function can call
// instead of touching the raw varyings.

in highp vec3 v_position; // world-space position
in vec3 v_normal; // world-space normal, unit per vertex, renormalize
in highp vec3 v_viewvector; // camera_position - vertex_position (world space)
in highp vec2 v_texture_coords;
in highp vec2 v_texture_coords_1;
in vec4 v_color;
in vec4 v_tangent;

out vec4 frag_color;

// A shader that takes only the varyings (the depth and mask passes) defines
// FLUTTER_SCENE_NO_VIEW_INFO to leave the block out. Declared but unread, it
// gets no binding and reflects at 0, where it collides with the vertex
// stage's FrameInfo; Vulkan rejects the pipeline layout and drops the draws.
// TODO(binding-liveness): a custom shader that includes this file and never
// calls GetViewDirection hits the same collision. The durable fix is for the
// shader compiler to give unread resources a binding too; until then
// test/shader_binding_ranges_test.dart guards the engine's own shaders.
#ifndef FLUTTER_SCENE_NO_VIEW_INFO
// The camera axis, for the view direction under an orthographic camera, where
// every view ray is parallel and v_viewvector (which stays the true vector to
// the eye, for derivatives and depth) does not point along one. Bound by the
// engine wherever a shader reads it. xyz: the world-space camera forward.
// w: 1 for an orthographic camera, 0 for perspective.
uniform ViewInfo {
  highp vec4 camera_forward;
}
view_info;
#endif  // FLUTTER_SCENE_NO_VIEW_INFO

// World-space position of the fragment.
highp vec3 GetWorldPosition() { return v_position; }

// Normalized world-space geometric normal (before any normal-map perturbation).
// Back-facing fragments use the reversed normal required by two-sided lighting.
vec3 GetWorldNormal() {
  float face_direction = gl_FrontFacing ? 1.0 : -1.0;
  return normalize(v_normal) * face_direction;
}

#ifndef FLUTTER_SCENE_NO_VIEW_INFO
// Normalized direction from the fragment toward the viewer: toward the eye for
// perspective, against the camera axis for orthographic.
vec3 GetViewDirection() {
  return view_info.camera_forward.w > 0.5 ? -view_info.camera_forward.xyz
                                          : normalize(v_viewvector);
}
#endif  // FLUTTER_SCENE_NO_VIEW_INFO

// Primary texture coordinates.
highp vec2 GetUV0() { return v_texture_coords; }

// Secondary texture coordinates.
highp vec2 GetUV1() { return v_texture_coords_1; }

highp vec2 GetUV(int channel) { return channel == 1 ? GetUV1() : GetUV0(); }

// Interpolated per-vertex color (white if the mesh has none).
vec4 GetVertexColor() { return v_color; }

// World-space tangent and bitangent sign. A zero vector means the mesh did
// not provide tangents and the fragment shader derives its tangent frame.
vec4 GetWorldTangent() { return v_tangent; }
