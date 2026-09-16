// Camera facts a vertex stage reads from its view-projection transform.
//
// A perspective view-projection's w row is the view depth, so its xyz is
// nonzero; an orthographic one's is constant. The x and y rows hold the
// camera's right and up axes, which neither an oblique near-plane clip (it
// replaces the z row) nor subpixel jitter (it moves the translation) touches,
// so their cross product is the forward axis for any orthographic transform.

#ifndef VIEW_VECTOR_GLSL_
#define VIEW_VECTOR_GLSL_

bool CameraTransformIsOrthographic(mat4 camera_transform) {
  vec3 w_row = vec3(camera_transform[0][3], camera_transform[1][3],
                    camera_transform[2][3]);
  return dot(w_row, w_row) < 1e-12;
}

vec3 CameraTransformForward(mat4 camera_transform) {
  vec3 x_row = vec3(camera_transform[0][0], camera_transform[1][0],
                    camera_transform[2][0]);
  vec3 y_row = vec3(camera_transform[0][1], camera_transform[1][1],
                    camera_transform[2][1]);
  return normalize(cross(x_row, y_row));
}

// The unit direction from [world_position] toward the viewer: toward the eye
// for perspective, against the camera axis for orthographic (every view ray is
// parallel there, including behind the eye plane).
vec3 DirectionToViewer(mat4 camera_transform, vec3 camera_position,
                       vec3 world_position) {
  if (CameraTransformIsOrthographic(camera_transform)) {
    return -CameraTransformForward(camera_transform);
  }
  vec3 to_camera = camera_position - world_position;
  float length_squared = dot(to_camera, to_camera);
  return length_squared > 1e-12 ? to_camera * inversesqrt(length_squared)
                                : vec3(0.0, 0.0, 1.0);
}

#endif  // VIEW_VECTOR_GLSL_
