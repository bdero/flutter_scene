import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/instance_batching.dart';
import 'package:flutter_scene/src/render/instance_packing.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

class _StubGeometry extends Geometry {
  _StubGeometry({bool instanced = true}) {
    if (instanced) {
      setVertexLayout(const VertexLayoutDescriptor(buffers: []));
    }
  }

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
    double depthBias = 0.0,
  }) {
    throw UnsupportedError('Stub geometry is not renderable');
  }
}

class _StubMaterial extends Material {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Lighting lighting,
  ) {
    throw UnsupportedError('Stub material is not renderable');
  }
}

class _OpaqueCandidate implements OpaqueBatchRecord {
  _OpaqueCandidate({
    required this.geometry,
    required this.material,
    required this.pipeline,
    this.fade = 1,
    this.lightListOffset = 0,
    this.lightListCount = 0,
    this.lightChannelMask = 0xFF,
    this.jointsTexture,
    this.morphWeights,
  });

  @override
  final Geometry geometry;
  @override
  final Material material;
  @override
  final Object pipeline;
  @override
  final double fade;
  @override
  final int lightListOffset;
  @override
  final int lightListCount;
  @override
  final int lightChannelMask;
  @override
  final Object? jointsTexture;
  @override
  final Object? morphWeights;
}

RenderItem _item(Geometry geometry, Material material) =>
    RenderItem(geometry: geometry, material: material);

