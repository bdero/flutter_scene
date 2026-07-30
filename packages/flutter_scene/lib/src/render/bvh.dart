import 'dart:typed_data';

import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:vector_math/vector_math.dart';

/// A bounding volume hierarchy over the bounded [RenderItem]s of a
/// [RenderScene].
///
/// Built from each item's world-space AABB. A render pass queries it with
/// its view frustum to collect potentially-visible items without testing
/// every item in the scene.
///
/// Nodes live in flat typed-data arrays rather than a pointer tree, so
/// build, refit, and query all stream contiguous memory. The build sorts
/// items along a Morton curve with a radix sort and splits ranges at the
/// median, which costs O(n) per level with no per-level sorting; children
/// are allocated before their parent, so [refit] is a single forward pass.
///
/// Engine-internal; rebuilt by [RenderScene] when the scene changes.
class Bvh {
  Bvh._(this._bounds, this._children, this._items, this._nodeCount);

  /// Builds a BVH over [items]. Every item must have a non-null
  /// [RenderItem.worldBounds].
  factory Bvh.build(List<RenderItem> items) {
    final n = items.length;
    if (n == 0) {
      return Bvh._(Float32List(0), Int32List(0), const [], 0);
    }

    // Quantize each item's centroid into a 30-bit Morton key.
    final centroids = Float32List(n * 3);
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity,
        maxY = -double.infinity,
        maxZ = -double.infinity;
    for (var i = 0; i < n; i++) {
      final b = items[i].worldBounds!;
      final cx = (b.min.x + b.max.x) * 0.5;
      final cy = (b.min.y + b.max.y) * 0.5;
      final cz = (b.min.z + b.max.z) * 0.5;
      centroids[i * 3] = cx;
      centroids[i * 3 + 1] = cy;
      centroids[i * 3 + 2] = cz;
      if (cx < minX) minX = cx;
      if (cy < minY) minY = cy;
      if (cz < minZ) minZ = cz;
      if (cx > maxX) maxX = cx;
      if (cy > maxY) maxY = cy;
      if (cz > maxZ) maxZ = cz;
    }
    final spanX = maxX - minX, spanY = maxY - minY, spanZ = maxZ - minZ;
    final scaleX = spanX > 0 ? 1023.0 / spanX : 0.0;
    final scaleY = spanY > 0 ? 1023.0 / spanY : 0.0;
    final scaleZ = spanZ > 0 ? 1023.0 / spanZ : 0.0;
    final keys = Uint32List(n);
    for (var i = 0; i < n; i++) {
      final qx = ((centroids[i * 3] - minX) * scaleX).toInt();
      final qy = ((centroids[i * 3 + 1] - minY) * scaleY).toInt();
      final qz = ((centroids[i * 3 + 2] - minZ) * scaleZ).toInt();
      keys[i] =
          _spreadBits(qx) | (_spreadBits(qy) << 1) | (_spreadBits(qz) << 2);
    }

    // Radix-sort item indices by Morton key, three 10-bit passes.
    var order = Uint32List(n);
    var scratch = Uint32List(n);
    for (var i = 0; i < n; i++) {
      order[i] = i;
    }
    final histogram = Uint32List(1024);
    for (var shift = 0; shift < 30; shift += 10) {
      histogram.fillRange(0, 1024, 0);
      for (var i = 0; i < n; i++) {
        histogram[(keys[order[i]] >> shift) & 1023]++;
      }
      var sum = 0;
      for (var bucket = 0; bucket < 1024; bucket++) {
        final count = histogram[bucket];
        histogram[bucket] = sum;
        sum += count;
      }
      for (var i = 0; i < n; i++) {
        final index = order[i];
        scratch[histogram[(keys[index] >> shift) & 1023]++] = index;
      }
      final swap = order;
      order = scratch;
      scratch = swap;
    }

    // Emit nodes over the sorted order, splitting ranges at the median.
    // Post-order allocation, so both children of a node precede it.
    final nodeCap = 2 * n - 1;
    final bounds = Float32List(nodeCap * 6);
    final children = Int32List(nodeCap * 2);
    final leafItems = List<RenderItem>.filled(n, items[0]);
    var nodeCount = 0;
    var leafCount = 0;

    int emit(int lo, int hi) {
      if (hi - lo == 1) {
        final item = items[order[lo]];
        final leaf = leafCount++;
        leafItems[leaf] = item;
        final node = nodeCount++;
        final b = item.worldBounds!;
        final o = node * 6;
        bounds[o] = b.min.x;
        bounds[o + 1] = b.min.y;
        bounds[o + 2] = b.min.z;
        bounds[o + 3] = b.max.x;
        bounds[o + 4] = b.max.y;
        bounds[o + 5] = b.max.z;
        children[node * 2] = ~leaf;
        return node;
      }
      final mid = (lo + hi) >> 1;
      final left = emit(lo, mid);
      final right = emit(mid, hi);
      final node = nodeCount++;
      final o = node * 6, l = left * 6, r = right * 6;
      for (var axis = 0; axis < 3; axis++) {
        final lMin = bounds[l + axis], rMin = bounds[r + axis];
        bounds[o + axis] = lMin < rMin ? lMin : rMin;
        final lMax = bounds[l + 3 + axis], rMax = bounds[r + 3 + axis];
        bounds[o + 3 + axis] = lMax > rMax ? lMax : rMax;
      }
      children[node * 2] = left;
      children[node * 2 + 1] = right;
      return node;
    }

    emit(0, n);
    return Bvh._(bounds, children, leafItems, nodeCount);
  }

