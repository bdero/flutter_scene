import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:vector_math/vector_math.dart';

/// A bounding volume hierarchy over the bounded [RenderItem]s of a
/// [RenderScene].
///
/// Built from each item's world-space AABB. A render pass queries it with
/// its view frustum to collect potentially-visible items without testing
/// every item in the scene.
///
/// Engine-internal; rebuilt by [RenderScene] when the scene changes.
class Bvh {
  Bvh._(this._root);

  /// Builds a BVH over [items]. Every item must have a non-null
  /// [RenderItem.worldBounds].
  factory Bvh.build(List<RenderItem> items) {
    if (items.isEmpty) return Bvh._(null);
    final entries = [for (final item in items) _Entry(item)];
    return Bvh._(_buildNode(entries));
  }

  final _BvhNode? _root;

  /// Calls [visit] once for every item whose world AABB intersects
  /// [frustum].
  void query(Frustum frustum, void Function(RenderItem) visit) {
    _query(_root, frustum, visit);
  }

  static void _query(
    _BvhNode? node,
    Frustum frustum,
    void Function(RenderItem) visit,
  ) {
    if (node == null) return;
    if (!frustum.intersectsWithAabb3(node.bounds)) return;
    final item = node.item;
    if (item != null) {
      visit(item);
      return;
    }
    _query(node.left, frustum, visit);
    _query(node.right, frustum, visit);
  }

  static _BvhNode _buildNode(List<_Entry> entries) {
    // Node bounds: the hull of every item in the set.
    final bounds = Aabb3.copy(entries.first.item.worldBounds!);
    for (int i = 1; i < entries.length; i++) {
      bounds.hull(entries[i].item.worldBounds!);
    }
    if (entries.length == 1) {
      return _BvhNode.leaf(entries.first.item, bounds);
    }

    // Split the longest axis of the centroid spread at the median.
    final centroidMin = entries.first.centroid.clone();
    final centroidMax = entries.first.centroid.clone();
    for (int i = 1; i < entries.length; i++) {
      Vector3.min(centroidMin, entries[i].centroid, centroidMin);
      Vector3.max(centroidMax, entries[i].centroid, centroidMax);
    }
    int axis = 0;
    double longest = centroidMax.x - centroidMin.x;
    final spanY = centroidMax.y - centroidMin.y;
    if (spanY > longest) {
      axis = 1;
      longest = spanY;
    }
    if (centroidMax.z - centroidMin.z > longest) {
      axis = 2;
    }
    entries.sort((a, b) => a.centroid[axis].compareTo(b.centroid[axis]));

    final mid = entries.length >> 1;
    return _BvhNode.internal(
      _buildNode(entries.sublist(0, mid)),
      _buildNode(entries.sublist(mid)),
      bounds,
    );
  }
}

/// A render item paired with the centroid of its world AABB, used during
/// the build to avoid recomputing centroids in the sort comparator.
class _Entry {
  _Entry(this.item) : centroid = _centroidOf(item);

  final RenderItem item;
  final Vector3 centroid;

  static Vector3 _centroidOf(RenderItem item) {
    final bounds = item.worldBounds!;
    return (bounds.min + bounds.max)..scale(0.5);
  }
}

class _BvhNode {
  _BvhNode.leaf(this.item, this.bounds) : left = null, right = null;
  _BvhNode.internal(this.left, this.right, this.bounds) : item = null;

  /// Non-null for a leaf, which holds exactly one render item.
  final RenderItem? item;
  final _BvhNode? left;
  final _BvhNode? right;

  /// AABB enclosing every item under this node.
  final Aabb3 bounds;
}
