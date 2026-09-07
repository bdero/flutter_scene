// Morph target (blend shape) coverage over the pure-data layers: glTF
// parsing and packing (dense and sparse deltas), additive CPU blending,
// top-N weight selection, the delta-texture packing layout, node weight
// defaults/overrides, and weights-channel playback. No GPU needed.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/animation.dart' as engine;
import 'package:flutter_scene/src/geometry/morph_targets.dart';
import 'package:flutter_scene/src/geometry/morphed_geometry.dart';
import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:flutter_scene/src/runtime_importer/animation_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Matrix4;

// A single-triangle primitive with two morph targets. Target 0's POSITION
// deltas are sparse-encoded over a null bufferView (the spec-recommended
// shape for morph deltas); target 1 is dense and carries NORMAL deltas.
({
  GltfMeshPrimitive primitive,
  List<GltfAccessor> accessors,
  List<GltfBufferView> bufferViews,
  Uint8List bufferData,
})
_syntheticMorphFixture() {
  final positions = Float32List.fromList([
    0, 0, 0, //
    1, 0, 0, //
    0, 1, 0, //
  ]);
  final normals = Float32List.fromList([
    0, 0, 1, //
    0, 0, 1, //
    0, 0, 1, //
  ]);
  // Sparse target 0: only vertex 1 moves, by (0.5, 0, 0.25).
  final sparseIndices = Uint16List.fromList([1]);
  final sparseValues = Float32List.fromList([0.5, 0, 0.25]);
  // Dense target 1 deltas.
  final densePositions = Float32List.fromList([
    0, 0, 1, //
    0, 0, 2, //
    0, 0, 3, //
  ]);
  final denseNormals = Float32List.fromList([
    1, 0, -1, //
    0, 0, 0, //
    0, 1, 0, //
  ]);

  final blob = BytesBuilder();
  int add(TypedData data) {
    while (blob.length % 4 != 0) {
      blob.addByte(0);
    }
    final offset = blob.length;
    blob.add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    return offset;
  }

  final offsets = [
    add(positions),
    add(normals),
    add(sparseIndices),
    add(sparseValues),
    add(densePositions),
    add(denseNormals),
  ];
  final lengths = [
    positions.lengthInBytes,
    normals.lengthInBytes,
    sparseIndices.lengthInBytes,
    sparseValues.lengthInBytes,
    densePositions.lengthInBytes,
    denseNormals.lengthInBytes,
  ];
  final bufferViews = [
    for (var i = 0; i < offsets.length; i++)
      GltfBufferView(buffer: 0, byteOffset: offsets[i], byteLength: lengths[i]),
  ];
  final accessors = [
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
    // Sparse morph deltas over a zero-filled base.
    GltfAccessor(
      componentType: GltfComponentType.float,
      count: 3,
      type: GltfAccessorType.vec3,
      sparse: GltfAccessorSparse(
        count: 1,
        indicesBufferView: 2,
        indicesComponentType: GltfComponentType.unsignedShort,
        valuesBufferView: 3,
      ),
    ),
    GltfAccessor(
      componentType: GltfComponentType.float,
      count: 3,
      type: GltfAccessorType.vec3,
      bufferView: 4,
    ),
    GltfAccessor(
      componentType: GltfComponentType.float,
      count: 3,
      type: GltfAccessorType.vec3,
      bufferView: 5,
    ),
  ];
  return (
    primitive: GltfMeshPrimitive(
      attributes: {'POSITION': 0, 'NORMAL': 1},
      targets: [
        {'POSITION': 2},
        {'POSITION': 3, 'NORMAL': 4},
      ],
    ),
    accessors: accessors,
    bufferViews: bufferViews,
    bufferData: blob.toBytes(),
  );
}

