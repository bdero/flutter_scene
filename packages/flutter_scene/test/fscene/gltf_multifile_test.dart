// Covers multi-file glTF import. The method: take a corpus .glb, "unpack" it
// into the .gltf form (JSON with external-uri buffers/images plus a resolver
// returning the bytes), import it through importGltfToSceneDocument, and assert
// the result equals the direct .glb import. Equality means the external-buffer
// resolution, the multi-buffer offset rebasing, and the uri-image embedding all
// reproduce the single-file path exactly.
//
// Runs only when the source GLB corpus is present (CI without it skips).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:flutter_scene/src/importer/in_memory_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('importGltfToSceneDocument', () {
    for (final name in const [
      'fcar.glb',
      'dash.glb',
      'flutter_logo_baked.glb',
    ]) {
      test(
        'unpacked $name equals the .glb import (single external buffer)',
        () {
          final glb = _load(name);
          if (glb == null) return;
          final unpacked = _unpack(glb);
          _expectEquivalent(
            importGltfToSceneDocument(
              unpacked.gltf,
              resolveUri: unpacked.resolve,
            ),
            importGlbToSceneDocument(glb),
          );
        },
      );
    }

    test('unpacked fcar.glb equals the .glb import (two external buffers)', () {
      final glb = _load('fcar.glb');
      if (glb == null) return;
      final unpacked = _unpack(glb, prependPadBuffer: true);
      _expectEquivalent(
        importGltfToSceneDocument(unpacked.gltf, resolveUri: unpacked.resolve),
        importGlbToSceneDocument(glb),
      );
    });

    test('a textured model with the image as an external file embeds it', () {
      final glb = _load('flutter_logo_baked.glb');
      if (glb == null) return;
      final unpacked = _unpack(glb, externalizeImages: true);
      _expectEquivalent(
        importGltfToSceneDocument(unpacked.gltf, resolveUri: unpacked.resolve),
        importGlbToSceneDocument(glb),
      );
    });

    test('a data-uri buffer needs no resolver', () {
      final glb = _load('fcar.glb');
      if (glb == null) return;
      final unpacked = _unpack(glb, dataUriBuffer: true);
      _expectEquivalent(
        importGltfToSceneDocument(
          unpacked.gltf,
          resolveUri: (_) => null, // never called: the buffer is a data uri
        ),
        importGlbToSceneDocument(glb),
      );
    });
  });
}

// Rewrites a GLB into the .gltf form: the embedded binary chunk becomes one (or
// two) external buffers, optionally images become external files or the buffer
// becomes a data uri. Returns the JSON bytes and a resolver for the files.
({Uint8List gltf, GltfUriResolver resolve}) _unpack(
  Uint8List glb, {
  bool prependPadBuffer = false,
  bool externalizeImages = false,
  bool dataUriBuffer = false,
}) {
  final container = parseGlb(glb);
  final json = _deepCopyJson(container.json);
  final chunk = container.binaryChunk;
  final files = <String, Uint8List>{};

  if (dataUriBuffer) {
    final uri = 'data:application/octet-stream;base64,${base64Encode(chunk)}';
    json['buffers'] = [
      {'byteLength': chunk.length, 'uri': uri},
    ];
  } else if (prependPadBuffer) {
    // A 16-byte pad buffer at index 0 forces the real data to buffer 1 with a
    // non-zero base offset, exercising the rebasing.
    final pad = Uint8List(16);
    files['pad.bin'] = pad;
    files['data.bin'] = chunk;
    json['buffers'] = [
      {'byteLength': pad.length, 'uri': 'pad.bin'},
      {'byteLength': chunk.length, 'uri': 'data.bin'},
    ];
    for (final view in (json['bufferViews'] as List).cast<Map>()) {
      view['buffer'] = 1;
    }
  } else {
    files['data.bin'] = chunk;
    json['buffers'] = [
      {'byteLength': chunk.length, 'uri': 'data.bin'},
    ];
  }

  if (externalizeImages) {
    final views = (json['bufferViews'] as List).cast<Map>();
    final images = (json['images'] as List?)?.cast<Map>() ?? const [];
    for (var i = 0; i < images.length; i++) {
      final image = images[i];
      final viewIndex = image['bufferView'] as int?;
      if (viewIndex == null) continue;
      final view = views[viewIndex];
      final offset = (view['byteOffset'] as int?) ?? 0;
      final length = view['byteLength'] as int;
      // Offsets in `chunk` regardless of the buffer split, since the data
      // buffer holds the original chunk verbatim.
      final bytes = Uint8List.sublistView(chunk, offset, offset + length);
      final fileName = 'image_$i.bin';
      files[fileName] = Uint8List.fromList(bytes);
      image.remove('bufferView');
      image['uri'] = fileName;
    }
  }

  final gltf = Uint8List.fromList(utf8.encode(jsonEncode(json)));
  return (gltf: gltf, resolve: (uri) => files[uri]);
}

void _expectEquivalent(SceneDocument actual, SceneDocument expected) {
  expect(actual.nodes.length, expected.nodes.length, reason: 'nodes');
  expect(actual.resources.length, expected.resources.length, reason: 'res');
  expect(actual.skins.length, expected.skins.length, reason: 'skins');
  expect(actual.animations.length, expected.animations.length, reason: 'anim');
  expect(actual.payloads.length, expected.payloads.length, reason: 'payloads');
  final a = actual.payloads.values.map((p) => p.bytes).toList();
  final b = expected.payloads.values.map((p) => p.bytes).toList();
  for (var i = 0; i < a.length; i++) {
    expect(listEquals(a[i], b[i]), isTrue, reason: 'payload $i bytes differ');
  }
}

Map<String, Object?> _deepCopyJson(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

Uint8List? _load(String name) {
  final path = _resolve('examples/assets_src/$name');
  if (!File(path).existsSync()) {
    // ignore: avoid_print
    print('Test data missing ($path) - skipping.');
    return null;
  }
  return File(path).readAsBytesSync();
}

String _resolve(String relative) {
  for (final prefix in ['', '../../']) {
    final candidate = '$prefix$relative';
    if (File(candidate).existsSync()) return candidate;
  }
  return relative;
}
