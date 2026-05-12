// Bounds API tests. Exercises Mesh.localBounds, Node.combinedLocalBounds,
// and the markBoundsDirty invalidation chain. Uses a stub Geometry that
// skips shader-library access so the tests don't need a Flutter GPU
// context.

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Geometry that skips shader-library access. Lets us exercise bounds
/// logic without a Flutter GPU context.
class _StubGeometry extends Geometry {
  _StubGeometry({Aabb3? aabb}) {
    if (aabb != null) {
      setLocalBounds(
        aabb,
        Sphere.centerRadius(
          (aabb.min + aabb.max) * 0.5,
          ((aabb.max - aabb.min) * 0.5).length,
        ),
      );
    }
  }

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

/// Material that doesn't try to load a fragment shader on construction.
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

Aabb3 _aabb(Vector3 a, Vector3 b) => Aabb3.minMax(a, b);

MeshPrimitive _primWithBounds(Aabb3? aabb) =>
    MeshPrimitive(_StubGeometry(aabb: aabb), _StubMaterial());

void main() {
  group('Geometry.setLocalBounds', () {
    test('round-trips an explicitly-set AABB and sphere', () {
      final g = _StubGeometry(
        aabb: _aabb(Vector3(-1, -2, -3), Vector3(1, 2, 3)),
      );
      expect(g.localBounds!.min, Vector3(-1, -2, -3));
      expect(g.localBounds!.max, Vector3(1, 2, 3));
      expect(
        g.localBoundingSphere!.radius,
        closeTo(Vector3(1, 2, 3).length, 1e-6),
      );
    });

    test('null bounds when not set', () {
      final g = _StubGeometry();
      expect(g.localBounds, isNull);
      expect(g.localBoundingSphere, isNull);
    });
  });

  group('Mesh.localBounds', () {
    test('returns the bound when the mesh has a single primitive', () {
      final m = Mesh.primitives(
        primitives: [
          _primWithBounds(_aabb(Vector3(-1, -1, -1), Vector3(1, 1, 1))),
        ],
      );
      expect(m.localBounds!.min, Vector3(-1, -1, -1));
      expect(m.localBounds!.max, Vector3(1, 1, 1));
    });

    test('unions multiple primitives', () {
      final m = Mesh.primitives(
        primitives: [
          _primWithBounds(_aabb(Vector3(-1, 0, 0), Vector3(0, 1, 1))),
          _primWithBounds(_aabb(Vector3(0, -1, 0), Vector3(1, 0, 1))),
        ],
      );
      expect(m.localBounds!.min, Vector3(-1, -1, 0));
      expect(m.localBounds!.max, Vector3(1, 1, 1));
    });

    test('returns null when no primitive contributes bounds', () {
      final m = Mesh.primitives(
        primitives: [_primWithBounds(null), _primWithBounds(null)],
      );
      expect(m.localBounds, isNull);
    });

    test('skips primitives without bounds when others have them', () {
      final m = Mesh.primitives(
        primitives: [
          _primWithBounds(null),
          _primWithBounds(_aabb(Vector3(1, 1, 1), Vector3(2, 2, 2))),
        ],
      );
      expect(m.localBounds!.min, Vector3(1, 1, 1));
      expect(m.localBounds!.max, Vector3(2, 2, 2));
    });

    test('caches the result and rebuilds on markLocalBoundsDirty', () {
      final p = _primWithBounds(_aabb(Vector3(0, 0, 0), Vector3(1, 1, 1)));
      final m = Mesh.primitives(primitives: [p]);
      // Prime the cache.
      expect(m.localBounds!.max, Vector3(1, 1, 1));
      // Swap in a different geometry; without invalidation, the cache
      // would still report the old extents.
      p.geometry = _StubGeometry(
        aabb: _aabb(Vector3(0, 0, 0), Vector3(5, 5, 5)),
      );
      expect(m.localBounds!.max, Vector3(1, 1, 1), reason: 'cache hit');
      m.markLocalBoundsDirty();
      expect(m.localBounds!.max, Vector3(5, 5, 5), reason: 'after dirty');
    });
  });

  group('Node.combinedLocalBounds', () {
    test('null on an empty node', () {
      expect(Node().combinedLocalBounds, isNull);
    });

    test('matches own mesh bounds with no children', () {
      final node = Node(
        mesh: Mesh.primitives(
          primitives: [
            _primWithBounds(_aabb(Vector3(-1, -1, -1), Vector3(1, 1, 1))),
          ],
        ),
      );
      expect(node.combinedLocalBounds!.min, Vector3(-1, -1, -1));
      expect(node.combinedLocalBounds!.max, Vector3(1, 1, 1));
    });

    test('unions child bounds transformed by the child local transform', () {
      final parent = Node(
        mesh: Mesh.primitives(
          primitives: [
            _primWithBounds(_aabb(Vector3(-1, -1, -1), Vector3(1, 1, 1))),
          ],
        ),
      );
      final child = Node(
        localTransform: Matrix4.translationValues(10, 0, 0),
        mesh: Mesh.primitives(
          primitives: [
            _primWithBounds(_aabb(Vector3(-1, -1, -1), Vector3(1, 1, 1))),
          ],
        ),
      );
      parent.add(child);

      // Child contributes a [9,11] x [-1,1] x [-1,1] AABB into parent
      // local space; union with parent's own [-1,1]^3.
      expect(parent.combinedLocalBounds!.min, Vector3(-1, -1, -1));
      expect(parent.combinedLocalBounds!.max, Vector3(11, 1, 1));
    });

    test('handles negative-determinant child transforms correctly', () {
      // The scene-root coordinate flip uses a (1,1,-1) scale; verify the
      // transformed AABB is still correct.
      final parent = Node();
      final child = Node(
        localTransform: Matrix4.identity()..setEntry(2, 2, -1.0),
        mesh: Mesh.primitives(
          primitives: [
            _primWithBounds(_aabb(Vector3(-1, -2, 3), Vector3(1, 2, 5))),
          ],
        ),
      );
      parent.add(child);
      // Child's z range [3,5] flips to [-5,-3] under the (1,1,-1) scale.
      expect(parent.combinedLocalBounds!.min, Vector3(-1, -2, -5));
      expect(parent.combinedLocalBounds!.max, Vector3(1, 2, -3));
    });

    test('ignores subtrees whose primitives have no bounds', () {
      final parent = Node();
      parent.add(
        Node(mesh: Mesh.primitives(primitives: [_primWithBounds(null)])),
      );
      // The single subtree contributes nothing usable, so the parent
      // is unbounded too.
      expect(parent.combinedLocalBounds, isNull);
    });

    test('caches the result and invalidates on add/remove', () {
      final parent = Node(
        mesh: Mesh.primitives(
          primitives: [
            _primWithBounds(_aabb(Vector3(-1, -1, -1), Vector3(1, 1, 1))),
          ],
        ),
      );
      // Prime the cache.
      expect(parent.combinedLocalBounds!.max, Vector3(1, 1, 1));

      final child = Node(
        localTransform: Matrix4.translationValues(10, 0, 0),
        mesh: Mesh.primitives(
          primitives: [
            _primWithBounds(_aabb(Vector3(-1, -1, -1), Vector3(1, 1, 1))),
          ],
        ),
      );
      parent.add(child);
      expect(
        parent.combinedLocalBounds!.max,
        Vector3(11, 1, 1),
        reason: 'add() should invalidate the cache',
      );

      parent.remove(child);
      expect(
        parent.combinedLocalBounds!.max,
        Vector3(1, 1, 1),
        reason: 'remove() should invalidate the cache',
      );
    });

    test('invalidates ancestors on markBoundsDirty', () {
      final root = Node();
      final mid = Node();
      final leaf = Node(
        mesh: Mesh.primitives(
          primitives: [
            _primWithBounds(_aabb(Vector3(0, 0, 0), Vector3(1, 1, 1))),
          ],
        ),
      );
      root.add(mid);
      mid.add(leaf);
      // Prime caches at every level.
      expect(root.combinedLocalBounds!.max, Vector3(1, 1, 1));

      // Mutate the leaf's mesh contents and call markBoundsDirty on the
      // leaf. The root's cache should drop too.
      leaf.mesh!.primitives[0].geometry = _StubGeometry(
        aabb: _aabb(Vector3(0, 0, 0), Vector3(5, 5, 5)),
      );
      leaf.mesh!.markLocalBoundsDirty();
      leaf.markBoundsDirty();
      expect(root.combinedLocalBounds!.max, Vector3(5, 5, 5));
    });

    test('skinned node uses the geometry localBounds (which the importer '
        'pre-populates with the pose-union AABB)', () {
      // Stub geometry stands in for an importer-baked geometry whose
      // localBounds was set from skinnedPoseUnionAabb.
      final node = Node(
        mesh: Mesh.primitives(
          primitives: [
            _primWithBounds(_aabb(Vector3(-2, -2, -2), Vector3(2, 2, 2))),
          ],
        ),
      );
      node.skin = Skin();
      // The bound the test injects via setLocalBounds is treated as
      // already representing the pose-union extent, so the runtime
      // uses it for cull.
      expect(node.combinedLocalBounds!.min, Vector3(-2, -2, -2));
      expect(node.combinedLocalBounds!.max, Vector3(2, 2, 2));
    });

    test('skinned node with no geometry bounds is treated as unbounded', () {
      // Falls through the bake (no animations to derive a pose-union
      // from, or analysis was skipped). Runtime conservatively
      // treats the subtree as always visible.
      final node = Node(
        mesh: Mesh.primitives(primitives: [_primWithBounds(null)]),
      );
      node.skin = Skin();
      expect(node.combinedLocalBounds, isNull);
    });

    test('mesh setter invalidates the cache', () {
      final node = Node(
        mesh: Mesh.primitives(
          primitives: [
            _primWithBounds(_aabb(Vector3(-1, -1, -1), Vector3(1, 1, 1))),
          ],
        ),
      );
      expect(node.combinedLocalBounds!.max, Vector3(1, 1, 1));
      node.mesh = Mesh.primitives(
        primitives: [
          _primWithBounds(_aabb(Vector3(-2, -2, -2), Vector3(2, 2, 2))),
        ],
      );
      expect(node.combinedLocalBounds!.max, Vector3(2, 2, 2));
    });
  });
}
