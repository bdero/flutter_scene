// Covers assignLightsToItems: ranged lights reach only the items their
// influence AABB overlaps (scattered through the BVH), infinite-influence
// lights reach every item, unbounded items receive every light, and each
// item's list keeps the closest lights when capped at maxPerItem.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/bvh.dart';
import 'package:flutter_scene/src/render/light_culling.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

class _StubGeometry extends Geometry {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
    double depthBias = 0.0,
  }) => throw UnsupportedError('stub');
}

class _StubMaterial extends Material {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Lighting l,
  ) => throw UnsupportedError('stub');
}

RenderItem _itemAt(double x) =>
    RenderItem(geometry: _StubGeometry(), material: _StubMaterial())
      ..worldBounds = Aabb3.minMax(
        Vector3(x - 0.5, -0.5, -0.5),
        Vector3(x + 0.5, 0.5, 0.5),
      );

RenderItem _unboundedItem() =>
    RenderItem(geometry: _StubGeometry(), material: _StubMaterial());

void main() {
  test('a ranged light reaches only the items it overlaps', () {
    final near = _itemAt(0);
    final far = _itemAt(10);
    final items = [near, far];
    final bvh = Bvh.build(items);

    // Range 1.5 at the origin: AABB [-1.5, 1.5], overlaps `near`, not `far`.
    final light = CullableLight(0, lightInfluenceBounds(Vector3.zero(), 1.5));
    final result = assignLightsToItems(
      items: items,
      bvh: bvh,
      lights: [light],
      maxPerItem: 16,
    );

    expect(near.lightListCount, 1);
    expect(near.lightListOffset, 0);
    expect(far.lightListCount, 0);
    expect(result.indices, [0]);
    expect(result.overflowed, isFalse);
    // The far item's slice is empty.
    expect(
      result.indices.sublist(
        far.lightListOffset,
        far.lightListOffset + far.lightListCount,
      ),
      isEmpty,
    );
  });

  test('infinite-influence lights share one index slice', () {
    final a = _itemAt(0);
    final b = _itemAt(100);
    final items = [a, b];
    final result = assignLightsToItems(
      items: items,
      bvh: Bvh.build(items),
      lights: const [
        CullableLight(7, null),
        CullableLight(9, null),
      ], // null bounds = infinite
      maxPerItem: 16,
    );
    expect(a.lightListOffset, 0);
    expect(b.lightListOffset, 0);
    expect(a.lightListCount, 2);
    expect(b.lightListCount, 2);
    expect(result.indices, [7, 9]);
  });

  test('lightInfluenceBounds is null for a non-positive range', () {
    expect(lightInfluenceBounds(Vector3.zero(), 0.0), isNull);
    expect(lightInfluenceBounds(Vector3.zero(), -1.0), isNull);
    expect(lightInfluenceBounds(Vector3.zero(), 2.0), isNotNull);
  });

  test('an unbounded item receives every light', () {
    final bounded = _itemAt(0);
    final unbounded = _unboundedItem();
    final items = [bounded, unbounded];
    // Only the bounded item is in the BVH (mirrors RenderScene.rebuildIfDirty).
    final bvh = Bvh.build([bounded]);

    // A ranged light far from the bounded item plus an infinite one.
    final ranged = CullableLight(
      1,
      lightInfluenceBounds(Vector3(500, 0, 0), 1.0),
    );
    final result = assignLightsToItems(
      items: items,
      bvh: bvh,
      lights: [ranged, const CullableLight(2, null)],
      maxPerItem: 16,
    );

    // The bounded item is out of the ranged light's reach: infinite only.
    expect(bounded.lightListCount, 1);
    // The unbounded item cannot be culled: it gets both.
    expect(unbounded.lightListCount, 2);
    expect(result.overflowed, isFalse);
  });

  test('a per-item list keeps the nearest lights when it overflows', () {
    final item = _itemAt(0);
    final items = [item];
    CullableLight local(int index, double x) => CullableLight(
      index,
      lightInfluenceBounds(Vector3(x, 0, 0), 20),
      worldPosition: Vector3(x, 0, 0),
    );
    final result = assignLightsToItems(
      items: items,
      bvh: Bvh.build(items),
      lights: [local(0, 9), local(1, 3), local(2, 1), local(3, 2), local(4, 5)],
      maxPerItem: 3,
    );
    expect(item.lightListCount, 3);
    expect(result.indices, [2, 3, 1]);
    expect(result.overflowed, isTrue);
  });

  test('directional lights sort ahead of local lights on overflow', () {
    final item = _itemAt(0);
    final items = [item];
    final result = assignLightsToItems(
      items: items,
      bvh: Bvh.build(items),
      lights: [
        CullableLight(
          0,
          lightInfluenceBounds(Vector3(4, 0, 0), 10),
          worldPosition: Vector3(4, 0, 0),
        ),
        const CullableLight(1, null),
        CullableLight(
          2,
          lightInfluenceBounds(Vector3(1, 0, 0), 10),
          worldPosition: Vector3(1, 0, 0),
        ),
      ],
      maxPerItem: 2,
    );

    expect(result.indices, [1, 2]);
    expect(result.overflowed, isTrue);
  });

  test('infinite-range local lights are still ranked by distance', () {
    final item = _itemAt(0);
    final items = [item];
    final result = assignLightsToItems(
      items: items,
      bvh: Bvh.build(items),
      lights: [
        CullableLight(3, null, worldPosition: Vector3(10, 0, 0)),
        CullableLight(4, null, worldPosition: Vector3(1, 0, 0)),
      ],
      maxPerItem: 1,
    );

    expect(result.indices, [4]);
    expect(result.overflowed, isTrue);
  });

  test('offsets pack items back to back', () {
    final a = _itemAt(0);
    final b = _itemAt(0); // same spot, both overlap the light
    final items = [a, b];
    final bvh = Bvh.build(items);
    final light = CullableLight(4, lightInfluenceBounds(Vector3.zero(), 1.0));
    final result = assignLightsToItems(
      items: items,
      bvh: bvh,
      lights: [light],
      maxPerItem: 16,
    );
    expect(a.lightListOffset, 0);
    expect(a.lightListCount, 1);
    expect(b.lightListOffset, 1);
    expect(b.lightListCount, 1);
    expect(result.indices, [4, 4]);
  });
}
