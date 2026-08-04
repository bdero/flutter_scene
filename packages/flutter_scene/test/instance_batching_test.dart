import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/instance_batching.dart';
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
    this.jointsTexture,
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
  final Object? jointsTexture;
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

    test('opaque run splits on lighting, fade, and joints', () {
      final geometry = _StubGeometry();
      final material = _StubMaterial();
      final pipeline = Object();
      _OpaqueCandidate candidate({
        double fade = 1,
        int lightListOffset = 0,
        int lightListCount = 0,
        Object? jointsTexture,
      }) => _OpaqueCandidate(
        geometry: geometry,
        material: material,
        pipeline: pipeline,
        fade: fade,
        lightListOffset: lightListOffset,
        lightListCount: lightListCount,
        jointsTexture: jointsTexture,
      );

      expect(opaqueBatchEnd([candidate(), candidate(), candidate()], 0), 3);
      expect(
        opaqueBatchEnd([candidate(), candidate(lightListOffset: 1)], 0),
        1,
      );
      expect(opaqueBatchEnd([candidate(), candidate(lightListCount: 1)], 0), 1);
      expect(opaqueBatchEnd([candidate(), candidate(fade: 0.5)], 0), 1);
      expect(
        opaqueBatchEnd([candidate(), candidate(jointsTexture: Object())], 0),
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
    });
  });
}
