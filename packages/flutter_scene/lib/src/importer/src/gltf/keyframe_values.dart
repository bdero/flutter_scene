import 'dart:typed_data';

/// A sampler's keyframe values, with a cubic spline's in-tangents and
/// out-tangents split out. The tangents are null for other interpolations.
typedef GltfKeyframes = ({
  Float32List values,
  Float32List? inTangents,
  Float32List? outTangents,
});

/// Splits a sampler's decoded [output] into [GltfKeyframes]. A CUBICSPLINE
/// output stores an in-tangent, a value, and an out-tangent per keyframe,
/// each [componentCount] floats.
GltfKeyframes splitGltfKeyframes(
  Float32List output, {
  required int componentCount,
  required bool cubicSpline,
}) {
  if (!cubicSpline || componentCount <= 0) {
    return (
      values: Float32List.fromList(output),
      inTangents: null,
      outTangents: null,
    );
  }
  final keyframes = output.length ~/ (componentCount * 3);
  final inTangents = Float32List(keyframes * componentCount);
  final values = Float32List(keyframes * componentCount);
  final outTangents = Float32List(keyframes * componentCount);
  for (var keyframe = 0; keyframe < keyframes; keyframe++) {
    for (var component = 0; component < componentCount; component++) {
      final source = keyframe * componentCount * 3 + component;
      final target = keyframe * componentCount + component;
      inTangents[target] = output[source];
      values[target] = output[source + componentCount];
      outTangents[target] = output[source + componentCount * 2];
    }
  }
  return (values: values, inTangents: inTangents, outTangents: outTangents);
}