void main() {
  group('encoder instance batching', () {
    test('depth run merges matching plain meshes', () {
      final geometry = _StubGeometry();
      final material = _StubMaterial();
      final records = [
        _item(geometry, material),
        _item(geometry, material),
        _item(geometry, material),
      ];

      expect(depthBatchEnd(records, 0), 3);
    });

    test('depth run splits on geometry and material', () {
      final geometry = _StubGeometry();
      final material = _StubMaterial();

      expect(
        depthBatchEnd([
          _item(geometry, material),
          _item(_StubGeometry(), material),
        ], 0),
        1,
      );
      expect(
        depthBatchEnd([
          _item(geometry, material),
          _item(geometry, _StubMaterial()),
        ], 0),
        1,
      );
    });

    test('opaque run splits on lighting, fade, joints, and morphs', () {
      final geometry = _StubGeometry();
      final material = _StubMaterial();
      final pipeline = Object();
      _OpaqueCandidate candidate({
        double fade = 1,
        int lightListOffset = 0,
        int lightListCount = 0,
        int lightChannelMask = 0xFF,
        Object? jointsTexture,
        Object? morphWeights,
      }) => _OpaqueCandidate(
        geometry: geometry,
        material: material,
        pipeline: pipeline,
        fade: fade,
        lightListOffset: lightListOffset,
        lightListCount: lightListCount,
        lightChannelMask: lightChannelMask,
        jointsTexture: jointsTexture,
        morphWeights: morphWeights,
      );

      expect(opaqueBatchEnd([candidate(), candidate(), candidate()], 0), 3);
      expect(
        opaqueBatchEnd([candidate(), candidate(lightListOffset: 1)], 0),
        1,
      );
      expect(opaqueBatchEnd([candidate(), candidate(lightListCount: 1)], 0), 1);
      expect(opaqueBatchEnd([candidate(), candidate(fade: 0.5)], 0), 1);
      // The primary directional rides a per-draw uniform, so items on
      // different light channels cannot share one instanced draw.
      expect(
        opaqueBatchEnd([candidate(), candidate(lightChannelMask: 0x01)], 0),
        1,
      );
      expect(
        opaqueBatchEnd([candidate(), candidate(jointsTexture: Object())], 0),
        1,
      );
      // Morphed items carry per-item weights, so they never merge (in either
      // position of the run).
      expect(
        opaqueBatchEnd([candidate(), candidate(morphWeights: Object())], 0),
        1,
      );
      expect(
        opaqueBatchEnd([candidate(morphWeights: Object()), candidate()], 0),
        1,
      );
    });

    test('selects single, uncached, and cached instance data', () {
      final geometry = _StubGeometry();
      final material = _StubMaterial();
      final single = _item(geometry, material);
      expect(instanceDataBatchFor(single, indices: null).instances, isNull);

      final item = _item(geometry, material)
        ..instanceTransforms = [Matrix4.identity(), Matrix4.identity()]
        ..instanceColors = [Vector4.all(1), Vector4.all(1)]
        ..visibleInstanceIndices = [1];
      final uncached = instanceDataBatchFor(
        item,
        indices: item.visibleInstanceIndices,
      );
      expect(uncached.instances, same(item.instanceTransforms));
      expect(uncached.indices, [1]);

      final uncachedShadow = instanceDataBatchFor(item, indices: null);
      expect(uncachedShadow.instances, same(item.instanceTransforms));
      expect(uncachedShadow.indices, isNull);

      final packed = Float32List(40);
      final winding = Uint8List.fromList([0, 1]);
      item
        ..instanceWorldData = packed
        ..instanceWorldWindingFlipped = winding;
      final cached = instanceDataBatchFor(
        item,
        indices: item.visibleInstanceIndices,
      );
      expect(cached.packedWorldData, same(packed));
      expect(cached.packedWindingFlipped, same(winding));
      expect(cached.indices, [1]);

      final cachedShadow = instanceDataBatchFor(item, indices: null);
      expect(cachedShadow.packedWorldData, same(packed));
      expect(cachedShadow.packedWindingFlipped, same(winding));
      expect(cachedShadow.indices, isNull);

      final alternateWinding = instanceDataBatchFor(
        item,
        indices: item.visibleInstanceIndices,
        windingFlipped: true,
      );
      expect(alternateWinding.packedWorldData, isNull);
      expect(alternateWinding.nodeWindingFlipped, isTrue);
    });
  });

  group('instance data batch pool', () {
    test('reuses batch objects across resets', () {
      final geometry = _StubGeometry();
      final material = _StubMaterial();
      final pool = InstanceDataBatchPool();

      pool
        ..addFor(_item(geometry, material), indices: null)
        ..addFor(_item(geometry, material), indices: null);
      expect(pool.batches, hasLength(2));
      final first = pool.batches[0];
      final second = pool.batches[1];

      pool.reset();
      expect(pool.batches, isEmpty);

      pool
        ..addFor(_item(geometry, material), indices: null)
        ..addFor(_item(geometry, material), indices: null);
      // The identities are the previous frame's, in some order: a steady-state
      // frame allocates no batches at all.
      expect(pool.batches, hasLength(2));
      expect(pool.batches, containsAll(<Object>[first, second]));
    });

    test('a recycled batch keeps nothing from its previous group', () {
      final geometry = _StubGeometry();
      final material = _StubMaterial();
      final pool = InstanceDataBatchPool();

      final cachedItem = _item(geometry, material)
        ..instanceTransforms = [Matrix4.identity(), Matrix4.identity()]
        ..instanceColors = [Vector4.all(1), Vector4.all(1)]
        ..instanceWorldData = Float32List(40)
        ..instanceWorldWindingFlipped = Uint8List(2)
        ..visibleInstanceIndices = [1];
      pool.addFor(cachedItem, indices: cachedItem.visibleInstanceIndices);
      expect(pool.batches.single.packedWorldData, isNotNull);
      expect(pool.batches.single.indices, [1]);

      // Refilling from a plain mesh must clear the cached path's fields, or
      // the pack call reads the previous group's world data for this one.
      pool
        ..reset()
        ..addFor(_item(geometry, material), indices: null);
      final recycled = pool.batches.single;
      expect(recycled.packedWorldData, isNull);
      expect(recycled.packedWindingFlipped, isNull);
      expect(recycled.instances, isNull);
      expect(recycled.colors, isNull);
      expect(recycled.indices, isNull);
      expect(recycled.attributeData, isNull);
      expect(recycled.attributeFloats, 0);
      expect(recycled.length, 1);

      // And the reverse: an unpacked fill followed by a cached one.
      pool
        ..reset()
        ..addFor(cachedItem, indices: null);
      expect(pool.batches.single.instances, isNull);
      expect(pool.batches.single.colors, isNull);
      expect(pool.batches.single.packedWorldData, isNotNull);
    });

    test('the shared scratch hands back one reused single-batch list', () {
      final scratch = InstancePackingScratch();
      final first = scratch.singleCachedBatch(
        packedWorldData: Float32List(40),
        packedWindingFlipped: Uint8List(2),
        indices: [1],
      );
      expect(first.single.indices, [1]);

      final second = scratch.singleInstanceBatch(
        nodeTransform: Matrix4.identity(),
        instances: [Matrix4.identity()],
        colors: [Vector4.all(1)],
        nodeWindingFlipped: false,
      );
      expect(second, same(first));
      expect(second.single.packedWorldData, isNull);
      expect(second.single.indices, isNull);
    });
  });
}
