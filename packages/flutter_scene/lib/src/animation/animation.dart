part of '../animation.dart';

/// One of the three node-local transform components an animation channel
/// can drive.
enum AnimationProperty {
  /// Animates [Node.localTransform]'s translation.
  translation,

  /// Animates [Node.localTransform]'s rotation.
  rotation,

  /// Animates [Node.localTransform]'s scale.
  scale,
}

/// Identifies a single animation target as a (node name, property) pair.
///
/// Channel resolution is name-based rather than reference-based so that
/// an [Animation] parsed from a model can be applied to any matching
/// subtree (including cloned subtrees).
class BindKey implements Comparable<BindKey> {
  /// Name of the [Node] this channel targets, matched via
  /// [Node.getChildByName].
  final String nodeName;

  /// Which component of the node's transform this channel drives.
  final AnimationProperty property;

  /// Creates a key that targets [nodeName] / [property].
  BindKey({
    required this.nodeName,
    this.property = AnimationProperty.translation,
  });

  @override
  int compareTo(BindKey other) {
    if (nodeName == other.nodeName && property == other.property) {
      return 0;
    }
    return -1;
  }
}

/// One keyframed track within an [Animation], pairing a [BindKey] target
/// with a [PropertyResolver] that produces values over time.
class AnimationChannel {
  /// The (node, property) target this channel writes to.
  final BindKey bindTarget;

  /// The keyframe interpolator that produces values for [bindTarget].
  final PropertyResolver resolver;

  /// Creates a channel that drives [bindTarget] with [resolver].
  AnimationChannel({required this.bindTarget, required this.resolver});
}

/// A reusable description of an animation, parsed from a model.
///
/// An `Animation` is essentially a named bundle of [AnimationChannel]s,
/// each driving a single (node, property) target via a
/// [PropertyResolver]. To play an animation, instantiate it as an
/// [AnimationClip] bound to a target subtree with
/// [Node.createAnimationClip].
/// {@category Animation}
class Animation {
  /// Display name of the animation, used by [Node.findAnimationByName].
  final String name;

  /// All keyframed channels in this animation.
  final List<AnimationChannel> channels;

  final double _endTime;

  /// Creates an [Animation] with the given [name] and [channels].
  ///
  /// [endTime] is computed as the maximum end time across all channels'
  /// [PropertyResolver]s.
  Animation({this.name = '', List<AnimationChannel>? channels})
    : channels = channels ?? [],
      _endTime =
          channels?.fold<double>(0.0, (
            double previousValue,
            AnimationChannel element,
          ) {
            return max(element.resolver.getEndTime(), previousValue);
          }) ??
          0.0;

  /// Time of the last keyframe across all channels, in seconds.
  ///
  /// [AnimationClip.advance] uses this to clamp playback time and
  /// implement looping.
  double get endTime => _endTime;
}