  // Node storage. Node i owns bounds[i*6..i*6+6) as
  // (minX, minY, minZ, maxX, maxY, maxZ). children[i*2] is the left child
  // index, or ~leafIndex for a leaf (children[i*2+1] then unused). The
  // root is the last node.
  final Float32List _bounds;
  final Int32List _children;
  final List<RenderItem> _items;
  final int _nodeCount;

  // Traversal stack, sized for a balanced tree far deeper than any
  // realistic item count. Queries are single-threaded and never nest (a
  // visit callback must not query the same Bvh).
  final Int32List _stack = Int32List(64);

  // Frustum planes as (nx, ny, nz, constant) rows, reloaded per query.
  final Float64List _planes = Float64List(24);

  /// Calls [visit] once for every item whose world AABB intersects
  /// [frustum].
  void query(Frustum frustum, void Function(RenderItem) visit) {
    if (_nodeCount == 0) return;
    _loadPlane(0, frustum.plane0);
    _loadPlane(1, frustum.plane1);
    _loadPlane(2, frustum.plane2);
    _loadPlane(3, frustum.plane3);
    _loadPlane(4, frustum.plane4);
    _loadPlane(5, frustum.plane5);
    final bounds = _bounds;
    final children = _children;
    final planes = _planes;
    final stack = _stack;
    var top = 0;
    stack[top++] = _nodeCount - 1;
    while (top > 0) {
      final node = stack[--top];
      final o = node * 6;
      // Outside when the corner farthest along a plane's normal is below
      // that plane, matching Frustum.intersectsWithAabb3.
      var outside = false;
      for (var p = 0; p < 24; p += 4) {
        final nx = planes[p], ny = planes[p + 1], nz = planes[p + 2];
        final px = nx < 0 ? bounds[o] : bounds[o + 3];
        final py = ny < 0 ? bounds[o + 1] : bounds[o + 4];
        final pz = nz < 0 ? bounds[o + 2] : bounds[o + 5];
        if (nx * px + ny * py + nz * pz + planes[p + 3] < 0) {
          outside = true;
          break;
        }
      }
      if (outside) continue;
      final left = children[node * 2];
      if (left < 0) {
        visit(_items[~left]);
        continue;
      }
      stack[top++] = left;
      stack[top++] = children[node * 2 + 1];
    }
  }

  void _loadPlane(int index, Plane plane) {
    final o = index * 4;
    _planes[o] = plane.normal.x;
    _planes[o + 1] = plane.normal.y;
    _planes[o + 2] = plane.normal.z;
    _planes[o + 3] = plane.constant;
  }

  /// Calls [visit] once for every item whose world AABB intersects [box].
  ///
  /// Used to scatter a light's influence volume onto the items it can reach,
  /// so each item collects only the lights near it.
  void queryAabb(Aabb3 box, void Function(RenderItem) visit) {
    if (_nodeCount == 0) return;
    final minX = box.min.x, minY = box.min.y, minZ = box.min.z;
    final maxX = box.max.x, maxY = box.max.y, maxZ = box.max.z;
    final bounds = _bounds;
    final children = _children;
    final stack = _stack;
    var top = 0;
    stack[top++] = _nodeCount - 1;
    while (top > 0) {
      final node = stack[--top];
      final o = node * 6;
      if (bounds[o] > maxX ||
          bounds[o + 1] > maxY ||
          bounds[o + 2] > maxZ ||
          bounds[o + 3] < minX ||
          bounds[o + 4] < minY ||
          bounds[o + 5] < minZ) {
        continue;
      }
      final left = children[node * 2];
      if (left < 0) {
        visit(_items[~left]);
        continue;
      }
      stack[top++] = left;
      stack[top++] = children[node * 2 + 1];
    }
  }

  /// Recomputes every node's AABB from the leaves' current
  /// [RenderItem.worldBounds] without changing the tree topology.
  ///
  /// Valid only while the item set and each leaf's item are unchanged
  /// since the build; a moved item is fine, an added or removed one
  /// needs a rebuild. Cheaper than a rebuild (O(n), no sort), but tree
  /// quality degrades as items drift from their build-time grouping.
  void refit() {
    final bounds = _bounds;
    final children = _children;
    // Children precede parents, so one forward pass refreshes everything.
    for (var node = 0; node < _nodeCount; node++) {
      final o = node * 6;
      final left = children[node * 2];
      if (left < 0) {
        final b = _items[~left].worldBounds!;
        bounds[o] = b.min.x;
        bounds[o + 1] = b.min.y;
        bounds[o + 2] = b.min.z;
        bounds[o + 3] = b.max.x;
        bounds[o + 4] = b.max.y;
        bounds[o + 5] = b.max.z;
        continue;
      }
      final l = left * 6, r = children[node * 2 + 1] * 6;
      for (var axis = 0; axis < 3; axis++) {
        final lMin = bounds[l + axis], rMin = bounds[r + axis];
        bounds[o + axis] = lMin < rMin ? lMin : rMin;
        final lMax = bounds[l + 3 + axis], rMax = bounds[r + 3 + axis];
        bounds[o + 3 + axis] = lMax > rMax ? lMax : rMax;
      }
    }
  }

  // Spreads the low 10 bits of [value] so consecutive bits land three
  // apart (Morton interleave).
  static int _spreadBits(int value) {
    var x = value & 0x3ff;
    x = (x | (x << 16)) & 0x030000ff;
    x = (x | (x << 8)) & 0x0300f00f;
    x = (x | (x << 4)) & 0x030c30c3;
    x = (x | (x << 2)) & 0x09249249;
    return x;
  }
}
