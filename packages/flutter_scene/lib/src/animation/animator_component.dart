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

  final Map<String, AnimationClip> _clips = {};
  final Set<String> _missing = {};

  /// The clips this component drives, by name. Empty before it attaches.
  Map<String, AnimationClip> get clips => Map.unmodifiable(_clips);

  @override
  void onAttach() {
    // Every clip a state could ask for, instantiated once. Doing this lazily
    // in update would allocate mid-frame the first time a state is entered.
    for (final state in animator.states) {
      for (final name in _clipNamesOf(state.motion)) {
        if (_clips.containsKey(name) || _missing.contains(name)) continue;
        final animation = node.findAnimationByName(name);
        if (animation == null) {
          _missing.add(name);
          debugPrint(
            'AnimatorComponent: no animation named "$name" on '
            '"${node.name}"; states using it will play nothing',
          );
          continue;
        }
        _clips[name] = node.createAnimationClip(animation)
          ..loop = state.loop
          ..playbackTimeScale = state.speed
          ..weight = 0.0
          ..play();
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
    final weights = animator.evaluate(deltaSeconds);
    for (final entry in _clips.entries) {
      final weight = weights[entry.key] ?? 0.0;
      entry.value.weight = weight;
      // A clip at zero weight is left playing rather than paused, so its
      // time keeps advancing: a walk cycle blended back in should be where
      // the legs would have got to, not where they were when it faded out.
      entry.value.playing = true;
    }
  }

  static Iterable<String> _clipNamesOf(AnimatorMotion motion) =>
      switch (motion) {
        ClipMotion(:final clip) => [clip],
        BlendMotion(:final stops) => stops.map((stop) => stop.clip),
        BlendMotion2D(:final stops) => stops.map((stop) => stop.clip),
      };
}
