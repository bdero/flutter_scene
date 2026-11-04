// The CPU side of per-instance shadow culling: light volumes, per-view
// selection, draw selectors and packed payloads. ShadowEncoder's own draw
// path needs a render pass and is not run here.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/instance_batching.dart';
import 'package:flutter_scene/src/render/instance_packing.dart';
import 'package:flutter_scene/src/render/mesh_draw_selection.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/render/shadow_receiver_culling.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

class _Geometry extends Geometry {
  _Geometry({bool bounded = true, bool instanced = true}) {
    if (bounded) {
      setLocalBounds(
        Aabb3.minMax(Vector3.all(-0.5), Vector3.all(0.5)),
        Sphere.centerRadius(Vector3.zero(), 1),
      );
    }
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
  bool mirrorNode = false,
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
  if (mirrorNode) item.worldTransform.scaleByVector3(Vector3(-1, 1, 1));
  item.refreshWinding(mirrorNode);
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

// Independent record oracle: directly multiply only the accepted matrices,
// and append their own color/attributes. It does not use the packing helpers.
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
  final stride = withAttributes ? 22 : 16;
  expect(packed.ccwCount, expected[0].length ~/ stride);
  expect(packed.cwCount, expected[1].length ~/ stride);
}

void main() {
  test(
    'light keeps an off-camera caster but rejects receiver-plane outsiders',
    () {
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
        Vector3(0, 30, -10), // Above a visible receiver, outside camera view.
        Vector3(0, 4, 3), // Behind the receiver volume.
        Vector3(0, -40, -10), // Underground, still inside the light box.
        Vector3(0, 2, -10),
        Vector3(1000, 0, 0),
      ]);
      expect(
        item.cullVisibleInstances(Frustum.matrix(cameraMatrix), []),
        isTrue,
      );
      expect(_indices(item), [3]);
      expect(item.cullVisibleInstances(lightFrustum, []), isTrue);
      expect(_indices(item), containsAll([0, 1, 2, 3]));
      expect(item.cullVisibleInstances(lightFrustum, planes), isTrue);
      expect(_indices(item), [0, 3]);
      final pool = InstanceDataBatchPool()
        ..addFor(item, indices: item.visibleInstanceIndices);
      _expectPayload(packInstanceTransformBatches(pool.batches), [
        (item, [0, 3]),
      ], withAttributes: false);
    },
  );

  test(
    'two light views then depth and scene recompute their own selection',
    () {
      final item = _item([Vector3.zero(), Vector3(4, 0, 0), Vector3(8, 0, 0)]);
      final pool = InstanceDataBatchPool();
      // Each view consumes its borrowed indices before the next view reculls.
      // Camera view differs from both light tiles; the second camera pass must
      // not reuse the preceding light selection, including an empty selection.
      for (final (frustum, wanted) in [
        (_box(-2, 2), [0]),
        (_box(6, 10), [2]),
        (_box(2, 6), [1]),
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
      expect(
        item.visibleInstanceIndices,
        isNull,
      ); // Restores all-instance path.
    },
  );

  test(
    'two computed cascades keep independent payloads before camera passes',
    () {
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
        shadowCascadeCount: 2,
        shadowMaxDistance: 100,
      );
      final positions = [
        for (final z in [1.0, 4.0, 10.0, 20.0, 40.0, 70.0, 95.0])
          Vector3(0, 2, -z),
        Vector3(0, 30, -10),
        Vector3(1000, 0, 0),
      ];
      final item = _item(positions);
      final cameraMatrix = camera.getViewTransform(size);
      final cameraFrustum = Frustum.matrix(cameraMatrix);
      expect(item.cullVisibleInstances(cameraFrustum, []), isTrue);
      final cameraIndices = _indices(item);
      expect(cameraIndices, [0, 1, 2, 3, 4, 5, 6]);
      final selections = <List<int>>[];
      for (final cascade in light.computeCascades(camera, 16 / 9, sun)) {
        final frustum = Frustum.matrix(cascade.lightSpaceMatrix);
        final planes = shadowReceiverCullingPlanes(
          receiverFrustum: shadowReceiverFrustum(cameraMatrix, size),
          lightSpaceMatrix: cascade.lightSpaceMatrix,
          margin: 0,
        )!;
        // Independent world AABBs, not the item's cached per-instance bounds.
        final wanted = <int>[];
        for (var i = 0; i < positions.length; i++) {
          final box = Aabb3.minMax(
            positions[i] - Vector3.all(0.5),
            positions[i] + Vector3.all(0.5),
          );
          if (!frustum.intersectsWithAabb3(box)) continue;
          if (planes.every((plane) {
            final n = plane.normal;
            final corner = Vector3(
              n.x < 0 ? box.min.x : box.max.x,
              n.y < 0 ? box.min.y : box.max.y,
              n.z < 0 ? box.min.z : box.max.z,
            );
            return n.dot(corner) + plane.constant >= 0;
          })) {
            wanted.add(i);
          }
        }
        expect(item.cullVisibleInstances(frustum, planes), wanted.isNotEmpty);
        expect(_indices(item), wanted);
        selections.add(_indices(item));
        _expectPayload(
          packInstanceTransformBatches([
            instanceDataBatchFor(item, indices: item.visibleInstanceIndices),
          ]),
          [(item, wanted)],
          withAttributes: false,
        );
      }
      expect(selections, hasLength(2));
      expect(selections[0], isNot(equals(selections[1])));
      expect(selections.expand((indices) => indices), contains(7));
      for (var cameraPass = 0; cameraPass < 2; cameraPass++) {
        expect(item.cullVisibleInstances(cameraFrustum, []), isTrue);
        expect(_indices(item), cameraIndices);
      }
    },
  );

  test('a caster touching receiver or frustum planes remains accepted', () {
    final item = _item([
      Vector3(-0.5, 0, 0), // AABB max x exactly at receiver x=0.
      Vector3(-0.501, 0, 0),
      Vector3(4.5, 0, 0), // AABB min x exactly at light right x=4.
      Vector3(4.501, 0, 0),
    ]);
    expect(
      item.cullVisibleInstances(_box(-4, 4), [Plane.components(1, 0, 0, 0)]),
      isTrue,
    );
    expect(_indices(item), [0, 2]);
  });

  test(
    'aggregate inside the light still honors individual receiver planes',
    () {
      final item = _item([Vector3(-4, 0, 0), Vector3(4, 0, 0)])
        ..worldBounds = Aabb3.minMax(
          Vector3(-4.5, -0.5, -0.5),
          Vector3(4.5, 0.5, 0.5),
        );
      expect(item.cullVisibleInstances(_box(-10, 10), []), isTrue);
      expect(item.visibleInstanceIndices, isNull);
      expect(
        item.cullVisibleInstances(_box(-10, 10), [
          Plane.components(1, 0, 0, 0),
        ]),
        isTrue,
      );
      expect(_indices(item), [1]);
      expect(item.cullVisibleInstances(_box(-10, 10), []), isTrue);
      expect(item.visibleInstanceIndices, isNull);
    },
  );

  test(
    'partial cached and uncached payloads preserve custom data and winding',
    () {
      final item = _item(
        [for (var i = 0; i < 6; i++) Vector3(i * 4, 0, 0)],
        mirrorNode: true,
        mirroredInstances: {1, 4},
      );
      expect(item.cullVisibleInstances(_box(-17, -3), []), isTrue);
      expect(_indices(item), [1, 2, 3, 4]);
      final indices = limitInstanceIndices(item.visibleInstanceIndices, 6, 4);
      expect(indices, [1, 2, 3]);
      final cached = instanceDataBatchFor(item, indices: indices);
      expect(cached.packedWorldData, isNotNull);
      _expectPayload(packInstanceDataBatches([cached], attributeFloats: 2), [
        (item, [1, 2, 3]),
      ], withAttributes: true);
      _expectPayload(packInstanceTransformBatches([cached]), [
        (item, [1, 2, 3]),
      ], withAttributes: false);
      item
        ..instanceWorldData = null
        ..instanceWorldWindingFlipped = null;
      final uncached = instanceDataBatchFor(item, indices: indices);
      expect(uncached.instances, isNotNull);
      _expectPayload(packInstanceDataBatches([uncached], attributeFloats: 2), [
        (item, [1, 2, 3]),
      ], withAttributes: true);
      _expectPayload(packInstanceTransformBatches([uncached]), [
        (item, [1, 2, 3]),
      ], withAttributes: false);
    },
  );

  test(
    'batching keeps each sparse selection, rather than a first-N prefix',
    () {
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
    },
  );

  test(
    'shadow selector limits original indices and stays out of batch runs',
    () {
      final item = _item([for (var i = 0; i < 6; i++) Vector3(i * 4, 0, 0)]);
      final eye = Vector3(3, 7, -2);
      final mesh = MeshPrimitive(item.geometry, item.material)
        ..drawSelector = (context) {
          expect(context.pass, MeshDrawPass.shadow);
          expect(context.cameraPosition, eye);
          expect(context.primaryView, isFalse);
          return const MeshDrawSelection(instanceCount: 3);
        };
      item.drawSource = mesh;
      expect(item.cullVisibleInstances(_box(3, 17), []), isTrue);
      expect(_indices(item), [1, 2, 3, 4]);
      expect(depthBatchEnd([item, item], 0), 1);
      final selection = beginMeshDraw(
        item,
        item.geometry,
        MeshDrawPass.shadow,
        eye,
        false,
      );
      final indices = limitInstanceIndices(
        item.visibleInstanceIndices,
        6,
        selection.instanceCount,
      );
      expect(indices, [1, 2]);
      _expectPayload(
        packInstanceTransformBatches([
          instanceDataBatchFor(item, indices: indices),
        ]),
        [
          (item, [1, 2]),
        ],
        withAttributes: false,
      );
      expect(limitInstanceIndices(item.visibleInstanceIndices, 6, 1), isEmpty);
      endMeshDraw(item.geometry);
    },
  );

  test('unbounded or disabled culling resets stale indices conservatively', () {
    final item = _item([Vector3.zero(), Vector3(20, 0, 0)]);
    expect(item.cullVisibleInstances(_box(-2, 2), []), isTrue);
    expect(_indices(item), [0]);
    item.cullInstances = false;
    expect(item.cullVisibleInstances(_box(100, 104), []), isTrue);
    expect(item.visibleInstanceIndices, isNull);
    item.cullInstances = true;
    expect(item.cullVisibleInstances(_box(-2, 2), []), isTrue);
    expect(_indices(item), [0]);
    final unbounded = _item([
      Vector3.zero(),
      Vector3(20, 0, 0),
    ], geometry: _Geometry(bounded: false))..visibleInstanceIndices = [1];
    expect(unbounded.cullVisibleInstances(_box(100, 104), []), isTrue);
    expect(unbounded.visibleInstanceIndices, isNull);
    final single = RenderItem(geometry: _Geometry(), material: _Material())
      ..cullInstances = true
      ..visibleInstanceIndices = [1];
    expect(single.cullVisibleInstances(_box(100, 104), []), isTrue);
    expect(single.visibleInstanceIndices, isNull);
  });

  test(
    'non-instanced-layout fallback keeps sparse original matrix indices',
    () {
      final item = _item(
        [Vector3(20, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)],
        geometry: _Geometry(instanced: false),
        mirroredInstances: {2},
      );
      expect(item.geometry.instancedVertexLayout, isNull);
      expect(item.cullVisibleInstances(_box(-4, 4), []), isTrue);
      expect(_indices(item), [1, 2]);
      expect(depthBatchEnd([item, item], 0), 1);
      final selected = limitInstanceIndices(item.visibleInstanceIndices, 3, 2)!;
      expect(selected, [1]);
      expect(item.instanceTransforms![selected.single].getTranslation().x, 1);
      // This is the CPU selection contract, not execution of the GPU fallback.
      // The encoder must use selected indices, never instances.take(length).
    },
  );

  test(
    'refreshed transforms and empty instance groups cannot retain a view',
    () {
      final item = _item([Vector3.zero(), Vector3(20, 0, 0)]);
      expect(item.cullVisibleInstances(_box(-2, 2), []), isTrue);
      expect(_indices(item), [0]);
      item.instanceTransforms![0].setTranslationRaw(20, 0, 0);
      item.instanceTransforms![1].setTranslationRaw(0, 0, 0);
      item.refreshInstanceData();
      expect(item.cullVisibleInstances(_box(-2, 2), []), isTrue);
      expect(_indices(item), [1]);
      item
        ..instanceTransforms = []
        ..instanceColors = [];
      item.refreshInstanceData();
      expect(item.cullVisibleInstances(_box(-2, 2), []), isFalse);
      expect(_indices(item), isEmpty);
    },
  );
}
