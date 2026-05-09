part of '../animation.dart';

class AnimationPlayer {
  final Map<Node, AnimationTransforms> _targetTransforms = {};
  final Map<String, AnimationClip> _clips = {};
  int? _previousTimeInMilliseconds;

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

  AnimationClip? getClipByName(String name) {
    return _clips[name];
  }

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
