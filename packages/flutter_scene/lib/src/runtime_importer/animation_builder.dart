import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart';
import 'package:flutter_scene/src/importer/gltf.dart';

import '../animation.dart';
import '../node.dart';

/// Builds an engine [Animation] from a glTF animation. Each glTF channel
/// becomes an engine [AnimationChannel] keyed by the target node's name and
/// property (translation/rotation/scale/weights). The engine currently
/// supports linear timeline interpolation; STEP samplers degrade to "always
/// pick the next keyframe" via the same resolver, and CUBICSPLINE samplers
/// keep only the keyframe values (tangents discarded).
Animation buildAnimation({
  required GltfAnimation gltfAnimation,
  required List<GltfAccessor> accessors,
  required List<GltfBufferView> bufferViews,
  required Uint8List bufferData,
  required List<Node> engineNodes,
  required GltfCoordinatePolicy coordinatePolicy,
}) {
  final channels = <AnimationChannel>[];
  for (final channel in gltfAnimation.channels) {
    final targetNodeIdx = channel.targetNode;
    if (targetNodeIdx == null ||
        targetNodeIdx < 0 ||
        targetNodeIdx >= engineNodes.length) {
      continue;
    }
    if (channel.sampler < 0 ||
        channel.sampler >= gltfAnimation.samplers.length) {
      continue;
    }
    final sampler = gltfAnimation.samplers[channel.sampler];
    final inputAccessor = accessors[sampler.input];
    final outputAccessor = accessors[sampler.output];
    final times = readAccessorAsFloat32(inputAccessor, bufferViews, bufferData);
    final sourceValues = readAccessorAsFloat32(
      outputAccessor,
      bufferViews,
      bufferData,
    );

    AnimationProperty property;
    PropertyResolver resolver;
    final isCubic = sampler.interpolation == 'CUBICSPLINE';
    // A weights sampler is a flattened (frame x target) scalar stream, so its
    // per-keyframe component count comes from the output/input length ratio
    // instead of the target path.
    final componentCount = switch (channel.targetPath) {
      'rotation' => 4,
      'weights' =>
        times.isEmpty
            ? 0
            : sourceValues.length ~/ (times.length * (isCubic ? 3 : 1)),
      _ => 3,
    };
    final values = coordinatePolicy.convertAnimationValues(
      selectGltfKeyframeValues(
        sourceValues,
        componentCount: componentCount,
        cubicSpline: isCubic,
      ),
      targetPath: channel.targetPath,
    );

    switch (channel.targetPath) {
      case 'translation':
        property = AnimationProperty.translation;
        resolver = PropertyResolver.makeTranslationTimeline(
          times.toList(),
          _readVec3List(values),
        );
      case 'rotation':
        property = AnimationProperty.rotation;
        resolver = PropertyResolver.makeRotationTimeline(
          times.toList(),
          _readQuatList(values),
        );
      case 'scale':
        property = AnimationProperty.scale;
        resolver = PropertyResolver.makeScaleTimeline(
          times.toList(),
          _readVec3List(values),
        );
      case 'weights':
        if (componentCount == 0) continue;
        property = AnimationProperty.weights;
        resolver = PropertyResolver.makeMorphWeightsTimeline(
          times.toList(),
          values,
          targetCount: componentCount,
        );
      default:
        debugPrint(
          'Skipping unknown animation target path: ${channel.targetPath}',
        );
        continue;
    }

    final bindKey = BindKey(
      nodeName: engineNodes[targetNodeIdx].name,
      property: property,
    );
    channels.add(AnimationChannel(bindTarget: bindKey, resolver: resolver));
  }
  return Animation(name: gltfAnimation.name ?? '', channels: channels);
}

List<Vector3> _readVec3List(Float32List values) {
  final out = <Vector3>[];
  for (int i = 0; i + 3 <= values.length; i += 3) {
    out.add(Vector3(values[i], values[i + 1], values[i + 2]));
  }
  return out;
}

List<Quaternion> _readQuatList(Float32List values) {
  final out = <Quaternion>[];
  for (int i = 0; i + 4 <= values.length; i += 4) {
    out.add(Quaternion(values[i], values[i + 1], values[i + 2], values[i + 3]));
  }
  return out;
}
