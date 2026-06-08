// Covers the glTF -> .fscene importer. The load-bearing check is byte parity:
// a primitive's packed vertex/index payload must equal packGltfPrimitive's
// output, which is exactly what the .model emitter stores. This is the
// project's proven import-verification method (compare bytes against the
// known-good packer rather than eyeballing renders).
//
// Runs only when the source GLB corpus is present (CI without it skips).

import 'dart:io';

import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:flutter_scene/src/importer/in_memory_import.dart';
import 'package:flutter_test/flutter_test.dart';

// Every committed corpus GLB; each is checked when present.
const _corpus = [
  'fcar.glb',
  'dash.glb',
  'two_triangles.glb',
  'flutter_logo_baked.glb',
];

void main() {
  group('buildSceneDocument', () {
    for (final name in _corpus) {
      test('packs $name geometry byte-for-byte like the shared packer', () {
        final path = _resolve('examples/assets_src/$name');
        final file = File(path);
        if (!file.existsSync()) {
          // ignore: avoid_print
          print('Test data missing ($path) - skipping.');
          return;
        }
        final bytes = file.readAsBytesSync();
        final container = parseGlb(bytes);
        final doc = parseGltfJson(container.json);
        final document = importGlbToSceneDocument(bytes);

        // Expected packed primitives, in the same mesh/primitive walk order
        // the emitter uses.
        final expected = <PackedPrimitive>[];
        for (final mesh in doc.meshes) {
          for (final primitive in mesh.primitives) {
            if (primitive.mode != 4) continue;
            expected.add(
              packGltfPrimitive(
                primitive: primitive,
                accessors: doc.accessors,
                bufferViews: doc.bufferViews,
                bufferData: container.binaryChunk,
              ),
            );
          }
        }

        final geometries = document.resources.values
            .whereType<GeometryResource>()
            .toList();
        expect(geometries, hasLength(expected.length));
        expect(expected, isNotEmpty);

        for (var i = 0; i < expected.length; i++) {
          final packed = expected[i];
          final geometry = geometries[i];
          final vertexPayload = document.payload(geometry.vertices!)!;
          final indexPayload = document.payload(geometry.indices!)!;
          expect(
            vertexPayload.bytes,
            equals(packed.vertexBytes),
            reason: '$name geometry $i vertex bytes',
          );
          expect(
            indexPayload.bytes,
            equals(packed.indexBytes),
            reason: '$name geometry $i index bytes',
          );
          expect(
            vertexPayload.layout,
            packed.isSkinned ? 'skinned' : 'unskinned',
          );
          expect(
            indexPayload.format,
            packed.indices32Bit ? 'uint32' : 'uint16',
          );
        }
      });
    }

    test('declares right-handed glTF coordinates and a generator', () {
      final path = _resolve('examples/assets_src/fcar.glb');
      if (!File(path).existsSync()) {
        // ignore: avoid_print
        print('Test data missing ($path) - skipping.');
        return;
      }
      final document = importGlbToSceneDocument(File(path).readAsBytesSync());
      expect(document.stage.handedness, Handedness.right);
      expect(document.stage.upAxis, UpAxis.y);
      expect(document.generator, isNotNull);
      expect(document.roots, isNotEmpty);
    });

    test('is deterministic: re-importing yields identical container bytes', () {
      final path = _resolve('examples/assets_src/fcar.glb');
      if (!File(path).existsSync()) {
        // ignore: avoid_print
        print('Test data missing ($path) - skipping.');
        return;
      }
      final bytes = File(path).readAsBytesSync();
      expect(
        importGlbToFscenebBytes(bytes),
        equals(importGlbToFscenebBytes(bytes)),
      );
    });
  });
}

String _resolve(String relative) {
  for (final prefix in ['', '../../']) {
    final candidate = '$prefix$relative';
    if (File(candidate).existsSync() || Directory(candidate).existsSync()) {
      return candidate;
    }
  }
  return relative;
}
