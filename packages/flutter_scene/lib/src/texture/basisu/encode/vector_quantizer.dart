// A deterministic, weighted, tree-structured vector quantizer: it splits the
// cluster with the largest error along its principal axis until it has
// enough clusters, and keeps the split tree for finding near clusters.

import 'dart:math' as math;
import 'dart:typed_data';

/// The result of [quantize].
class Quantization {
  Quantization._(this.assignments, this.centroids, this.dimension, this._tree);

  /// Cluster index per input vector.
  final Int32List assignments;

  /// Cluster centroids, [dimension] values each.
  final Float64List centroids;
  final int dimension;
  final _SplitTree _tree;

  int get clusterCount => centroids.length ~/ dimension;

  /// Up to [count] clusters near [cluster] in the split tree, itself
  /// included.
  List<int> relatives(int cluster, int count) =>
      _tree.relatives(cluster, (count - 1).bitLength, count);
}

/// Splits [count] vectors of [dimension] values ([vectors], row-major) with
/// [weights] into at most [maxClusters] clusters.
Quantization quantize(
  Float64List vectors,
  Float64List weights,
  int count,
  int dimension,
  int maxClusters,
) {
  final tree = _SplitTree();
  final clusters = <_Cluster>[];
  final all = Int32List(count);
  for (var i = 0; i < count; i++) {
    all[i] = i;
  }
  final root = _Cluster.of(all, vectors, weights, dimension)
    ..node = tree.addLeaf(-1, 0);
  clusters.add(root);

  // Max-heap of splittable clusters by error.
  final heap = <int>[];
  void push(int index) {
    heap.add(index);
    var i = heap.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (!_higher(clusters, heap[i], heap[p])) break;
      final t = heap[p];
      heap[p] = heap[i];
      heap[i] = t;
      i = p;
    }
  }

  int pop() {
    final top = heap.first;
    final last = heap.removeLast();
    if (heap.isNotEmpty) {
      heap[0] = last;
      var i = 0;
      for (;;) {
        final l = i * 2 + 1;
        if (l >= heap.length) break;
        var m = l;
        if (l + 1 < heap.length && _higher(clusters, heap[l + 1], heap[l])) {
          m = l + 1;
        }
        if (!_higher(clusters, heap[m], heap[i])) break;
        final t = heap[m];
        heap[m] = heap[i];
        heap[i] = t;
        i = m;
      }
    }
    return top;
  }

  if (root.error > 0 && root.members.length > 1) push(0);
  while (clusters.length < maxClusters && heap.isNotEmpty) {
    final index = pop();
    final cluster = clusters[index];
    final halves = _split(cluster, vectors, weights, dimension);
    if (halves == null) continue;
    final (a, b) = halves;
    // The first half keeps the index; the second is appended.
    final node = cluster.node;
    a.node = tree.addLeaf(node, index);
    b.node = tree.addLeaf(node, clusters.length);
    tree.makeInner(node);
    clusters[index] = a;
    clusters.add(b);
    if (a.error > 0 && a.members.length > 1) push(index);
    if (b.error > 0 && b.members.length > 1) push(clusters.length - 1);
  }

  final assignments = Int32List(count);
  final centroids = Float64List(clusters.length * dimension);
  for (var c = 0; c < clusters.length; c++) {
    for (final m in clusters[c].members) {
      assignments[m] = c;
    }
    centroids.setRange(
      c * dimension,
      (c + 1) * dimension,
      clusters[c].centroid,
    );
  }
  tree.finish(clusters.length);
  return Quantization._(assignments, centroids, dimension, tree);
}

bool _higher(List<_Cluster> clusters, int a, int b) {
  final ea = clusters[a].error, eb = clusters[b].error;
  return ea > eb || (ea == eb && a < b);
}

class _Cluster {
  _Cluster(this.members, this.centroid, this.weight, this.error);

  factory _Cluster.of(
    Int32List members,
    Float64List vectors,
    Float64List weights,
    int dimension,
  ) {
    final centroid = Float64List(dimension);
    var weight = 0.0;
    for (final m in members) {
      final w = weights[m];
      weight += w;
      for (var d = 0; d < dimension; d++) {
        centroid[d] += vectors[m * dimension + d] * w;
      }
    }
    if (weight > 0) {
      for (var d = 0; d < dimension; d++) {
        centroid[d] /= weight;
      }
    }
    var error = 0.0;
    for (final m in members) {
      var e = 0.0;
      for (var d = 0; d < dimension; d++) {
        final v = vectors[m * dimension + d] - centroid[d];
        e += v * v;
      }
      error += e * weights[m];
    }
    return _Cluster(members, centroid, weight, error);
  }

  final Int32List members;
  final Float64List centroid;
  final double weight;
  final double error;
  int node = -1;
}

