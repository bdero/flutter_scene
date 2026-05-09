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

  /// Builds an [Animation] from a deserialized flatbuffer animation
  /// description.
  ///
  /// Channels with missing or malformed keyframe data are skipped with
  /// no error. Node references are resolved against [sceneNodes] to
  /// recover the target name for each channel's [BindKey].
  factory Animation.fromFlatbuffer(
    fb.Animation animation,
    List<Node> sceneNodes,
  ) {
    List<AnimationChannel> channels = [];
    for (fb.Channel fbChannel in animation.channels!) {
      if (fbChannel.node < 0 ||
          fbChannel.node >= sceneNodes.length ||
          fbChannel.timeline == null) {
        continue;
      }

      final outTimes = fbChannel.timeline!;
      AnimationProperty outProperty;
      PropertyResolver resolver;

      // TODO(bdero): Why are the entries in the keyframe value arrays not
      //              contiguous in the flatbuffer? We should be able to get rid
      //              of the subloops below and just memcpy instead.
      switch (fbChannel.keyframesType) {
        case fb.KeyframesTypeId.TranslationKeyframes:
          outProperty = AnimationProperty.translation;
          fb.TranslationKeyframes? keyframes =
              fbChannel.keyframes as fb.TranslationKeyframes?;
          if (keyframes?.values == null) {
            continue;
          }
          List<Vector3> outValues = [];
          for (int i = 0; i < keyframes!.values!.length; i++) {
            outValues.add(keyframes.values![i].toVector3());
          }
          resolver = PropertyResolver.makeTranslationTimeline(
            outTimes,
            outValues,
          );
          break;
        case fb.KeyframesTypeId.RotationKeyframes:
          outProperty = AnimationProperty.rotation;
          fb.RotationKeyframes? keyframes =
              fbChannel.keyframes as fb.RotationKeyframes?;
          if (keyframes?.values == null) {
            continue;
          }
          List<Quaternion> outValues = [];
          for (int i = 0; i < keyframes!.values!.length; i++) {
            outValues.add(keyframes.values![i].toQuaternion());
          }
          resolver = PropertyResolver.makeRotationTimeline(outTimes, outValues);
          break;
        case fb.KeyframesTypeId.ScaleKeyframes:
          outProperty = AnimationProperty.scale;
          fb.ScaleKeyframes? keyframes =
              fbChannel.keyframes as fb.ScaleKeyframes?;
          if (keyframes?.values == null) {
            continue;
          }
          List<Vector3> outValues = [];
          for (int i = 0; i < keyframes!.values!.length; i++) {
            outValues.add(keyframes.values![i].toVector3());
          }
          resolver = PropertyResolver.makeScaleTimeline(outTimes, outValues);
          break;
        default:
          continue;
      }

      final bindKey = BindKey(
        nodeName: sceneNodes[fbChannel.node].name,
        property: outProperty,
      );
      channels.add(AnimationChannel(bindTarget: bindKey, resolver: resolver));
    }

    return Animation(name: animation.name!.toString(), channels: channels);
  }

  /// Time of the last keyframe across all channels, in seconds.
  ///
  /// [AnimationClip.advance] uses this to clamp playback time and
  /// implement looping.
  double get endTime => _endTime;
}
