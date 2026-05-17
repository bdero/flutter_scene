part of '../animation.dart';

/// Drives playback and blending for the [AnimationClip]s on a single
/// node subtree.
///
/// Each animated [Node] lazily owns one `AnimationPlayer`; applications
/// usually interact with it indirectly through [Node.createAnimationClip]
/// and [AnimationClip].
///
/// [update] is called automatically by the scene's per-frame pre-pass.
/// It advances every clip by the wall-clock delta since the previous
/// frame, blends their results into the bind pose, and writes the
/// resulting transforms back to the bound nodes.
class AnimationPlayer {
  final Map<Node, AnimationTransforms> _targetTransforms = {};
  final Map<String, AnimationClip> _clips = {};
  int? _previousTimeInMilliseconds;

  /// Instantiates [animation] as an [AnimationClip] bound to [bindTarget]
  /// and registers it with this player.
  ///
  /// The clip starts paused at time `0`; call [AnimationClip.play] to
  /// begin playback. Subsequent calls with the same [Animation.name]
  /// replace the previously registered clip.
  AnimationClip createAnimationClip(Animation animation, Node bindTarget) {
    final clip = AnimationClip(animation, bindTarget);

    // Record all of the unique default transforms that this AnimationClip
    // will mutate.
    for (final binding in clip._bindings) {
      _targetTransforms[binding.node] = AnimationTransforms(
        bindPose: DecomposedTransform.fromMatrix(binding.node.localTransform),
      );
    }

    _clips[animation.name] = clip;
    return clip;
  }

  /// Returns the registered clip whose [Animation.name] equals [name],
  /// or `null` if none is registered.
  AnimationClip? getClipByName(String name) {
    return _clips[name];
  }

  /// Advances all registered clips by the wall-clock delta since the
  /// previous call and applies their blended result to the bound nodes.
  ///
  /// Resets each animated node to its bind pose, advances every clip by
  /// the delta, normalizes weights when their sum exceeds `1`, and then
  /// writes the resulting `(translation, rotation, scale)` decomposition
  /// back to [Node.localTransform].
  void update() {
    // Initialize the previous time if it has not been set yet.
    _previousTimeInMilliseconds ??= DateTime.now().millisecondsSinceEpoch;

    int newTime = DateTime.now().millisecondsSinceEpoch;
    double deltaTime = (newTime - _previousTimeInMilliseconds!) / 1000.0;
    _previousTimeInMilliseconds = newTime;

    // Reset the animated pose state.
    for (final transforms in _targetTransforms.values) {
      transforms.animatedPose = transforms.bindPose.clone();
    }

    // Compute a weight multiplier for normalizing the animation.
    double totalWeight = 0.0;
    for (final clip in _clips.values) {
      totalWeight += clip.weight;
    }
    double weightMultiplier = totalWeight > 1.0 ? 1.0 / totalWeight : 1.0;

    // Update and apply all clips to the animation pose state.
    for (final clip in _clips.values) {
      clip.advance(deltaTime);
      clip.applyToBindings(_targetTransforms, weightMultiplier);
    }

    // Apply the animated pose to the bound joints.
    for (final entry in _targetTransforms.entries) {
      final node = entry.key;
      final transforms = entry.value;
      node.localTransform = transforms.animatedPose.toMatrix4();
    }
  }
}