/// Splits [cluster] in two along its principal axis, then settles the
/// halves with 2-means. Null when every member is the same vector.
(_Cluster, _Cluster)? _split(
  _Cluster cluster,
  Float64List vectors,
  Float64List weights,
  int dimension,
) {
  final members = cluster.members;
  final c = cluster.centroid;
  // Weighted covariance, then power iteration for the principal axis.
  final cov = Float64List(dimension * dimension);
  for (final m in members) {
    final w = weights[m];
    for (var i = 0; i < dimension; i++) {
      final di = vectors[m * dimension + i] - c[i];
      for (var j = i; j < dimension; j++) {
        cov[i * dimension + j] += di * (vectors[m * dimension + j] - c[j]) * w;
      }
    }
  }
  for (var i = 0; i < dimension; i++) {
    for (var j = 0; j < i; j++) {
      cov[i * dimension + j] = cov[j * dimension + i];
    }
  }
  final axis = Float64List(dimension);
  // Start from the axis of largest variance.
  var start = 0;
  for (var i = 1; i < dimension; i++) {
    if (cov[i * dimension + i] > cov[start * dimension + start]) start = i;
  }
  axis[start] = 1;
  final next = Float64List(dimension);
  for (var iteration = 0; iteration < 12; iteration++) {
    var length = 0.0;
    for (var i = 0; i < dimension; i++) {
      var s = 0.0;
      for (var j = 0; j < dimension; j++) {
        s += cov[i * dimension + j] * axis[j];
      }
      next[i] = s;
      length += s * s;
    }
    if (length == 0) break;
    length = math.sqrt(length);
    for (var i = 0; i < dimension; i++) {
      axis[i] = next[i] / length;
    }
  }

  // Initial halves by the sign of the projection, then 2-means.
  final side = Uint8List(members.length);
  for (var k = 0; k < members.length; k++) {
    final m = members[k];
    var p = 0.0;
    for (var d = 0; d < dimension; d++) {
      p += (vectors[m * dimension + d] - c[d]) * axis[d];
    }
    side[k] = p > 0 ? 1 : 0;
  }
  final ca = Float64List(dimension), cb = Float64List(dimension);
  for (var iteration = 0; iteration < 4; iteration++) {
    ca.fillRange(0, dimension, 0);
    cb.fillRange(0, dimension, 0);
    var wa = 0.0, wb = 0.0;
    for (var k = 0; k < members.length; k++) {
      final m = members[k];
      final w = weights[m];
      final target = side[k] == 0 ? ca : cb;
      if (side[k] == 0) {
        wa += w;
      } else {
        wb += w;
      }
      for (var d = 0; d < dimension; d++) {
        target[d] += vectors[m * dimension + d] * w;
      }
    }
    if (wa == 0 || wb == 0) return null;
    for (var d = 0; d < dimension; d++) {
      ca[d] /= wa;
      cb[d] /= wb;
    }
    var changed = false;
    for (var k = 0; k < members.length; k++) {
      final m = members[k];
      var da = 0.0, db = 0.0;
      for (var d = 0; d < dimension; d++) {
        final v = vectors[m * dimension + d];
        da += (v - ca[d]) * (v - ca[d]);
        db += (v - cb[d]) * (v - cb[d]);
      }
      final s = db < da ? 1 : 0;
      if (s != side[k]) {
        side[k] = s;
        changed = true;
      }
    }
    if (!changed) break;
  }
  var countA = 0;
  for (final s in side) {
    if (s == 0) countA++;
  }
  if (countA == 0 || countA == members.length) return null;
  final a = Int32List(countA), b = Int32List(members.length - countA);
  var ia = 0, ib = 0;
  for (var k = 0; k < members.length; k++) {
    if (side[k] == 0) {
      a[ia++] = members[k];
    } else {
      b[ib++] = members[k];
    }
  }
  return (
    _Cluster.of(a, vectors, weights, dimension),
    _Cluster.of(b, vectors, weights, dimension),
  );
}

/// The split history: a binary tree whose leaves are the final clusters.
class _SplitTree {
  final _parents = <int>[];
  final _children = <List<int>>[];
  final _clusterOfNode = <int>[];
  late final Int32List _nodeOfCluster;

  int addLeaf(int parent, int cluster) {
    _parents.add(parent);
    _children.add(const []);
    _clusterOfNode.add(cluster);
    final node = _parents.length - 1;
    if (parent >= 0) {
      _children[parent] = [..._children[parent], node];
    }
    return node;
  }

  void makeInner(int node) => _clusterOfNode[node] = -1;

  void finish(int clusterCount) {
    _nodeOfCluster = Int32List(clusterCount);
    for (var node = 0; node < _clusterOfNode.length; node++) {
      final cluster = _clusterOfNode[node];
      if (cluster >= 0) _nodeOfCluster[cluster] = node;
    }
  }

  List<int> relatives(int cluster, int levels, int limit) {
    var node = _nodeOfCluster[cluster];
    for (var i = 0; i < levels && _parents[node] >= 0; i++) {
      node = _parents[node];
    }
    final out = <int>[];
    final stack = [node];
    while (stack.isNotEmpty && out.length < limit) {
      final n = stack.removeLast();
      final c = _clusterOfNode[n];
      if (c >= 0) {
        out.add(c);
      } else {
        stack.addAll(_children[n].reversed);
      }
    }
    if (!out.contains(cluster)) out[out.length - 1] = cluster;
    return out;
  }
}
