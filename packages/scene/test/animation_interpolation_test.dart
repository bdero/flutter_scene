/// Covers how a channel's interpolation and cubic tangents survive the
/// document codec, and that recording them changed nothing for the linear
/// channels that every existing document is made of.
library;

import 'dart:typed_data';

import 'package:scene/scene.dart';
import 'package:test/test.dart';

LocalId _floatPayload(SceneDocument document, List<double> values) {
  final floats = Float32List.fromList(values);
  final id = document.newId();
  document.addPayload(
    PayloadSpec(
      id,
      encoding: PayloadEncoding.floats,
      bytes: floats.buffer.asUint8List(
        floats.offsetInBytes,
        floats.lengthInBytes,
      ),
    ),
  );
  return id;
}

/// A document with one animation whose single channel is built by [channel]
/// from the timeline and keyframe payload ids.
SceneDocument _document(
  AnimationChannelSpec Function(SceneDocument, LocalId, LocalId) channel,
) {
  final document = SceneDocument();
  final node = NodeSpec(id: document.newId(), name: 'joint');
  document.addNode(node);
  final timeline = _floatPayload(document, [0.0, 1.0]);
  final keyframes = _floatPayload(document, [0, 0, 0, 10, 0, 0]);
  document.addAnimation(
    AnimationSpec(
      document.newId(),
      name: 'wave',
      channels: [channel(document, timeline, keyframes)],
    ),
  );
  return document;
}

AnimationChannelSpec _only(SceneDocument document) =>
    document.animations.values.single.channels.single;

void main() {
  test('a linear channel encodes exactly as it did before', () {
    final document = _document(
      (doc, timeline, keyframes) => AnimationChannelSpec(
        target: doc.nodes.keys.first,
        targetName: 'joint',
        property: AnimationProperty.translation,
        timeline: timeline,
        keyframes: keyframes,
      ),
    );

    final encoded = encodeDocument(document);
    final animation =
        (encoded['animations'] as Map).values.single as Map<String, dynamic>;
    final channel = (animation['channels'] as List).single as Map;

    // Absent, not written as "linear". Every document ever written has these
    // channels, and they must not all churn because the field now exists.
    expect(channel.keys, isNot(contains('interpolation')));
    expect(channel.keys, isNot(contains('inTangents')));
    expect(channel.keys, isNot(contains('outTangents')));
  });

  test('a step channel round-trips', () {
    final document = _document(
      (doc, timeline, keyframes) => AnimationChannelSpec(
        target: doc.nodes.keys.first,
        property: AnimationProperty.translation,
        timeline: timeline,
        keyframes: keyframes,
        interpolation: AnimationInterpolation.step,
      ),
    );

    final decoded = decodeDocument(encodeDocument(document));

    expect(_only(decoded).interpolation, AnimationInterpolation.step);
    expect(_only(decoded).inTangents, isNull);
  });

  test('a cubic channel round-trips with its tangents', () {
    final document = _document((doc, timeline, keyframes) {
      return AnimationChannelSpec(
        target: doc.nodes.keys.first,
        property: AnimationProperty.translation,
        timeline: timeline,
        keyframes: keyframes,
        interpolation: AnimationInterpolation.cubic,
        inTangents: _floatPayload(doc, [0, 0, 0, 4, 0, 0]),
        outTangents: _floatPayload(doc, [2, 0, 0, 0, 0, 0]),
      );
    });

    final decoded = decodeDocument(encodeDocument(document));
    final channel = _only(decoded);

    expect(channel.interpolation, AnimationInterpolation.cubic);
    expect(channel.inTangents, isNotNull);
    expect(channel.outTangents, isNotNull);
    expect(decoded.payloads[channel.inTangents!], isNotNull);
    expect(decoded.payloads[channel.outTangents!], isNotNull);
    expect(
      channel.inTangents,
      isNot(channel.outTangents),
      reason: 'the two tangent streams must not collapse to one chunk',
    );
  });

  test('a cubic channel keeps one keyframe value per key', () {
    // The whole point of tangents living in their own chunks: the keyframes
    // chunk stays the shape every existing reader assumes, so a reader that
    // knows nothing about interpolation still sees a sound linear timeline
    // rather than reading packed tangents as keys.
    final document = _document((doc, timeline, keyframes) {
      return AnimationChannelSpec(
        target: doc.nodes.keys.first,
        property: AnimationProperty.translation,
        timeline: timeline,
        keyframes: keyframes,
        interpolation: AnimationInterpolation.cubic,
        inTangents: _floatPayload(doc, [0, 0, 0, 4, 0, 0]),
        outTangents: _floatPayload(doc, [2, 0, 0, 0, 0, 0]),
      );
    });

    final channel = _only(document);
    int floats(LocalId id) => document.payloads[id]!.bytes!.lengthInBytes ~/ 4;

    expect(
      floats(channel.keyframes),
      floats(channel.timeline) * 3,
      reason: 'three floats per key, one Vector3, cubic or not',
    );
    expect(floats(channel.inTangents!), floats(channel.keyframes));
    expect(floats(channel.outTangents!), floats(channel.keyframes));
  });
}
