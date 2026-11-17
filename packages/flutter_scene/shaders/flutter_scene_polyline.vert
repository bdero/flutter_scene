// Vertex shader for PolylineGeometry: expands a polyline into a strip that
// faces the camera of whichever pass draws it, with a camera-facing disk at
// each round cap. Widths are world units or screen pixels, and a draw range
// trims both ends. Outputs the standard engine varyings so any material
// fragment (unlit, PBR, a .fmat's Surface()) shades the line.

uniform FrameInfo {
  mat4 camera_transform; // view-projection
  mat4 model_transform;  // node world transform
  // The view-projection pixel widths are measured in. A shadow or
  // reflection pass draws with its own camera_transform and keeps the
  // view's here, so a pixel-wide line is as wide there as it looks.
  mat4 sizing_transform;
  vec4 camera_position;  // world-space camera position (xyz)
  // xy: the sizing view's logical size. z: 1 when widths are pixels, 0 when
  // they are world units.
  vec4 params;
  // xy: the drawn range, as fractions of the line's arc length.
  vec4 draw_range;
  // The local-space points the drawn range starts and ends at (xyz).
  vec4 range_start;
  vec4 range_end;
  // The material's depth-layer offset (xy), see ApplyDepthOffset.
  vec4 depth_offset;
}
frame_info;

#include <view_vector.glsl>
#include <depth_bias.glsl>

// This point and the two neighbors its tangent runs between, in the
// geometry's local space. An end point is its own missing neighbor.
in vec3 position;
in vec3 previous;
in vec3 next;
// x: the strip side (-1 or +1), or with y a cap disk's unit offset.
// z: the half width at this point. w: 1 for a cap disk vertex.
in vec4 shape;
// The arc-length fractions of this point and of its two neighbors.
in vec3 arcs;
in vec2 texture_coords;
in vec4 color;

out vec3 v_position;
out vec3 v_normal;
out vec3 v_viewvector;
out vec2 v_texture_coords;
out vec2 v_texture_coords_1;
out vec4 v_color;
out vec4 v_tangent;

// How far a cap disk sits toward the viewer, in radii, so it draws over the
// strip instead of z-fighting with it.
const float kDiskLift = 0.1;

// A point outside the drawn range collapses onto the boundary it is past.
vec3 TrimToRange(vec3 point, float arc) {
  vec3 trimmed = point;
  if (arc < frame_info.draw_range.x) {
    trimmed = frame_info.range_start.xyz;
  } else if (arc > frame_info.draw_range.y) {
    trimmed = frame_info.range_end.xyz;
  }
  return trimmed;
}

vec3 AnyPerpendicular(vec3 direction) {
  vec3 reference =
      abs(direction.x) < 0.9 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
  return normalize(cross(direction, reference));
}

// The pixels of the sizing view that one world unit along `direction`
// covers at `world_position`.
float PixelsPerWorldUnit(vec3 world_position, vec3 direction) {
  vec4 clip = frame_info.sizing_transform * vec4(world_position, 1.0);
  vec4 clip_step = frame_info.sizing_transform * vec4(direction, 0.0);
  float w = abs(clip.w) < 1e-6 ? 1e-6 : clip.w;
  vec2 ndc_step = (clip_step.xy * w - clip.xy * clip_step.w) / (w * w);
  return length(ndc_step * frame_info.params.xy * 0.5);
}

// The half width in world units, measured along `direction`.
float WorldHalfWidth(float half_width, vec3 world_position, vec3 direction) {
  float result = half_width;
  if (frame_info.params.z > 0.5) {
    float pixels = PixelsPerWorldUnit(world_position, direction);
    result = pixels > 1e-9 ? half_width / pixels : 0.0;
  }
  return result;
}

void main() {
  bool drawn = arcs.x >= frame_info.draw_range.x &&
               arcs.x <= frame_info.draw_range.y;
  float half_width = drawn ? shape.z : 0.0;

  mat4 model = frame_info.model_transform;
  vec3 center = (model * vec4(TrimToRange(position, arcs.x), 1.0)).xyz;
  vec3 before = (model * vec4(TrimToRange(previous, arcs.y), 1.0)).xyz;
  vec3 after = (model * vec4(TrimToRange(next, arcs.z), 1.0)).xyz;

  vec3 view = DirectionToViewer(frame_info.camera_transform,
                                frame_info.camera_position.xyz, center);

  vec3 pos;
  if (shape.w > 0.5) {
    // A cap disk: a ring around the point in the plane facing the viewer.
    vec3 u = AnyPerpendicular(view);
    vec3 v = cross(view, u);
    float radius = WorldHalfWidth(half_width, center, u);
    pos = center + view * (radius * kDiskLift) +
          (u * shape.x + v * shape.y) * radius;
  } else {
    // The strip: step across the line, perpendicular to it and to the view
    // direction. A line pointing at the eye has no such direction, so it
    // takes an arbitrary one.
    vec3 tangent = after - before;
    float tangent_length = length(tangent);
    tangent = tangent_length > 1e-6 ? tangent / tangent_length
                                    : vec3(1.0, 0.0, 0.0);
    vec3 across = cross(tangent, view);
    float across_length = length(across);
    across = across_length > 1e-6 ? across / across_length
                                  : AnyPerpendicular(tangent);
    pos = center +
          across * (WorldHalfWidth(half_width, center, across) * shape.x);
  }

  v_position = pos;
  vec4 clip_position = frame_info.camera_transform * vec4(pos, 1.0);
  gl_Position = ApplyDepthOffset(
      clip_position, vec4(frame_info.depth_offset.xy, 0.0, 0.0), vec3(0.0),
      frame_info.camera_transform, pos, frame_info.camera_position.xyz);
  v_viewvector = frame_info.camera_position.xyz - pos;
  v_normal = view;
  v_texture_coords = texture_coords;
  v_texture_coords_1 = texture_coords;
  v_color = color;
  v_tangent = vec4(0.0);
}
