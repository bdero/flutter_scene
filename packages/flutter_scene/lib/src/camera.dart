import 'dart:math';
import 'dart:ui' as ui;

import 'package:vector_math/vector_math.dart';

abstract class Camera {
  Vector3 get position;
  Matrix4 getViewTransform(ui.Size dimensions);
}

Matrix4 _matrix4LookAt(Vector3 position, Vector3 target, Vector3 up) {
  Vector3 forward = (target - position).normalized();
  Vector3 right = up.cross(forward).normalized();
  up = forward.cross(right).normalized();

  return Matrix4(
    right.x,
    up.x,
    forward.x,
    0.0, //
    right.y,
    up.y,
    forward.y,
    0.0, //
    right.z,
    up.z,
    forward.z,
    0.0, //
    -right.dot(position),
    -up.dot(position),
    -forward.dot(position),
    1.0, //
  );
}

Matrix4 _matrix4Perspective(
  double fovRadiansY,
  double aspectRatio,
  double zNear,
  double zFar,
) {
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

class PerspectiveCamera extends Camera {
  PerspectiveCamera({
    this.fovRadiansY = 45 * degrees2Radians,
    Vector3? position,
    Vector3? target,
    Vector3? up,
    this.fovNear = 0.1,
    this.fovFar = 1000.0,
  }) : position = position ?? Vector3(0, 0, -5),
       target = target ?? Vector3(0, 0, 0),
       up = up ?? Vector3(0, 1, 0);

  double fovRadiansY;
  @override
  Vector3 position = Vector3(0, 0, -5);
  Vector3 target;
  Vector3 up;
  double fovNear;
  double fovFar;

  @override
  Matrix4 getViewTransform(ui.Size dimensions) {
    return _matrix4Perspective(
          fovRadiansY,
          dimensions.width / dimensions.height,
          fovNear,
          fovFar,
        ) *
        _matrix4LookAt(position, target, up);
  }
}
