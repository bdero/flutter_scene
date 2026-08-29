/// Drives a node's animation clips from an [Animator].
library;

import 'package:flutter/foundation.dart';

import 'package:flutter_scene/src/animation.dart' show AnimationClip;
import 'package:flutter_scene/src/animation/animator.dart';
import 'package:flutter_scene/src/components/component.dart';

/// Plays the clips an [Animator] asks for on the node this is attached to.
///
/// The machine decides weights; this is the part that puts them on clips. It
/// binds clip names to the node's own animations on attach, so a state naming
/// a clip the model does not have is reported once rather than failing
/// silently every frame.
///
/// ```dart
/// final animator = Animator(
///   states: [
///     AnimatorState('move', BlendMotion('speed', [
///       (at: 0, clip: 'Idle'),
///       (at: 4, clip: 'Run'),
///     ])),
///   ],
/// );
/// node.addComponent(AnimatorComponent(animator));
/// // then, from gameplay:
/// animator.parameters.setNumber('speed', velocity.length);
/// ```
/// {@category Animation}
class AnimatorComponent extends Component {
  /// Drives [animator] on the owning node.
  AnimatorComponent(this.animator);

  /// The machine deciding what plays.
  final Animator animator;

  // Keyed by layer and clip name, because two layers may play the same
  // animation -- an aim over a run, both wanting the same idle underneath --
  // and each needs its own weight and its own mask.
  final Map<String, AnimationClip> _clips = {};
  final Set<String> _missing = {};

  /// The clips this component drives, keyed `layer:clip`. Empty before it
  /// attaches.
  Map<String, AnimationClip> get clips => Map.unmodifiable(_clips);

  /// The clip [name] on [layer], or null when the model has no such
  /// animation.
  AnimationClip? clipFor(String layer, String name) => _clips['$layer:$name'];

  @override
  void onAttach() {
    // Every clip a state could ask for, instantiated once. Doing this lazily
    // in update would allocate mid-frame the first time a state is entered.
    for (final layer in animator.layers) {
      for (final state in layer.states) {
        for (final name in _clipNamesOf(state.motion)) {
          final key = '${layer.name}:$name';
          if (_clips.containsKey(key) || _missing.contains(key)) continue;
          final animation = node.findAnimationByName(name);
          if (animation == null) {
            _missing.add(key);
            debugPrint(
              'AnimatorComponent: no animation named "$name" on '
              '"${node.name}"; states using it will play nothing',
            );
            continue;
          }
          _clips[key] = node.createAnimationClip(animation, key: key)
            ..loop = state.loop
            ..playbackTimeScale = state.speed
            ..mask = layer.mask
            ..weight = 0.0
            ..play();
        }
      }
    }
  }

  @override
  void onDetach() {
    for (final clip in _clips.values) {
      node.removeAnimationClip(clip);
    }
    _clips.clear();
    _missing.clear();
  }

  @override
  void update(double deltaSeconds) {
    if (!isAttached || _clips.isEmpty) return;
    for (final result in animator.evaluateLayers(deltaSeconds)) {
      final layer = result.layer;
      final prefix = '${layer.name}:';
      for (final entry in _clips.entries) {
        if (!entry.key.startsWith(prefix)) continue;
        final name = entry.key.substring(prefix.length);
        // The layer's own weight scales what its states asked for, so
        // fading a layer out fades everything on it together.
        entry.value.weight = (result.weights[name] ?? 0.0) * layer.weight;
        // A clip at zero weight is left playing rather than paused, so its
        // time keeps advancing: a walk cycle blended back in should be where
        // the legs would have got to, not where they were when it faded out.
        entry.value.playing = true;
      }
    }
  }

  /// Re-reads every layer's mask onto its clips.
  ///
  /// Masks resolve to per-node weights when they are set, so changing one
  /// after attach -- widening an upper-body mask down the spine, say -- needs
  /// saying rather than being noticed per frame.
  void refreshMasks() {
    for (final layer in animator.layers) {
      final prefix = '${layer.name}:';
      for (final entry in _clips.entries) {
        if (entry.key.startsWith(prefix)) entry.value.mask = layer.mask;
      }
    }
  }

  static Iterable<String> _clipNamesOf(AnimatorMotion motion) =>
      switch (motion) {
        ClipMotion(:final clip) => [clip],
        BlendMotion(:final stops) => stops.map((stop) => stop.clip),
        BlendMotion2D(:final stops) => stops.map((stop) => stop.clip),
      };
}
