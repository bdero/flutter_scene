import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/render/gi_bvh.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// Nearest hit distance along a ray, or infinity. The intersection test both
// walkers share.
double _hitTriangle(Float32List tris, int i, Vector3 o, Vector3 d) {
  final b = i * kGiTriangleStride;
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
  final b = n * kGiBvhNodeStride;
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

// The shader's stackless walk over one tree, transcribed. [visit] tests one
// leaf primitive and returns its hit distance.
double _walk(
  Float32List nodes,
  int nodeCount,
  Vector3 o,
  Vector3 d,
  double best,
  double Function(int primitive, double best) visit,
) {
  final inv = Vector3(1 / d.x, 1 / d.y, 1 / d.z);
  var node = 0;
  while (node >= 0 && node < nodeCount) {
    final b = node * kGiBvhNodeStride;
    final miss = nodes[b + 3].toInt();
    final leaf = nodes[b + 7];
    if (_hitBox(nodes, node, o, inv, best)) {
      if (leaf < 0) {
        node++;
        continue;
      }
      final first = leaf.toInt() ~/ 8;
      final count = leaf.toInt() % 8;
      for (var p = first; p < first + count; p++) {
        best = math.min(best, visit(p, best));
      }
    }
    node = miss;
  }
  return best;
}

double _traceBlas(GiBlas blas, Vector3 o, Vector3 d, double best) => _walk(
  blas.nodes,
  blas.nodeCount,
  o,
  d,
  best,
  (t, _) => _hitTriangle(blas.triangles, t, o, d),
);

// Random small triangles in a 20-unit cube, as 9 floats per triangle.
Float32List _soup(math.Random random, int count) {
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
  return positions;
}

// A ray from somewhere around the soup, half of them aimed at a centroid.
(Vector3, Vector3) _ray(math.Random random, Float32List positions, int r) {
  final o = Vector3(
    random.nextDouble() * 24 - 12,
    random.nextDouble() * 24 - 12,
    random.nextDouble() * 24 - 12,
  );
  if (r.isOdd) {
    return (o, (Vector3.random(random) - Vector3.all(0.5))..normalize());
  }
  final t = random.nextInt(positions.length ~/ 9) * 9;
  return (
    o,
    Vector3(
      (positions[t] + positions[t + 3] + positions[t + 6]) / 3 - o.x,
      (positions[t + 1] + positions[t + 4] + positions[t + 7]) / 3 - o.y,
      (positions[t + 2] + positions[t + 5] + positions[t + 8]) / 3 - o.z,
    )..normalize(),
  );
}

void main() {
  test('the threaded walk finds the same nearest hit as brute force', () {
    final random = math.Random(7);
    const count = 600;
    final positions = _soup(random, count);
    final blas = buildGiBlas(GiBlasInput(positions: positions));
    expect(blas.triangleCount, count);
    expect(blas.nodeCount, greaterThan(count ~/ kGiBvhMaxLeaf));

    var hits = 0;
    for (var r = 0; r < 400; r++) {
      final (o, d) = _ray(random, positions, r);
      var brute = double.infinity;
      for (var t = 0; t < count; t++) {
        brute = math.min(brute, _hitTriangle(blas.triangles, t, o, d));
      }
      final walked = _traceBlas(blas, o, d, double.infinity);
      expect(walked, brute, reason: 'ray $r');
      if (brute.isFinite) hits++;
    }
    expect(hits, greaterThan(100), reason: 'enough rays hit to mean anything');
  });

  test('the two-level walk matches brute force over instances', () {
    final random = math.Random(11);
    final positions = _soup(random, 200);
    final blas = buildGiBlas(GiBlasInput(positions: positions));
    final transforms = [
      for (var i = 0; i < 6; i++)
        Matrix4.compose(
          Vector3(i * 30.0 - 75, random.nextDouble() * 10, 0),
          Quaternion.axisAngle(
            (Vector3.random(random)..normalize()),
            random.nextDouble() * 6,
          ),
          Vector3.all(0.5 + random.nextDouble()),
        ),
    ];
    // World boxes of the instances, as the TLAS build sees them.
    final boxes = Float32List(transforms.length * 6);
    for (var i = 0; i < transforms.length; i++) {
      final box = Aabb3();
      var first = true;
      for (var c = 0; c < positions.length ~/ 3; c++) {
        final p = transforms[i].transformed3(
          Vector3(positions[c * 3], positions[c * 3 + 1], positions[c * 3 + 2]),
        );
        if (first) {
          box.setCenterAndHalfExtents(p, Vector3.zero());
          first = false;
        } else {
          box.hullPoint(p);
        }
      }
      boxes.setAll(i * 6, [...box.min.storage, ...box.max.storage]);
    }
    final tlas = GiBvhNodes.build(boxes, maxLeaf: 2);
    final inverses = [for (final m in transforms) Matrix4.inverted(m)];

    double traceInstance(int instance, Vector3 o, Vector3 d, double best) {
      // The ray's affine image keeps its parameter, so distances compare
      // across instances without renormalizing.
      final inverse = inverses[instance];
      final lo = inverse.transformed3(o);
      final ld = inverse.getRotation().transformed(d);
      return _traceBlas(blas, lo, ld, best);
    }

    var hits = 0;
    for (var r = 0; r < 300; r++) {
      final o = Vector3(
        random.nextDouble() * 200 - 100,
        random.nextDouble() * 30 - 10,
        random.nextDouble() * 40 - 20,
      );
      final Vector3 d;
      if (r.isEven) {
        // Aim at a triangle's first corner in a random instance.
        final c = random.nextInt(positions.length ~/ 9) * 9;
        final target = transforms[random.nextInt(transforms.length)]
            .transformed3(
              Vector3(positions[c], positions[c + 1], positions[c + 2]),
            );
        d = (target - o)..normalize();
      } else {
        d = (Vector3.random(random) - Vector3.all(0.5))..normalize();
      }
      var brute = double.infinity;
      for (var i = 0; i < transforms.length; i++) {
        brute = math.min(brute, traceInstance(i, o, d, double.infinity));
      }
      final walked = _walk(
        tlas.nodes,
        tlas.nodeCount,
        o,
        d,
        double.infinity,
        (leaf, best) => traceInstance(tlas.order[leaf], o, d, best),
      );
      expect(
        walked,
        brute.isFinite ? closeTo(brute, 1e-4) : brute,
        reason: 'ray $r',
      );
      if (brute.isFinite) hits++;
    }
    expect(hits, greaterThan(20));
  });

  test('a refit in level order bounds the deformed triangles', () {
    final random = math.Random(3);
    final positions = _soup(random, 300);
    final blas = buildGiBlas(GiBlasInput(positions: positions));

    // Deform every vertex, rebuild the triangles from the corner indices,
    // then refit node bounds one depth group at a time, as the GPU does.
    final moved = Float32List.fromList([
      for (var i = 0; i < positions.length; i++)
        positions[i] + math.sin(i * 0.37) * 2,
    ]);
    final triangles = Float32List.fromList(blas.triangles);
    for (var t = 0; t < blas.triangleCount; t++) {
      final out = t * kGiTriangleStride;
      final v = [for (var k = 0; k < 3; k++) blas.corners[t * 3 + k] * 3];
      for (var axis = 0; axis < 3; axis++) {
        final v0 = moved[v[0] + axis];
        triangles[out + axis] = v0;
        triangles[out + 4 + axis] = moved[v[1] + axis] - v0;
        triangles[out + 8 + axis] = moved[v[2] + axis] - v0;
      }
    }
    final nodes = Float32List.fromList(blas.nodes);
    for (var group = 0; group + 1 < blas.levelStarts.length; group++) {
      for (
        var i = blas.levelStarts[group];
        i < blas.levelStarts[group + 1];
        i++
      ) {
        final n = blas.refitOrder[i];
        final b = n * kGiBvhNodeStride;
        final lo = [double.infinity, double.infinity, double.infinity];
        final hi = [
          double.negativeInfinity,
          double.negativeInfinity,
          double.negativeInfinity,
        ];
        void grow(List<double> p) {
          for (var a = 0; a < 3; a++) {
            lo[a] = math.min(lo[a], p[a]);
            hi[a] = math.max(hi[a], p[a]);
          }
        }

        final leaf = nodes[b + 7];
        if (leaf < 0) {
          // Left child is the next node; right child is where it ends.
          final left = n + 1;
          final right = nodes[left * kGiBvhNodeStride + 3].toInt();
          for (final c in [left, right]) {
            final cb = c * kGiBvhNodeStride;
            grow([nodes[cb], nodes[cb + 1], nodes[cb + 2]]);
            grow([nodes[cb + 4], nodes[cb + 5], nodes[cb + 6]]);
          }
        } else {
          final first = leaf.toInt() ~/ 8;
          for (var t = first; t < first + leaf.toInt() % 8; t++) {
            final o = t * kGiTriangleStride;
            final v0 = [triangles[o], triangles[o + 1], triangles[o + 2]];
            grow(v0);
            grow([for (var a = 0; a < 3; a++) v0[a] + triangles[o + 4 + a]]);
            grow([for (var a = 0; a < 3; a++) v0[a] + triangles[o + 8 + a]]);
          }
        }
        nodes.setAll(b, [lo[0], lo[1], lo[2]]);
        nodes.setAll(b + 4, [hi[0], hi[1], hi[2]]);
      }
    }

    final refit = GiBlasView(nodes, triangles, blas.nodeCount);
    for (var r = 0; r < 300; r++) {
      final (o, d) = _ray(random, moved, r);
      var brute = double.infinity;
      for (var t = 0; t < blas.triangleCount; t++) {
        brute = math.min(brute, _hitTriangle(triangles, t, o, d));
      }
      final walked = _walk(
        refit.nodes,
        refit.nodeCount,
        o,
        d,
        double.infinity,
        (t, _) => _hitTriangle(refit.triangles, t, o, d),
      );
      expect(walked, brute, reason: 'ray $r');
    }
  });

  test('corner texture coordinates follow their triangle', () {
    final positions = Float32List.fromList([
      for (var t = 0; t < 10; t++) ...[
        t * 3.0, 0, 0, t * 3.0 + 1, 0, 0, t * 3.0, 1, 0, //
      ],
    ]);
    final uvs = Float32List.fromList([
      for (var v = 0; v < 30; v++) ...[v.toDouble(), -v.toDouble()],
    ]);
    final blas = buildGiBlas(GiBlasInput(positions: positions, uvs: uvs));
    for (var i = 0; i < 10; i++) {
      final b = i * kGiTriangleStride;
      final first = blas.corners[i * 3];
      expect(blas.triangles[b], positions[first * 3]);
      expect(blas.triangles[b + 3], first.toDouble());
      expect(blas.triangles[b + 7], -first.toDouble());
      expect(blas.triangles[b + 12], blas.corners[i * 3 + 1].toDouble());
      expect(blas.triangles[b + 14], blas.corners[i * 3 + 2].toDouble());
    }
  });

  test('an empty mesh builds no nodes', () {
    final blas = buildGiBlas(GiBlasInput(positions: Float32List(0)));
    expect(blas.nodeCount, 0);
    expect(blas.triangleCount, 0);
    expect(blas.refitOrder, isEmpty);
  });
}

class GiBlasView {
  GiBlasView(this.nodes, this.triangles, this.nodeCount);
  final Float32List nodes;
  final Float32List triangles;
  final int nodeCount;
}
