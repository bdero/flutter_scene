import 'dart:math' as math;
import 'dart:typed_data';

/// Floats per BVH node: `min.xyz, miss, max.xyz, leaf`.
///
/// Nodes are stored in depth-first preorder, so a hit inner node continues to
/// the next node (its first child) and anything else jumps to its miss link,
/// the first node after its subtree. `miss` is -1 past the last subtree and
/// `leaf` is -1 for an inner node or `first * 8 + count` for a leaf over
/// primitives `[first, first + count)` of the build order. Indices are local
/// to one tree, so trees can be packed into a shared buffer at any offset.
const int kGiBvhNodeStride = 8;

/// The most primitives one leaf holds. The leaf encoding allows up to 7.
const int kGiBvhMaxLeaf = 4;

/// Floats per BLAS triangle:
/// `v0.xyz, uv0.x, e1.xyz, uv0.y, e2.xyz, 0, uv1.xy, uv2.xy`, the edges from
/// `v0` the intersection test reads and the corner texture coordinates the
/// hit's material lookup interpolates.
const int kGiTriangleStride = 16;

/// A BVH over axis-aligned boxes, flattened into the threaded layout the GI
/// trace walks without a stack.
class GiBvhNodes {
  GiBvhNodes._(this.nodes, this.order, this.nodeCount, this.depths);

  /// [kGiBvhNodeStride] floats per node.
  final Float32List nodes;

  /// The input primitive at each leaf position, so leaves address
  /// `order[first]` through `order[first + count - 1]`.
  final Int32List order;

  final int nodeCount;

  /// Each node's depth below the root.
  final Int32List depths;

  /// Builds over [boxes], 6 floats (`min.xyz, max.xyz`) per primitive.
  ///
  /// Splits by binned surface area heuristic on the longest centroid axis,
  /// falling back to the median when every centroid shares a bin.
  factory GiBvhNodes.build(Float32List boxes, {int maxLeaf = kGiBvhMaxLeaf}) {
    assert(maxLeaf >= 1 && maxLeaf <= 7);
    final count = boxes.length ~/ 6;
    final centroids = Float32List(count * 3);
    for (var p = 0; p < count; p++) {
      for (var axis = 0; axis < 3; axis++) {
        centroids[p * 3 + axis] =
            (boxes[p * 6 + axis] + boxes[p * 6 + 3 + axis]) * 0.5;
      }
    }
    final order = Int32List(count);
    for (var i = 0; i < count; i++) {
      order[i] = i;
    }
    final builder = _Builder(centroids, boxes, order, maxLeaf);
    if (count > 0) builder.split(0, count, 0);

    final nodeCount = builder.nodes.length ~/ kGiBvhNodeStride;
    final nodes = Float32List.fromList(builder.nodes);
    // A subtree's preorder span ends where its miss link points.
    for (var n = 0; n < nodeCount; n++) {
      final end = builder.subtreeEnds[n];
      nodes[n * kGiBvhNodeStride + 3] = end >= nodeCount
          ? -1.0
          : end.toDouble();
    }
    return GiBvhNodes._(
      nodes,
      order,
      nodeCount,
      Int32List.fromList(builder.depths),
    );
  }
}

/// The input to [buildGiBlas], sendable to an isolate.
class GiBlasInput {
  const GiBlasInput({required this.positions, this.uvs, this.indices});

  /// Object-space vertex positions, three floats each.
  final Float32List positions;

  /// Texture coordinates, two floats each, or null for all zero.
  final Float32List? uvs;

  /// Triangle list indices, or null for a non-indexed mesh.
  final Int32List? indices;
}

/// A bottom-level BVH over one mesh's triangles in object space.
class GiBlas {
  GiBlas._({
    required this.nodes,
    required this.triangles,
    required this.corners,
    required this.nodeCount,
    required this.triangleCount,
    required this.refitOrder,
    required this.levelStarts,
  });

  /// [kGiBvhNodeStride] floats per node, leaves addressing [triangles].
  final Float32List nodes;

  /// [kGiTriangleStride] floats per triangle, in leaf order.
  final Float32List triangles;

  /// Each triangle's three vertex indices, in leaf order, for rebuilding the
  /// triangles from deformed vertices.
  final Int32List corners;

  final int nodeCount;
  final int triangleCount;

