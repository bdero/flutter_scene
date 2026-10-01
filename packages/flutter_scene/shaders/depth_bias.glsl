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

// Moves `clip` toward the camera by a whole number of depth-buffer steps.
// `offset.xy` is the draw's offset and `offset.zw` one instance rank's, each
// as (relative z scale, multiple of w) from DepthRaster.writeOffset. Applied
// after projection, so the shift is exact in depth units at any distance.
vec4 ApplyDepthOffset(vec4 clip, vec4 offset, float instance_rank) {
  vec2 total = offset.xy + offset.zw * instance_rank;
  clip.z = clip.z * (1.0 + total.x) + total.y * clip.w;
  return clip;
}

#endif  // DEPTH_BIAS_GLSL_
