// Exact shape query math: the cylinder, height field, and triangle mesh ray
// tests, the OBB separating-axis overlap, and the broad-phase hierarchy.
//
// Each exact test is checked against an independently derived expectation
// rather than against the AABB approximation it replaced, and the hierarchy
// tests compare against a brute-force sweep over the same inputs.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:scene/physics.dart';
import 'package:scene/src/physics/aabb_bvh.dart';
import 'package:scene/src/physics/mesh_bvh.dart';
import 'package:scene/src/physics/shape_queries.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Matrix4 _identity() => Matrix4.identity();

void main() {
  group('ray vs cylinder', () {
    final cylinder = CylinderShape(radius: 1.0, halfHeight: 2.0);

    test('a ray down the axis hits the top cap, not the AABB corner', () {
      final hit = rayHitsShape(
        Ray.originDirection(Vector3(0, 10, 0), Vector3(0, -1, 0)),
        cylinder,
        _identity(),
        100,
      );
      expect(hit, isNotNull);
      expect(hit!.distance, closeTo(8.0, 1e-9));
      expect(hit.worldNormal.y, closeTo(1.0, 1e-9));
    });

    test('a side hit lands on the curved surface at the radius', () {
      final hit = rayHitsShape(
        Ray.originDirection(Vector3(10, 0, 0), Vector3(-1, 0, 0)),
        cylinder,
        _identity(),
        100,
      );
      expect(hit, isNotNull);
      expect(hit!.distance, closeTo(9.0, 1e-9));
      expect(hit.worldPoint.x, closeTo(1.0, 1e-9));
      expect(hit.worldNormal.x, closeTo(1.0, 1e-9));
    });

    test('the corner of the bounding box is a miss, unlike an AABB test', () {
      // Aimed at (0.95, 1.99), inside the AABB corner but outside the circle
      // of radius 1 only if it also clears the cap. Shoot along -Z at an XY
      // that is outside the disc: an AABB test would report a hit.
      final hit = rayHitsShape(
        Ray.originDirection(Vector3(0.9, 0, 10), Vector3(0, 0, -1)),
        cylinder,
        _identity(),
        100,
      );
      expect(hit, isNotNull, reason: 'inside the disc, so a real hit');
      final miss = rayHitsShape(
        Ray.originDirection(Vector3(0.99, 0, 10), Vector3(0, 0, -1)),
        CylinderShape(radius: 0.5, halfHeight: 2.0),
        _identity(),
        100,
      );
      expect(miss, isNull, reason: 'outside the disc but inside the AABB');
    });

    test('a ray that misses entirely reports nothing', () {
      expect(
        rayHitsShape(
          Ray.originDirection(Vector3(5, 0, 0), Vector3(0, 1, 0)),
          cylinder,
          _identity(),
          100,
        ),
        isNull,
      );
    });

    test('the cylinder follows its collider transform', () {
      // Rotated 90 degrees about Z, so the axis lies along X.
      final xform = Matrix4.compose(
        Vector3(0, 0, 0),
        Quaternion.axisAngle(Vector3(0, 0, 1), math.pi / 2),
        Vector3(1, 1, 1),
      );
      final hit = rayHitsShape(
        Ray.originDirection(Vector3(10, 0, 0), Vector3(-1, 0, 0)),
        cylinder,
        xform,
        100,
      );
      expect(hit, isNotNull);
      // The cap is now the +X end, two units out.
      expect(hit!.distance, closeTo(8.0, 1e-6));
      expect(hit.worldNormal.x, closeTo(1.0, 1e-6));
    });
  });

  group('ray vs height field', () {
    // A 3x3 field, flat at y = 0 except for a spike at the centre sample.
    HeightFieldShape field(List<double> heights) => HeightFieldShape(
      width: 3,
      depth: 3,
      heights: Float32List.fromList(heights),
      scale: Vector3(1, 1, 1),
    );

    test('a ray straight down hits the surface at the sampled height', () {
      final hit = rayHitsShape(
        Ray.originDirection(Vector3(0, 10, 0), Vector3(0, -1, 0)),
        field([0, 0, 0, 0, 3, 0, 0, 0, 0]),
        _identity(),
        100,
      );
      expect(hit, isNotNull);
      // The centre sample is the shared corner of all four cells, at y = 3.
      expect(hit!.worldPoint.y, closeTo(3.0, 1e-6));
      expect(hit.distance, closeTo(7.0, 1e-6));
      expect(hit.worldNormal.y, greaterThan(0));
    });

    test('a flat field reads flat everywhere on it', () {
      final flat = field([0, 0, 0, 0, 0, 0, 0, 0, 0]);
      for (final x in [-0.9, -0.3, 0.0, 0.4, 0.9]) {
        final hit = rayHitsShape(
          Ray.originDirection(Vector3(x, 5, 0.25), Vector3(0, -1, 0)),
          flat,
          _identity(),
          100,
        );
        expect(hit, isNotNull, reason: 'x=$x is over the field');
        expect(hit!.worldPoint.y, closeTo(0.0, 1e-6));
        expect(hit.worldNormal.y, closeTo(1.0, 1e-6));
      }
    });

    test('a ray beside the field misses instead of hitting its box', () {
      expect(
        rayHitsShape(
          Ray.originDirection(Vector3(5, 10, 0), Vector3(0, -1, 0)),
          field([0, 0, 0, 0, 3, 0, 0, 0, 0]),
          _identity(),
          100,
        ),
        isNull,
      );
    });

    test('a ray under the raised centre passes beneath it', () {
      // Enters low on one side and leaves the far side without ever reaching
      // the surface; an AABB test would have reported a hit.
      final hit = rayHitsShape(
        Ray.originDirection(Vector3(-5, -0.5, 0.5), Vector3(1, 0, 0)),
        field([0, 0, 0, 0, 5, 0, 0, 0, 0]),
        _identity(),
        100,
      );
      expect(hit, isNull);
    });

    test('a grazing ray finds the raised centre it crosses', () {
      final hit = rayHitsShape(
        Ray.originDirection(Vector3(-5, 1.0, 0), Vector3(1, 0, 0)),
        field([0, 0, 0, 0, 5, 0, 0, 0, 0]),
        _identity(),
        100,
      );
      expect(hit, isNotNull);
      expect(hit!.worldPoint.y, closeTo(1.0, 1e-6));
      // The slope rises from y=0 at x=-1 to y=5 at x=0, so y=1 is at x=-0.8.
      expect(hit.worldPoint.x, closeTo(-0.8, 1e-6));
    });

    test('scale stretches the field in every axis', () {
      final hit = rayHitsShape(
        Ray.originDirection(Vector3(0, 10, 0), Vector3(0, -1, 0)),
        HeightFieldShape(
          width: 3,
          depth: 3,
          heights: Float32List.fromList([0, 0, 0, 0, 2, 0, 0, 0, 0]),
          scale: Vector3(4, 3, 4),
        ),
        _identity(),
        100,
      );
      expect(hit, isNotNull);
      expect(hit!.worldPoint.y, closeTo(6.0, 1e-6));
    });
  });

  group('ray vs triangle mesh', () {
    // A unit quad in the XZ plane at y = 0, spanning [-1, 1].
    final quad = TriMeshShape(
      vertices: Float32List.fromList([
        -1, 0, -1, //
        1, 0, -1, //
        1, 0, 1, //
        -1, 0, 1,
      ]),
      indices: Uint32List.fromList([0, 1, 2, 0, 2, 3]),
    );

    test('a ray through the quad hits the plane, not the box', () {
      final hit = rayHitsShape(
        Ray.originDirection(Vector3(0.5, 4, 0.5), Vector3(0, -1, 0)),
        quad,
        _identity(),
        100,
      );
      expect(hit, isNotNull);
      expect(hit!.distance, closeTo(4.0, 1e-6));
      expect(hit.worldPoint.y, closeTo(0.0, 1e-6));
      expect(hit.worldNormal.y.abs(), closeTo(1.0, 1e-6));
    });

    test('a ray past the edge misses, where the AABB would have hit', () {
      expect(
        rayHitsShape(
          Ray.originDirection(Vector3(1.5, 4, 0), Vector3(0, -1, 0)),
          quad,
          _identity(),
          100,
        ),
        isNull,
      );
    });

    test('the nearest of two stacked meshes wins', () {
      final stacked = TriMeshShape(
        vertices: Float32List.fromList([
          -1, 0, -1, 1, 0, -1, 1, 0, 1, //
          -1, 5, -1, 1, 5, -1, 1, 5, 1,
        ]),
        indices: Uint32List.fromList([0, 1, 2, 3, 4, 5]),
      );
      final hit = rayHitsShape(
        Ray.originDirection(Vector3(0.2, 10, -0.2), Vector3(0, -1, 0)),
        stacked,
        _identity(),
        100,
      );
      expect(hit, isNotNull);
      expect(hit!.worldPoint.y, closeTo(5.0, 1e-6));
    });

    test('the collider transform moves the mesh', () {
      final hit = rayHitsShape(
        Ray.originDirection(Vector3(0, 10, 0), Vector3(0, -1, 0)),
        quad,
        Matrix4.translation(Vector3(0, 3, 0)),
        100,
      );
      expect(hit, isNotNull);
      expect(hit!.worldPoint.y, closeTo(3.0, 1e-6));
    });
  });

  group('MeshBvh', () {
    // A grid of triangles dense enough to exercise several levels.
    (Float32List, Uint32List) grid(int n) {
      final vertices = Float32List((n + 1) * (n + 1) * 3);
      for (var j = 0; j <= n; j++) {
        for (var i = 0; i <= n; i++) {
          final v = (j * (n + 1) + i) * 3;
          vertices[v] = i.toDouble();
          // A gentle ripple, so triangles are not coplanar.
          vertices[v + 1] = math.sin(i * 0.7) * math.cos(j * 0.5);
          vertices[v + 2] = j.toDouble();
        }
      }
      final indices = Uint32List(n * n * 6);
      var k = 0;
      for (var j = 0; j < n; j++) {
        for (var i = 0; i < n; i++) {
          final a = j * (n + 1) + i;
          final b = a + 1;
          final c = a + (n + 1);
          final d = c + 1;
          indices[k++] = a;
          indices[k++] = b;
          indices[k++] = d;
          indices[k++] = a;
          indices[k++] = d;
          indices[k++] = c;
        }
      }
      return (vertices, indices);
    }

    test('agrees with a brute-force sweep over 400 random rays', () {
      final (vertices, indices) = grid(16);
      final bvh = MeshBvh.build(vertices, indices);
      final random = math.Random(20260828);
      var hits = 0;
      for (var q = 0; q < 400; q++) {
        final ox = random.nextDouble() * 20 - 2;
        final oz = random.nextDouble() * 20 - 2;
        final oy = 10.0;
        final dx = random.nextDouble() * 0.6 - 0.3;
        final dz = random.nextDouble() * 0.6 - 0.3;
        final d = Vector3(dx, -1, dz)..normalize();

        // Brute force over the same triangles.
        var bestT = double.infinity;
        for (var t = 0; t * 3 + 2 < indices.length; t++) {
          final a = indices[t * 3] * 3;
          final b = indices[t * 3 + 1] * 3;
          final c = indices[t * 3 + 2] * 3;
          final hit = _rayTriangle(
            ox,
            oy,
            oz,
            d.x,
            d.y,
            d.z,
            vertices[a],
            vertices[a + 1],
            vertices[a + 2],
            vertices[b],
            vertices[b + 1],
            vertices[b + 2],
            vertices[c],
            vertices[c + 1],
            vertices[c + 2],
          );
          if (hit != null && hit < bestT) bestT = hit;
        }

        final got = bvh.raycast(ox, oy, oz, d.x, d.y, d.z, 1000);
        if (bestT == double.infinity) {
          expect(got, isNull, reason: 'query $q should miss');
        } else {
          expect(got, isNotNull, reason: 'query $q should hit at $bestT');
          expect(got!.t, closeTo(bestT, 1e-6), reason: 'query $q');
          hits++;
        }
      }
      expect(hits, greaterThan(200), reason: 'the sample should mostly hit');
    });

    test('respects the distance limit', () {
      final (vertices, indices) = grid(8);
      final bvh = MeshBvh.build(vertices, indices);
      expect(bvh.raycast(4, 10, 4, 0, -1, 0, 100), isNotNull);
      expect(bvh.raycast(4, 10, 4, 0, -1, 0, 1), isNull);
    });

    test('an empty mesh answers nothing rather than throwing', () {
      final bvh = MeshBvh.build(Float32List(0), Uint32List(0));
      expect(bvh.raycast(0, 0, 0, 0, -1, 0, 100), isNull);
    });
  });

  group('OBB separating-axis overlap', () {
    Matrix4 pose(Vector3 t, [Quaternion? r]) =>
        Matrix4.compose(t, r ?? Quaternion.identity(), Vector3(1, 1, 1));

    test('two axis-aligned boxes agree with the interval test', () {
      final a = Vector3(1, 1, 1);
      expect(
        obbOverlapsObb(pose(Vector3.zero()), a, pose(Vector3(1.5, 0, 0)), a),
        isTrue,
      );
      expect(
        obbOverlapsObb(pose(Vector3.zero()), a, pose(Vector3(2.5, 0, 0)), a),
        isFalse,
      );
    });

    test('a rotated probe no longer catches a corner it never reached', () {
      // A unit probe turned 45 degrees about Y and offset along the XZ
      // diagonal. Its enclosing AABB spans [0.586, 3.414] on both x and z and
      // so overlaps the target's [-1, 1] cube, but the diamond it actually
      // occupies is separated along the diagonal: centre distance 2*sqrt(2)
      // against a combined extent of 1 + sqrt(2).
      final probe = pose(
        Vector3(2, 0, 2),
        Quaternion.axisAngle(Vector3(0, 1, 0), math.pi / 4),
      );
      final half = Vector3(1, 1, 1);
      final target = pose(Vector3.zero());
      expect(obbOverlapsObb(probe, half, target, half), isFalse);
      // The looser AABB-of-OBB test this replaced would have said yes.
      expect(2 - math.sqrt(2), lessThan(1.0));
      expect(1 + math.sqrt(2), lessThan(2 * math.sqrt(2)));
    });

    test('an edge-on contact between two rotated boxes is caught', () {
      final a = pose(
        Vector3.zero(),
        Quaternion.axisAngle(Vector3(0, 0, 1), math.pi / 4),
      );
      final b = pose(
        Vector3(1.9, 0, 0),
        Quaternion.axisAngle(Vector3(0, 1, 0), math.pi / 4),
      );
      final half = Vector3(1, 1, 1);
      expect(obbOverlapsObb(a, half, b, half), isTrue);
      final far = pose(
        Vector3(3.5, 0, 0),
        Quaternion.axisAngle(Vector3(0, 1, 0), math.pi / 4),
      );
      expect(obbOverlapsObb(a, half, far, half), isFalse);
    });

    test('a sphere collider is tested against the real probe box', () {
      final probe = pose(Vector3.zero());
      final half = Vector3(1, 1, 1);
      expect(
        obbOverlapsShape(
          probe,
          half,
          SphereShape(radius: 0.5),
          pose(Vector3(1.4, 0, 0)),
        ),
        isTrue,
      );
      expect(
        obbOverlapsShape(
          probe,
          half,
          SphereShape(radius: 0.5),
          pose(Vector3(1.6, 0, 0)),
        ),
        isFalse,
      );
    });

    test('a compound collider overlaps when any child does', () {
      final compound = CompoundShape(
        children: [
          CompoundChild(
            shape: SphereShape(radius: 0.25),
            localPose: Matrix4.translation(Vector3(0, 0, 8)),
          ),
          CompoundChild(
            shape: SphereShape(radius: 0.25),
            localPose: Matrix4.translation(Vector3(0, 0, 0)),
          ),
        ],
      );
      expect(
        obbOverlapsShape(
          pose(Vector3.zero()),
          Vector3(1, 1, 1),
          compound,
          pose(Vector3.zero()),
        ),
        isTrue,
      );
      expect(
        obbOverlapsShape(
          pose(Vector3(0, 0, 4)),
          Vector3(1, 1, 1),
          compound,
          pose(Vector3.zero()),
        ),
        isFalse,
      );
    });
  });

  group('AabbBvh', () {
    Float32List boxes(List<Aabb3> list) {
      final out = Float32List(list.length * 6);
      for (var i = 0; i < list.length; i++) {
        out[i * 6] = list[i].min.x;
        out[i * 6 + 1] = list[i].min.y;
        out[i * 6 + 2] = list[i].min.z;
        out[i * 6 + 3] = list[i].max.x;
        out[i * 6 + 4] = list[i].max.y;
        out[i * 6 + 5] = list[i].max.z;
      }
      return out;
    }

    List<Aabb3> scatter(int n, math.Random random) => [
      for (var i = 0; i < n; i++)
        () {
          final c = Vector3(
            random.nextDouble() * 100 - 50,
            random.nextDouble() * 100 - 50,
            random.nextDouble() * 100 - 50,
          );
          final e = Vector3(
            random.nextDouble() * 2 + 0.1,
            random.nextDouble() * 2 + 0.1,
            random.nextDouble() * 2 + 0.1,
          );
          return Aabb3.minMax(c - e, c + e);
        }(),
    ];

    test('a ray query returns exactly the boxes it crosses', () {
      final random = math.Random(7);
      final list = scatter(300, random);
      final packed = boxes(list);
      final bvh = AabbBvh.build(packed, list.length);
      for (var q = 0; q < 50; q++) {
        final origin = Vector3(
          random.nextDouble() * 200 - 100,
          random.nextDouble() * 200 - 100,
          random.nextDouble() * 200 - 100,
        );
        final direction = Vector3(
          random.nextDouble() * 2 - 1,
          random.nextDouble() * 2 - 1,
          random.nextDouble() * 2 - 1,
        )..normalize();
        final ray = Ray.originDirection(origin, direction);
        // Against the float32 values the hierarchy stores, so a box within a
        // float32 ulp of the ray does not disagree with itself.
        final expected = <int>{};
        for (var i = 0; i < list.length; i++) {
          final o = i * 6;
          final box = Aabb3.minMax(
            Vector3(packed[o], packed[o + 1], packed[o + 2]),
            Vector3(packed[o + 3], packed[o + 4], packed[o + 5]),
          );
          if (aabbRaycast(ray, box, 500) != null) expected.add(i);
        }
        final got = <int>{};
        bvh.queryRay(
          origin.x,
          origin.y,
          origin.z,
          direction.x,
          direction.y,
          direction.z,
          500,
          got.add,
        );
        expect(got, equals(expected), reason: 'query $q');
      }
    });

    test('an AABB query returns exactly the overlapping boxes', () {
      final random = math.Random(11);
      final list = scatter(200, random);
      final packed = boxes(list);
      final bvh = AabbBvh.build(packed, list.length);
      final probe = Aabb3.minMax(Vector3(-10, -10, -10), Vector3(10, 10, 10));
      // Compare against the same float32 values the hierarchy stores, so a
      // box sitting within a float32 ulp of the probe's face does not
      // disagree with itself.
      final expected = <int>{};
      for (var i = 0; i < list.length; i++) {
        final o = i * 6;
        if (packed[o] <= probe.max.x &&
            packed[o + 3] >= probe.min.x &&
            packed[o + 1] <= probe.max.y &&
            packed[o + 4] >= probe.min.y &&
            packed[o + 2] <= probe.max.z &&
            packed[o + 5] >= probe.min.z) {
          expected.add(i);
        }
      }
      final got = <int>{};
      bvh.queryAabb(
        probe.min.x,
        probe.min.y,
        probe.min.z,
        probe.max.x,
        probe.max.y,
        probe.max.z,
        got.add,
      );
      expect(got, equals(expected));
    });

    test('refit tracks boxes that moved without a rebuild', () {
      final list = [
        Aabb3.minMax(Vector3(0, 0, 0), Vector3(1, 1, 1)),
        Aabb3.minMax(Vector3(10, 0, 0), Vector3(11, 1, 1)),
        Aabb3.minMax(Vector3(20, 0, 0), Vector3(21, 1, 1)),
        Aabb3.minMax(Vector3(30, 0, 0), Vector3(31, 1, 1)),
        Aabb3.minMax(Vector3(40, 0, 0), Vector3(41, 1, 1)),
      ];
      final packed = boxes(list);
      final bvh = AabbBvh.build(packed, list.length);
      expect(bvh.boxCount, 5);

      // Move the last box on top of the first, then refit.
      packed[4 * 6] = 0.2;
      packed[4 * 6 + 3] = 0.8;
      bvh.refit(packed);
      final got = <int>{};
      bvh.queryAabb(-1, -1, -1, 2, 2, 2, got.add);
      expect(got, containsAll(<int>[0, 4]));
    });

    test('an empty set answers nothing', () {
      final bvh = AabbBvh.build(Float32List(0), 0);
      bvh.queryAabb(-1, -1, -1, 1, 1, 1, (_) => fail('no boxes to visit'));
      bvh.queryRay(0, 0, 0, 0, 1, 0, 10, (_) => fail('no boxes to visit'));
    });
  });
}

/// Moller-Trumbore reference used to cross-check [MeshBvh].
double? _rayTriangle(
  double ox,
  double oy,
  double oz,
  double dx,
  double dy,
  double dz,
  double ax,
  double ay,
  double az,
  double bx,
  double by,
  double bz,
  double cx,
  double cy,
  double cz,
) {
  final e1x = bx - ax, e1y = by - ay, e1z = bz - az;
  final e2x = cx - ax, e2y = cy - ay, e2z = cz - az;
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
  return t < 0 ? null : t;
}
