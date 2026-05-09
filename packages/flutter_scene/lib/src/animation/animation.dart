part of '../animation.dart';

enum AnimationProperty { translation, rotation, scale }

class BindKey implements Comparable<BindKey> {
  final String nodeName;
  final AnimationProperty property;

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

class AnimationChannel {
  final BindKey bindTarget;
  final PropertyResolver resolver;

  AnimationChannel({required this.bindTarget, required this.resolver});
}

class Animation {
  final String name;
  final List<AnimationChannel> channels;
  final double _endTime;

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

  double get endTime => _endTime;
}