  /// Node indices grouped by depth, deepest group first, so a refit can
  /// update one group per dispatch with every child already current.
  final Int32List refitOrder;

  /// Where each depth group starts in [refitOrder], plus a final entry equal
  /// to its length.
  final Int32List levelStarts;
}

/// Builds the BLAS for [input]. Top level so `compute` can run it on another
/// isolate.
GiBlas buildGiBlas(GiBlasInput input) {
  final positions = input.positions;
  final uvs = input.uvs;
  final indices = input.indices;
  final vertexCount = positions.length ~/ 3;
  final count = (indices?.length ?? vertexCount) ~/ 3;
  int corner(int t, int k) => indices == null ? t * 3 + k : indices[t * 3 + k];

  final boxes = Float32List(count * 6);
  for (var t = 0; t < count; t++) {
    final a = corner(t, 0) * 3;
    final b = corner(t, 1) * 3;
    final c = corner(t, 2) * 3;
    for (var axis = 0; axis < 3; axis++) {
      final x = positions[a + axis];
      final y = positions[b + axis];
      final z = positions[c + axis];
      boxes[t * 6 + axis] = math.min(x, math.min(y, z));
      boxes[t * 6 + 3 + axis] = math.max(x, math.max(y, z));
    }
  }
  final tree = GiBvhNodes.build(boxes);

  final triangles = Float32List(count * kGiTriangleStride);
  final corners = Int32List(count * 3);
  for (var i = 0; i < count; i++) {
    final t = tree.order[i];
    final out = i * kGiTriangleStride;
    final v = [corner(t, 0), corner(t, 1), corner(t, 2)];
    corners
      ..[i * 3] = v[0]
      ..[i * 3 + 1] = v[1]
      ..[i * 3 + 2] = v[2];
    for (var axis = 0; axis < 3; axis++) {
      final v0 = positions[v[0] * 3 + axis];
      triangles[out + axis] = v0;
      triangles[out + 4 + axis] = positions[v[1] * 3 + axis] - v0;
      triangles[out + 8 + axis] = positions[v[2] * 3 + axis] - v0;
    }
    if (uvs != null) {
      triangles
        ..[out + 3] = uvs[v[0] * 2]
        ..[out + 7] = uvs[v[0] * 2 + 1]
        ..[out + 12] = uvs[v[1] * 2]
        ..[out + 13] = uvs[v[1] * 2 + 1]
        ..[out + 14] = uvs[v[2] * 2]
        ..[out + 15] = uvs[v[2] * 2 + 1];
    }
  }

  // Group nodes by depth, deepest first.
  var maxDepth = 0;
  for (final d in tree.depths) {
    maxDepth = math.max(maxDepth, d);
  }
  final levelCounts = Int32List(maxDepth + 1);
  for (final d in tree.depths) {
    levelCounts[d]++;
  }
  final levelStarts = Int32List(maxDepth + 2);
  for (var group = 0; group <= maxDepth; group++) {
    levelStarts[group + 1] = levelStarts[group] + levelCounts[maxDepth - group];
  }
  final fill = Int32List.fromList(levelStarts.sublist(0, maxDepth + 1));
  final refitOrder = Int32List(tree.nodeCount);
  for (var n = 0; n < tree.nodeCount; n++) {
    final group = maxDepth - tree.depths[n];
    refitOrder[fill[group]++] = n;
  }

  return GiBlas._(
    nodes: tree.nodes,
    triangles: triangles,
    corners: corners,
    nodeCount: tree.nodeCount,
    triangleCount: count,
    refitOrder: refitOrder,
    levelStarts: levelStarts,
  );
}

class _Builder {
  _Builder(this.centroids, this.boxes, this.order, this.maxLeaf);

  final Float32List centroids;
  final Float32List boxes;
  final Int32List order;
  final int maxLeaf;
  final List<double> nodes = [];
  final List<int> subtreeEnds = [];
  final List<int> depths = [];

  static const int _bins = 12;

  void split(int start, int end, int depth) {
    final node = nodes.length ~/ kGiBvhNodeStride;
    final bounds = _bounds(start, end);
    nodes.addAll([
      bounds[0], bounds[1], bounds[2], 0.0, //
      bounds[3], bounds[4], bounds[5], -1.0,
    ]);
    subtreeEnds.add(0);
    depths.add(depth);

    final count = end - start;
    final mid = count <= maxLeaf ? -1 : _partition(start, end);
    if (mid < 0) {
      nodes[node * kGiBvhNodeStride + 7] = (start * 8 + count).toDouble();
      subtreeEnds[node] = node + 1;
      return;
    }
    split(start, mid, depth + 1);
    split(mid, end, depth + 1);
    subtreeEnds[node] = nodes.length ~/ kGiBvhNodeStride;
  }

