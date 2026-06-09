// Vertex shader for the skybox background draw. Driven by a 6-vertex buffer
// of NDC positions covering the screen (see skybox_encoder.dart).
//
// Reconstructs the world-space view direction for each pixel by unprojecting
// the far-plane point through the inverse of the camera's view-projection,
// then subtracting the camera position. Using the exact inverse of the
// matrix the scene geometry is drawn with keeps the sky aligned with the
// geometry on every backend (whatever Y orientation the backend applies to
// gl_Position is applied identically here). The direction is rotated by
// environment_transform so it matches the rotated image-based-lighting
// lookups in the standard material.
uniform SkyboxFrameInfo {
  mat4 inverse_view_projection;
  // A mat4 carrying the 3x3 environment rotation (mat3 has awkward std140
  // padding on some backends); column 3 is (0, 0, 0, 1).
  mat4 environment_transform;
  // xyz = camera world position; w unused.
  vec4 camera_position;
}
frame_info;

in vec2 position;

out vec3 v_ray;

void main() {
  // Unproject this quad vertex's far-plane clip point (z = 1) to world space.
  // The reconstructed ray is the world direction the camera looks through
  // this pixel: because the quad and the scene geometry share the same
  // rasterizer and the same per-backend gl_Position handling, using the
  // vertex's own clip x/y here makes the sky show exactly the direction the
  // geometry at that pixel would occupy, with no orientation flip needed.
  vec4 world =
      frame_info.inverse_view_projection * vec4(position, 1.0, 1.0);
  vec3 ray = world.xyz / world.w - frame_info.camera_position.xyz;
  v_ray = mat3(frame_info.environment_transform) * ray;
  // Sit at the far plane so geometry (depth-tested lessEqual against the
  // cleared far value) always draws in front.
  gl_Position = vec4(position, 1.0, 1.0);
}
