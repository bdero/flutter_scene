import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math.dart';
import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:scene/scene.dart' show AnimationInterpolation;

import '../animation.dart';
import '../node.dart';

/// Builds an engine [Animation] from a glTF animation. Each glTF channel
/// becomes an engine [AnimationChannel] keyed by the target node's name and
/// property (translation/rotation/scale/weights), or one per target node of
/// a `KHR_animation_pointer` channel's engine paths. Each channel keeps its
/// sampler's interpolation, and a CUBICSPLINE sampler keeps its tangents.
Animation buildAnimation({
  required GltfAnimation gltfAnimation,
  required List<GltfAccessor> accessors,
  required List<GltfBufferView> bufferViews,
  required Uint8List bufferData,
  required List<Node> engineNodes,
  required List<GltfPunctualLight> lights,
}) {
  final channels = <AnimationChannel>[];
  for (final channel in gltfAnimation.channels) {
    if (channel.pathTargets.isNotEmpty) {
      channels.addAll(
        _buildPathChannels(
          channel,
          gltfAnimation.samplers,
          accessors,
          bufferViews,
          bufferData,
          engineNodes,
          lights,
        ),
      );
      continue;
    }
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
    final interpolation = _interpolationOf(sampler);
    final isCubic = interpolation == AnimationInterpolation.cubicSpline;
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
    final keyframes = splitGltfKeyframes(
      sourceValues,
      componentCount: componentCount,
      cubicSpline: isCubic,
    );

    switch (channel.targetPath) {
      case 'translation':
        property = AnimationProperty.translation;
        resolver = PropertyResolver.makeTranslationTimeline(
          times.toList(),
          _readVec3List(keyframes.values),
          interpolation: interpolation,
          inTangents: _readVec3ListOrNull(keyframes.inTangents),
          outTangents: _readVec3ListOrNull(keyframes.outTangents),
        );
      case 'rotation':
        property = AnimationProperty.rotation;
        resolver = PropertyResolver.makeRotationTimeline(
          times.toList(),
          _readQuatList(keyframes.values),
          interpolation: interpolation,
          inTangents: _readQuatListOrNull(keyframes.inTangents),
          outTangents: _readQuatListOrNull(keyframes.outTangents),
        );
      case 'scale':
        property = AnimationProperty.scale;
        resolver = PropertyResolver.makeScaleTimeline(
          times.toList(),
          _readVec3List(keyframes.values),
          interpolation: interpolation,
          inTangents: _readVec3ListOrNull(keyframes.inTangents),
          outTangents: _readVec3ListOrNull(keyframes.outTangents),
        );
      case 'weights':
        if (componentCount == 0) continue;
        property = AnimationProperty.weights;
        resolver = PropertyResolver.makeMorphWeightsTimeline(
          times.toList(),
          keyframes.values,
          targetCount: componentCount,
          interpolation: interpolation,
          inTangents: keyframes.inTangents,
          outTangents: keyframes.outTangents,
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

Iterable<AnimationChannel> _buildPathChannels(
  GltfAnimationChannel channel,
  List<GltfAnimationSampler> samplers,
  List<GltfAccessor> accessors,
  List<GltfBufferView> bufferViews,
  Uint8List bufferData,
  List<Node> engineNodes,
  List<GltfPunctualLight> lights,
) sync* {
  if (channel.sampler < 0 || channel.sampler >= samplers.length) return;
  final sampler = samplers[channel.sampler];
  final interpolation = _interpolationOf(sampler);
  final times = readAccessorAsFloat32(
    accessors[sampler.input],
    bufferViews,
    bufferData,
  ).toList();
  final count = channel.pathComponentCount;
  final keyframes = splitGltfKeyframes(
    readAccessorAsFloat32(accessors[sampler.output], bufferViews, bufferData),
    componentCount: count,
    cubicSpline: interpolation == AnimationInterpolation.cubicSpline,
  );
  final values = convertGltfPathKeyframes(channel, lights, keyframes.values);
  if (times.isEmpty || values.length != times.length * count) {
    debugPrint(
      'Skipping animation pointer "${channel.pointer}" whose keyframes are '
      'not $count floats each',
    );
    return;
  }
  Float32List? tangents(Float32List? source) {
    if (source == null) return null;
    return convertGltfPathTangents(channel, lights, source, keyframes.values);
  }

  final inTangents = tangents(keyframes.inTangents);
  final outTangents = tangents(keyframes.outTangents);
  for (final target in channel.pathTargets) {
    if (target.node < 0 || target.node >= engineNodes.length) continue;
    yield AnimationChannel(
      bindTarget: BindKey(
        nodeName: engineNodes[target.node].name,
        property: AnimationProperty.path,
        path: target.path,
      ),
      resolver: PropertyResolver.makePathTimeline(
        target.path,
        times,
        values,
        componentCount: count,
        interpolation: interpolation,
        inTangents: inTangents,
        outTangents: outTangents,
      ),
    );
  }
}

AnimationInterpolation _interpolationOf(GltfAnimationSampler sampler) {
  return switch (sampler.interpolation) {
    'STEP' => AnimationInterpolation.step,
    'CUBICSPLINE' => AnimationInterpolation.cubicSpline,
    _ => AnimationInterpolation.linear,
  };
}

List<Vector3>? _readVec3ListOrNull(Float32List? values) =>
    values == null ? null : _readVec3List(values);

List<Quaternion>? _readQuatListOrNull(Float32List? values) =>
    values == null ? null : _readQuatList(values);

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
