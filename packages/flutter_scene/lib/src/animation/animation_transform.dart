part of '../animation.dart';

/// A decomposed animation transform consisting of a translation, rotation, and scale.
class DecomposedTransform {
  /// The translation component of the transform.
  Vector3 translation = Vector3.zero();

  /// The rotation component of the transform.
  Quaternion rotation = Quaternion.identity();

  /// The scale component of the transform.
  Vector3 scale = Vector3.all(1.0);

  /// Constructs a new instance of [DecomposedTransform].
  DecomposedTransform({
    required this.translation,
    required this.rotation,
    required this.scale,
  });

  /// Constructs a new instance of [DecomposedTransform] from a [Matrix4].
  DecomposedTransform.fromMatrix(Matrix4 matrix) {
    matrix.decompose(translation, rotation, scale);

    // TODO(bdero): Why do some of the bind pose quaternions end up being more
    //              than 180 degrees?
    double angle = 2 * acos(rotation.w);
    if (angle >= pi) {
      rotation.setAxisAngle(-rotation.axis, 2 * pi - angle);
    }
  }

  /// Converts this [DecomposedTransform] to a [Matrix4].
  Matrix4 toMatrix4() {
    return Matrix4.compose(translation, rotation, scale);
  }

  /// Returns a deep copy of this transform.
  DecomposedTransform clone() {
    return DecomposedTransform(
      translation: translation.clone(),
      rotation: rotation.clone(),
      scale: scale.clone(),
    );
  }
}

/// Per-node animation state held by an [AnimationPlayer].
///
/// Pairs the node's static [bindPose] (its rest transform) with a
/// scratch [animatedPose] that the player resets each frame and that
/// active [AnimationClip]s additively blend into.
class AnimationTransforms {
  /// The node's rest-pose transform, captured when the node is first
  /// registered with an [AnimationPlayer].
  DecomposedTransform bindPose;

  /// Scratch transform mutated by clips during [AnimationPlayer.update].
  ///
  /// Reset to a copy of [bindPose] at the start of each frame.
  DecomposedTransform animatedPose = DecomposedTransform(
    translation: Vector3.zero(),
    rotation: Quaternion.identity(),
    scale: Vector3.all(1.0),
  );

  /// Creates an [AnimationTransforms] anchored at the supplied bind pose.
  AnimationTransforms({required this.bindPose});
}
