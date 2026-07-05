// Vertex shader for LineSegmentsGeometry: expands each segment instance into
// a camera-facing quad of a fixed world-space width. Outputs the standard
// engine varyings so any material fragment (unlit, PBR, a .fmat's Surface())
// shades the ribbon; the normal faces the camera.

uniform FrameInfo {
  mat4 camera_transform; // view-projection
  mat4 model_transform;  // node world transform
  vec4 camera_position;  // world-space camera position (xyz)
  // x: half width in world units. yzw: unused.
  vec4 params;
}
frame_info;

// Per-vertex unit quad (slot 0): x selects the endpoint (0 start, 1 end),
// y is the side of the ribbon (-1 or +1).
in vec2 corner;

// Per-instance segment endpoints in the geometry's local space (slot 1).
in vec3 i_start;
in vec3 i_end;

out vec3 v_position;
out vec3 v_normal;
out vec3 v_viewvector;
out vec2 v_texture_coords;
out vec4 v_color;

void main() {
  vec3 world_start = (frame_info.model_transform * vec4(i_start, 1.0)).xyz;
  vec3 world_end = (frame_info.model_transform * vec4(i_end, 1.0)).xyz;
  vec3 pos = mix(world_start, world_end, corner.x);

  // Expand perpendicular to the segment and the view direction so the
  // ribbon always faces the camera. A segment pointing at the eye (or a
  // degenerate segment) collapses the cross product; it stays a hairline.
  vec3 dir = world_end - world_start;
  vec3 view = frame_info.camera_position.xyz - pos;
  vec3 perp = cross(dir, view);
  float perp_len = length(perp);
  perp = perp_len > 1e-12 ? perp / perp_len : vec3(0.0);
  // Orient the expansion so every quad winds as a front face under the
  // engine's winding convention (perp flips sign with the segment direction
  // otherwise, and a back-face culling material would drop the ribbons).
  if (dot(cross(perp, dir), view) > 0.0) {
    perp = -perp;
  }
  pos += perp * (frame_info.params.x * corner.y);

  // Camera-facing shading normal, perpendicular to both the segment and
  // the expansion direction.
  float dir_len = length(dir);
  vec3 n = dir_len > 1e-12 ? cross(dir / dir_len, perp) : vec3(0.0, 0.0, 1.0);

  v_position = pos;
  gl_Position = frame_info.camera_transform * vec4(pos, 1.0);
  v_viewvector = view;
  v_normal = n;
  // u runs along the segment, v across the ribbon.
  v_texture_coords = vec2(corner.x, corner.y * 0.5 + 0.5);
  v_color = vec4(1.0);
}
