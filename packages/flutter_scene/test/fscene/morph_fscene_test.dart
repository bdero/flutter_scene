// Covers the .fscene path for morph targets: the emitter bakes dense delta
// payloads, default weights, target names, node overrides, and weights
// animation channels; the .fsceneb container round-trips them; and the
// document animation builder decodes weights channels. Byte parity against
// the shared packer follows the project's import-verification method.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_scene/src/animation.dart' as engine;
import 'package:flutter_scene/src/fscene/realize/skin_animation.dart';
import 'package:flutter_scene/src/importer/gltf.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/importer/src/fscene_emitter/fscene_emitter.dart';
import 'package:flutter_scene/src/geometry/interleaved_layout.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';

({GltfDocument doc, Uint8List bin}) _load(String name) {
  final bytes = File('test/fixtures/$name').readAsBytesSync();
  final container = parseGlb(bytes);
  return (doc: parseGltfJson(container.json), bin: container.binaryChunk);
}

Uint8List _expectedDeltaBytes(PackedMorphTargets morph) {
  final builder = BytesBuilder(copy: false);
  void add(Float32List floats) => builder.add(
    floats.buffer.asUint8List(floats.offsetInBytes, floats.lengthInBytes),
  );
  add(morph.positionDeltas);
  if (morph.normalDeltas != null) add(morph.normalDeltas!);
  if (morph.tangentDeltas != null) add(morph.tangentDeltas!);
  return builder.toBytes();
}

