/// A bounding volume hierarchy over the triangles of a single mesh primitive.
library;

import 'dart:typed_data';

/// Triangles per leaf. Small enough that a leaf test stays cheap, large
/// enough that the tree stays shallow and the per-leaf callback amortizes
/// over several Moller-Trumbore tests.
const int _leafSize = 8;

/// A bounding volume hierarchy over one primitive's triangles, used to
/// answer scene raycasts without touching every triangle.
///
/// Built lazily the first time a dense mesh is raycast and then cached on the
/// geometry, so the build cost is paid once per mesh rather than per query.
/// Nodes live in flat typed-data arrays rather than a pointer tree, and the
/// build sorts triangle centroids along a Morton curve with a radix sort and
/// splits each range at the median: O(n) per level with no per-level sort,
/// and children allocated before their parent.
///
/// [raycast] descends nearest-child-first and re-tests each box against the
/// caller's running best distance, so a nearest-hit query on a dense mesh
/// visits O(log n) boxes and a handful of triangles instead of the whole
/// index buffer.
///
/// Engine-internal; see `raycast.dart`.
class TriangleBvh {
  TriangleBvh._(
    this._bounds,
    this._children,
    this.triVerts,
    this.triOrder,
    this._nodeCount,
  );

  /// The triangle count below which a hierarchy is not worth building: a
  /// brute-force sweep over the same arrays beats build plus traversal, and
  /// the node arrays would cost more memory than they save time.
  static const int minTriangles = 256;

