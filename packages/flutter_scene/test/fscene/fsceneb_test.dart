// Covers the .fsceneb binary container: round-tripping a document plus its
// embedded payload chunks, deterministic output, chunk alignment, and the
// malformed-input guards. All GPU-free (no realization).

import 'dart:typed_data';

import 'package:flutter_scene/fscene.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _ramp(int length) =>
    Uint8List.fromList(List.generate(length, (i) => i & 0xFF));

// A document with a couple of nodes and payload chunks of deliberately
// awkward (non-8-multiple) lengths to exercise chunk padding.
SceneDocument _sample() {
  final doc = SceneDocument();
  doc.generator = 'fsceneb_test';
  doc.createNode(name: 'world', root: true);
  doc.addPayload(
    PayloadSpec(
      doc.newId(),
      encoding: PayloadEncoding.vertexBuffer,
      layout: 'unskinned',
      bytes: _ramp(48),
    ),
  );
  doc.addPayload(
    PayloadSpec(
      doc.newId(),
      encoding: PayloadEncoding.indexBuffer,
      bytes: _ramp(5), // not a multiple of the alignment
    ),
  );
  doc.addPayload(
    PayloadSpec(doc.newId(), encoding: PayloadEncoding.bytes, bytes: _ramp(13)),
  );
  return doc;
}

void main() {
  group('writeFsceneb / readFsceneb', () {
    test('round-trips the document and every payload byte', () {
      final doc = _sample();
      final restored = readFsceneb(writeFsceneb(doc));

      expect(restored.documentId, doc.documentId);
      expect(restored.generator, 'fsceneb_test');
      expect(restored.rootNodes.single.name, 'world');

      expect(restored.payloads.length, doc.payloads.length);
      for (final entry in doc.payloads.entries) {
        final restoredPayload = restored.payload(entry.key);
        expect(restoredPayload, isNotNull);
        expect(restoredPayload!.encoding, entry.value.encoding);
        expect(restoredPayload.layout, entry.value.layout);
        expect(restoredPayload.bytes, equals(entry.value.bytes));
      }
    });

    test('a document with no payloads round-trips', () {
      final doc = SceneDocument();
      doc.createNode(name: 'solo', root: true);
      final restored = readFsceneb(writeFsceneb(doc));
      expect(restored.payloads, isEmpty);
      expect(restored.rootNodes.single.name, 'solo');
    });

    test('output is deterministic for a given document', () {
      final doc = _sample();
      expect(writeFsceneb(doc), equals(writeFsceneb(doc)));
    });

    test('header is well-formed and the container is 8-byte aligned', () {
      final bytes = writeFsceneb(_sample());
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'FSCB');
      final view = ByteData.sublistView(bytes);
      expect(view.getUint32(4, Endian.little), kFscenebVersion);
      expect(view.getUint32(8, Endian.little), bytes.length);
      expect(bytes.length % 8, 0);
    });
  });

  group('malformed input', () {
    test('a bad magic is rejected', () {
      final bytes = writeFsceneb(_sample());
      bytes[0] = 0;
      expect(() => readFsceneb(bytes), throwsA(isA<FscenebFormatException>()));
    });

    test('a truncated header is rejected', () {
      expect(
        () => readFsceneb(Uint8List(4)),
        throwsA(isA<FscenebFormatException>()),
      );
    });

    test('writing a payload with no bytes is rejected', () {
      final doc = SceneDocument();
      doc.addPayload(PayloadSpec(doc.newId(), encoding: PayloadEncoding.bytes));
      expect(() => writeFsceneb(doc), throwsA(isA<FscenebFormatException>()));
    });
  });
}
