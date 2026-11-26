/// Realizes a document's skins and animations onto a live node graph.
///
/// Skins bind live joint [Node]s and their inverse-bind matrices (from a
/// payload chunk) and attach to the skinned node via [Node.skin]; animations
/// become engine [engine.Animation]s parsed onto the root, ready for
/// [Node.createAnimationClip]. This layer is GPU-free; the joints texture is
/// built later by the renderer from the bound skin.
library;

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/animation.dart' as engine;
import 'package:scene/scene.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/skin.dart';

/// Builds the document's skins and animations and wires them onto the live
/// graph: skins onto their nodes, animations onto [root].
void realizeSkinsAndAnimations(
  SceneDocument document,
  Node root,
  Map<LocalId, Node> nodes,
) {
  final skins = <LocalId, Skin>{
    for (final spec in document.skins.values)
      spec.id: buildSkin(document, spec, nodes),
  };
  for (final nodeSpec in document.nodes.values) {
    final skinId = nodeSpec.skin;
    if (skinId == null) continue;
    final node = nodes[nodeSpec.id];
    final skin = skins[skinId];
    if (node != null && skin != null) node.skin = skin;
  }

  for (final spec in document.animations.values) {
    final animation = buildAnimation(document, spec, nodes);
    if (animation != null) root.addParsedAnimation(animation);
  }
}

/// Builds [spec] as a live [Skin] bound to the [nodes] joints (marking them
/// as joints). Also used by scene hot reload to rebuild a changed skin.
Skin buildSkin(
  SceneDocument document,
  SkinSpec spec,
  Map<LocalId, Node> nodes,
) {
  final skin = Skin();
  for (final jointId in spec.joints) {
    final node = nodes[jointId];
    if (node != null) node.isJoint = true;
    // A null joint renders as identity, matching Node.clone's skin handling.
    skin.joints.add(node);
  }
  final matrices = _matrices(document.payload(spec.inverseBindMatrices));
  for (var i = 0; i < spec.joints.length; i++) {
    skin.inverseBindMatrices.add(
      i < matrices.length ? matrices[i] : Matrix4.identity(),
    );
  }
  return skin;
}

/// Builds [spec] as an engine [engine.Animation], with channels bound by the
/// [nodes] targets' names. Returns null when the animation has no channels.
/// Also used by scene hot reload to rebuild changed animations.
engine.Animation? buildAnimation(
  SceneDocument document,
  AnimationSpec spec,
  Map<LocalId, Node> nodes,
) {
  final channels = <engine.AnimationChannel>[];
  for (final channel in spec.channels) {
    final times = _floats(document.payload(channel.timeline)).toList();
    final floats = _floats(document.payload(channel.keyframes));
    final name = nodes[channel.target]?.name ?? channel.targetName ?? '';
    final interpolation = _interpolation(channel.interpolation);

    final engine.AnimationProperty property;
    final engine.PropertyResolver resolver;
    switch (channel.property) {
      case AnimationProperty.translation:
        final keyframes = _keyframes(floats, 3, channel.interpolation);
        property = engine.AnimationProperty.translation;
        resolver = engine.PropertyResolver.makeTranslationTimeline(
          times,
          _vec3List(keyframes.values),
          interpolation: interpolation,
          inTangents: _vec3ListOrNull(keyframes.inTangents),
          outTangents: _vec3ListOrNull(keyframes.outTangents),
        );
      case AnimationProperty.rotation:
        final keyframes = _keyframes(floats, 4, channel.interpolation);
        property = engine.AnimationProperty.rotation;
        resolver = engine.PropertyResolver.makeRotationTimeline(
          times,
          _quaternionList(keyframes.values),
          interpolation: interpolation,
          inTangents: _quaternionListOrNull(keyframes.inTangents),
          outTangents: _quaternionListOrNull(keyframes.outTangents),
        );
      case AnimationProperty.scale:
        final keyframes = _keyframes(floats, 3, channel.interpolation);
        property = engine.AnimationProperty.scale;
        resolver = engine.PropertyResolver.makeScaleTimeline(
          times,
          _vec3List(keyframes.values),
          interpolation: interpolation,
          inTangents: _vec3ListOrNull(keyframes.inTangents),
          outTangents: _vec3ListOrNull(keyframes.outTangents),
        );
      case AnimationProperty.weights:
        // The keyframes payload is the flattened glTF shape, one weight per
        // target per keyframe. Trailing floats past a whole keyframe are
        // dropped rather than trusted.
        final width = _floatsPerComponent(channel.interpolation);
        final targetCount = times.isEmpty
            ? 0
            : floats.length ~/ (times.length * width);
        final keyframes = _keyframes(
          Float32List.sublistView(
            floats,
            0,
            times.length * targetCount * width,
          ),
          targetCount,
          channel.interpolation,
        );
        property = engine.AnimationProperty.weights;
        resolver = engine.PropertyResolver.makeMorphWeightsTimeline(
          times,
          keyframes.values,
          targetCount: targetCount,
          interpolation: interpolation,
          inTangents: keyframes.inTangents,
          outTangents: keyframes.outTangents,
        );
    }
    channels.add(
      engine.AnimationChannel(
        bindTarget: engine.BindKey(nodeName: name, property: property),
        resolver: resolver,
      ),
    );
  }
  for (final channel in spec.pathChannels) {
    final times = _floats(document.payload(channel.timeline)).toList();
    final floats = _floats(document.payload(channel.keyframes));
    final name = nodes[channel.target]?.name ?? channel.targetName ?? '';
    // Same trailing-float rule as weights.
    final width = _floatsPerComponent(channel.interpolation);
    final componentCount = times.isEmpty
        ? 0
        : floats.length ~/ (times.length * width);
    if (componentCount == 0) continue;
    final keyframes = _keyframes(
      Float32List.sublistView(floats, 0, times.length * componentCount * width),
      componentCount,
      channel.interpolation,
    );
    channels.add(
      engine.AnimationChannel(
        bindTarget: engine.BindKey(
          nodeName: name,
          property: engine.AnimationProperty.path,
          path: channel.path,
        ),
        resolver: engine.PropertyResolver.makePathTimeline(
          channel.path,
          times,
          keyframes.values,
          componentCount: componentCount,
          interpolation: _interpolation(channel.interpolation),
          inTangents: keyframes.inTangents,
          outTangents: keyframes.outTangents,
        ),
      ),
    );
  }
  if (channels.isEmpty) return null;
  return engine.Animation(name: spec.name, channels: channels);
}

