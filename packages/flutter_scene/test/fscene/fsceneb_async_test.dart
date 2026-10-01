// Covers readFscenebAsync: the same result as the synchronous reader, for a
// document rich enough that the isolate hop has to carry payload buffers,
// nested nodes and a manifest across, plus the error path.

import 'dart:typed_data';

import 'package:flutter_scene/fscene.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _ramp(int length) =>
    Uint8List.fromList(List.generate(length, (i) => i & 0xFF));

SceneDocument _sample() {
  final doc = SceneDocument();
  doc.generator = 'fsceneb_async_test';
  final child = doc.createNode(name: 'child');
  doc.createNode(name: 'world', root: true).children.add(child.id);
  doc.addPayload(
    PayloadSpec(
      doc.newId(),
      encoding: PayloadEncoding.vertexBuffer,
      layout: 'unskinned',
      bytes: _ramp(48),
    ),
  );
  // Large and repetitive, so the writer gzips it and the reader has to inflate
  // in the worker.
  doc.addPayload(
    PayloadSpec(
      doc.newId(),
      encoding: PayloadEncoding.bytes,
      bytes: Uint8List(256 * 1024),
    ),
  );
  return doc;
}

void main() {
  test('parses a container off the calling isolate, byte for byte', () async {
    final doc = _sample();
    final encoded = writeFsceneb(doc);

    final restored = await readFscenebAsync(encoded);

    expect(restored.documentId, doc.documentId);
    expect(restored.generator, 'fsceneb_async_test');
    expect(restored.rootNodes.single.name, 'world');
    expect(
      restored.node(restored.rootNodes.single.children.single)!.name,
      'child',
    );
    expect(restored.payloads.length, doc.payloads.length);
    for (final entry in doc.payloads.entries) {
      final payload = restored.payload(entry.key);
      expect(payload, isNotNull);
      expect(payload!.encoding, entry.value.encoding);
      expect(payload.layout, entry.value.layout);
      expect(payload.bytes, equals(entry.value.bytes));
    }
  });

  test('matches readFsceneb on the same bytes', () async {
    final encoded = writeFsceneb(_sample());
    final sync = readFsceneb(encoded);
    final async = await readFscenebAsync(encoded);
    expect(writeFsceneb(async), equals(writeFsceneb(sync)));
  });

  test('a malformed container throws through the isolate', () async {
    final bytes = writeFsceneb(_sample());
    bytes[0] = 0;
    await expectLater(
      readFscenebAsync(bytes),
      throwsA(isA<FscenebFormatException>()),
    );
  });
}
