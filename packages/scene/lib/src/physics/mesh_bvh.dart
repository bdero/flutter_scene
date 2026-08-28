// A bounding volume hierarchy over a triangle mesh collider.

import 'dart:typed_data';

/// Triangles per leaf. Large enough that the tree stays shallow, small
/// enough that a leaf sweep stays short.
const int _leafSize = 8;

/// The nearest local-space hit [MeshBvh.raycast] found: the distance along
/// the query direction and the triangle's unnormalized geometric normal.
typedef MeshBvhHit = ({double t, double nx, double ny, double nz});

/// A bounding volume hierarchy over the triangles of a [TriMeshShape],
/// cooked once per shape instance and cached by [triMeshBvh].
///
/// Nodes and triangles live in flat typed arrays rather than a pointer tree.
/// The build sorts triangle centroids along a Morton curve with a radix sort
/// and splits ranges at the median, which is O(n) per level with no per-level
/// sort. Triangle vertices are copied into hierarchy order, nine floats at a
/// time, so a leaf sweep is one sequential run with no index indirection.
///
/// [raycast] descends nearest-child-first and prunes each box against the
/// best distance found so far, so a mesh collider costs O(log n) box tests
/// instead of a sweep over every triangle.
class MeshBvh {
  MeshBvh._(this._bounds, this._children, this._tri, this._nodeCount);

