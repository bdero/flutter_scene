#ifndef DEPTH_BIAS_GLSL_
#define DEPTH_BIAS_GLSL_

#include <view_vector.glsl>

vec3 ApplyDepthBias(vec3 world_position, mat4 camera_transform,
                    vec3 camera_position, float depth_bias) {
  if (depth_bias <= 0.0) {
    return world_position;
  }
  if (CameraTransformIsOrthographic(camera_transform)) {
    // No eye to overshoot; move straight toward the viewer.
    return world_position -
           CameraTransformForward(camera_transform) * depth_bias;
  }
  vec3 to_camera = camera_position - world_position;
  float distance_squared = dot(to_camera, to_camera);
  if (distance_squared <= 1e-12) {
    return world_position;
  }
  float distance_fraction =
      min(depth_bias * inversesqrt(distance_squared), 0.99);
  return world_position + to_camera * distance_fraction;
}

// A stable tie-break rank in [0, 3) for the instance at `origin` (its model
// transform's translation), so coplanar instances of one draw resolve the
// same way every frame however the instance buffer is ordered.
float InstanceDepthRank(vec3 origin) {
  return floor(
      fract(sin(dot(origin, vec3(12.9898, 78.233, 37.719))) * 43758.5453) *
      3.0);
}

// How many depth-buffer steps of float32 rounding the view-projection puts
// on the depth of a vertex at `world_position`. The transform sums terms as
// large as the distances of the vertex and the eye from the world origin, so
// far from the origin its rounding outgrows the depth step, and an offset
// must grow with it to keep ahead.
// Rounding past this many steps is left to the depth test: a vertex near or
// behind the eye plane (a large ground quad's far corner) would otherwise
// get an offset that overwhelms its own clip position.
const float kMaxDepthRoundingSteps = 64.0;

float DepthRoundingSteps(vec4 clip, mat4 camera_transform,
                         vec3 world_position, vec3 camera_position) {
  float span = length(world_position) + length(camera_position);
  float steps;
  if (CameraTransformIsOrthographic(camera_transform)) {
    // Orthographic depth is linear in view z, scaled by the depth row.
    vec3 depth_row = vec3(camera_transform[0][2], camera_transform[1][2],
                          camera_transform[2][2]);
    steps = span * length(depth_row);
  } else {
    steps = span / max(abs(clip.w), max(span / kMaxDepthRoundingSteps, 1e-6));
  }
  return clamp(steps, 1.0, kMaxDepthRoundingSteps);
}

// Moves `clip` toward the camera by a whole number of depth-buffer steps,
// scaled by DepthRoundingSteps. `offset.xy` is the draw's offset and
// `offset.zw` that of one rank of the instance at `instance_origin`, each as
// (relative z scale, multiple of w) from DepthRaster.writeOffset. Applied
// after projection, so the shift holds in depth units at any distance. A
// draw with no offset (all zero, the default) skips the per-vertex work.
vec4 ApplyDepthOffset(vec4 clip, vec4 offset, vec3 instance_origin,
                      mat4 camera_transform, vec3 world_position,
                      vec3 camera_position) {
  vec4 result = clip;
  if (any(notEqual(offset, vec4(0.0)))) {
    float rank = 0.0;
    if (any(notEqual(offset.zw, vec2(0.0)))) {
      rank = InstanceDepthRank(instance_origin);
    }
    vec2 total = (offset.xy + offset.zw * rank) *
                 DepthRoundingSteps(clip, camera_transform, world_position,
                                    camera_position);
    result.z = clip.z * (1.0 + total.x) + total.y * clip.w;
  }
  return result;
}

// How steep a view DepthSlopes credits a layer offset (x) and a tie-break
// rank's (y) with. A flat surface past it gets less offset than its slope
// asks for; a smooth normal at a silhouette, which does not describe its
// triangle, gets no more than this. The tie-break touches every surface, so
// it is held to a shallower view.
const float kMaxDepthSlope = 64.0;
const float kMaxTieBreakDepthSlope = 8.0;

// How fast window depth changes across the screen on the surface through
// `world_position` with normal `world_normal`, per pixel, in units of
// DepthRaster's pixel slope: |N perp| / |N . (P - E)| for perspective and
// |N perp| / |N . F| for orthographic, where N perp is the normal's part
// across the view axis F. Both are constant over a flat triangle, which every
// vertex of it computes alike. Capped at kMaxDepthSlope (x) and
// kMaxTieBreakDepthSlope (y); zero for a zero normal.
vec2 DepthSlopes(vec3 world_normal, vec3 world_position,
                 mat4 camera_transform, vec3 camera_position) {
  float normal_length_squared = dot(world_normal, world_normal);
  if (normal_length_squared < 1e-12) {
    return vec2(0.0);
  }
  vec3 normal = world_normal * inversesqrt(normal_length_squared);
  float facing = dot(normal, CameraTransformForward(camera_transform));
  float across = sqrt(max(1.0 - facing * facing, 0.0));
  float flatness;
  float scale;
  if (CameraTransformIsOrthographic(camera_transform)) {
    flatness = abs(facing);
    scale = 1.0;
  } else {
    vec3 to_position = world_position - camera_position;
    flatness = abs(dot(normal, to_position));
    scale = max(length(to_position), 1e-6);
  }
  return vec2(across / max(flatness, scale / kMaxDepthSlope),
              across / max(flatness, scale / kMaxTieBreakDepthSlope));
}

// ApplyDepthOffset plus slope-scaled offsets, the vertex-stage form of a
// polygon offset's slope factor, in window depth per unit of DepthSlopes
// (for the surface through `world_position` with `world_normal`), from
// DepthRaster.slopeOffset. `slope.x` is the draw's layer offset, scaled by
// the layer slope; `slope.z` its tie-break offset and `slope.y` one instance
// rank's, scaled by the tie-break slope. Rasterizer snapping and
// interpolation perturb a surface's depth by a fraction of a pixel's worth
// of its own depth gradient, which on a grazing surface is far more than any
// fixed count of depth steps, so coplanar surfaces only stay ordered by an
// offset that scales with that gradient. All zero skips the work.
vec4 ApplySlopedDepthOffset(vec4 clip, vec4 offset, vec4 slope,
                            vec3 instance_origin, mat4 camera_transform,
                            vec3 world_position, vec3 camera_position,
                            vec3 world_normal) {
  vec4 result = clip;
  if (any(notEqual(offset, vec4(0.0))) || any(notEqual(slope, vec4(0.0)))) {
    float rank = 0.0;
    if (any(notEqual(offset.zw, vec2(0.0))) || slope.y != 0.0) {
      rank = InstanceDepthRank(instance_origin);
    }
    vec2 total = (offset.xy + offset.zw * rank) *
                 DepthRoundingSteps(clip, camera_transform, world_position,
                                    camera_position);
    float sloped = 0.0;
    if (any(notEqual(slope, vec4(0.0)))) {
      vec2 slopes = DepthSlopes(world_normal, world_position,
                                camera_transform, camera_position);
      sloped = slope.x * slopes.x + (slope.z + slope.y * rank) * slopes.y;
    }
    result.z = clip.z * (1.0 + total.x) + (total.y + sloped) * clip.w;
  }
  return result;
}

#endif  // DEPTH_BIAS_GLSL_
