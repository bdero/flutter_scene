// Covers the glTF -> .fscene importer. The load-bearing check is byte parity
// against the shared packer in native-baking mode.
// Skinned geometry is stored interleaved, so its payload equals the packer's
// bytes directly; unskinned geometry is stored de-interleaved (structure of
// arrays), so its payload equals the packer's interleaved bytes split into the
// six attribute streams and concatenated. This is the project's proven
// import-verification method (compare bytes against the known-good packer
// rather than eyeballing renders).
//
// Runs only when the source GLB corpus is present (CI without it skips).

import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:scene/scene.dart';
import 'package:flutter_scene/src/geometry/interleaved_layout.dart';
import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:flutter_scene/src/importer/in_memory_import.dart';
import 'package:flutter_scene/src/importer/src/gltf/bounds_baker.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/importer/src/fscene_emitter/fscene_emitter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// Every committed corpus GLB; each is checked when present.
const _corpus = [
  'fcar.glb',
  'dash.glb',
  'two_triangles.glb',
  'flutter_logo_baked.glb',
];

void main() {
  group('buildSceneDocument', () {
    test('emits punctual lights as node components', () {
      final source = GltfDocument(
        scenes: [
          GltfScene(nodes: [0, 1, 2]),
        ],
        nodes: [
          GltfNode(name: 'Sun', light: 0),
          GltfNode(name: 'Lamp', light: 1),
          GltfNode(name: 'Cone', light: 2),
        ],
        lights: [
          GltfPunctualLight(type: 'directional', intensity: 100000),
          GltfPunctualLight(
            type: 'point',
            color: Vector3(0, 0, 1),
            intensity: 4,
            range: 12,
          ),
          GltfPunctualLight(
            type: 'spot',
            intensity: 8,
            range: 20,
            innerConeAngle: 0.1,
            outerConeAngle: 0.5,
          ),
        ],
      );

      final document = buildSceneDocument(source, Uint8List(0));
      final nodes = {for (final node in document.nodes.values) node.name: node};
      final directional = nodes['Sun']!.components.single;
      final point = nodes['Lamp']!.components.single;
      final spot = nodes['Cone']!.components.single;

      expect(directional.type, 'directionalLight');
      expect(directional.properties, isNot(contains('direction')));
      expect(
        (directional.properties['castsShadow'] as BoolValue).value,
        isFalse,
      );
      expect(
        (directional.properties['intensity'] as DoubleValue).value,
        closeTo(100000 / 683, 1e-9),
      );
      expect(point.type, 'pointLight');
      expect(
        (point.properties['intensity'] as DoubleValue).value,
        closeTo(4 / (683 * 0.0722), 1e-9),
      );
      expect((point.properties['range'] as DoubleValue).value, 12);
      expect(spot.type, 'spotLight');
      expect(
        (spot.properties['intensity'] as DoubleValue).value,
        closeTo(8 / 683, 1e-12),
      );
      expect((spot.properties['innerConeAngle'] as DoubleValue).value, 0.1);
      expect((spot.properties['outerConeAngle'] as DoubleValue).value, 0.5);
      expect((spot.properties['castsShadow'] as BoolValue).value, isFalse);
    });

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
        for (var meshIndex = 0; meshIndex < doc.meshes.length; meshIndex++) {
          final users = doc.nodes.where((node) => node.mesh == meshIndex);
          final hasSkinnedUsers = users.any((node) => node.skin != null);
          final hasUnskinnedUsers = users.any((node) => node.skin == null);
          final modes = [
            if (hasUnskinnedUsers || !hasSkinnedUsers) false,
            if (hasSkinnedUsers) true,
          ];
          final mesh = doc.meshes[meshIndex];
          for (final includeSkinning in modes) {
            for (final primitive in mesh.primitives) {
              if (primitive.mode != 4) continue;
              expected.add(
                packGltfPrimitive(
                  primitive: primitive,
                  accessors: doc.accessors,
                  bufferViews: doc.bufferViews,
                  bufferData: container.binaryChunk,
                  coordinatePolicy: GltfCoordinatePolicy.bakeNative,
                  includeSkinning: includeSkinning,
                ),
              );
            }
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
          if (packed.isSkinned) {
            expect(
              vertexPayload.layout,
              InterleavedLayoutAdapter.skinnedLayout,
            );
            expect(
              vertexPayload.bytes,
              equals(packed.vertexBytes),
              reason: '$name geometry $i skinned vertex bytes',
            );
          } else {
            // Unskinned is de-interleaved: the packer's interleaved bytes,
            // split into per-attribute streams and concatenated.
            expect(
              vertexPayload.layout,
              InterleavedLayoutAdapter.unskinnedSoaLayout,
            );
            final expectedSoa = InterleavedLayoutAdapter.concatUnskinnedStreams(
              InterleavedLayoutAdapter.splitUnskinnedAttributes(
                ByteData.sublistView(packed.vertexBytes),
                packed.vertexCount,
              ),
            );
            expect(
              vertexPayload.bytes,
              equals(expectedSoa),
              reason: '$name geometry $i unskinned SoA vertex bytes',
            );
          }
          expect(
            indexPayload.bytes,
            equals(packed.indexBytes),
            reason: '$name geometry $i index bytes',
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

    test('joint attributes without a skin emit unskinned geometry', () {
      final document = importGlbToSceneDocument(_jointedStaticGlb());
      final geometry =
          document.resources.values.singleWhere(
                (resource) => resource is GeometryResource,
              )
              as GeometryResource;
      expect(
        document.payload(geometry.vertices!)!.layout,
        InterleavedLayoutAdapter.unskinnedSoaLayout,
      );
    });

    test('a -split name hint splits the mesh into grid cells at import', () {
      final document = importGlbToSceneDocument(_splitHintGlb());
      final node = document.nodes.values.singleWhere((n) => n.name == 'Ground');
      expect(node.components.where((c) => c.type == 'mesh'), isEmpty);
      // Two triangles a world apart on x; native coordinates negate z, so
      // the z in [0, 1] source geometry bins into the z-1 cell.
      final names = [for (final c in node.children) document.nodes[c]!.name]
        ..sort();
      expect(names, ['Ground_x0_z-1', 'Ground_x2_z-1']);
      // Re-importing reproduces the same split with the same ids, so the
      // hint is safe to leave on a source asset.
      final again = importGlbToSceneDocument(_splitHintGlb());
      expect(again.nodes.keys.toSet(), document.nodes.keys.toSet());
      expect(
        [for (final c in again.nodes.values) c.name]..sort(),
        [for (final c in document.nodes.values) c.name]..sort(),
      );
    });

    test('emits a native-space document and a generator', () {
      final path = _resolve('examples/assets_src/fcar.glb');
      if (!File(path).existsSync()) {
        // ignore: avoid_print
        print('Test data missing ($path) - skipping.');
        return;
      }
      final document = importGlbToSceneDocument(File(path).readAsBytesSync());
      expect(document.formatVersion, currentFsceneVersion);
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

    // The editor imports a GLB to an editable document and saves it as a
    // `.fscene`; that document must round-trip through the text codec.
    test('imported document round-trips through writeFscene/readFscene', () {
      final path = _resolve('examples/assets_src/fcar.glb');
      if (!File(path).existsSync()) {
        // ignore: avoid_print
        print('Test data missing ($path) - skipping.');
        return;
      }
      final document = importGlbToSceneDocument(File(path).readAsBytesSync());
      final text = writeFscene(document);
      final reparsed = readFscene(text);
      expect(reparsed.nodes.length, document.nodes.length);
      expect(reparsed.resources.length, document.resources.length);
      expect(reparsed.roots, document.roots);
      // Re-serializing the reparsed document is byte-stable.
      expect(writeFscene(reparsed), text);
    });

    // Local ids are positional (a fixed allocator session), not content-derived,
    // so re-importing an edited model keeps node ids stable and prefab overrides
    // keyed by them survive. Distinct models still get distinct document ids.
    test('node ids are positional and content-independent', () {
      final fcarPath = _resolve('examples/assets_src/fcar.glb');
      final logoPath = _resolve('examples/assets_src/flutter_logo_baked.glb');
      if (!File(fcarPath).existsSync() || !File(logoPath).existsSync()) {
        // ignore: avoid_print
        print('Test data missing - skipping.');
        return;
      }
      final fcar = importGlbToSceneDocument(File(fcarPath).readAsBytesSync());
      final logo = importGlbToSceneDocument(File(logoPath).readAsBytesSync());
      // Every node id in a document shares one session, and that session is the
      // same across two different models (so ids do not depend on content).
      final fcarSessions = fcar.nodes.keys.map((id) => id.session).toSet();
      final logoSessions = logo.nodes.keys.map((id) => id.session).toSet();
      expect(fcarSessions, hasLength(1));
      expect(logoSessions, {fcarSessions.single});
      // But the two models are still distinguished by their document id.
      expect(fcar.documentId.toToken(), isNot(logo.documentId.toToken()));
      // Re-importing the same model yields identical node id tokens.
      final fcar2 = importGlbToSceneDocument(File(fcarPath).readAsBytesSync());
      expect(
        fcar2.nodes.keys.map((id) => id.toToken()).toSet(),
        fcar.nodes.keys.map((id) => id.toToken()).toSet(),
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
            expect(bounds.min.z, _f32(-union.maxZ));
            expect(bounds.max.x, _f32(union.maxX));
            expect(bounds.max.y, _f32(union.maxY));
            expect(bounds.max.z, _f32(-union.minZ));
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
        expect(bounds!.min.x, _f32(min[0]));
        expect(bounds.min.y, _f32(min[1]));
        expect(bounds.min.z, _f32(-max[2]));
        expect(bounds.max.x, _f32(max[0]));
        expect(bounds.max.y, _f32(max[1]));
        expect(bounds.max.z, _f32(-min[2]));
        checked++;
      }
      expect(checked, greaterThan(0));
    });
  });
}

// A node named `Ground-split1` with two triangles a world apart along +X
// (x in [0, 1] and [2, 3], z in [0, 1]), so a 1-unit grid split puts each in
// its own cell.
Uint8List _splitHintGlb() {
  final buffer = BytesBuilder();
  buffer.add(
    Float32List.fromList([
      // Triangle 1.
      0, 0, 0, 1, 0, 0, 0, 0, 1,
      // Triangle 2.
      2, 0, 0, 3, 0, 0, 2, 0, 1,
    ]).buffer.asUint8List(),
  );
  buffer.add(
    Float32List.fromList([
      for (var i = 0; i < 6; i++) ...[0, 1, 0],
    ]).buffer.asUint8List(),
  );
  buffer.add(Uint16List.fromList([0, 1, 2, 3, 4, 5]).buffer.asUint8List());
  final binary = buffer.takeBytes();
  final json = {
    'asset': {'version': '2.0'},
    'scene': 0,
    'scenes': [
      {
        'nodes': [0],
      },
    ],
    'nodes': [
      {'name': 'Ground-split1', 'mesh': 0},
    ],
    'meshes': [
      {
        'primitives': [
          {
            'attributes': {'POSITION': 0, 'NORMAL': 1},
            'indices': 2,
          },
        ],
      },
    ],
    'buffers': [
      {'byteLength': binary.length},
    ],
    'bufferViews': [
      {'buffer': 0, 'byteOffset': 0, 'byteLength': 72},
      {'buffer': 0, 'byteOffset': 72, 'byteLength': 72},
      {'buffer': 0, 'byteOffset': 144, 'byteLength': 12},
    ],
    'accessors': [
      {
        'bufferView': 0,
        'componentType': 5126,
        'count': 6,
        'type': 'VEC3',
        'min': [0, 0, 0],
        'max': [3, 0, 1],
      },
      {'bufferView': 1, 'componentType': 5126, 'count': 6, 'type': 'VEC3'},
      {'bufferView': 2, 'componentType': 5123, 'count': 6, 'type': 'SCALAR'},
    ],
  };
  return _glb(json, binary);
}

Uint8List _jointedStaticGlb() {
  final buffer = BytesBuilder();
  buffer.add(
    Float32List.fromList([
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      1,
      0,
      0,
      1,
      0,
      0,
      1,
      0,
      0,
      1,
      0,
      0,
      1,
    ]).buffer.asUint8List(),
  );
  buffer.add(Uint16List(12).buffer.asUint8List());
  buffer.add(
    Float32List.fromList([
      1,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
    ]).buffer.asUint8List(),
  );
  buffer.add(Uint16List.fromList([0, 1, 2]).buffer.asUint8List());
  buffer.add(Uint8List(2));
  final binary = buffer.takeBytes();
  final json = {
    'asset': {'version': '2.0'},
    'scene': 0,
    'scenes': [
      {
        'nodes': [0],
      },
    ],
    'nodes': [
      {'mesh': 0},
    ],
    'meshes': [
      {
        'primitives': [
          {
            'attributes': {
              'POSITION': 0,
              'NORMAL': 1,
              'TEXCOORD_0': 2,
              'JOINTS_0': 3,
              'WEIGHTS_0': 4,
            },
            'indices': 5,
          },
        ],
      },
    ],
    'buffers': [
      {'byteLength': binary.length},
    ],
    'bufferViews': [
      {'buffer': 0, 'byteOffset': 0, 'byteLength': 36},
      {'buffer': 0, 'byteOffset': 36, 'byteLength': 36},
      {'buffer': 0, 'byteOffset': 72, 'byteLength': 24},
      {'buffer': 0, 'byteOffset': 96, 'byteLength': 24},
      {'buffer': 0, 'byteOffset': 120, 'byteLength': 48},
      {'buffer': 0, 'byteOffset': 168, 'byteLength': 6},
    ],
    'accessors': [
      {
        'bufferView': 0,
        'componentType': 5126,
        'count': 3,
        'type': 'VEC3',
        'min': [0, 0, 0],
        'max': [1, 1, 0],
      },
      {'bufferView': 1, 'componentType': 5126, 'count': 3, 'type': 'VEC3'},
      {'bufferView': 2, 'componentType': 5126, 'count': 3, 'type': 'VEC2'},
      {'bufferView': 3, 'componentType': 5123, 'count': 3, 'type': 'VEC4'},
      {'bufferView': 4, 'componentType': 5126, 'count': 3, 'type': 'VEC4'},
      {'bufferView': 5, 'componentType': 5123, 'count': 3, 'type': 'SCALAR'},
    ],
  };
  return _glb(json, binary);
}

Uint8List _glb(Map<String, Object?> json, Uint8List binary) {
  final jsonBytes = utf8.encode(jsonEncode(json));
  final jsonLength = (jsonBytes.length + 3) & ~3;
  final binaryLength = (binary.length + 3) & ~3;
  final output = BytesBuilder();
  void uint32(int value) => output.add(
    Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little),
  );
  output.add(ascii.encode('glTF'));
  uint32(2);
  uint32(12 + 8 + jsonLength + 8 + binaryLength);
  uint32(jsonLength);
  output.add(ascii.encode('JSON'));
  output.add(jsonBytes);
  output.add(
    Uint8List(jsonLength - jsonBytes.length)
      ..fillRange(0, jsonLength - jsonBytes.length, 0x20),
  );
  uint32(binaryLength);
  output.add([0x42, 0x49, 0x4e, 0]);
  output.add(binary);
  output.add(Uint8List(binaryLength - binary.length));
  return output.takeBytes();
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
