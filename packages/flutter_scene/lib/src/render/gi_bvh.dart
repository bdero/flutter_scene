import 'dart:math' as math;
import 'dart:typed_data';

/// A bounding volume hierarchy over world-space triangles, flattened into the
/// threaded layout the GI trace walks without a stack.
///
/// Nodes are stored in depth-first preorder, so a hit inner node continues to
/// the next node (its first child) and anything else jumps to its miss link,
/// the first node after its subtree. Each node is 8 floats:
/// `min.xyz, miss, max.xyz, leaf`, where `miss` is -1 past the last subtree
/// and `leaf` is -1 for an inner node or `first * 8 + count` for a leaf over
/// [triangles] `[first, first + count)`.
///
/// Each triangle is 12 floats, `v0.xyz, material, e1.xyz, 0, e2.xyz, 0`, with
/// the edges from `v0`, which is what the intersection test reads.
class GiBvh {
  GiBvh._(this.nodes, this.triangles, this.nodeCount, this.triangleCount);

  /// Floats per node.
  static const int nodeStride = 8;

  /// Floats per triangle.
  static const int triangleStride = 12;

  /// The most triangles one leaf holds. The leaf encoding allows up to 7.
  static const int maxLeafTriangles = 4;

  final Float32List nodes;
  final Float32List triangles;
  final int nodeCount;
  final int triangleCount;

  /// Builds over [positions], 9 floats (three corners) per triangle, with
  /// [materials] holding each triangle's material index.
  ///
  /// Splits by binned surface area heuristic on the longest centroid axis,
  /// falling back to the median when every centroid shares a bin.
  factory GiBvh.build(Float32List positions, List<int> materials) {
    final count = positions.length ~/ 9;
    assert(materials.length >= count);
    final centroids = Float32List(count * 3);
    final boxes = Float32List(count * 6);
    for (var t = 0; t < count; t++) {
      for (var axis = 0; axis < 3; axis++) {
        final a = positions[t * 9 + axis];
        final b = positions[t * 9 + 3 + axis];
        final c = positions[t * 9 + 6 + axis];
        centroids[t * 3 + axis] = (a + b + c) / 3.0;
        boxes[t * 6 + axis] = math.min(a, math.min(b, c));
        boxes[t * 6 + 3 + axis] = math.max(a, math.max(b, c));
      }
    }
    final order = Int32List.fromList(List<int>.generate(count, (i) => i));
    final builder = _Builder(centroids, boxes, order);
    if (count > 0) builder.split(0, count);

    final nodeCount = builder.nodes.length ~/ nodeStride;
    final nodes = Float32List.fromList(builder.nodes);
    // A subtree's preorder span ends where its miss link points.
    for (var n = 0; n < nodeCount; n++) {
      final end = builder.subtreeEnds[n];
      nodes[n * nodeStride + 3] = end >= nodeCount ? -1.0 : end.toDouble();
    }

    final triangles = Float32List(count * triangleStride);
    for (var i = 0; i < count; i++) {
      final t = order[i];
      final base = t * 9;
      final out = i * triangleStride;
      for (var axis = 0; axis < 3; axis++) {
        final v0 = positions[base + axis];
        triangles[out + axis] = v0;
        triangles[out + 4 + axis] = positions[base + 3 + axis] - v0;
        triangles[out + 8 + axis] = positions[base + 6 + axis] - v0;
      }
      triangles[out + 3] = materials[t].toDouble();
    }
    return GiBvh._(nodes, triangles, nodeCount, count);
  }
}

class _Builder {
  _Builder(this.centroids, this.boxes, this.order);

  final Float32List centroids;
  final Float32List boxes;
  final Int32List order;
  final List<double> nodes = [];
  final List<int> subtreeEnds = [];

  static const int _bins = 12;

  void split(int start, int end) {
    final node = nodes.length ~/ GiBvh.nodeStride;
    final bounds = _bounds(start, end);
    nodes.addAll([
      bounds[0], bounds[1], bounds[2], 0.0, //
      bounds[3], bounds[4], bounds[5], -1.0,
    ]);
    subtreeEnds.add(0);

    final count = end - start;
    final mid = count <= GiBvh.maxLeafTriangles ? -1 : _partition(start, end);
    if (mid < 0) {
      nodes[node * GiBvh.nodeStride + 7] = (start * 8 + count).toDouble();
      subtreeEnds[node] = node + 1;
      return;
    }
    split(start, mid);
    split(mid, end);
    subtreeEnds[node] = nodes.length ~/ GiBvh.nodeStride;
  }

  // Reorders [start, end) around a split and returns the split index, or -1
  // to make a leaf.
  int _partition(int start, int end) {
    var lo = [double.infinity, double.infinity, double.infinity];
    var hi = [
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
      return count > GiBvh.maxLeafTriangles ? start + count ~/ 2 : -1;
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
