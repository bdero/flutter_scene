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
