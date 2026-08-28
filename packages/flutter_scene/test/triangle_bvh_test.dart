// Triangle BVH tests. Builds a hierarchy over a dense mesh and checks it
// agrees, hit for hit, with a brute-force sweep over the same triangles.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/geometry/triangle_bvh.dart';
import 'package:flutter_test/flutter_test.dart';

/// A rippled grid mesh: `n` by `n` cells, two triangles each, no two
/// coplanar so the hierarchy has real structure to build.
(Float32List, Uint32List) _grid(int n) {
  final positions = Float32List((n + 1) * (n + 1) * 3);
  for (var j = 0; j <= n; j++) {
    for (var i = 0; i <= n; i++) {
      final v = (j * (n + 1) + i) * 3;
      positions[v] = i.toDouble();
      positions[v + 1] = math.sin(i * 0.6) * math.cos(j * 0.4) * 2;
      positions[v + 2] = j.toDouble();
    }
  }
  final triVerts = Uint32List(n * n * 6);
  var k = 0;
  for (var j = 0; j < n; j++) {
    for (var i = 0; i < n; i++) {
      final a = j * (n + 1) + i;
      final b = a + 1;
      final c = a + (n + 1);
      final d = c + 1;
      triVerts[k++] = a;
      triVerts[k++] = b;
      triVerts[k++] = d;
      triVerts[k++] = a;
      triVerts[k++] = d;
      triVerts[k++] = c;
    }
  }
  return (positions, triVerts);
}

/// Moller-Trumbore reference, independent of the implementation under test.
double? _rayTriangle(
  Float32List p,
  int ia,
  int ib,
  int ic,
  double ox,
  double oy,
  double oz,
  double dx,
  double dy,
  double dz,
) {
  final ax = p[ia * 3], ay = p[ia * 3 + 1], az = p[ia * 3 + 2];
  final e1x = p[ib * 3] - ax, e1y = p[ib * 3 + 1] - ay, e1z = p[ib * 3 + 2] - az;
  final e2x = p[ic * 3] - ax, e2y = p[ic * 3 + 1] - ay, e2z = p[ic * 3 + 2] - az;
  final px = dy * e2z - dz * e2y;
  final py = dz * e2x - dx * e2z;
  final pz = dx * e2y - dy * e2x;
  final det = e1x * px + e1y * py + e1z * pz;
  if (det.abs() < 1e-12) return null;
  final invDet = 1.0 / det;
  final tx = ox - ax, ty = oy - ay, tz = oz - az;
  final u = (tx * px + ty * py + tz * pz) * invDet;
  if (u < 0 || u > 1) return null;
  final qx = ty * e1z - tz * e1y;
  final qy = tz * e1x - tx * e1z;
  final qz = tx * e1y - ty * e1x;
  final v = (dx * qx + dy * qy + dz * qz) * invDet;
  if (v < 0 || u + v > 1) return null;
  final t = (e2x * qx + e2y * qy + e2z * qz) * invDet;
  return t <= 0 ? null : t;
}

void main() {
  group('TriangleBvh (GPU-free)', () {
    test('the nearest hit matches a brute-force sweep on 500 random rays', () {
      final (positions, source) = _grid(20);
      final bvh = TriangleBvh.build(positions, source);
      final random = math.Random(20260828);
      var hits = 0;
      for (var q = 0; q < 500; q++) {
        final ox = random.nextDouble() * 24 - 2;
        final oz = random.nextDouble() * 24 - 2;
        const oy = 20.0;
        final dx = random.nextDouble() * 0.8 - 0.4;
        final dz = random.nextDouble() * 0.8 - 0.4;
        final len = math.sqrt(dx * dx + 1 + dz * dz);
        final ux = dx / len, uy = -1 / len, uz = dz / len;

        var expected = double.infinity;
        for (var t = 0; t * 3 + 2 < source.length; t++) {
          final hit = _rayTriangle(
            positions,
            source[t * 3],
            source[t * 3 + 1],
            source[t * 3 + 2],
            ox,
            oy,
            oz,
            ux,
            uy,
            uz,
          );
          if (hit != null && hit < expected) expected = hit;
        }

        var got = double.infinity;
        bvh.raycast(ox, oy, oz, ux, uy, uz, 1000, (first, end, limit) {
          for (var slot = first; slot < end; slot++) {
            final hit = _rayTriangle(
              positions,
              bvh.triVerts[slot * 3],
              bvh.triVerts[slot * 3 + 1],
              bvh.triVerts[slot * 3 + 2],
              ox,
              oy,
              oz,
              ux,
              uy,
              uz,
            );
            if (hit != null && hit < got) got = hit;
          }
          return got < limit ? got : limit;
        });

        if (expected == double.infinity) {
          expect(got, double.infinity, reason: 'query $q should miss');
        } else {
          expect(got, closeTo(expected, 1e-9), reason: 'query $q');
          hits++;
        }
      }
      expect(hits, greaterThan(200), reason: 'the sample should mostly hit');
    });

    test('an axis-parallel ray sitting exactly on a node plane still hits', () {
      // Integer coordinates put node planes exactly on the ray, which is the
      // case a slab test built on infinities turns into a NaN and drops.
      final (positions, source) = _grid(8);
      final bvh = TriangleBvh.build(positions, source);
      for (var i = 0; i <= 8; i++) {
        var found = false;
        bvh.raycast(i.toDouble(), 20, 4, 0, -1, 0, 100, (first, end, limit) {
          for (var slot = first; slot < end; slot++) {
            final hit = _rayTriangle(
              positions,
              bvh.triVerts[slot * 3],
              bvh.triVerts[slot * 3 + 1],
              bvh.triVerts[slot * 3 + 2],
              i.toDouble(),
              20,
              4,
              0,
              -1,
              0,
            );
            if (hit != null) found = true;
          }
          return limit;
        });
        expect(found, isTrue, reason: 'x=$i is over the mesh');
      }
    });

    test('triOrder maps every slot back to its source triangle', () {
      final (positions, source) = _grid(12);
      final bvh = TriangleBvh.build(positions, source);
      final triangles = source.length ~/ 3;
      expect(bvh.triOrder, hasLength(triangles));
      expect(bvh.triOrder.toSet(), hasLength(triangles));
      for (var slot = 0; slot < triangles; slot++) {
        final t = bvh.triOrder[slot];
        for (var corner = 0; corner < 3; corner++) {
          expect(bvh.triVerts[slot * 3 + corner], source[t * 3 + corner]);
        }
      }
    });

    test('the distance limit prunes the walk', () {
      final (positions, source) = _grid(10);
      final bvh = TriangleBvh.build(positions, source);
      var leaves = 0;
      bvh.raycast(5, 20, 5, 0, -1, 0, 1.0, (first, end, limit) {
        leaves++;
        return limit;
      });
      expect(leaves, 0, reason: 'nothing is within one unit of the origin');
    });

    test('a single triangle builds a one-leaf hierarchy', () {
      final positions = Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 0, 1]);
      final bvh = TriangleBvh.build(positions, Uint32List.fromList([0, 1, 2]));
      var visited = 0;
      bvh.raycast(0.25, 1, 0.25, 0, -1, 0, 10, (first, end, limit) {
        visited += end - first;
        return limit;
      });
      expect(visited, 1);
    });
  });
}
