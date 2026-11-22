// The instance selection ShadowEncoder makes per light view. The encoder's
// draw path needs a render pass and is not run here.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/instance_batching.dart';
import 'package:flutter_scene/src/render/instance_packing.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/render/shadow_receiver_culling.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

class _Geometry extends Geometry {
  _Geometry() {
    setLocalBounds(
      Aabb3.minMax(Vector3.all(-0.5), Vector3.all(0.5)),
      Sphere.centerRadius(Vector3.zero(), 1),
    );
    setVertexLayout(const VertexLayoutDescriptor(buffers: []));
  }

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
    double depthBias = 0,
  }) => throw UnsupportedError('CPU fixture');
}

class _Material extends Material {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Lighting lighting,
  ) => throw UnsupportedError('CPU fixture');
}

RenderItem _item(
  List<Vector3> positions, {
  _Geometry? geometry,
  _Material? material,
  Set<int> mirroredInstances = const {},
}) {
  final item =
      RenderItem(
          geometry: geometry ?? _Geometry(),
          material: material ?? _Material(),
        )
        ..cullInstances = true
        ..instanceTransforms = [
          for (var i = 0; i < positions.length; i++)
            Matrix4.translation(positions[i])..scaleByVector3(
              Vector3(mirroredInstances.contains(i) ? -1 : 1, 1, 1),
            ),
        ]
        ..instanceColors = [
          for (var i = 0; i < positions.length; i++)
            Vector4(i / 8, (i + 1) / 8, (i + 2) / 8, 1),
        ]
        ..instanceAttributeFloats = 2
        ..instanceAttributeData = Float32List.fromList([
          for (var i = 0; i < positions.length; i++) ...[i + 0.25, -i - 0.5],
        ]);
  item.refreshWinding(false);
  item.refreshInstanceData();
  return item;
}

Frustum _box(double left, double right) =>
    Frustum.matrix(makeOrthographicMatrix(left, right, -10, 10, -10, 10));

List<int> _indices(RenderItem item) => List<int>.of(
  item.visibleInstanceIndices ??
      List.generate(item.instanceTransforms!.length, (i) => i),
);

Uint8List _bytes(Float32List floats) => Uint8List.sublistView(floats);

// Builds the expected payload directly from the selected instances, without
// the packing helpers.
void _expectPayload(
  PackedInstances packed,
  List<(RenderItem, List<int>)> selected, {
  required bool withAttributes,
}) {
  final expected = [<double>[], <double>[]];
  for (final (item, indices) in selected) {
    for (final i in indices) {
      final transform = item.instanceTransforms![i];
      final flipped = item.windingFlipped != (transform.determinant() < 0);
      final record = expected[flipped ? 1 : 0];
      record.addAll((item.worldTransform * transform).storage);
      if (withAttributes) {
        record.addAll(item.instanceColors![i].storage);
        record.addAll(item.instanceAttributeData!.sublist(i * 2, i * 2 + 2));
      }
    }
  }
  expect(_bytes(packed.ccw), _bytes(Float32List.fromList(expected[0])));
  expect(_bytes(packed.cw), _bytes(Float32List.fromList(expected[1])));
}

void main() {
  test('a light keeps an off-camera caster and drops receiver outsiders', () {
    const size = ui.Size(1280, 720);
    final camera = PerspectiveCamera(
      position: Vector3(0, 2, 0),
      target: Vector3(0, 2, -1),
      fovRadiansY: 60 * degrees2Radians,
    );
    final sun = Vector3(0, -1, 0);
    final light = DirectionalLight(
      castsShadow: true,
      direction: sun,
      shadowCascadeCount: 4,
      shadowMaxDistance: 100,
    );
    final cascade = light.computeCascades(camera, 16 / 9, sun)[1];
    final cameraMatrix = camera.getViewTransform(size);
    final lightFrustum = Frustum.matrix(cascade.lightSpaceMatrix);
    final planes = shadowReceiverCullingPlanes(
      receiverFrustum: shadowReceiverFrustum(cameraMatrix, size),
      lightSpaceMatrix: cascade.lightSpaceMatrix,
      margin: 0,
    )!;
    final item = _item([
      Vector3(0, 30, -10), // Off camera, above a visible receiver.
      Vector3(0, 4, 3), // Behind the receivers.
      Vector3(0, -40, -10), // Underground.
      Vector3(0, 2, -10),
      Vector3(1000, 0, 0),
    ]);
    expect(item.cullVisibleInstances(Frustum.matrix(cameraMatrix), []), isTrue);
    expect(_indices(item), [3]);
    expect(item.cullVisibleInstances(lightFrustum, []), isTrue);
    expect(_indices(item), containsAll([0, 1, 2, 3]));
    expect(item.cullVisibleInstances(lightFrustum, planes), isTrue);
    expect(_indices(item), [0, 3]);
  });

  test('each view recomputes its own selection', () {
    final item = _item([Vector3.zero(), Vector3(4, 0, 0), Vector3(8, 0, 0)]);
    final pool = InstanceDataBatchPool();
    // Two light tiles, an empty one, then camera views.
    for (final (frustum, wanted) in [
      (_box(-2, 2), [0]),
      (_box(6, 10), [2]),
      (_box(20, 24), <int>[]),
      (_box(2, 6), [1]),
      (_box(-2, 10), [0, 1, 2]),
    ]) {
      expect(item.cullVisibleInstances(frustum, []), wanted.isNotEmpty);
      expect(_indices(item), wanted);
      pool
        ..reset()
        ..addFor(item, indices: item.visibleInstanceIndices);
      _expectPayload(packInstanceTransformBatches(pool.batches), [
        (item, wanted),
      ], withAttributes: false);
    }
    expect(item.visibleInstanceIndices, isNull);
  });

  test('batching keeps each sparse selection', () {
    final geometry = _Geometry();
    final material = _Material();
    final a = _item(
      [Vector3(-20, 0, 0), Vector3(1, 0, 0), Vector3(20, 0, 0)],
      geometry: geometry,
      material: material,
    );
    final b = _item(
      [Vector3(20, 0, 0), Vector3(-20, 0, 0), Vector3(2, 0, 0)],
      geometry: geometry,
      material: material,
      mirroredInstances: {2},
    );
    expect(a.cullVisibleInstances(_box(-4, 4), []), isTrue);
    expect(b.cullVisibleInstances(_box(-4, 4), []), isTrue);
    expect(depthBatchEnd([a, b], 0), 2);
    final pool = InstanceDataBatchPool()
      ..addFor(a, indices: a.visibleInstanceIndices)
      ..addFor(b, indices: b.visibleInstanceIndices);
    for (final attributes in [false, true]) {
      _expectPayload(
        attributes
            ? packInstanceDataBatches(pool.batches, attributeFloats: 2)
            : packInstanceTransformBatches(pool.batches),
        [
          (a, [1]),
          (b, [2]),
        ],
        withAttributes: attributes,
      );
    }
  });
}
