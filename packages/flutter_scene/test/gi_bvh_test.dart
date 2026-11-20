import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/render/gi_bvh.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// Nearest hit distance along a ray, or infinity. The intersection test both
// walkers share.
double _hitTriangle(Float32List tris, int i, Vector3 o, Vector3 d) {
  final b = i * GiBvh.triangleStride;
  final v0 = Vector3(tris[b], tris[b + 1], tris[b + 2]);
  final e1 = Vector3(tris[b + 4], tris[b + 5], tris[b + 6]);
  final e2 = Vector3(tris[b + 8], tris[b + 9], tris[b + 10]);
  final p = d.cross(e2);
  final det = e1.dot(p);
  if (det.abs() < 1e-12) return double.infinity;
  final inv = 1.0 / det;
  final s = o - v0;
  final u = s.dot(p) * inv;
  if (u < 0 || u > 1) return double.infinity;
  final q = s.cross(e1);
  final v = d.dot(q) * inv;
  if (v < 0 || u + v > 1) return double.infinity;
  final t = e2.dot(q) * inv;
  return t > 1e-6 ? t : double.infinity;
}

bool _hitBox(Float32List nodes, int n, Vector3 o, Vector3 inv, double tMax) {
  final b = n * GiBvh.nodeStride;
  var t0 = 0.0;
  var t1 = tMax;
  for (var axis = 0; axis < 3; axis++) {
    var near = (nodes[b + axis] - o[axis]) * inv[axis];
    var far = (nodes[b + 4 + axis] - o[axis]) * inv[axis];
    if (near > far) (near, far) = (far, near);
    t0 = math.max(t0, near);
    t1 = math.min(t1, far);
  }
  return t0 <= t1;
}

// The shader's stackless walk, transcribed.
double _traverse(GiBvh bvh, Vector3 o, Vector3 d) {
  final inv = Vector3(1 / d.x, 1 / d.y, 1 / d.z);
  var best = double.infinity;
  var node = 0;
  while (node >= 0 && node < bvh.nodeCount) {
    final b = node * GiBvh.nodeStride;
    final miss = bvh.nodes[b + 3].toInt();
    final leaf = bvh.nodes[b + 7];
    if (_hitBox(bvh.nodes, node, o, inv, best)) {
      if (leaf < 0) {
        node++;
        continue;
      }
      final first = leaf.toInt() ~/ 8;
      final count = leaf.toInt() % 8;
      for (var t = first; t < first + count; t++) {
        best = math.min(best, _hitTriangle(bvh.triangles, t, o, d));
      }
    }
    node = miss;
  }
  return best;
}

void main() {
  test('the threaded walk finds the same nearest hit as brute force', () {
    final random = math.Random(7);
    const count = 600;
    final positions = Float32List(count * 9);
    for (var t = 0; t < count; t++) {
      final center = Vector3(
        random.nextDouble() * 20 - 10,
        random.nextDouble() * 20 - 10,
        random.nextDouble() * 20 - 10,
      );
      for (var c = 0; c < 3; c++) {
        for (var axis = 0; axis < 3; axis++) {
          positions[t * 9 + c * 3 + axis] =
              center[axis] + random.nextDouble() * 2 - 1;
        }
      }
    }
    final bvh = GiBvh.build(positions, List<int>.generate(count, (i) => i));
    expect(bvh.triangleCount, count);
    expect(bvh.nodeCount, greaterThan(count ~/ GiBvh.maxLeafTriangles));

    var hits = 0;
    for (var r = 0; r < 400; r++) {
      final o = Vector3(
        random.nextDouble() * 24 - 12,
        random.nextDouble() * 24 - 12,
        random.nextDouble() * 24 - 12,
      );
      // Half the rays aim at a triangle's centroid, so many of them hit.
      final Vector3 d;
      if (r.isEven) {
        final t = random.nextInt(count) * 9;
        d = Vector3(
          (positions[t] + positions[t + 3] + positions[t + 6]) / 3 - o.x,
          (positions[t + 1] + positions[t + 4] + positions[t + 7]) / 3 - o.y,
          (positions[t + 2] + positions[t + 5] + positions[t + 8]) / 3 - o.z,
        )..normalize();
      } else {
        d = (Vector3.random(random) - Vector3.all(0.5))..normalize();
      }
      var brute = double.infinity;
      for (var t = 0; t < count; t++) {
        brute = math.min(brute, _hitTriangle(bvh.triangles, t, o, d));
      }
      final walked = _traverse(bvh, o, d);
      expect(walked, brute, reason: 'ray $r');
      if (brute.isFinite) hits++;
    }
    expect(hits, greaterThan(100), reason: 'enough rays hit to mean anything');
  });

  test('every triangle keeps its material through the reorder', () {
    final positions = Float32List.fromList([
      for (var t = 0; t < 10; t++) ...[
        t * 3.0, 0, 0, t * 3.0 + 1, 0, 0, t * 3.0, 1, 0, //
      ],
    ]);
    final bvh = GiBvh.build(positions, List<int>.generate(10, (i) => 100 + i));
    for (var i = 0; i < 10; i++) {
      final b = i * GiBvh.triangleStride;
      final material = bvh.triangles[b + 3].toInt();
      expect(bvh.triangles[b], (material - 100) * 3.0);
    }
  });

  test('an empty scene builds no nodes', () {
    final bvh = GiBvh.build(Float32List(0), const []);
    expect(bvh.nodeCount, 0);
    expect(bvh.triangleCount, 0);
  });
}
