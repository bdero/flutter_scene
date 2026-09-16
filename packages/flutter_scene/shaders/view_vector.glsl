// The world-space vector from a point toward the viewer, for any camera.
//
// A perspective view-projection's w row is the view depth, so its xyz is
// nonzero; an orthographic one's is constant. Under an orthographic camera
// every view ray is parallel to the camera axis, so the vector runs along that
// axis (the camera's z row) to the camera plane rather than to the eye. Its
// planar depth, dot(-vector, forward), matches the perspective form either way.

#ifndef VIEW_VECTOR_GLSL_
#define VIEW_VECTOR_GLSL_

bool CameraTransformIsOrthographic(mat4 camera_transform) {
  vec3 w_row = vec3(camera_transform[0][3], camera_transform[1][3],
                    camera_transform[2][3]);
  return dot(w_row, w_row) < 1e-12;
}

vec3 ViewVector(mat4 camera_transform, vec3 camera_position,
                vec3 world_position) {
  vec3 to_camera = camera_position - world_position;
  if (!CameraTransformIsOrthographic(camera_transform)) {
    return to_camera;
  }
  vec3 forward = normalize(vec3(camera_transform[0][2], camera_transform[1][2],
                                camera_transform[2][2]));
  return forward * dot(to_camera, forward);
}

#endif  // VIEW_VECTOR_GLSL_