engine.AnimationInterpolation _interpolation(
  AnimationInterpolation interpolation,
) => switch (interpolation) {
  AnimationInterpolation.step => engine.AnimationInterpolation.step,
  AnimationInterpolation.linear => engine.AnimationInterpolation.linear,
  AnimationInterpolation.cubicSpline =>
    engine.AnimationInterpolation.cubicSpline,
};

// The floats a keyframe holds per component: a cubic spline's in-tangent,
// value, and out-tangent, or the value alone.
int _floatsPerComponent(AnimationInterpolation interpolation) =>
    interpolation == AnimationInterpolation.cubicSpline ? 3 : 1;

typedef _Keyframes = ({
  Float32List values,
  Float32List? inTangents,
  Float32List? outTangents,
});

// Splits a channel's keyframe floats, [componentCount] per value. A cubic
// spline's tangents sit on either side of each value, as glTF lays them out.
_Keyframes _keyframes(
  Float32List floats,
  int componentCount,
  AnimationInterpolation interpolation,
) {
  if (interpolation != AnimationInterpolation.cubicSpline) {
    return (values: floats, inTangents: null, outTangents: null);
  }
  final stride = componentCount * 3;
  final count = stride <= 0 ? 0 : floats.length ~/ stride;
  final values = Float32List(count * componentCount);
  final inTangents = Float32List(count * componentCount);
  final outTangents = Float32List(count * componentCount);
  for (var keyframe = 0; keyframe < count; keyframe++) {
    final from = keyframe * stride;
    final to = keyframe * componentCount;
    final end = to + componentCount;
    inTangents.setRange(to, end, floats, from);
    values.setRange(to, end, floats, from + componentCount);
    outTangents.setRange(to, end, floats, from + componentCount * 2);
  }
  return (values: values, inTangents: inTangents, outTangents: outTangents);
}

List<Matrix4> _matrices(PayloadSpec? payload) {
  final floats = _floats(payload);
  final count = floats.length ~/ 16;
  return [
    for (var i = 0; i < count; i++)
      Matrix4.fromFloat32List(
        Float32List.fromList(floats.sublist(i * 16, i * 16 + 16)),
      ),
  ];
}

// Reads a payload's bytes as native-endian float32s, matching how the emitter
// (and the engine's vertex buffers) store them.
Float32List _floats(PayloadSpec? payload) {
  final bytes = payload?.bytes;
  if (bytes == null) return Float32List(0);
  if (bytes.offsetInBytes % 4 == 0) {
    return bytes.buffer.asFloat32List(
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ 4,
    );
  }
  final aligned = Uint8List.fromList(bytes);
  return aligned.buffer.asFloat32List(0, aligned.lengthInBytes ~/ 4);
}

List<Vector3> _vec3List(Float32List v) => [
  for (var i = 0; i + 3 <= v.length; i += 3) Vector3(v[i], v[i + 1], v[i + 2]),
];

List<Quaternion> _quaternionList(Float32List v) => [
  for (var i = 0; i + 4 <= v.length; i += 4)
    Quaternion(v[i], v[i + 1], v[i + 2], v[i + 3]),
];

List<Vector3>? _vec3ListOrNull(Float32List? v) =>
    v == null ? null : _vec3List(v);

List<Quaternion>? _quaternionListOrNull(Float32List? v) =>
    v == null ? null : _quaternionList(v);
