// Covers assignLightsToItems: ranged lights reach only the items their
// influence AABB overlaps (scattered through the BVH), infinite-influence
// lights reach every item, unbounded items receive every light, and each
// item's list is capped at maxPerItem with the excess flagged.

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
    gpu.HostBuffer transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
  }) => throw UnsupportedError('stub');
}

class _StubMaterial extends Material {
  @override
  void bind(gpu.RenderPass pass, gpu.HostBuffer transientsBuffer, Lighting l) =>
      throw UnsupportedError('stub');
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

  test('an infinite-influence light reaches every item', () {
    final a = _itemAt(0);
    final b = _itemAt(100);
    final items = [a, b];
    final result = assignLightsToItems(
      items: items,
      bvh: Bvh.build(items),
      lights: [const CullableLight(7, null)], // null bounds = infinite
      maxPerItem: 16,
    );
    expect(a.lightListCount, 1);
    expect(b.lightListCount, 1);
    expect(result.indices, [7, 7]);
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

  test('a per-item list is capped at maxPerItem and flags overflow', () {
    final item = _itemAt(0);
    final items = [item];
    // Five infinite lights, cap of 3.
    final result = assignLightsToItems(
      items: items,
      bvh: Bvh.build(items),
      lights: [for (var i = 0; i < 5; i++) CullableLight(i, null)],
      maxPerItem: 3,
    );
    expect(item.lightListCount, 3);
    expect(result.indices, [0, 1, 2]);
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
