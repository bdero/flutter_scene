// A refittable bounding volume hierarchy over a flat array of world AABBs,
// used as the broad phase for scene queries.

import 'dart:typed_data';

/// Leaves per node. One box per leaf keeps [refit] exact and the tree small
/// enough that the extra levels cost less than the boxes they reject.
const int _leafSize = 4;

/// A bounding volume hierarchy over `count` world-space AABBs packed six
/// floats at a time (minX, minY, minZ, maxX, maxY, maxZ).
///
/// The broad phase for [BasicSimulation]'s scene queries. Without it every
/// query runs the exact shape test against every collider, which since the
/// mesh and height field tests became exact is the difference between one
/// hierarchy descent and a full sweep of the world.
///
/// Leaves reference the caller's array by index, so the hierarchy owns no
/// collider state. [refit] recomputes the boxes without touching the
/// topology, which is what makes it usable against bodies whose owner can
/// move them at any time: rebuilding sorts, refitting does not.
class AabbBvh {
  AabbBvh._(this._bounds, this._children, this._order, this._nodeCount);

  // The caller's packed boxes, refreshed by every [refit]. Held so a leaf can
  // test its own boxes rather than reporting the whole leaf as candidates.
  Float32List _boxes = Float32List(0);

  /// Builds a hierarchy over the first [count] boxes of [boxes].
  factory AabbBvh.build(Float32List boxes, int count) {
    if (count == 0) {
      return AabbBvh._(Float32List(0), Int32List(0), Int32List(0), 0);
    }

    // Quantize each box centroid into a 30-bit Morton key, then radix-sort
    // the box indices by it in three 10-bit passes: O(n) per pass, no
    // comparison sort, no per-level sorting during the split.
    var minCx = double.infinity,
        minCy = double.infinity,
        minCz = double.infinity;
    var maxCx = -double.infinity,
        maxCy = -double.infinity,
        maxCz = -double.infinity;
    final centroids = Float32List(count * 3);
    for (var i = 0; i < count; i++) {
      final o = i * 6;
      final cx = (boxes[o] + boxes[o + 3]) * 0.5;
      final cy = (boxes[o + 1] + boxes[o + 4]) * 0.5;
      final cz = (boxes[o + 2] + boxes[o + 5]) * 0.5;
      centroids[i * 3] = cx;
      centroids[i * 3 + 1] = cy;
      centroids[i * 3 + 2] = cz;
      if (cx < minCx) minCx = cx;
      if (cy < minCy) minCy = cy;
      if (cz < minCz) minCz = cz;
      if (cx > maxCx) maxCx = cx;
      if (cy > maxCy) maxCy = cy;
      if (cz > maxCz) maxCz = cz;
    }
    final spanX = maxCx - minCx, spanY = maxCy - minCy, spanZ = maxCz - minCz;
    final scaleX = spanX > 0 ? 1023.0 / spanX : 0.0;
    final scaleY = spanY > 0 ? 1023.0 / spanY : 0.0;
    final scaleZ = spanZ > 0 ? 1023.0 / spanZ : 0.0;
    final keys = Uint32List(count);
    for (var i = 0; i < count; i++) {
      keys[i] =
          _spreadBits(((centroids[i * 3] - minCx) * scaleX).toInt()) |
          (_spreadBits(((centroids[i * 3 + 1] - minCy) * scaleY).toInt()) <<
              1) |
          (_spreadBits(((centroids[i * 3 + 2] - minCz) * scaleZ).toInt()) << 2);
    }
    var order = Int32List(count);
    var scratch = Int32List(count);
    for (var i = 0; i < count; i++) {
      order[i] = i;
    }
    final histogram = Int32List(1024);
    for (var shift = 0; shift < 30; shift += 10) {
      histogram.fillRange(0, 1024, 0);
      for (var i = 0; i < count; i++) {
        histogram[(keys[order[i]] >> shift) & 1023]++;
      }
      var sum = 0;
      for (var bucket = 0; bucket < 1024; bucket++) {
        final n = histogram[bucket];
        histogram[bucket] = sum;
        sum += n;
      }
      for (var i = 0; i < count; i++) {
        final index = order[i];
        scratch[histogram[(keys[index] >> shift) & 1023]++] = index;
      }
      final swap = order;
      order = scratch;
      scratch = swap;
    }

    // Emit nodes over the sorted order, splitting each range at the median.
    // A parent reserves its slot before recursing, so the root is node 0 and
    // parents precede their children, which is the order [refit] needs to
    // walk backwards. Median splitting bottoms out at two boxes per leaf, so
    // the node count cannot exceed count.
    final nodeCap = count + 2;
    final bounds = Float32List(nodeCap * 6);
    final children = Int32List(nodeCap * 2);
    var nodeCount = 0;

    int emit(int lo, int hi) {
      final node = nodeCount++;
      if (hi - lo <= _leafSize) {
        children[node * 2] = ~lo;
        children[node * 2 + 1] = hi - lo;
        return node;
      }
      final mid = (lo + hi) >> 1;
      children[node * 2] = emit(lo, mid);
      children[node * 2 + 1] = emit(mid, hi);
      return node;
    }

    emit(0, count);
    final bvh = AabbBvh._(
      Float32List.fromList(bounds.sublist(0, nodeCount * 6)),
      Int32List.fromList(children.sublist(0, nodeCount * 2)),
      Int32List.fromList(order.sublist(0, count)),
      nodeCount,
    );
    bvh.refit(boxes);
    return bvh;
  }

