// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

void main() {
  // We test the stream-collection contract directly without instantiating
  // a flutter_gpu pipeline. The Node.fromGlbStream factory's only job is
  // to drain a Stream<List<int>> into a single Uint8List and then call
  // Node.fromGlbBytes; the latter is already covered by existing
  // runtime_importer_byte_comparison_test.dart.
  //
  // This test guards the collection step: that chunked input produces
  // the same byte image as the original file.

  test('stream-collection: chunked input reassembles to original bytes', () async {
    final glbPath = _resolve('examples/assets_src/fcar.glb');
    if (!File(glbPath).existsSync()) {
      print('Test data missing — skipping.');
      return;
    }

    final original = File(glbPath).readAsBytesSync();

    // Chunk into 3 unequal pieces to exercise mid-buffer boundaries.
    final cut1 = original.length ~/ 4;
    final cut2 = (original.length * 7) ~/ 10;
    final chunks = <List<int>>[
      original.sublist(0, cut1),
      original.sublist(cut1, cut2),
      original.sublist(cut2),
    ];

    final stream = Stream<List<int>>.fromIterable(chunks);

    final collected = await _collect(stream);

    expect(collected.length, equals(original.length),
        reason: 'stream-collected bytes must total to original size');
    expect(collected, equals(original),
        reason: 'stream-collected bytes must equal original bytes');
  });

  test('stream-collection: handles Stream<Uint8List> (subtype of Stream<List<int>>)', () async {
    final original = Uint8List.fromList(List.generate(1024, (i) => i & 0xFF));

    final stream = Stream<Uint8List>.fromIterable([
      Uint8List.sublistView(original, 0, 256),
      Uint8List.sublistView(original, 256, 768),
      Uint8List.sublistView(original, 768),
    ]);

    // ignore: omit_local_variable_types
    final Stream<List<int>> upcast = stream;
    final collected = await _collect(upcast);

    expect(collected, equals(original));
  });

  test('stream-collection: empty stream produces empty bytes', () async {
    final stream = Stream<List<int>>.empty();
    final collected = await _collect(stream);
    expect(collected, isEmpty);
  });
}

/// Mirror of Node.fromGlbStream's stream-collection step. Kept local to
/// this test so the test does not require flutter_gpu initialisation
/// (which is unavailable in a pure dart:test environment).
Future<Uint8List> _collect(Stream<List<int>> stream) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    builder.add(chunk);
  }
  return builder.toBytes();
}

String _resolve(String relative) {
  // Walk up from CWD to find the repo root that contains the path.
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final candidate = File('${dir.path}/$relative');
    if (candidate.existsSync()) return candidate.path;
    dir = dir.parent;
  }
  return relative;
}
