import 'dart:math';

import 'package:vector_math/vector_math_64.dart';

Matrix4 matrix4LookAt(Vector3 position, Vector3 target, Vector3 up) {
  Vector3 forward = (target - position).normalized();
  Vector3 right = up.cross(forward).normalized();
  up = forward.cross(right).normalized();

  return Matrix4(
    right.x, up.x, forward.x, 0.0, //
    right.y, up.y, forward.y, 0.0, //
    right.z, up.z, forward.z, 0.0, //
    -right.dot(position), -up.dot(position), -forward.dot(position), 1.0, //
  );
}

Matrix4 matrix4Perspective(
    double fovRadiansY, double aspectRatio, double zNear, double zFar) {
  double height = tan(fovRadiansY * 0.5);
  double width = height * aspectRatio;

  return Matrix4(
    1.0 / width,
    0.0,
    0.0,
    0.0,
    0.0,
    1.0 / height,
    0.0,
    0.0,
    0.0,
    0.0,
    zFar / (zFar - zNear),
    1.0,
    0.0,
    0.0,
    -(zFar * zNear) / (zFar - zNear),
    0.0,
  );
}

class Camera {
  Camera(
      {this.fovRadiansY = 45 * degrees2Radians,
      Vector3? position,
      Vector3? target,
      Vector3? up})
      : position = position ?? Vector3(0, 0, -5),
        target = target ?? Vector3(0, 0, 0),
        up = up ?? Vector3(0, 1, 0);

  double fovRadiansY;
  Vector3 position;
  Vector3 target;
  Vector3 up;

  Matrix4 computeTransform(double aspectRatio) {
    return matrix4Perspective(fovRadiansY, aspectRatio, 0.1, 1000) *
        matrix4LookAt(position, target, up);
  }
}
