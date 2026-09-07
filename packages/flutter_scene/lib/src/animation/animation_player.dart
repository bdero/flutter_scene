part of '../animation.dart';

/// Drives playback and blending for the [AnimationClip]s on a single
/// node subtree.
///
/// Each animated [Node] lazily owns one `AnimationPlayer`; applications
/// usually interact with it indirectly through [Node.createAnimationClip]
/// and [AnimationClip].
///
/// [update] is called automatically by the scene's per-frame pre-pass.
/// It advances every clip by the frame delta, blends their results into
/// the bind pose, and writes the resulting transforms back to the bound
/// nodes.
/// {@category Animation}
class AnimationPlayer {
  final Map<Node, AnimationTransforms> _targetTransforms = {};
  final Map<String, AnimationClip> _clips = {};

  // Reused across frames: a rig is hundreds of nodes and this runs every
  // frame, so the maps are cleared rather than rebuilt.
  final Map<Node, double> _weightTotals = {};
  final Map<Node, double> _weightMultipliers = {};

  /// Instantiates [animation] as an [AnimationClip] bound to [bindTarget]
  /// and registers it with this player.
  ///
  /// The clip starts paused at time `0`; call [AnimationClip.play] to
  /// begin playback. Subsequent calls with the same [key] replace the
  /// previously registered clip, and [key] defaults to the animation's name,
  /// so registering the same animation twice replaces it.
  ///
  /// Pass a [key] to hold two instances of one animation at once. That is
  /// what a layered animator needs: an upper-body layer and a base layer can
  /// both play the same clip, masked differently and at different weights,
  /// and they have to be two clips to do it.
  AnimationClip createAnimationClip(
    Animation animation,
    Node bindTarget, {
    String? key,
  }) {
    final clip = AnimationClip(animation, bindTarget);

    // Record the default transforms this clip will mutate. Nodes already
    // bound by another clip keep their recorded bind pose; re-capturing here
    // would snapshot the current (possibly mid-playback, animated) transform
    // as the rest pose and corrupt the blend baseline for every clip.
    for (final binding in clip._bindings) {
      final transforms = _targetTransforms.putIfAbsent(
        binding.node,
        () => AnimationTransforms(bindPose: _bindPoseOf(binding.node)),
      );
      _recordChannelKind(transforms, binding);
    }

    _clips[key ?? animation.name] = clip;
    return clip;
  }

  // Marks what the bound channel drives. A weights channel captures the
  // node's rest weights once (same corruption rule as the bind pose); a
  // node whose mesh has no morph targets keeps null weight state and the
  // channel no-ops.
  static void _recordChannelKind(
    AnimationTransforms transforms,
    _ChannelBinding binding,
  ) {
    if (binding.channel.bindTarget.property != AnimationProperty.weights) {
      transforms.drivesTransform = true;
      return;
    }
    if (transforms.bindMorphWeights != null) return;
    final live = binding.node.internalMorphWeights;
    if (live == null) return;
    transforms.bindMorphWeights = Float32List.fromList(live);
    transforms.animatedMorphWeights = Float32List.fromList(live);
  }

  /// Unregisters [clip] so it no longer contributes to the blend.
  ///
  /// Bind poses recorded for its nodes are kept (other clips may share
  /// them). No-op when [clip] is not registered.
  void removeClip(AnimationClip clip) {
    _clips.removeWhere((_, registered) => identical(registered, clip));
  }

  /// Returns the registered clip whose [Animation.name] equals [name],
  /// or `null` if none is registered.
  AnimationClip? getClipByName(String name) {
    return _clips[name];
  }

  /// Re-binds every registered clip to the swapped-in subtree rooted at
  /// [newRoot] and rebuilds the bind-pose table from the new nodes' current
  /// transforms. Each clip keeps its playback state; its animation is refreshed
  /// from [animations] by name when a match exists (so reloaded curves take
  /// effect) and left as-is otherwise.
  ///
  /// Used by model hot reload ([Node.reloadFromTemplate]) after a subtree is
  /// replaced in place.
  void rebind(Node newRoot, {List<Animation> animations = const []}) {
    final byName = <String, Animation>{for (final a in animations) a.name: a};
    _targetTransforms.clear();
    for (final clip in _clips.values) {
      clip.rebind(newRoot, animation: byName[clip._animation.name]);
      for (final binding in clip._bindings) {
        final transforms = _targetTransforms.putIfAbsent(
          binding.node,
          () => AnimationTransforms(bindPose: _bindPoseOf(binding.node)),
        );
        _recordChannelKind(transforms, binding);
      }
    }
  }

  /// Prefers the node's authored decomposition over decomposing the
  /// matrix, which would move a mirrored axis's negative scale onto X and
  /// make blends on mirrored bones fade through zero scale.
  static DecomposedTransform _bindPoseOf(Node node) {
    return node.localTransformTrs?.clone() ??
        DecomposedTransform.fromMatrix(node.localTransform);
  }

  /// Advances all registered clips by [deltaSeconds] and applies their
  /// blended result to the bound nodes.
  ///
  /// Resets each animated node to its bind pose, advances every clip by
  /// the delta, normalizes per node where the clips touching it sum to
  /// more than `1`, and then
  /// writes the resulting `(translation, rotation, scale)` decomposition
  /// back to [Node.localTransform].
  void update(double deltaSeconds) {
    // Reset the animated pose state.
    for (final transforms in _targetTransforms.values) {
      transforms.animatedPose = transforms.bindPose.clone();
      final bindWeights = transforms.bindMorphWeights;
      if (bindWeights != null) {
        transforms.animatedMorphWeights!.setAll(0, bindWeights);
      }
    }

    // Normalization is per node, not per player. Once a clip can be masked
    // to part of a skeleton, the total weight on the arms and the total on
    // the legs are different numbers: an aim clip over a run would otherwise
    // halve the run everywhere, including on the legs the aim never touched.
    _weightTotals.clear();
    for (final clip in _clips.values) {
      clip.accumulateWeights(_weightTotals);
    }
    _weightMultipliers.clear();
    for (final entry in _weightTotals.entries) {
      if (entry.value > 1.0) _weightMultipliers[entry.key] = 1.0 / entry.value;
    }

    // Update and apply all clips to the animation pose state.
    for (final clip in _clips.values) {
      clip.advance(deltaSeconds);
      clip.applyToBindings(_targetTransforms, _weightMultipliers);
    }

    // Apply the animated pose to the bound joints, keeping the
    // decomposition so a later rebind anchors to consistent scale signs.
    // Nodes bound only by weights channels keep their manual transform.
    for (final entry in _targetTransforms.entries) {
      final node = entry.key;
      final transforms = entry.value;
      if (transforms.drivesTransform) {
        node.setLocalTransformTrs(transforms.animatedPose);
      }
      final animatedWeights = transforms.animatedMorphWeights;
      if (animatedWeights != null && node.internalMorphWeights != null) {
        node.setMorphWeights(animatedWeights);
      }
    }
  }
}
