import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart';
import 'package:flutter_scene_importer/gltf.dart';

import '../animation.dart';
import '../node.dart';

/// Builds an engine [Animation] from a glTF animation. Each glTF channel
/// becomes an engine [AnimationChannel] keyed by the target node's name and
/// transform property (translation/rotation/scale). The engine currently
/// supports linear timeline interpolation; STEP samplers degrade to "always
/// pick the next keyframe" via the same resolver, and CUBICSPLINE samplers
/// keep only the keyframe values (tangents discarded).
Animation buildAnimation({
  required GltfAnimation gltfAnimation,
  required List<GltfAccessor> accessors,
  required List<GltfBufferView> bufferViews,
  required Uint8List bufferData,
  required List<Node> engineNodes,
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
    final inputView = bufferViews[inputAccessor.bufferView!];
    final outputView = bufferViews[outputAccessor.bufferView!];
    final times = readAccessorAsFloat32(inputAccessor, inputView, bufferData);
    final values = readAccessorAsFloat32(
      outputAccessor,
      outputView,
      bufferData,
    );

    AnimationProperty property;
    PropertyResolver resolver;
    final isCubic = sampler.interpolation == 'CUBICSPLINE';

    switch (channel.targetPath) {
      case 'translation':
        property = AnimationProperty.translation;
        resolver = PropertyResolver.makeTranslationTimeline(
          times.toList(),
          _readVec3List(values, isCubic),
        );
      case 'rotation':
        property = AnimationProperty.rotation;
        resolver = PropertyResolver.makeRotationTimeline(
          times.toList(),
          _readQuatList(values, isCubic),
        );
      case 'scale':
        property = AnimationProperty.scale;
        resolver = PropertyResolver.makeScaleTimeline(
          times.toList(),
          _readVec3List(values, isCubic),
        );
      case 'weights':
        // Morph target weights — not supported by flutter_scene yet.
        debugPrint('Skipping morph-target animation channel (weights).');
        continue;
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

List<Vector3> _readVec3List(Float32List values, bool isCubic) {
  // CUBICSPLINE has 3 vec3s per keyframe (in-tangent, value, out-tangent).
  // We only consume the value; tangents are discarded.
  final stride = isCubic ? 9 : 3;
  final valueOffset = isCubic ? 3 : 0;
  final out = <Vector3>[];
  for (int i = 0; i + stride <= values.length; i += stride) {
    out.add(
      Vector3(
        values[i + valueOffset],
        values[i + valueOffset + 1],
        values[i + valueOffset + 2],
      ),
    );
  }
  return out;
}

List<Quaternion> _readQuatList(Float32List values, bool isCubic) {
  // CUBICSPLINE has 3 vec4s per keyframe.
  final stride = isCubic ? 12 : 4;
  final valueOffset = isCubic ? 4 : 0;
  final out = <Quaternion>[];
  for (int i = 0; i + stride <= values.length; i += stride) {
    out.add(
      Quaternion(
        values[i + valueOffset],
        values[i + valueOffset + 1],
        values[i + valueOffset + 2],
        values[i + valueOffset + 3],
      ),
    );
  }
  return out;
}
