import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

/// Removes cubic spline tangents, leaving one value per keyframe.
Float32List selectGltfKeyframeValues(
  Float32List values, {
  required int componentCount,
  required bool cubicSpline,
}) {
  if (!cubicSpline) return Float32List.fromList(values);
  final stride = componentCount * 3;
  final result = <double>[];
  for (var i = 0; i + stride <= values.length; i += stride) {
    result.addAll(values.sublist(i + componentCount, i + componentCount * 2));
  }
  return Float32List.fromList(result);
}

/// Selects where glTF coordinates become native scene coordinates.
enum GltfCoordinatePolicy {
  /// Keeps glTF data unchanged and converts once at the imported root.
  runtimeBoundary,

  /// Converts glTF data while producing native scene resources.
  bakeNative,
}

extension GltfCoordinateConversion on GltfCoordinatePolicy {
  /// Whether vertex and document data are converted during import.
  bool get bakesNative => this == GltfCoordinatePolicy.bakeNative;

  /// Whether packed source triangles use the opposite native winding.
  bool get sourceWindingFlipped => false;

  /// Converts a source position or translation.
  Vector3 convertPosition(Vector3 value) =>
      bakesNative ? Vector3(value.x, value.y, -value.z) : value.clone();

  /// Converts a source direction.
  Vector3 convertDirection(Vector3 value) =>
      bakesNative ? Vector3(value.x, value.y, -value.z) : value.clone();

  /// Converts a source rotation using `F * R * F`.
  Quaternion convertRotation(Quaternion value) => bakesNative
      ? Quaternion(-value.x, -value.y, value.z, value.w)
      : value.clone();

  /// Converts a source transform using `F * M * F`.
  Matrix4 convertTransform(Matrix4 value) {
    final result = value.clone();
    if (!bakesNative) return result;
    for (var column = 0; column < 4; column++) {
      for (var row = 0; row < 4; row++) {
        if ((row == 2) != (column == 2)) {
          final index = column * 4 + row;
          result.storage[index] = -result.storage[index];
        }
      }
    }
    return result;
  }

  /// Converts column-major source matrices using `F * M * F`.
  Float32List convertMatrices(Float32List values) {
    final result = Float32List.fromList(values);
    if (!bakesNative) return result;
    for (var base = 0; base + 16 <= result.length; base += 16) {
      for (var column = 0; column < 4; column++) {
        for (var row = 0; row < 4; row++) {
          if ((row == 2) != (column == 2)) {
            final index = base + column * 4 + row;
            result[index] = -result[index];
          }
        }
      }
    }
    return result;
  }

  /// Converts packed animation values after cubic tangents are removed.
  Float32List convertAnimationValues(
    Float32List values, {
    required String targetPath,
  }) {
    final result = Float32List.fromList(values);
    if (!bakesNative) return result;
    switch (targetPath) {
      case 'translation':
        for (var i = 2; i < result.length; i += 3) {
          result[i] = -result[i];
        }
      case 'rotation':
        for (var i = 0; i + 3 < result.length; i += 4) {
          result[i] = -result[i];
          result[i + 1] = -result[i + 1];
        }
    }
    return result;
  }
}
