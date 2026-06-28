// Covers the procedural primitive generators: cuboid, plane, and
// sphere vertex/index arrays. Pure logic, so these run without a
// Flutter GPU context; constructing the geometry classes themselves
// uploads to the GPU and is exercised by the example app.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/geometry/primitives.dart';
import 'package:flutter_scene/src/physics/shape.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// Right-hand-rule normal of a triangle. The engine treats the side
// opposite this normal as the front face.
Vector3 triangleNormal(Float32List positions, List<int> indices, int triangle) {
  Vector3 at(int v) =>
      Vector3(positions[v * 3], positions[v * 3 + 1], positions[v * 3 + 2]);
  final a = at(indices[triangle * 3]);
  final b = at(indices[triangle * 3 + 1]);
  final c = at(indices[triangle * 3 + 2]);
  return (b - a).cross(c - a);
}

// Asserts every (non-degenerate) triangle is wound so its front face points
// outward, i.e. the right-hand-rule geometric normal opposes the stored
// per-vertex shading normals (the engine's front-face convention).
void expectOutwardWinding(PrimitiveArrays arrays) {
  final positions = arrays.positions;
  final normals = arrays.normals!;
  final indices = arrays.indices;
  Vector3 shadingAt(int v) =>
      Vector3(normals[v * 3], normals[v * 3 + 1], normals[v * 3 + 2]);
  for (var tri = 0; tri < indices.length ~/ 3; tri++) {
    final geo = triangleNormal(positions, indices, tri);
    // Skip degenerate triangles (zero area, e.g. at a cone apex or pole).
    if (geo.length < 1e-9) continue;
    final avg =
        shadingAt(indices[tri * 3]) +
        shadingAt(indices[tri * 3 + 1]) +
        shadingAt(indices[tri * 3 + 2]);
    expect(geo.dot(avg), lessThan(0), reason: 'triangle $tri is inside-out');
  }
}

void expectUnitNormals(PrimitiveArrays arrays) {
  final normals = arrays.normals!;
  for (var v = 0; v < normals.length ~/ 3; v++) {
    final n = Vector3(normals[v * 3], normals[v * 3 + 1], normals[v * 3 + 2]);
    expect(n.length, closeTo(1, 1e-5));
  }
}