void main() {
  group('emitter', () {
    test('bakes AnimatedMorphCube morph payloads and weights animation', () {
      final (:doc, :bin) = _load('AnimatedMorphCube.glb');
      final document = buildSceneDocument(doc, bin);

      final geometries = document.resources.values
          .whereType<GeometryResource>()
          .toList();
      expect(geometries, hasLength(1));
      final geometry = geometries.single;
      final morph = geometry.morphTargets!;
      expect(morph.targetCount, 2);
      expect(morph.hasNormalDeltas, isTrue);
      expect(morph.hasTangentDeltas, isTrue);
      expect(morph.defaultWeights, [0.0, 0.0]);

      // Morphed geometry stays interleaved so the realizer can stash the
      // base for CPU blending.
      final vertexPayload = document.payload(geometry.vertices!)!;
      expect(
        vertexPayload.layout,
        InterleavedLayoutAdapter.unskinnedInterleavedLayout,
      );

      // The delta payload is byte-for-byte the shared packer's slabs.
      final packed = packGltfPrimitive(
        primitive: doc.meshes.single.primitives.single,
        accessors: doc.accessors,
        bufferViews: doc.bufferViews,
        bufferData: bin,
        coordinatePolicy: GltfCoordinatePolicy.bakeNative,
      );
      expect(
        document.payload(morph.deltas)!.bytes,
        _expectedDeltaBytes(packed.morphTargets!),
      );

      final animation = document.animations.values.single;
      final channel = animation.channels.single;
      expect(channel.property, AnimationProperty.weights);
      final times = document.payload(channel.timeline)!;
      final keyframes = document.payload(channel.keyframes)!;
      expect(times.bytes!.length ~/ 4, 127);
      expect(keyframes.bytes!.length ~/ 4, 254);
    });

    test('bakes both MorphPrimitivesTest primitives with one target', () {
      final (:doc, :bin) = _load('MorphPrimitivesTest.glb');
      final document = buildSceneDocument(doc, bin);
      final geometries = document.resources.values
          .whereType<GeometryResource>()
          .toList();
      expect(geometries, hasLength(2));
      for (final geometry in geometries) {
        final morph = geometry.morphTargets!;
        expect(morph.targetCount, 1);
        expect(morph.defaultWeights, [0.5]);
        expect(morph.hasNormalDeltas, isFalse);
      }
    });

    test('a node weights override rides the mesh component', () {
      final positions = Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]);
      final deltas = Float32List.fromList([0, 0, 1, 0, 0, 1, 0, 0, 1]);
      final blob = BytesBuilder()
        ..add(positions.buffer.asUint8List())
        ..add(deltas.buffer.asUint8List());
      final doc = GltfDocument(
        scenes: [
          GltfScene(nodes: [0]),
        ],
        nodes: [
          GltfNode(name: 'morphed', mesh: 0, weights: [0.75]),
        ],
        meshes: [
          GltfMesh(
            weights: const [0.25],
            targetNames: const ['puff'],
            primitives: [
              GltfMeshPrimitive(
                attributes: const {'POSITION': 0},
                targets: [
                  {'POSITION': 1},
                ],
              ),
            ],
          ),
        ],
        accessors: [
          GltfAccessor(
            componentType: GltfComponentType.float,
            count: 3,
            type: GltfAccessorType.vec3,
            bufferView: 0,
          ),
          GltfAccessor(
            componentType: GltfComponentType.float,
            count: 3,
            type: GltfAccessorType.vec3,
            bufferView: 1,
          ),
        ],
        bufferViews: [
          GltfBufferView(
            buffer: 0,
            byteOffset: 0,
            byteLength: positions.lengthInBytes,
          ),
          GltfBufferView(
            buffer: 0,
            byteOffset: positions.lengthInBytes,
            byteLength: deltas.lengthInBytes,
          ),
        ],
      );
      final document = buildSceneDocument(doc, blob.toBytes());
      final node = document.nodes.values.singleWhere(
        (n) => n.name == 'morphed',
      );
      final mesh = node.components.singleWhere((c) => c.type == 'mesh');
      final weights = mesh.properties['morphWeights'] as ListValue;
      expect(weights.values, hasLength(1));
      expect((weights.values.single as DoubleValue).value, 0.75);

      final geometry = document.resources.values
          .whereType<GeometryResource>()
          .single;
      expect(geometry.morphTargets!.targetNames, ['puff']);
      expect(geometry.morphTargets!.defaultWeights, [0.25]);
    });

    test('mismatched target counts refuse to emit', () {
      final doc = GltfDocument(
        meshes: [
          GltfMesh(
            primitives: [
              GltfMeshPrimitive(
                attributes: const {'POSITION': 0},
                targets: [
                  {'POSITION': 0},
                ],
              ),
              GltfMeshPrimitive(attributes: const {'POSITION': 0}),
            ],
          ),
        ],
        accessors: [
          GltfAccessor(
            componentType: GltfComponentType.float,
            count: 1,
            type: GltfAccessorType.vec3,
          ),
        ],
      );
      expect(
        () => buildSceneDocument(doc, Uint8List(0)),
        throwsFormatException,
      );
    });
  });

  group('.fsceneb round trip', () {
    test('morph payloads, metadata, and weights channels survive', () {
      final (:doc, :bin) = _load('AnimatedMorphCube.glb');
      final original = buildSceneDocument(doc, bin);
      final reread = readFsceneb(writeFsceneb(original));

      final geometry = reread.resources.values
          .whereType<GeometryResource>()
          .single;
      final morph = geometry.morphTargets!;
      expect(morph.targetCount, 2);
      expect(morph.hasNormalDeltas, isTrue);
      expect(morph.hasTangentDeltas, isTrue);
      expect(morph.defaultWeights, [0.0, 0.0]);

      final originalGeometry = original.resources.values
          .whereType<GeometryResource>()
          .single;
      expect(
        reread.payload(morph.deltas)!.bytes,
        original.payload(originalGeometry.morphTargets!.deltas)!.bytes,
      );
      expect(
        reread.payload(geometry.vertices!)!.bytes,
        original.payload(originalGeometry.vertices!)!.bytes,
      );

      final channel = reread.animations.values.single.channels.single;
      expect(channel.property, AnimationProperty.weights);

      // The document animation builder decodes the flattened weights
      // keyframes into the engine's weights resolver.
      final engineNodes = {
        for (final spec in reread.nodes.values) spec.id: Node(name: spec.name),
      };
      final animation = buildAnimation(
        reread,
        reread.animations.values.single,
        engineNodes,
      )!;
      final resolver =
          animation.channels.single.resolver
              as engine.MorphWeightsTimelineResolver;
      expect(resolver.targetCount, 2);
      expect(resolver.times, hasLength(127));
      expect(resolver.values, hasLength(254));
      expect(
        animation.channels.single.bindTarget.property,
        engine.AnimationProperty.weights,
      );
    });
  });
}