  /// Builds a hierarchy over the triangles described by [triVerts] (three
  /// vertex indices per triangle) and [positions] (three floats per vertex).
  ///
  /// Neither input is retained: the triangles are permuted into hierarchy
  /// order and exposed as [triVerts] and [triOrder], so a leaf's slot range
  /// is contiguous in both and the hot loop reads them without indirection.
  factory TriangleBvh.build(Float32List positions, Uint32List sourceTriVerts) {
    final n = sourceTriVerts.length ~/ 3;
    assert(n > 0);

    // Per-triangle AABB and centroid, computed once so neither the sort nor
    // the node build has to re-read the position stream.
    final triBounds = Float32List(n * 6);
    var minCx = double.infinity, minCy = double.infinity, minCz = double.infinity;
    var maxCx = -double.infinity, maxCy = -double.infinity, maxCz = -double.infinity;
    final centroids = Float32List(n * 3);
    for (var t = 0; t < n; t++) {
      final a = sourceTriVerts[t * 3] * 3;
      final b = sourceTriVerts[t * 3 + 1] * 3;
      final c = sourceTriVerts[t * 3 + 2] * 3;
      final o = t * 6;
      for (var axis = 0; axis < 3; axis++) {
        final va = positions[a + axis];
        final vb = positions[b + axis];
        final vc = positions[c + axis];
        var lo = va, hi = va;
        if (vb < lo) lo = vb;
        if (vb > hi) hi = vb;
        if (vc < lo) lo = vc;
        if (vc > hi) hi = vc;
        triBounds[o + axis] = lo;
        triBounds[o + 3 + axis] = hi;
        centroids[t * 3 + axis] = (lo + hi) * 0.5;
      }
      final cx = centroids[t * 3];
      final cy = centroids[t * 3 + 1];
      final cz = centroids[t * 3 + 2];
      if (cx < minCx) minCx = cx;
      if (cy < minCy) minCy = cy;
      if (cz < minCz) minCz = cz;
      if (cx > maxCx) maxCx = cx;
      if (cy > maxCy) maxCy = cy;
      if (cz > maxCz) maxCz = cz;
    }

    // Quantize each centroid into a 30-bit Morton key.
    final spanX = maxCx - minCx, spanY = maxCy - minCy, spanZ = maxCz - minCz;
    final scaleX = spanX > 0 ? 1023.0 / spanX : 0.0;
    final scaleY = spanY > 0 ? 1023.0 / spanY : 0.0;
    final scaleZ = spanZ > 0 ? 1023.0 / spanZ : 0.0;
    final keys = Uint32List(n);
    for (var t = 0; t < n; t++) {
      final qx = ((centroids[t * 3] - minCx) * scaleX).toInt();
      final qy = ((centroids[t * 3 + 1] - minCy) * scaleY).toInt();
      final qz = ((centroids[t * 3 + 2] - minCz) * scaleZ).toInt();
      keys[t] = _spreadBits(qx) | (_spreadBits(qy) << 1) | (_spreadBits(qz) << 2);
    }

    // Radix-sort triangle indices by Morton key, three 10-bit passes.
    var order = Uint32List(n);
    var scratch = Uint32List(n);
    for (var t = 0; t < n; t++) {
      order[t] = t;
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

    // Materialize the permuted triangle streams, so a leaf range is one
    // contiguous run in both.
    final triVerts = Uint32List(n * 3);
    final triOrder = Uint32List(n);
    for (var slot = 0; slot < n; slot++) {
      final t = order[slot];
      triOrder[slot] = t;
      triVerts[slot * 3] = sourceTriVerts[t * 3];
      triVerts[slot * 3 + 1] = sourceTriVerts[t * 3 + 1];
      triVerts[slot * 3 + 2] = sourceTriVerts[t * 3 + 2];
    }

    // Emit nodes over the sorted order, splitting ranges at the median.
    // Post-order allocation, so both children of a node precede it. Median
    // splitting stops at [_leafSize], which bottoms out at four triangles per
    // leaf, so the node count cannot exceed n / 2.
    final nodeCap = (n ~/ 2) + 2;
    final bounds = Float32List(nodeCap * 6);
    final children = Int32List(nodeCap * 2);
    var nodeCount = 0;

    int emit(int lo, int hi) {
      final node = nodeCount++;
      final o = node * 6;
      if (hi - lo <= _leafSize) {
        var bMinX = double.infinity, bMinY = double.infinity, bMinZ = double.infinity;
        var bMaxX = -double.infinity, bMaxY = -double.infinity, bMaxZ = -double.infinity;
        for (var slot = lo; slot < hi; slot++) {
          final t = order[slot] * 6;
          if (triBounds[t] < bMinX) bMinX = triBounds[t];
          if (triBounds[t + 1] < bMinY) bMinY = triBounds[t + 1];
          if (triBounds[t + 2] < bMinZ) bMinZ = triBounds[t + 2];
          if (triBounds[t + 3] > bMaxX) bMaxX = triBounds[t + 3];
          if (triBounds[t + 4] > bMaxY) bMaxY = triBounds[t + 4];
          if (triBounds[t + 5] > bMaxZ) bMaxZ = triBounds[t + 5];
        }
        bounds[o] = bMinX;
        bounds[o + 1] = bMinY;
        bounds[o + 2] = bMinZ;
        bounds[o + 3] = bMaxX;
        bounds[o + 4] = bMaxY;
        bounds[o + 5] = bMaxZ;
        // A leaf stores its slot range: ~first, then the count.
        children[node * 2] = ~lo;
        children[node * 2 + 1] = hi - lo;
        return node;
      }
      // Reserve this node's slot before recursing so the parent index is
      // stable, then fill it from the children's boxes.
      final mid = (lo + hi) >> 1;
      final left = emit(lo, mid);
      final right = emit(mid, hi);
      final l = left * 6, r = right * 6;
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
    return TriangleBvh._(
      // Trim the slack off the capacity estimate; this array outlives the
      // build as part of the cached hierarchy.
      nodeCount * 6 == bounds.length
          ? bounds
          : Float32List.fromList(bounds.sublist(0, nodeCount * 6)),
      nodeCount * 2 == children.length
          ? children
          : Int32List.fromList(children.sublist(0, nodeCount * 2)),
      triVerts,
      triOrder,
      nodeCount,
    );
  }

  /// Triangle vertex indices in hierarchy order, three per triangle. A leaf's
  /// slot range indexes straight into this.
  final Uint32List triVerts;

  /// Maps a hierarchy slot back to the triangle's index in the source index
  /// stream, which is what a hit reports.
  final Uint32List triOrder;

  // Node i owns bounds[i*6..i*6+6) as (minX, minY, minZ, maxX, maxY, maxZ).
  // children[i*2] is the left child index for an interior node, or ~firstSlot
  // for a leaf, in which case children[i*2+1] is the triangle count. Unlike
  // the render-scene BVH the root is node 0, since a parent reserves its slot
  // before recursing.
  final Float32List _bounds;
  final Int32List _children;
  final int _nodeCount;

  // Traversal stack. Node index and the box's entry distance are interleaved
  // so a popped entry can be discarded outright once the running limit has
  // dropped below it. Deep enough for any triangle count a CPU raycast is
  // sane on; queries are single-threaded and never nest.
  final Int32List _stack = Int32List(64);
  final Float64List _stackEntry = Float64List(64);

  /// Walks the hierarchy along the ray, calling [testRange] once for every
  /// leaf the ray's segment enters, nearest leaf first.
  ///
  /// [testRange] tests the leaf's triangles and returns the distance to
  /// prune the rest of the walk by: its own running best for a nearest-hit
  /// query, or the unchanged `limit` for a collect-everything query, in which
  /// case the walk simply visits every leaf the ray touches.
  ///
  /// [dx], [dy], [dz] are the ray direction in the same space as the
  /// positions the hierarchy was built from; it need not be unit length, and
  /// distances are in units of that direction.
  void raycast(
    double ox,
    double oy,
    double oz,
    double dx,
    double dy,
    double dz,
    double maxDistance,
    double Function(int firstSlot, int endSlot, double limit) testRange,
  ) {
    if (_nodeCount == 0) return;
    // Reciprocals once, so the slab test is three multiplies per axis. A zero
    // component becomes a large finite value rather than an infinity: an
    // axis-parallel ray whose origin sits exactly on a slab plane would
    // otherwise compute 0 * infinity and reject the box it is lying on.
    final invX = 1.0 / dx, invY = 1.0 / dy, invZ = 1.0 / dz;
    final bounds = _bounds;
    final children = _children;
    final stack = _stack;
    final stackEntry = _stackEntry;
    var limit = maxDistance;

    var top = 0;
    stack[top] = 0;
    stackEntry[top] = 0.0;
    top++;

    while (top > 0) {
      top--;
      // The limit may have dropped below this box since it was pushed.
      if (stackEntry[top] >= limit) continue;
      final node = stack[top];

      final left = children[node * 2];
      if (left < 0) {
        limit = testRange(~left, ~left + children[node * 2 + 1], limit);
        continue;
      }

      final right = children[node * 2 + 1];
      final tLeft = _slab(bounds, left * 6, ox, oy, oz, invX, invY, invZ, limit);
      final tRight = _slab(bounds, right * 6, ox, oy, oz, invX, invY, invZ, limit);
      if (tLeft < 0) {
        if (tRight >= 0) {
          stack[top] = right;
          stackEntry[top] = tRight;
          top++;
        }
        continue;
      }
      if (tRight < 0) {
        stack[top] = left;
        stackEntry[top] = tLeft;
        top++;
        continue;
      }
      // Push the farther child first so the nearer one pops next: hits found
      // there shrink the limit before the farther subtree is ever entered.
      final farNode = tLeft <= tRight ? right : left;
      final nearNode = tLeft <= tRight ? left : right;
      final farT = tLeft <= tRight ? tRight : tLeft;
      final nearT = tLeft <= tRight ? tLeft : tRight;
      stack[top] = farNode;
      stackEntry[top] = farT;
      top++;
      stack[top] = nearNode;
      stackEntry[top] = nearT;
      top++;
    }
  }

  /// Distance at which the ray enters the box at [offset], or -1 when it
  /// never does within [limit].
  ///
  /// An infinite reciprocal marks an axis the ray runs parallel to. That axis
  /// then constrains nothing and only has to contain the origin, which is the
  /// case a finite formulation gets wrong: a ray lying exactly in a box's face
  /// plane produces a zero-width interval on that axis and drops the box it is
  /// touching.
  static double _slab(
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
      if (ox < bounds[offset] || ox > bounds[offset + 3]) return -1.0;
    } else {
      final t0 = (bounds[offset] - ox) * invX;
      final t1 = (bounds[offset + 3] - ox) * invX;
      final lo = t0 < t1 ? t0 : t1;
      final hi = t0 < t1 ? t1 : t0;
      if (lo > tMin) tMin = lo;
      if (hi < tMax) tMax = hi;
    }

    if (invY.isInfinite) {
      if (oy < bounds[offset + 1] || oy > bounds[offset + 4]) return -1.0;
    } else {
      final t0 = (bounds[offset + 1] - oy) * invY;
      final t1 = (bounds[offset + 4] - oy) * invY;
      final lo = t0 < t1 ? t0 : t1;
      final hi = t0 < t1 ? t1 : t0;
      if (lo > tMin) tMin = lo;
      if (hi < tMax) tMax = hi;
    }

    if (invZ.isInfinite) {
      if (oz < bounds[offset + 2] || oz > bounds[offset + 5]) return -1.0;
    } else {
      final t0 = (bounds[offset + 2] - oz) * invZ;
      final t1 = (bounds[offset + 5] - oz) * invZ;
      final lo = t0 < t1 ? t0 : t1;
      final hi = t0 < t1 ? t1 : t0;
      if (lo > tMin) tMin = lo;
      if (hi < tMax) tMax = hi;
    }

    return tMin > tMax ? -1.0 : tMin;
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

