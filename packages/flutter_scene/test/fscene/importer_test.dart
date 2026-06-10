// Covers the glTF -> .fscene importer. The load-bearing check is byte parity:
// a primitive's packed vertex/index payload must equal packGltfPrimitive's
// output, which is exactly what the .model emitter stores. This is the
// project's proven import-verification method (compare bytes against the
// known-good packer rather than eyeballing renders).
//
// Runs only when the source GLB corpus is present (CI without it skips).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:flutter_scene/src/importer/in_memory_import.dart';
import 'package:flutter_scene/src/importer/src/gltf/bounds_baker.dart';
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

    test('emits skins and animations for a skinned, animated model', () {
      final path = _resolve('examples/assets_src/dash.glb');
      if (!File(path).existsSync()) {
        // ignore: avoid_print
        print('Test data missing ($path) - skipping.');
        return;
      }
      final document = importGlbToSceneDocument(File(path).readAsBytesSync());
      expect(document.skins, isNotEmpty);
      expect(document.animations, isNotEmpty);

      // Every skin references an inverse-bind-matrices payload with bytes.
      for (final skin in document.skins.values) {
        expect(skin.joints, isNotEmpty);
        final payload = document.payload(skin.inverseBindMatrices);
        expect(payload?.encoding, PayloadEncoding.matrices);
        expect(payload?.bytes, isNotNull);
      }
      // Every channel references timeline + keyframe payloads with bytes.
      final channels = document.animations.values.expand((a) => a.channels);
      expect(channels, isNotEmpty);
      for (final channel in channels) {
        expect(document.payload(channel.timeline)?.bytes, isNotNull);
        expect(document.payload(channel.keyframes)?.bytes, isNotNull);
      }
    });

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

  group('geometry bounds', () {
    for (final name in ['dash.glb', 'two_triangles.glb']) {
      test('skinned primitives carry pose-union bounds ($name)', () {
        final path = _resolve('examples/assets_src/$name');
        if (!File(path).existsSync()) {
          // ignore: avoid_print
          print('Test data missing ($path) - skipping.');
          return;
        }
        final bytes = File(path).readAsBytesSync();
        final container = parseGlb(bytes);
        final doc = parseGltfJson(container.json);
        final document = importGlbToSceneDocument(bytes);

        final unions = bakeSkinnedPoseUnionAabbs(doc, container.binaryChunk);
        expect(unions, isNotEmpty, reason: '$name has skinned nodes');

        // Geometries are emitted in mesh/primitive walk order; map each
        // skinned node's mesh primitives back to their geometry resources.
        final geometries = document.resources.values
            .whereType<GeometryResource>()
            .toList();
        int meshOffset(int meshIndex) {
          var offset = 0;
          for (var m = 0; m < meshIndex; m++) {
            offset += doc.meshes[m].primitives.where((p) => p.mode == 4).length;
          }
          return offset;
        }

        var checked = 0;
        for (final entry in unions.entries) {
          final meshIndex = doc.nodes[entry.key].mesh!;
          final offset = meshOffset(meshIndex);
          for (var i = 0; i < entry.value.length; i++) {
            final union = entry.value[i];
            if (union == null) continue; // jointless primitive: rest bounds
            final bounds = geometries[offset + i].bounds;
            expect(bounds, isNotNull, reason: '$name mesh $meshIndex prim $i');
            // BoundsSpec vectors store float32; quantize the baker's doubles.
            expect(bounds!.min.x, _f32(union.minX));
            expect(bounds.min.y, _f32(union.minY));
            expect(bounds.min.z, _f32(union.minZ));
            expect(bounds.max.x, _f32(union.maxX));
            expect(bounds.max.y, _f32(union.maxY));
            expect(bounds.max.z, _f32(union.maxZ));
            checked++;
          }
        }
        expect(checked, greaterThan(0));
      });
    }

    test('animated poses extend bounds beyond the rest AABB (dash.glb)', () {
      final path = _resolve('examples/assets_src/dash.glb');
      if (!File(path).existsSync()) {
        // ignore: avoid_print
        print('Test data missing ($path) - skipping.');
        return;
      }
      final bytes = File(path).readAsBytesSync();
      final container = parseGlb(bytes);
      final doc = parseGltfJson(container.json);
      final unions = bakeSkinnedPoseUnionAabbs(doc, container.binaryChunk);

      var anyDiffers = false;
      for (final entry in unions.entries) {
        final prims = doc.meshes[doc.nodes[entry.key].mesh!].primitives
            .where((p) => p.mode == 4)
            .toList();
        for (var i = 0; i < entry.value.length; i++) {
          final union = entry.value[i];
          if (union == null) continue;
          final accessor = doc.accessors[prims[i].attributes['POSITION']!];
          final min = accessor.min;
          final max = accessor.max;
          if (min == null || max == null) continue;
          if (union.minX != min[0] ||
              union.minY != min[1] ||
              union.minZ != min[2] ||
              union.maxX != max[0] ||
              union.maxY != max[1] ||
              union.maxZ != max[2]) {
            anyDiffers = true;
          }
        }
      }
      expect(anyDiffers, isTrue);
    });

    test('unskinned primitives keep their rest bounds (fcar.glb)', () {
      final path = _resolve('examples/assets_src/fcar.glb');
      if (!File(path).existsSync()) {
        // ignore: avoid_print
        print('Test data missing ($path) - skipping.');
        return;
      }
      final bytes = File(path).readAsBytesSync();
      final container = parseGlb(bytes);
      final doc = parseGltfJson(container.json);
      final document = importGlbToSceneDocument(bytes);

      final geometries = document.resources.values
          .whereType<GeometryResource>()
          .toList();
      final prims = [
        for (final mesh in doc.meshes)
          for (final p in mesh.primitives)
            if (p.mode == 4) p,
      ];
      expect(geometries, hasLength(prims.length));
      var checked = 0;
      for (var i = 0; i < prims.length; i++) {
        final accessor = doc.accessors[prims[i].attributes['POSITION']!];
        final min = accessor.min;
        final max = accessor.max;
        if (min == null || max == null) continue;
        final bounds = geometries[i].bounds;
        expect(bounds, isNotNull);
        expect(bounds!.min.x, min[0]);
        expect(bounds.min.y, min[1]);
        expect(bounds.min.z, min[2]);
        expect(bounds.max.x, max[0]);
        expect(bounds.max.y, max[1]);
        expect(bounds.max.z, max[2]);
        checked++;
      }
      expect(checked, greaterThan(0));
    });
  });
}

double _f32(double v) => (Float32List(1)..[0] = v)[0];

String _resolve(String relative) {
  for (final prefix in ['', '../../']) {
    final candidate = '$prefix$relative';
    if (File(candidate).existsSync() || Directory(candidate).existsSync()) {
      return candidate;
    }
  }
  return relative;
}