  // Node i owns bounds[i*6..i*6+6). children[i*2] is the left child for an
  // interior node, or ~firstSlot for a leaf, in which case children[i*2+1] is
  // the box count. Slots index [_order], which maps to the caller's boxes.
  final Float32List _bounds;
  final Int32List _children;
  final Int32List _order;
  final int _nodeCount;

  final Int32List _stack = Int32List(64);

  /// How many boxes this hierarchy was built over; a caller whose count has
  /// changed needs a rebuild rather than a [refit].
  int get boxCount => _order.length;

  /// Recomputes every node's box from [boxes] without changing the topology.
  ///
  /// O(n), no sort and no allocation. Valid as long as the box count is
  /// unchanged; tree quality degrades as boxes drift from the grouping they
  /// were built with, which for a rebuild-on-change broad phase means it
  /// degrades only across a single frame's movement.
  void refit(Float32List boxes) {
    _boxes = boxes;
    final bounds = _bounds;
    final children = _children;
    final order = _order;
    // Parents precede children, so one backward pass refreshes everything.
    for (var node = _nodeCount - 1; node >= 0; node--) {
      final o = node * 6;
      final left = children[node * 2];
      if (left < 0) {
        var minX = double.infinity,
            minY = double.infinity,
            minZ = double.infinity;
        var maxX = -double.infinity,
            maxY = -double.infinity,
            maxZ = -double.infinity;
        final first = ~left;
        final end = first + children[node * 2 + 1];
        for (var slot = first; slot < end; slot++) {
          final b = order[slot] * 6;
          if (boxes[b] < minX) minX = boxes[b];
          if (boxes[b + 1] < minY) minY = boxes[b + 1];
          if (boxes[b + 2] < minZ) minZ = boxes[b + 2];
          if (boxes[b + 3] > maxX) maxX = boxes[b + 3];
          if (boxes[b + 4] > maxY) maxY = boxes[b + 4];
          if (boxes[b + 5] > maxZ) maxZ = boxes[b + 5];
        }
        bounds[o] = minX;
        bounds[o + 1] = minY;
        bounds[o + 2] = minZ;
        bounds[o + 3] = maxX;
        bounds[o + 4] = maxY;
        bounds[o + 5] = maxZ;
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

  /// Calls [visit] with the caller-array index of every box the ray at
  /// ([ox], [oy], [oz]) along ([dx], [dy], [dz]) crosses within
  /// [maxDistance].
  ///
  /// The direction should be unit length. Boxes arrive in no particular
  /// order, and each is tested individually rather than reported because its
  /// leaf was reached, so the caller's own (much more expensive) shape test
  /// runs only on boxes the ray really passes through.
  void queryRay(
    double ox,
    double oy,
    double oz,
    double dx,
    double dy,
    double dz,
    double maxDistance,
    void Function(int index) visit,
  ) {
    if (_nodeCount == 0) return;
    final invX = 1.0 / dx, invY = 1.0 / dy, invZ = 1.0 / dz;
    final bounds = _bounds;
    final children = _children;
    final order = _order;
    final boxes = _boxes;
    final stack = _stack;
    var top = 0;
    stack[top++] = 0;
    while (top > 0) {
      final node = stack[--top];
      if (!_raySlab(
        bounds,
        node * 6,
        ox,
        oy,
        oz,
        invX,
        invY,
        invZ,
        maxDistance,
      )) {
        continue;
      }
      final left = children[node * 2];
      if (left < 0) {
        final first = ~left;
        final end = first + children[node * 2 + 1];
        for (var slot = first; slot < end; slot++) {
          final index = order[slot];
          if (_raySlab(
            boxes,
            index * 6,
            ox,
            oy,
            oz,
            invX,
            invY,
            invZ,
            maxDistance,
          )) {
            visit(index);
          }
        }
        continue;
      }
      stack[top++] = left;
      stack[top++] = children[node * 2 + 1];
    }
  }

  /// Calls [visit] with the caller-array index of every box overlapping the
  /// AABB (`min`, `max`). Exact: a leaf's boxes are each tested, not reported
  /// wholesale.
  void queryAabb(
    double minX,
    double minY,
    double minZ,
    double maxX,
    double maxY,
    double maxZ,
    void Function(int index) visit,
  ) {
    if (_nodeCount == 0) return;
    final bounds = _bounds;
    final children = _children;
    final order = _order;
    final boxes = _boxes;
    final stack = _stack;
    var top = 0;
    stack[top++] = 0;
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
        final first = ~left;
        final end = first + children[node * 2 + 1];
        for (var slot = first; slot < end; slot++) {
          final index = order[slot];
          final b = index * 6;
          if (boxes[b] > maxX ||
              boxes[b + 1] > maxY ||
              boxes[b + 2] > maxZ ||
              boxes[b + 3] < minX ||
              boxes[b + 4] < minY ||
              boxes[b + 5] < minZ) {
            continue;
          }
          visit(index);
        }
        continue;
      }
      stack[top++] = left;
      stack[top++] = children[node * 2 + 1];
    }
  }

  /// Whether the ray reaches the box at [offset] within [limit].
  ///
  /// An infinite reciprocal marks an axis the ray runs parallel to. That axis
  /// then constrains nothing and only has to contain the origin, which is the
  /// case a finite formulation gets wrong: a ray lying exactly in a box's face
  /// plane produces a zero-width interval on that axis and drops the box it is
  /// touching.
  static bool _raySlab(
    Float32List bounds,
    int offset,
    double ox,
    double oy,
    double oz,
    double invX,
    double invY,
    double invZ,
    double limit,
  ) {
    // Seeded with the ray's own span, so "behind the origin" and "past the
    // limit" fall out of the same interval intersection as the slabs.
    var tMin = 0.0;
    var tMax = limit;

    if (invX.isInfinite) {
      if (ox < bounds[offset] || ox > bounds[offset + 3]) return false;
    } else {
      final t0 = (bounds[offset] - ox) * invX;
      final t1 = (bounds[offset + 3] - ox) * invX;
      final lo = t0 < t1 ? t0 : t1;
      final hi = t0 < t1 ? t1 : t0;
      if (lo > tMin) tMin = lo;
      if (hi < tMax) tMax = hi;
    }

    if (invY.isInfinite) {
      if (oy < bounds[offset + 1] || oy > bounds[offset + 4]) return false;
    } else {
      final t0 = (bounds[offset + 1] - oy) * invY;
      final t1 = (bounds[offset + 4] - oy) * invY;
      final lo = t0 < t1 ? t0 : t1;
      final hi = t0 < t1 ? t1 : t0;
      if (lo > tMin) tMin = lo;
      if (hi < tMax) tMax = hi;
    }

    if (invZ.isInfinite) {
      if (oz < bounds[offset + 2] || oz > bounds[offset + 5]) return false;
    } else {
      final t0 = (bounds[offset + 2] - oz) * invZ;
      final t1 = (bounds[offset + 5] - oz) * invZ;
      final lo = t0 < t1 ? t0 : t1;
      final hi = t0 < t1 ? t1 : t0;
      if (lo > tMin) tMin = lo;
      if (hi < tMax) tMax = hi;
    }

    return tMin <= tMax;
  }

  // Spreads the low 10 bits of [value] so consecutive bits land three apart
  // (Morton interleave).
  static int _spreadBits(int value) {
    var x = value & 0x3ff;
    x = (x | (x << 16)) & 0x030000ff;
    x = (x | (x << 8)) & 0x0300f00f;
    x = (x | (x << 4)) & 0x030c30c3;
    x = (x | (x << 2)) & 0x09249249;
    return x;
  }
}

