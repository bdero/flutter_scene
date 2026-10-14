import 'dart:typed_data';

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