MorphTargetData _dataFromFixture({GltfCoordinatePolicy? policy}) {
  final fixture = _syntheticMorphFixture();
  final packed = packGltfPrimitive(
    primitive: fixture.primitive,
    accessors: fixture.accessors,
    bufferViews: fixture.bufferViews,
    bufferData: fixture.bufferData,
    coordinatePolicy: policy ?? GltfCoordinatePolicy.runtimeBoundary,
  );
  final morph = packed.morphTargets!;
  return MorphTargetData(
    vertexCount: morph.vertexCount,
    targetCount: morph.targetCount,
    positionDeltas: morph.positionDeltas,
    normalDeltas: morph.normalDeltas,
    tangentDeltas: morph.tangentDeltas,
  );
}

void main() {
  group('glTF morph parsing and packing', () {
    test('sparse and dense targets pack into target-major delta slabs', () {
      final fixture = _syntheticMorphFixture();
      final packed = packGltfPrimitive(
        primitive: fixture.primitive,
        accessors: fixture.accessors,
        bufferViews: fixture.bufferViews,
        bufferData: fixture.bufferData,
        coordinatePolicy: GltfCoordinatePolicy.runtimeBoundary,
      );
      final morph = packed.morphTargets!;
      expect(morph.targetCount, 2);
      expect(morph.vertexCount, 3);
      // Sparse target 0: only vertex 1 moved.
      expect(morph.positionDeltas.sublist(0, 9), [
        0,
        0,
        0,
        0.5,
        0,
        0.25,
        0,
        0,
        0,
      ]);
      // Dense target 1.
      expect(morph.positionDeltas.sublist(9, 18), [0, 0, 1, 0, 0, 2, 0, 0, 3]);
      // Target 0 has no NORMAL deltas; its slab section stays zero.
      expect(morph.normalDeltas!.sublist(0, 9), List.filled(9, 0));
      expect(morph.normalDeltas!.sublist(9, 18), [1, 0, -1, 0, 0, 0, 0, 1, 0]);
      expect(morph.tangentDeltas, isNull);
    });

    test('a native-baking policy negates delta Z like the base vertices', () {
      final fixture = _syntheticMorphFixture();
      final packed = packGltfPrimitive(
        primitive: fixture.primitive,
        accessors: fixture.accessors,
        bufferViews: fixture.bufferViews,
        bufferData: fixture.bufferData,
        coordinatePolicy: GltfCoordinatePolicy.bakeNative,
      );
      final morph = packed.morphTargets!;
      expect(morph.positionDeltas.sublist(3, 6), [0.5, 0, -0.25]);
      expect(morph.positionDeltas.sublist(9, 12), [0, 0, -1]);
      expect(morph.normalDeltas!.sublist(9, 12), [1, 0, 1]);
    });

    test('an unmorphed primitive packs no morph data', () {
      final fixture = _syntheticMorphFixture();
      final packed = packGltfPrimitive(
        primitive: GltfMeshPrimitive(attributes: fixture.primitive.attributes),
        accessors: fixture.accessors,
        bufferViews: fixture.bufferViews,
        bufferData: fixture.bufferData,
        coordinatePolicy: GltfCoordinatePolicy.runtimeBoundary,
      );
      expect(packed.morphTargets, isNull);
    });

    test('mismatched per-primitive target counts fail loudly', () {
      final mesh = GltfMesh(
        name: 'bad',
        primitives: [
          GltfMeshPrimitive(
            attributes: const {'POSITION': 0},
            targets: [
              {'POSITION': 2},
            ],
          ),
          GltfMeshPrimitive(attributes: const {'POSITION': 0}),
        ],
      );
      expect(() => validateMorphTargetConsistency(mesh), throwsFormatException);
    });

    test('matching target counts validate', () {
      final mesh = GltfMesh(
        primitives: [
          GltfMeshPrimitive(
            attributes: const {'POSITION': 0},
            targets: [
              {'POSITION': 2},
            ],
          ),
          GltfMeshPrimitive(
            attributes: const {'POSITION': 1},
            targets: [
              {'POSITION': 3},
            ],
          ),
        ],
      );
      expect(() => validateMorphTargetConsistency(mesh), returnsNormally);
    });

    test('mesh weights, node weights, and targetNames parse', () {
      final doc = parseGltfJson({
        'meshes': [
          {
            'primitives': [
              {
                'attributes': {'POSITION': 0},
                'targets': [
                  {'POSITION': 1},
                  {'POSITION': 2},
                ],
              },
            ],
            'weights': [0.25, 0.75],
            'extras': {
              'targetNames': ['smile', 'frown'],
            },
          },
        ],
        'nodes': [
          {
            'mesh': 0,
            'weights': [1.0, 0.0],
          },
        ],
      });
      final mesh = doc.meshes.single;
      expect(mesh.weights, [0.25, 0.75]);
      expect(mesh.targetNames, ['smile', 'frown']);
      expect(mesh.primitives.single.targets, hasLength(2));
      expect(mesh.primitives.single.targets[0], {'POSITION': 1});
      expect(doc.nodes.single.weights, [1.0, 0.0]);
    });
  });

  group('sample asset fixtures', () {
    test('AnimatedMorphCube parses, packs, and animates weights', () {
      final bytes = File(
        'test/fixtures/AnimatedMorphCube.glb',
      ).readAsBytesSync();
      final container = parseGlb(bytes);
      final doc = parseGltfJson(container.json);
      final mesh = doc.meshes.single;
      expect(mesh.weights, [0.0, 0.0]);
      validateMorphTargetConsistency(mesh);

      final packed = packGltfPrimitive(
        primitive: mesh.primitives.single,
        accessors: doc.accessors,
        bufferViews: doc.bufferViews,
        bufferData: container.binaryChunk,
        coordinatePolicy: GltfCoordinatePolicy.runtimeBoundary,
      );
      final morph = packed.morphTargets!;
      expect(morph.targetCount, 2);
      expect(morph.vertexCount, packed.vertexCount);
      expect(morph.normalDeltas, isNotNull);
      expect(morph.tangentDeltas, isNotNull);

      final engineNodes = [for (final _ in doc.nodes) Node()];
      final animation = buildAnimation(
        gltfAnimation: doc.animations.single,
        accessors: doc.accessors,
        bufferViews: doc.bufferViews,
        bufferData: container.binaryChunk,
        engineNodes: engineNodes,
        coordinatePolicy: GltfCoordinatePolicy.runtimeBoundary,
      );
      final channel = animation.channels.single;
      expect(channel.bindTarget.property, engine.AnimationProperty.weights);
      final resolver = channel.resolver as engine.MorphWeightsTimelineResolver;
      expect(resolver.targetCount, 2);
      expect(resolver.times, hasLength(127));
      expect(resolver.values, hasLength(254));
    });

    test('MorphPrimitivesTest primitives share one target count', () {
      final bytes = File(
        'test/fixtures/MorphPrimitivesTest.glb',
      ).readAsBytesSync();
      final container = parseGlb(bytes);
      final doc = parseGltfJson(container.json);
      final mesh = doc.meshes.single;
      expect(mesh.primitives, hasLength(2));
      expect(mesh.weights, [0.5]);
      validateMorphTargetConsistency(mesh);
      for (final primitive in mesh.primitives) {
        final packed = packGltfPrimitive(
          primitive: primitive,
          accessors: doc.accessors,
          bufferViews: doc.bufferViews,
          bufferData: container.binaryChunk,
          coordinatePolicy: GltfCoordinatePolicy.runtimeBoundary,
        );
        expect(packed.morphTargets!.targetCount, 1);
        expect(packed.morphTargets!.vertexCount, packed.vertexCount);
      }
    });
  });

  group('additive CPU blend', () {
    test('positions blend as base plus weighted deltas', () {
      final data = _dataFromFixture();
      final base = Float32List.fromList([
        0, 0, 0, //
        1, 0, 0, //
        0, 1, 0, //
      ]);
      final blended = data.blendPositions(
        base,
        Float32List.fromList([2.0, 0.5]),
      );
      // v0: base + 2*(0,0,0) + 0.5*(0,0,1)
      expect(blended.sublist(0, 3), [0, 0, 0.5]);
      // v1: base + 2*(0.5,0,0.25) + 0.5*(0,0,2)
      expect(blended.sublist(3, 6), [2, 0, 1.5]);
      // v2: base + 0.5*(0,0,3)
      expect(blended.sublist(6, 9), [0, 1, 1.5]);
    });

    test('zero weights return the base unchanged', () {
      final data = _dataFromFixture();
      final base = Float32List.fromList([
        0, 0, 0, //
        1, 0, 0, //
        0, 1, 0, //
      ]);
      expect(data.blendPositions(base, Float32List(2)), base);
    });

    test('normals renormalize after the weighted sum', () {
      final data = _dataFromFixture();
      final base = Float32List.fromList([
        0, 0, 1, //
        0, 0, 1, //
        0, 0, 1, //
      ]);
      final blended = data.blendNormals(base, Float32List.fromList([0.0, 1.0]));
      // v0: (0,0,1) + (1,0,-1) = (1,0,0), unit already.
      expect(blended.sublist(0, 3), [1, 0, 0]);
      // v1: unchanged, still unit.
      expect(blended.sublist(3, 6), [0, 0, 1]);
      // v2: (0,0,1) + (0,1,0) = (0,1,1), renormalized.
      final invSqrt2 = 0.7071067811865475;
      expect(blended[6], closeTo(0, 1e-6));
      expect(blended[7], closeTo(invSqrt2, 1e-6));
      expect(blended[8], closeTo(invSqrt2, 1e-6));
    });

    test('a collapsed normal sum keeps the base normal', () {
      final data = MorphTargetData(
        vertexCount: 1,
        targetCount: 1,
        positionDeltas: Float32List(3),
        normalDeltas: Float32List.fromList([0, 0, -1]),
      );
      final blended = data.blendNormals(
        Float32List.fromList([0, 0, 1]),
        Float32List.fromList([1.0]),
      );
      expect(blended, [0, 0, 1]);
    });
  });

  group('top weight selection', () {
    test('picks the largest magnitudes and drops the smallest', () {
      final weights = Float32List.fromList([
        0.1,
        0.9,
        0.0,
        -0.8,
        0.2,
        0.3,
        0.4,
        0.5,
        0.6,
        0.05,
      ]);
      final active = MorphTargetData.selectActiveTargets(weights);
      expect(active, hasLength(kMaxGpuMorphTargets));
      expect(active.first.index, 1);
      expect(active.first.weight, closeTo(0.9, 1e-6));
      final indices = [for (final a in active) a.index];
      // Nine nonzero weights compete for eight slots; the smallest magnitude
      // (0.05 at index 9) falls out and zero weights never appear.
      expect(indices, isNot(contains(9)));
      expect(indices, isNot(contains(2)));
      expect(indices, contains(0));
      // Negative weights count by magnitude.
      expect(indices, contains(3));
    });

    test('ties keep the lower index first', () {
      final active = MorphTargetData.selectActiveTargets(
        Float32List.fromList([0.5, -0.5, 0.5]),
        cap: 2,
      );
      expect(active[0].index, 0);
      expect(active[1].index, 1);
    });
  });

  group('delta texture packing', () {
    test('bands wrap vertices without crossing targets', () {
      final data = MorphTargetData(
        vertexCount: 5,
        targetCount: 2,
        positionDeltas: Float32List.fromList([
          for (var t = 0; t < 2; t++)
            for (var v = 0; v < 5; v++) ...[(t * 100 + v).toDouble(), 0, 0],
        ]),
        normalDeltas: Float32List.fromList([
          for (var t = 0; t < 2; t++)
            for (var v = 0; v < 5; v++) ...[0, (t * 100 + v).toDouble(), 0],
        ]),
      );
      // Width 2 forces each 5-vertex attribute across 3 rows.
      final packing = computeMorphTexturePacking(data, maxWidth: 2)!;
      expect(packing.width, 2);
      expect(packing.rowsPerAttribute, 3);
      expect(packing.includesNormals, isTrue);
      expect(packing.bandRows, 6);
      expect(packing.height, 12);
      expect(packing.bandStart(1), 6);

      final texels = buildMorphTexturePayload(data, packing);
      expect(texels, hasLength(packing.width * packing.height * 4));
      double positionX(int target, int vertex) {
        final row = packing.bandStart(target) + vertex ~/ packing.width;
        final column = vertex % packing.width;
        return texels[(row * packing.width + column) * 4];
      }

      double normalY(int target, int vertex) {
        final row =
            packing.bandStart(target) +
            packing.rowsPerAttribute +
            vertex ~/ packing.width;
        final column = vertex % packing.width;
        return texels[(row * packing.width + column) * 4 + 1];
      }

      for (var t = 0; t < 2; t++) {
        for (var v = 0; v < 5; v++) {
          expect(positionX(t, v), (t * 100 + v).toDouble());
          expect(normalY(t, v), (t * 100 + v).toDouble());
        }
      }
      // The padding texel after vertex 4 in each band's last row stays zero,
      // so a wrap boundary never bleeds into the next target's rows.
      final padTexel = ((packing.bandStart(0) + 2) * packing.width + 1) * 4;
      expect(texels[padTexel], 0);
      expect(texels[padTexel + 1], 0);
    });

    test('a small mesh packs one row per attribute at vertex-count width', () {
      final data = _dataFromFixture();
      final packing = computeMorphTexturePacking(data)!;
      expect(packing.width, 3);
      expect(packing.rowsPerAttribute, 1);
      expect(packing.height, 4);
    });

    test('oversized data reports no packing', () {
      final data = MorphTargetData(
        vertexCount: 4,
        targetCount: 3,
        positionDeltas: Float32List(3 * 4 * 3),
      );
      expect(
        computeMorphTexturePacking(data, maxWidth: 2, maxHeight: 4),
        isNull,
      );
    });
  });

  group('node weights', () {
    Node morphedNode({List<double>? defaults}) {
      final data = MorphTargetData(
        vertexCount: 3,
        targetCount: 2,
        positionDeltas: Float32List(2 * 3 * 3),
        targetNames: const ['a', 'b'],
        defaultWeights: defaults,
      );
      final node = Node();
      node.mesh = Mesh(MorphedUnskinnedGeometry(data), UnlitMaterial());
      return node;
    }

    test('defaults seed the instance weights', () {
      final node = morphedNode(defaults: [0.25, 0.5]);
      expect(node.morphTargetCount, 2);
      expect(node.morphTargetNames, ['a', 'b']);
      expect(node.defaultMorphWeights, [0.25, 0.5]);
      expect(node.morphWeights, [0.25, 0.5]);
    });

    test('per-instance weights override without touching defaults', () {
      final node = morphedNode(defaults: [0.25, 0.5]);
      node.setMorphWeight(1, 0.75);
      expect(node.morphWeights, [0.25, 0.75]);
      expect(node.defaultMorphWeights, [0.25, 0.5]);

      final clone = node.clone();
      expect(clone.morphWeights, [0.25, 0.75]);
      clone.setMorphWeights([0.0, 0.0]);
      expect(clone.morphWeights, [0.0, 0.0]);
      expect(node.morphWeights, [0.25, 0.75]);
    });

    test('an unmorphed node exposes no weights', () {
      final node = Node();
      expect(node.morphTargetCount, 0);
      expect(node.morphWeights, isNull);
      expect(() => node.setMorphWeight(0, 1), throwsStateError);
    });
  });

  group('weights animation playback', () {
    test('a weights channel drives the node weights over time', () {
      final data = MorphTargetData(
        vertexCount: 3,
        targetCount: 2,
        positionDeltas: Float32List(2 * 3 * 3),
      );
      final node = Node(name: 'morphed');
      node.mesh = Mesh(MorphedUnskinnedGeometry(data), UnlitMaterial());

      final animation = engine.Animation(
        name: 'weights',
        channels: [
          engine.AnimationChannel(
            bindTarget: engine.BindKey(
              nodeName: 'morphed',
              property: engine.AnimationProperty.weights,
            ),
            resolver: engine.PropertyResolver.makeMorphWeightsTimeline(
              [0.0, 1.0],
              Float32List.fromList([0, 0, 1, 0.5]),
              targetCount: 2,
            ),
          ),
        ],
      );

      final player = engine.AnimationPlayer();
      final clip = player.createAnimationClip(animation, node)..play();
      player.update(0.5);
      expect(node.morphWeights![0], closeTo(0.5, 1e-6));
      expect(node.morphWeights![1], closeTo(0.25, 1e-6));
      player.update(0.5);
      expect(node.morphWeights![0], closeTo(1.0, 1e-6));
      expect(node.morphWeights![1], closeTo(0.5, 1e-6));
      // A weights-only channel leaves the node transform untouched.
      expect(node.localTransform, Matrix4.identity());
      expect(clip.playbackTime, 1.0);
    });

    test('clip weight scales the offset from the rest weights', () {
      final data = MorphTargetData(
        vertexCount: 1,
        targetCount: 1,
        positionDeltas: Float32List(3),
        defaultWeights: const [0.2],
      );
      final node = Node(name: 'morphed');
      node.mesh = Mesh(MorphedUnskinnedGeometry(data), UnlitMaterial());

      final animation = engine.Animation(
        name: 'weights',
        channels: [
          engine.AnimationChannel(
            bindTarget: engine.BindKey(
              nodeName: 'morphed',
              property: engine.AnimationProperty.weights,
            ),
            resolver: engine.PropertyResolver.makeMorphWeightsTimeline(
              [0.0],
              Float32List.fromList([1.0]),
              targetCount: 1,
            ),
          ),
        ],
      );
      final player = engine.AnimationPlayer();
      player.createAnimationClip(animation, node)
        ..play()
        ..weight = 0.5;
      player.update(0.0);
      // rest 0.2 + (1.0 - 0.2) * 0.5
      expect(node.morphWeights![0], closeTo(0.6, 1e-6));
    });
  });

  group('morph bounds range', () {
    // Two targets over one vertex: the first pushes +X, the second -Y.
    final data = MorphTargetData(
      vertexCount: 1,
      targetCount: 2,
      positionDeltas: Float32List.fromList([2, 0, 0, 0, -3, 0]),
      targetNames: const ['a', 'b'],
    );
    final extremes = computeMorphDeltaExtremes(data);
    final out = Float32List(6);

    void range(List<double>? weights) => morphWeightedDeltaRange(
      extremes.lo,
      extremes.hi,
      data.targetCount,
      weights == null ? null : Float32List.fromList(weights),
      out,
    );

    test('per-target extremes never cross zero on the wrong side', () {
      // Zero-seeded, so a target that only pushes one way has zero on the
      // other. That is what lets a weight of zero contribute nothing.
      expect(extremes.lo.toList(), [0, 0, 0, 0, -3, 0]);
      expect(extremes.hi.toList(), [2, 0, 0, 0, 0, 0]);
    });

    test('zero weights displace nothing', () {
      range([0.0, 0.0]);
      expect(out.toList(), [0, 0, 0, 0, 0, 0]);
    });

    test('weights inside [0, 1] scale the envelope', () {
      range([1.0, 1.0]);
      expect(out.toList(), [0, -3, 0, 2, 0, 0]);
      range([0.5, 0.5]);
      expect(out.toList(), [0, -1.5, 0, 1, 0, 0]);
    });

    test('a weight past 1 widens past the authored envelope', () {
      range([3.0, 0.0]);
      expect(out[3], 6.0, reason: 'three times the target: the whole point');
      range(null);
      expect(out[3], 2.0, reason: 'the seed envelope is every target at 1');
    });

    test('a negative weight flips the target contribution', () {
      range([-1.0, 0.0]);
      // The +X target pulled backwards becomes the low, not the high.
      expect(out[0], -2.0);
      expect(out[3], 0.0);
      range([0.0, -2.0]);
      expect(out[4], 6.0, reason: 'the -Y target pushed +Y');
      expect(out[1], 0.0);
    });

    test('a short weight list only applies the targets it covers', () {
      range([1.0]);
      expect(out.toList(), [0, 0, 0, 2, 0, 0]);
    });
  });
}
