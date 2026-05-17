// BVH tests. Builds a Bvh over RenderItems with stub geometry/material
// and checks that query agrees with a brute-force frustum test.

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/render/bvh.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

class _StubGeometry extends Geometry {
  @override
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition,
  ) {
    throw UnsupportedError('Stub geometry is not renderable');
  }
}

class _StubMaterial extends Material {
  @override
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    Lighting lighting,
  ) {
    throw UnsupportedError('Stub material is not renderable');
  }
}

RenderItem _renderItem() =>
    RenderItem(geometry: _StubGeometry(), material: _StubMaterial());

/// A render item with a unit world AABB centered at `(x, 0, 0)`.
RenderItem _itemAt(double x) {
  return _renderItem()
    ..worldBounds = Aabb3.minMax(
      Vector3(x - 0.5, -0.5, -0.5),
      Vector3(x + 0.5, 0.5, 0.5),
    );
}

void main() {
  group('Bvh', () {
    test('an empty BVH yields nothing', () {
      final hits = <RenderItem>[];
      Bvh.build([]).query(Frustum.matrix(Matrix4.identity()), hits.add);
      expect(hits, isEmpty);
    });

    test('a single-item BVH yields that item when it intersects', () {
      final item = _itemAt(0);
      final hits = <RenderItem>[];
      Bvh.build([item]).query(
        Frustum.matrix(makeOrthographicMatrix(-5, 5, -5, 5, -5, 5)),
        hits.add,
      );
      expect(hits, [item]);
    });

    test('query agrees with a brute-force frustum test', () {
      final items = [for (int i = 0; i < 8; i++) _itemAt(i * 4.0)];
      final bvh = Bvh.build(items);
      final frustum = Frustum.matrix(
        makeOrthographicMatrix(-2, 14, -10, 10, -100, 100),
      );

      final expected =
          items
              .where((i) => frustum.intersectsWithAabb3(i.worldBounds!))
              .toSet();
      // The frustum must select a proper, non-empty subset, or the test
      // proves nothing.
      expect(expected, isNotEmpty);
      expect(expected.length, lessThan(items.length));

      final hits = <RenderItem>{};
      bvh.query(frustum, hits.add);
      expect(hits, expected);
    });

    test('a frustum containing every item returns them all', () {
      final items = [for (int i = 0; i < 8; i++) _itemAt(i * 4.0)];
      final frustum = Frustum.matrix(
        makeOrthographicMatrix(-1000, 1000, -1000, 1000, -1000, 1000),
      );
      final hits = <RenderItem>{};
      Bvh.build(items).query(frustum, hits.add);
      expect(hits, items.toSet());
    });

    test('refit tracks an item that moved', () {
      final mover = _itemAt(0);
      final bvh = Bvh.build([
        mover,
        for (int i = 1; i < 5; i++) _itemAt(i * 4.0),
      ]);

      final nearOrigin = Frustum.matrix(
        makeOrthographicMatrix(-2, 2, -2, 2, -100, 100),
      );
      var hits = <RenderItem>{};
      bvh.query(nearOrigin, hits.add);
      expect(hits, {mover}, reason: 'mover starts in the frustum');

      // Move the item far away and refit.
      mover.worldBounds = Aabb3.minMax(
        Vector3(99.5, -0.5, -0.5),
        Vector3(100.5, 0.5, 0.5),
      );
      bvh.refit();

      hits = <RenderItem>{};
      bvh.query(nearOrigin, hits.add);
      expect(hits, isEmpty, reason: 'the moved item left the frustum');

      hits = <RenderItem>{};
      bvh.query(
        Frustum.matrix(makeOrthographicMatrix(98, 102, -2, 2, -100, 100)),
        hits.add,
      );
      expect(hits, {mover}, reason: 'the moved item is found at its new spot');
    });
  });

  group('RenderScene.cull', () {
    test('always-visible items are returned regardless of the frustum', () {
      final scene = RenderScene();
      final bounded = _itemAt(0);
      final unbounded = _renderItem(); // worldBounds stays null
      final optedOut = _itemAt(1000)..frustumCulled = false;
      scene.add(bounded);
      scene.add(unbounded);
      scene.add(optedOut);
      scene.rebuildIfDirty();

      // A frustum far from every item's bounds.
      final frustum = Frustum.matrix(
        makeOrthographicMatrix(500, 510, 500, 510, -1, 1),
      );
      final hits = <RenderItem>{};
      scene.cull(frustum, hits.add);

      expect(hits.contains(unbounded), isTrue);
      expect(hits.contains(optedOut), isTrue);
      expect(hits.contains(bounded), isFalse);
    });
  });
}