void main() {
  group('buildCuboidArrays', () {
    test(
      'produces 24 per-face vertices, 12 triangles, flat outward normals',
      () {
        final arrays = buildCuboidArrays(Vector3(2, 2, 2));
        expect(arrays.positions, hasLength(24 * 3));
        expect(arrays.normals, hasLength(24 * 3));
        expect(arrays.indices, hasLength(12 * 3));
        // No vertex colors unless explicitly requested.
        expect(arrays.colors, isNull);
        // The first vertex sits at -extents/2 on each axis.
        expect(arrays.positions.sublist(0, 3), [-1, -1, -1]);

        // Each of the six faces shares one axis-aligned unit normal across its
        // four vertices, and both its triangles are wound so the front face
        // points opposite that normal (the engine's front-face convention),
        // i.e. the stored normal faces outward.
        final normals = arrays.normals!;
        for (var f = 0; f < 6; f++) {
          final base = f * 4;
          final n = Vector3(
            normals[base * 3],
            normals[base * 3 + 1],
            normals[base * 3 + 2],
          );
          expect(n.length, closeTo(1, 1e-6));
          for (var i = 1; i < 4; i++) {
            final v = base + i;
            expect(normals[v * 3], n.x);
            expect(normals[v * 3 + 1], n.y);
            expect(normals[v * 3 + 2], n.z);
          }
          expect(
            triangleNormal(arrays.positions, arrays.indices, f * 2).dot(n),
            lessThan(0),
          );
          expect(
            triangleNormal(arrays.positions, arrays.indices, f * 2 + 1).dot(n),
            lessThan(0),
          );
        }
      },
    );

    test('debugColors emits one color per vertex', () {
      final arrays = buildCuboidArrays(Vector3(2, 2, 2), debugColors: true);
      expect(arrays.colors, hasLength(24 * 4));
    });
  });

  group('buildPlaneArrays', () {
    test('a single-segment plane is one quad facing +Y', () {
      final arrays = buildPlaneArrays(
        width: 2,
        depth: 4,
        segmentsX: 1,
        segmentsZ: 1,
      );
      expect(arrays.positions, hasLength(4 * 3));
      expect(arrays.indices, hasLength(6));
      for (var v = 0; v < 4; v++) {
        expect(arrays.normals!.sublist(v * 3, v * 3 + 3), [0, 1, 0]);
        // The surface lies in the y == 0 plane.
        expect(arrays.positions[v * 3 + 1], 0);
      }
    });

    test('subdivision sets the vertex and index counts', () {
      final arrays = buildPlaneArrays(
        width: 1,
        depth: 1,
        segmentsX: 3,
        segmentsZ: 2,
      );
      expect(arrays.positions, hasLength((3 + 1) * (2 + 1) * 3));
      expect(arrays.indices, hasLength(3 * 2 * 6));
    });

    test('rejects a plane with no segments', () {
      expect(
        () => buildPlaneArrays(width: 1, depth: 1, segmentsX: 0, segmentsZ: 1),
        throwsArgumentError,
      );
    });

    test('triangles are wound so the surface faces +Y', () {
      final arrays = buildPlaneArrays(
        width: 2,
        depth: 2,
        segmentsX: 1,
        segmentsZ: 1,
      );
      // A +Y-facing surface has a -Y geometric normal.
      expect(
        triangleNormal(arrays.positions, arrays.indices, 0).y,
        lessThan(0),
      );
    });
  });

  group('buildSphereArrays', () {
    test('vertex and index counts follow the tessellation', () {
      final arrays = buildSphereArrays(radius: 1, segments: 8, rings: 4);
      expect(arrays.positions, hasLength((8 + 1) * (4 + 1) * 3));
      expect(arrays.indices, hasLength(8 * 4 * 6));
    });

    test('normals are unit length and positions lie on the radius', () {
      final arrays = buildSphereArrays(radius: 2, segments: 12, rings: 6);
      final count = arrays.positions.length ~/ 3;
      for (var v = 0; v < count; v++) {
        final nx = arrays.normals![v * 3];
        final ny = arrays.normals![v * 3 + 1];
        final nz = arrays.normals![v * 3 + 2];
        expect(math.sqrt(nx * nx + ny * ny + nz * nz), closeTo(1, 1e-5));
        final px = arrays.positions[v * 3];
        final py = arrays.positions[v * 3 + 1];
        final pz = arrays.positions[v * 3 + 2];
        expect(math.sqrt(px * px + py * py + pz * pz), closeTo(2, 1e-4));
      }
    });

    test('rejects a degenerate tessellation', () {
      expect(
        () => buildSphereArrays(radius: 1, segments: 2, rings: 4),
        throwsArgumentError,
      );
      expect(
        () => buildSphereArrays(radius: 1, segments: 8, rings: 1),
        throwsArgumentError,
      );
    });
  });

  group('buildCylinderArrays', () {
    PrimitiveArrays cylinder({
      double bottomRadius = 1,
      double topRadius = 1,
      double height = 2,
      int radialSegments = 8,
      int heightSegments = 1,
      bool bottomCap = true,
      bool topCap = true,
    }) => buildCylinderArrays(
      bottomRadius: bottomRadius,
      topRadius: topRadius,
      height: height,
      radialSegments: radialSegments,
      heightSegments: heightSegments,
      bottomCap: bottomCap,
      topCap: topCap,
    );

    test('side spans the requested height and radius', () {
      final arrays = cylinder(bottomRadius: 2, topRadius: 2, height: 4);
      var minY = double.infinity;
      var maxY = -double.infinity;
      for (var v = 0; v < arrays.positions.length ~/ 3; v++) {
        final y = arrays.positions[v * 3 + 1];
        minY = math.min(minY, y);
        maxY = math.max(maxY, y);
      }
      expect(minY, closeTo(-2, 1e-6));
      expect(maxY, closeTo(2, 1e-6));
      // A side vertex sits at the radius from the Y axis.
      final px = arrays.positions[0];
      final pz = arrays.positions[2];
      expect(math.sqrt(px * px + pz * pz), closeTo(2, 1e-6));
    });

    test('caps can be omitted and a zero top radius makes a cone', () {
      final capped = cylinder();
      final open = cylinder(bottomCap: false, topCap: false);
      expect(open.indices.length, lessThan(capped.indices.length));
      // A cone has no top cap even when topCap is requested.
      final cone = cylinder(topRadius: 0);
      final coneCapped = cylinder(topRadius: 0, topCap: false);
      expect(cone.indices.length, coneCapped.indices.length);
    });

    test('normals are unit length and wound outward (cylinder and cone)', () {
      expectUnitNormals(cylinder());
      expectOutwardWinding(cylinder());
      expectOutwardWinding(cylinder(topRadius: 0));
      expectOutwardWinding(cylinder(bottomRadius: 0.5, topRadius: 2));
    });

    test('rejects degenerate parameters', () {
      expect(() => cylinder(radialSegments: 2), throwsArgumentError);
      expect(() => cylinder(heightSegments: 0), throwsArgumentError);
      expect(
        () => cylinder(bottomRadius: 0, topRadius: 0),
        throwsArgumentError,
      );
    });
  });

  group('buildCapsuleArrays', () {
    test('total extent is height plus two radii', () {
      final arrays = buildCapsuleArrays(
        radius: 0.5,
        height: 2,
        radialSegments: 12,
        capRings: 4,
      );
      var minY = double.infinity;
      var maxY = -double.infinity;
      for (var v = 0; v < arrays.positions.length ~/ 3; v++) {
        final y = arrays.positions[v * 3 + 1];
        minY = math.min(minY, y);
        maxY = math.max(maxY, y);
      }
      expect(maxY, closeTo(1.5, 1e-6));
      expect(minY, closeTo(-1.5, 1e-6));
    });

    test('every surface point is within the capsule radius of its axis', () {
      const radius = 0.75;
      const height = 2.0;
      final arrays = buildCapsuleArrays(
        radius: radius,
        height: height,
        radialSegments: 16,
        capRings: 6,
      );
      for (var v = 0; v < arrays.positions.length ~/ 3; v++) {
        final x = arrays.positions[v * 3];
        final y = arrays.positions[v * 3 + 1];
        final z = arrays.positions[v * 3 + 2];
        // Distance to the capsule's segment (the Y axis clamped to the
        // cylinder section) equals the radius on the surface.
        final clampedY = y.clamp(-height / 2, height / 2);
        final dy = y - clampedY;
        expect(math.sqrt(x * x + z * z + dy * dy), closeTo(radius, 1e-4));
      }
    });

    test('normals are unit length and wound outward', () {
      final arrays = buildCapsuleArrays(
        radius: 0.5,
        height: 1.5,
        radialSegments: 12,
        capRings: 4,
      );
      expectUnitNormals(arrays);
      expectOutwardWinding(arrays);
    });

    test('rejects degenerate parameters', () {
      expect(
        () => buildCapsuleArrays(
          radius: 0,
          height: 1,
          radialSegments: 8,
          capRings: 2,
        ),
        throwsArgumentError,
      );
      expect(
        () => buildCapsuleArrays(
          radius: 1,
          height: 1,
          radialSegments: 2,
          capRings: 2,
        ),
        throwsArgumentError,
      );
    });
  });

  group('buildTorusArrays', () {
    test('points lie on the tube and counts follow the tessellation', () {
      const radius = 1.0;
      const tube = 0.25;
      const radial = 10;
      const tubular = 6;
      final arrays = buildTorusArrays(
        radius: radius,
        tubeRadius: tube,
        radialSegments: radial,
        tubularSegments: tubular,
      );
      expect(arrays.positions, hasLength((radial + 1) * (tubular + 1) * 3));
      expect(arrays.indices, hasLength(radial * tubular * 6));
      for (var v = 0; v < arrays.positions.length ~/ 3; v++) {
        final x = arrays.positions[v * 3];
        final y = arrays.positions[v * 3 + 1];
        final z = arrays.positions[v * 3 + 2];
        // Distance from the tube centerline circle equals the tube radius.
        final ringDist = math.sqrt(x * x + z * z) - radius;
        expect(math.sqrt(ringDist * ringDist + y * y), closeTo(tube, 1e-5));
      }
    });

    test('normals are unit length and wound outward', () {
      final arrays = buildTorusArrays(
        radius: 1,
        tubeRadius: 0.3,
        radialSegments: 12,
        tubularSegments: 8,
      );
      expectUnitNormals(arrays);
      expectOutwardWinding(arrays);
    });

    test('rejects degenerate parameters', () {
      expect(
        () => buildTorusArrays(
          radius: 1,
          tubeRadius: 0.2,
          radialSegments: 2,
          tubularSegments: 8,
        ),
        throwsArgumentError,
      );
    });
  });

  group('buildDiscArrays and buildRingArrays', () {
    test('a disc is a +Y-facing fan within its radius', () {
      final arrays = buildDiscArrays(radius: 2, segments: 8);
      expect(arrays.indices, hasLength(8 * 3));
      for (var v = 0; v < arrays.positions.length ~/ 3; v++) {
        expect(arrays.positions[v * 3 + 1], 0);
        expect(arrays.normals!.sublist(v * 3, v * 3 + 3), [0, 1, 0]);
      }
      // Front face points +Y, so the geometric normal points -Y.
      expect(
        triangleNormal(arrays.positions, arrays.indices, 0).y,
        lessThan(0),
      );
    });

    test('a ring spans inner to outer radius and faces +Y', () {
      const inner = 0.5;
      const outer = 1.5;
      final arrays = buildRingArrays(
        innerRadius: inner,
        outerRadius: outer,
        segments: 12,
      );
      var minR = double.infinity;
      var maxR = -double.infinity;
      for (var v = 0; v < arrays.positions.length ~/ 3; v++) {
        final x = arrays.positions[v * 3];
        final z = arrays.positions[v * 3 + 2];
        final r = math.sqrt(x * x + z * z);
        minR = math.min(minR, r);
        maxR = math.max(maxR, r);
      }
      expect(minR, closeTo(inner, 1e-6));
      expect(maxR, closeTo(outer, 1e-6));
      expectOutwardWinding(arrays);
    });

    test('reject degenerate parameters', () {
      expect(
        () => buildDiscArrays(radius: 1, segments: 2),
        throwsArgumentError,
      );
      expect(
        () => buildRingArrays(innerRadius: 1, outerRadius: 0.5, segments: 8),
        throwsArgumentError,
      );
    });
  });

  group('buildIcosphereArrays', () {
    test('subdivision quadruples the face count from 20', () {
      expect(
        buildIcosphereArrays(radius: 1, subdivisions: 0).indices,
        hasLength(20 * 3),
      );
      expect(
        buildIcosphereArrays(radius: 1, subdivisions: 1).indices,
        hasLength(80 * 3),
      );
      expect(
        buildIcosphereArrays(radius: 1, subdivisions: 2).indices,
        hasLength(320 * 3),
      );
    });

    test('all points lie on the sphere and faces wind outward', () {
      final arrays = buildIcosphereArrays(radius: 2, subdivisions: 2);
      for (var v = 0; v < arrays.positions.length ~/ 3; v++) {
        final x = arrays.positions[v * 3];
        final y = arrays.positions[v * 3 + 1];
        final z = arrays.positions[v * 3 + 2];
        expect(math.sqrt(x * x + y * y + z * z), closeTo(2, 1e-5));
      }
      expectUnitNormals(arrays);
      expectOutwardWinding(arrays);
    });

    test('rejects negative subdivisions', () {
      expect(
        () => buildIcosphereArrays(radius: 1, subdivisions: -1),
        throwsArgumentError,
      );
    });
  });

  group('collision shape bridge', () {
    test('a cuboid maps to a box of half its extents', () {
      final shape = cuboidCollisionShape(Vector3(2, 4, 6));
      expect(shape, isA<BoxShape>());
      expect((shape as BoxShape).halfExtents, Vector3(1, 2, 3));
    });

    test('a capsule keeps its radius and half mid-section height', () {
      final shape = capsuleCollisionShape(radius: 0.5, height: 2);
      expect(shape, isA<CapsuleShape>());
      expect((shape as CapsuleShape).radius, 0.5);
      // halfHeight is half the mid-section, excluding the caps.
      expect(shape.halfHeight, 1.0);
    });

    test('an equal-radius cylinder maps to a cylinder shape', () {
      final shape = cylinderCollisionShape(
        bottomRadius: 1,
        topRadius: 1,
        height: 3,
        radialSegments: 8,
      );
      expect(shape, isA<CylinderShape>());
      expect((shape as CylinderShape).radius, 1);
      expect(shape.halfHeight, 1.5);
    });

    test('a cone maps to a convex hull of its base ring plus the apex', () {
      final shape = cylinderCollisionShape(
        bottomRadius: 1,
        topRadius: 0,
        height: 2,
        radialSegments: 8,
      );
      expect(shape, isA<ConvexHullShape>());
      // 8 base-ring points plus a single apex point, xyz each.
      expect((shape as ConvexHullShape).points, hasLength((8 + 1) * 3));
    });

    test('a wedge maps to the convex hull of its six corners', () {
      final shape = wedgeCollisionShape(Vector3(2, 1, 2));
      expect(shape, isA<ConvexHullShape>());
      expect((shape as ConvexHullShape).points, hasLength(6 * 3));
    });

    test('a torus maps to a compound of convex chunks around the ring', () {
      final shape = torusCollisionShape(
        radius: 1,
        tubeRadius: 0.25,
        segments: 12,
        tubularSegments: 6,
      );
      expect(shape, isA<CompoundShape>());
      final children = (shape as CompoundShape).children;
      expect(children, hasLength(12));
      // Each chunk is the convex hull of two tube cross-sections.
      final first = children.first.shape;
      expect(first, isA<ConvexHullShape>());
      expect((first as ConvexHullShape).points, hasLength(2 * 6 * 3));
      // The chunks leave the hole open: no point sits at the center.
      for (final child in children) {
        final pts = (child.shape as ConvexHullShape).points;
        for (var i = 0; i < pts.length; i += 3) {
          final r = math.sqrt(pts[i] * pts[i] + pts[i + 2] * pts[i + 2]);
          expect(r, greaterThan(0.7)); // radius - tubeRadius
        }
      }
    });

    test('a disc maps to a thin cylinder', () {
      final shape = discCollisionShape(radius: 1.5);
      expect(shape, isA<CylinderShape>());
      final cylinder = shape as CylinderShape;
      expect(cylinder.radius, 1.5);
      expect(cylinder.halfHeight, lessThan(0.2)); // thin coin
    });

    test('a ring maps to a compound of thin segments around the hole', () {
      final shape = ringCollisionShape(
        innerRadius: 0.5,
        outerRadius: 1,
        segments: 10,
      );
      expect(shape, isA<CompoundShape>());
      final children = (shape as CompoundShape).children;
      expect(children, hasLength(10));
      // Each segment is an 8-point extruded convex hull, and none reach the
      // hole (radius below innerRadius).
      for (final child in children) {
        expect(child.shape, isA<ConvexHullShape>());
        final pts = (child.shape as ConvexHullShape).points;
        expect(pts, hasLength(8 * 3));
        for (var i = 0; i < pts.length; i += 3) {
          final r = math.sqrt(pts[i] * pts[i] + pts[i + 2] * pts[i + 2]);
          expect(r, greaterThanOrEqualTo(0.5 - 1e-9));
        }
      }
    });
  });
}