  // Reorders [start, end) around a split and returns the split index, or -1
  // to make a leaf.
  int _partition(int start, int end) {
    final lo = [double.infinity, double.infinity, double.infinity];
    final hi = [
      double.negativeInfinity,
      double.negativeInfinity,
      double.negativeInfinity,
    ];
    for (var i = start; i < end; i++) {
      final t = order[i];
      for (var axis = 0; axis < 3; axis++) {
        final c = centroids[t * 3 + axis];
        lo[axis] = math.min(lo[axis], c);
        hi[axis] = math.max(hi[axis], c);
      }
    }
    var axis = 0;
    for (var a = 1; a < 3; a++) {
      if (hi[a] - lo[a] > hi[axis] - lo[axis]) axis = a;
    }
    final extent = hi[axis] - lo[axis];
    final count = end - start;
    if (extent <= 0) {
      // Every centroid coincides, so only an arbitrary split is left, and a
      // big leaf would blow the encoding.
      return count > maxLeaf ? start + count ~/ 2 : -1;
    }

    // Bin the centroids, then pick the boundary with the lowest SAH cost.
    final binCounts = List<int>.filled(_bins, 0);
    final binBoxes = List<List<double>>.generate(_bins, (_) => _emptyBox());
    int binOf(int t) => math.min(
      _bins - 1,
      ((centroids[t * 3 + axis] - lo[axis]) / extent * _bins).floor(),
    );
    for (var i = start; i < end; i++) {
      final t = order[i];
      final b = binOf(t);
      binCounts[b]++;
      _grow(binBoxes[b], t);
    }
    var bestCost = double.infinity;
    var bestBin = -1;
    for (var split = 1; split < _bins; split++) {
      final left = _emptyBox();
      final right = _emptyBox();
      var leftCount = 0;
      var rightCount = 0;
      for (var b = 0; b < split; b++) {
        _merge(left, binBoxes[b]);
        leftCount += binCounts[b];
      }
      for (var b = split; b < _bins; b++) {
        _merge(right, binBoxes[b]);
        rightCount += binCounts[b];
      }
      if (leftCount == 0 || rightCount == 0) continue;
      final cost = _area(left) * leftCount + _area(right) * rightCount;
      if (cost < bestCost) {
        bestCost = cost;
        bestBin = split;
      }
    }
    if (bestBin < 0) return start + count ~/ 2;

    // Partition in place around the chosen bin boundary.
    var i = start;
    var j = end - 1;
    while (i <= j) {
      if (binOf(order[i]) < bestBin) {
        i++;
      } else {
        final swap = order[i];
        order[i] = order[j];
        order[j] = swap;
        j--;
      }
    }
    if (i == start || i == end) return start + count ~/ 2;
    return i;
  }

  List<double> _bounds(int start, int end) {
    final box = _emptyBox();
    for (var i = start; i < end; i++) {
      _grow(box, order[i]);
    }
    return box;
  }

  static List<double> _emptyBox() => [
    double.infinity, double.infinity, double.infinity, //
    double.negativeInfinity, double.negativeInfinity, double.negativeInfinity,
  ];

  void _grow(List<double> box, int t) {
    for (var axis = 0; axis < 3; axis++) {
      box[axis] = math.min(box[axis], boxes[t * 6 + axis]);
      box[3 + axis] = math.max(box[3 + axis], boxes[t * 6 + 3 + axis]);
    }
  }

  static void _merge(List<double> box, List<double> other) {
    for (var axis = 0; axis < 3; axis++) {
      box[axis] = math.min(box[axis], other[axis]);
      box[3 + axis] = math.max(box[3 + axis], other[3 + axis]);
    }
  }

  static double _area(List<double> box) {
    final x = box[3] - box[0];
    final y = box[4] - box[1];
    final z = box[5] - box[2];
    if (x < 0 || y < 0 || z < 0) return 0;
    return x * y + y * z + z * x;
  }
}
