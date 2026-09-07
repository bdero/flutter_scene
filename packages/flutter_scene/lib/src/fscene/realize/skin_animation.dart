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
    final values = _floats(document.payload(channel.keyframes));
    final name = nodes[channel.target]?.name ?? channel.targetName ?? '';
    // Cubic tangents live in payloads of their own, one per keyframe like
    // the values. A channel that claims cubic but has lost a tangent chunk
    // (a hand-edited or partially merged document) falls back to linear
    // rather than failing to realize: the keyframes alone are still a sound
    // timeline, which is why they are stored apart from the tangents.
    var interpolation = _interpolationOf(channel.interpolation);
    var inTangents = channel.inTangents == null
        ? null
        : _floats(document.payload(channel.inTangents!));
    var outTangents = channel.outTangents == null
        ? null
        : _floats(document.payload(channel.outTangents!));
    if (interpolation == engine.TimelineInterpolation.cubic &&
        (inTangents == null ||
            outTangents == null ||
            inTangents.length != values.length ||
            outTangents.length != values.length)) {
      interpolation = engine.TimelineInterpolation.linear;
      inTangents = null;
      outTangents = null;
    }

    final engine.AnimationProperty property;
    final engine.PropertyResolver resolver;
    switch (channel.property) {
      case AnimationProperty.translation:
        property = engine.AnimationProperty.translation;
        resolver = engine.PropertyResolver.makeTranslationTimeline(
          times,
          _vec3List(values),
          interpolation: interpolation,
          inTangents: inTangents == null ? null : _vec3List(inTangents),
          outTangents: outTangents == null ? null : _vec3List(outTangents),
        );
      case AnimationProperty.rotation:
        property = engine.AnimationProperty.rotation;
        resolver = engine.PropertyResolver.makeRotationTimeline(
          times,
          _quaternionList(values),
          interpolation: interpolation,
          inTangents: inTangents == null ? null : _quaternionList(inTangents),
          outTangents: outTangents == null
              ? null
              : _quaternionList(outTangents),
        );
      case AnimationProperty.scale:
        property = engine.AnimationProperty.scale;
        resolver = engine.PropertyResolver.makeScaleTimeline(
          times,
          _vec3List(values),
          interpolation: interpolation,
          inTangents: inTangents == null ? null : _vec3List(inTangents),
          outTangents: outTangents == null ? null : _vec3List(outTangents),
        );
      case AnimationProperty.weights:
        // The keyframes payload is the flattened glTF shape, one weight per
        // target per keyframe. Trailing floats past a whole keyframe are
        // dropped rather than trusted.
        final targetCount = times.isEmpty ? 0 : values.length ~/ times.length;
        final used = times.length * targetCount;
        property = engine.AnimationProperty.weights;
        resolver = engine.PropertyResolver.makeMorphWeightsTimeline(
          times,
          Float32List.sublistView(values, 0, used),
          targetCount: targetCount,
          interpolation: interpolation,
          inTangents: inTangents == null
              ? null
              : Float32List.sublistView(inTangents, 0, used),
          outTangents: outTangents == null
              ? null
              : Float32List.sublistView(outTangents, 0, used),
        );
    }
    channels.add(
      engine.AnimationChannel(
        bindTarget: engine.BindKey(nodeName: name, property: property),
        resolver: resolver,
      ),
    );
  }
  if (channels.isEmpty) return null;
  return engine.Animation(name: spec.name, channels: channels);
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

/// Maps a document channel's interpolation onto the engine's timeline modes.
/// A channel written before interpolation was recorded has none, and loads
/// linear.
engine.TimelineInterpolation _interpolationOf(
  AnimationInterpolation? interpolation,
) => switch (interpolation) {
  AnimationInterpolation.step => engine.TimelineInterpolation.step,
  AnimationInterpolation.cubic => engine.TimelineInterpolation.cubic,
  AnimationInterpolation.linear || null => engine.TimelineInterpolation.linear,
};
