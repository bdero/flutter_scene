import 'package:vector_math/vector_math.dart';

/// A decomposed animation transform consisting of a translation, rotation, and scale.
class DecomposedTransform {
  /// The translation component of the transform.
  late final Vector3 translation;

  /// The rotation component of the transform.
  late final Quaternion rotation;

  /// The scale component of the transform.
  late final Vector3 scale;

  /// Constructs a new instance of [DecomposedTransform].
  DecomposedTransform({
    required this.translation,
    required this.rotation,
    required this.scale,
  });

  /// Constructs a new instance of [DecomposedTransform] from a [Matrix4].
  DecomposedTransform.fromMatrix(Matrix4 matrix) {
    matrix.decompose(translation, rotation, scale);
  }

  /// Converts this [DecomposedTransform] to a [Matrix4].
  Matrix4 toMatrix4() {
    final matrix = Matrix4.identity();
    Matrix4.compose(translation, rotation, scale);
    return matrix;
  }
}

class AnimationTransforms {
  DecomposedTransform bindPose;
  DecomposedTransform animatedPose;

  AnimationTransforms({
    required this.bindPose,
    required this.animatedPose,
  });
}