  /// Cooks a hierarchy from packed `xyz` [vertices] and triangle [indices].
  factory MeshBvh.build(Float32List vertices, Uint32List indices) {
    final n = indices.length ~/ 3;
    if (n == 0) {
      return MeshBvh._(Float32List(0), Int32List(0), Float32List(0), 0);
    }

    // Per-triangle box and centroid, computed once so neither the sort nor
    // the node build re-reads the vertex stream.
    final triBounds = Float32List(n * 6);
    final centroids = Float32List(n * 3);
    var minCx = double.infinity,
        minCy = double.infinity,
        minCz = double.infinity;
    var maxCx = -double.infinity,
        maxCy = -double.infinity,
        maxCz = -double.infinity;
    for (var t = 0; t < n; t++) {
      final a = indices[t * 3] * 3;
      final b = indices[t * 3 + 1] * 3;
      final c = indices[t * 3 + 2] * 3;
      for (var axis = 0; axis < 3; axis++) {
        final va = vertices[a + axis];
        final vb = vertices[b + axis];
        final vc = vertices[c + axis];
        var lo = va, hi = va;
        if (vb < lo) lo = vb;
        if (vb > hi) hi = vb;
        if (vc < lo) lo = vc;
        if (vc > hi) hi = vc;
        triBounds[t * 6 + axis] = lo;
        triBounds[t * 6 + 3 + axis] = hi;
        centroids[t * 3 + axis] = (lo + hi) * 0.5;
      }
      final cx = centroids[t * 3],
          cy = centroids[t * 3 + 1],
          cz = centroids[t * 3 + 2];
      if (cx < minCx) minCx = cx;
      if (cy < minCy) minCy = cy;
      if (cz < minCz) minCz = cz;
      if (cx > maxCx) maxCx = cx;
      if (cy > maxCy) maxCy = cy;
      if (cz > maxCz) maxCz = cz;
    }

    // Quantize each centroid into a 30-bit Morton key, then radix-sort the
    // triangle indices by it in three 10-bit passes.
    final spanX = maxCx - minCx, spanY = maxCy - minCy, spanZ = maxCz - minCz;
    final scaleX = spanX > 0 ? 1023.0 / spanX : 0.0;
    final scaleY = spanY > 0 ? 1023.0 / spanY : 0.0;
    final scaleZ = spanZ > 0 ? 1023.0 / spanZ : 0.0;
    final keys = Uint32List(n);
    for (var t = 0; t < n; t++) {
      keys[t] =
          _spreadBits(((centroids[t * 3] - minCx) * scaleX).toInt()) |
          (_spreadBits(((centroids[t * 3 + 1] - minCy) * scaleY).toInt()) <<
              1) |
          (_spreadBits(((centroids[t * 3 + 2] - minCz) * scaleZ).toInt()) << 2);
    }
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

    // Materialize triangle vertices in hierarchy order: a leaf sweep then
    // reads one contiguous run rather than chasing the index buffer.
    final tri = Float32List(n * 9);
    for (var slot = 0; slot < n; slot++) {
      final t = order[slot];
      for (var corner = 0; corner < 3; corner++) {
        final v = indices[t * 3 + corner] * 3;
        tri[slot * 9 + corner * 3] = vertices[v];
        tri[slot * 9 + corner * 3 + 1] = vertices[v + 1];
        tri[slot * 9 + corner * 3 + 2] = vertices[v + 2];
      }
    }

    // Emit nodes over the sorted order, splitting at the median. A parent
    // reserves its slot before recursing, so the root is node 0. Median
    // splitting bottoms out at four triangles per leaf, so the node count
    // cannot exceed n / 2.
    final nodeCap = (n ~/ 2) + 2;
    final bounds = Float32List(nodeCap * 6);
    final children = Int32List(nodeCap * 2);
    var nodeCount = 0;

    int emit(int lo, int hi) {
      final node = nodeCount++;
      final o = node * 6;
      if (hi - lo <= _leafSize) {
        var bMinX = double.infinity,
            bMinY = double.infinity,
            bMinZ = double.infinity;
        var bMaxX = -double.infinity,
            bMaxY = -double.infinity,
            bMaxZ = -double.infinity;
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
        children[node * 2] = ~lo;
        children[node * 2 + 1] = hi - lo;
        return node;
      }
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
    return MeshBvh._(
      Float32List.fromList(bounds.sublist(0, nodeCount * 6)),
      Int32List.fromList(children.sublist(0, nodeCount * 2)),
      tri,
      nodeCount,
    );
  }

  // Node i owns bounds[i*6..i*6+6) as (minX, minY, minZ, maxX, maxY, maxZ).
  // children[i*2] is the left child for an interior node, or ~firstSlot for a
  // leaf, in which case children[i*2+1] is the triangle count.
  final Float32List _bounds;
  final Int32List _children;
  final Float32List _tri;
  final int _nodeCount;

  // Traversal stack: node index plus the box's entry distance, so a popped
  // entry can be dropped outright once the running best has passed it.
  final Int32List _stack = Int32List(64);
  final Float64List _stackEntry = Float64List(64);

  /// The nearest hit of the local-space ray at ([ox], [oy], [oz]) along
  /// ([dx], [dy], [dz]) within [maxDistance], or null.
  ///
  /// The direction need not be unit length; the returned distance is in
  /// units of it. Both faces hit, matching the other shape tests.
  MeshBvhHit? raycast(
    double ox,
    double oy,
    double oz,
    double dx,
    double dy,
    double dz,
    double maxDistance,
  ) {
    if (_nodeCount == 0) return null;
    // Reciprocals once. A zero component becomes a large finite value rather
    // than an infinity, so an axis-parallel ray whose origin sits exactly on
    // a slab plane does not compute 0 * infinity and reject the box it lies
    // on.
    final invX = 1.0 / dx, invY = 1.0 / dy, invZ = 1.0 / dz;
    final bounds = _bounds;
    final children = _children;
    final tri = _tri;
    final stack = _stack;
    final stackEntry = _stackEntry;

    var best = maxDistance;
    var hitNx = 0.0, hitNy = 0.0, hitNz = 0.0;
    var found = false;

    var top = 0;
    stack[top] = 0;
    stackEntry[top] = 0.0;
    top++;

    while (top > 0) {
      top--;
      if (stackEntry[top] >= best) continue;
      final node = stack[top];
      final left = children[node * 2];

      if (left < 0) {
        final first = ~left;
        final end = first + children[node * 2 + 1];
        for (var slot = first; slot < end; slot++) {
          final o = slot * 9;
          final ax = tri[o], ay = tri[o + 1], az = tri[o + 2];
          final e1x = tri[o + 3] - ax;
          final e1y = tri[o + 4] - ay;
          final e1z = tri[o + 5] - az;
          final e2x = tri[o + 6] - ax;
          final e2y = tri[o + 7] - ay;
          final e2z = tri[o + 8] - az;

          // Moller-Trumbore, scalar and allocation free.
          final px = dy * e2z - dz * e2y;
          final py = dz * e2x - dx * e2z;
          final pz = dx * e2y - dy * e2x;
          final det = e1x * px + e1y * py + e1z * pz;
          if (det.abs() < 1e-12) continue;
          final invDet = 1.0 / det;
          final tx = ox - ax, ty = oy - ay, tz = oz - az;
          final u = (tx * px + ty * py + tz * pz) * invDet;
          if (u < 0.0 || u > 1.0) continue;
          final qx = ty * e1z - tz * e1y;
          final qy = tz * e1x - tx * e1z;
          final qz = tx * e1y - ty * e1x;
          final v = (dx * qx + dy * qy + dz * qz) * invDet;
          if (v < 0.0 || u + v > 1.0) continue;
          final t = (e2x * qx + e2y * qy + e2z * qz) * invDet;
          if (t < 0.0 || t > best) continue;
          best = t;
          found = true;
          hitNx = e1y * e2z - e1z * e2y;
          hitNy = e1z * e2x - e1x * e2z;
          hitNz = e1x * e2y - e1y * e2x;
        }
        continue;
      }

      final right = children[node * 2 + 1];
      final tLeft = _slab(bounds, left * 6, ox, oy, oz, invX, invY, invZ, best);
      final tRight = _slab(
        bounds,
        right * 6,
        ox,
        oy,
        oz,
        invX,
        invY,
        invZ,
        best,
      );
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
      // Push the farther child first so the nearer one pops next and its
      // hits shrink the limit before the farther subtree is entered.
      final nearFirst = tLeft <= tRight;
      stack[top] = nearFirst ? right : left;
      stackEntry[top] = nearFirst ? tRight : tLeft;
      top++;
      stack[top] = nearFirst ? left : right;
      stackEntry[top] = nearFirst ? tLeft : tRight;
      top++;
    }

    if (!found) return null;
    return (t: best, nx: hitNx, ny: hitNy, nz: hitNz);
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

