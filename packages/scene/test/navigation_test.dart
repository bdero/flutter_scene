// End-to-end nav mesh tests: bake a level, then ask the questions a game asks.

import 'dart:typed_data';

import 'package:scene/navigation.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void addFloor(
  NavGeometryBuilder builder,
  double minX,
  double minZ,
  double maxX,
  double maxZ, {
  double y = 0,
  int area = NavArea.nonWalkable,
}) {
  builder.addMesh(
    positions: [minX, y, minZ, maxX, y, minZ, maxX, y, maxZ, minX, y, maxZ],
    triangleIndices: const [0, 2, 1, 0, 3, 2],
    area: area,
  );
}

void addWall(
  NavGeometryBuilder builder,
  double x0,
  double z0,
  double x1,
  double z1, {
  double height = 3,
}) {
  builder.addMesh(
    positions: [x0, 0, z0, x1, 0, z1, x1, height, z1, x0, height, z0],
    triangleIndices: const [0, 1, 2, 0, 2, 3],
  );
}

const config = NavMeshConfig(
  cellSize: 0.3,
  cellHeight: 0.2,
  agentRadius: 0.5,
  agentHeight: 2.0,
  agentMaxClimb: 0.5,
);

/// Whether every polygon's neighbour links are symmetric, which is the
/// invariant the search relies on to be able to walk back.
void expectConsistentAdjacency(NavMesh mesh) {
  for (var poly = 0; poly < mesh.polygonCount; poly++) {
    final count = mesh.vertexCountOf(poly);
    expect(count, greaterThanOrEqualTo(3));
    for (var edge = 0; edge < count; edge++) {
      final neighbour = mesh.neighbourOf(poly, edge);
      if (neighbour == navNoPolygon) continue;
      expect(neighbour, inInclusiveRange(0, mesh.polygonCount - 1));
      expect(
        mesh.edgeTo(neighbour, poly),
        isNot(-1),
        reason: 'polygon $poly links to $neighbour but not the other way',
      );
    }
  }
}

void main() {
  group('baking', () {
    test('an empty world bakes to nothing rather than throwing', () {
      expect(buildNavMesh(NavGeometryBuilder().build(), config), isNull);
    });

    test('an open room bakes to a walkable mesh', () {
      final builder = NavGeometryBuilder();
      addFloor(builder, 0, 0, 20, 20);
      final mesh = buildNavMesh(builder.build(), config)!;

      expect(mesh.polygonCount, greaterThan(0));
      expectConsistentAdjacency(mesh);

      // The mesh covers the room, pulled in by the agent radius on every side.
      final centre = mesh.findPolygon(Vector3(10, 0, 10));
      expect(centre, isNot(navNoPolygon));
      // Just outside the wall is off the mesh.
      expect(mesh.findPolygon(Vector3(25, 0, 10)), navNoPolygon);
    });

    test('the surface is eroded by the agent radius', () {
      final builder = NavGeometryBuilder();
      addFloor(builder, 0, 0, 20, 20);
      final mesh = buildNavMesh(builder.build(), config)!;

      // A point a hand's width from the wall is closer than the agent's
      // radius, so no polygon covers it. findPolygon's default search box is
      // generous on purpose, snapping an agent nudged off the mesh back onto
      // it, so this asks with a tight one to see the surface itself.
      final tight = Vector3(0.05, 0.5, 0.05);
      expect(
        mesh.findPolygon(Vector3(0.1, 0, 10), halfExtents: tight),
        navNoPolygon,
      );
      final inside = mesh.findPolygon(Vector3(1.5, 0, 10), halfExtents: tight);
      expect(inside, isNot(navNoPolygon));
      expect(mesh.containsXZ(inside, 1.5, 10), isTrue);

      // The generous default is what snaps that same off-mesh point back.
      expect(mesh.findPolygon(Vector3(0.1, 0, 10)), isNot(navNoPolygon));
    });

    test('a bake reports every stage it runs', () {
      final builder = NavGeometryBuilder();
      addFloor(builder, 0, 0, 10, 10);
      final stages = <NavBakeStage>[];
      buildNavMesh(builder.build(), config, onStage: stages.add);
      expect(stages, NavBakeStage.values);
    });
  });

  group('pathfinding', () {
    test('a straight run across open ground is a straight line', () {
      final builder = NavGeometryBuilder();
      addFloor(builder, 0, 0, 20, 20);
      final query = NavMeshQuery(buildNavMesh(builder.build(), config)!);

      final path = query.findPath(Vector3(2, 0, 10), Vector3(18, 0, 10));
      expect(path.status, NavPathStatus.complete);
      // The funnel should collapse the corridor to its two endpoints: nothing
      // is in the way, so nothing should bend it.
      expect(path.points, hasLength(2));
      expect(path.length, closeTo(16, 1.0));
    });

    test('a path around a wall bends at the corner, not at every polygon', () {
      // A room split by a wall with a gap at one end.
      final builder = NavGeometryBuilder();
      addFloor(builder, 0, 0, 20, 20);
      addWall(builder, 10, 0, 10, 15);
      final query = NavMeshQuery(buildNavMesh(builder.build(), config)!);

      final path = query.findPath(Vector3(4, 0, 5), Vector3(16, 0, 5));
      expect(path.status, NavPathStatus.complete);

      // It must go round the wall's end, so it is longer than the straight
      // line, and it must be a handful of corners rather than dozens.
      expect(path.length, greaterThan(20));
      expect(path.points.length, lessThan(8));
      expect(path.points.first.x, closeTo(4, 0.6));
      expect(path.points.last.x, closeTo(16, 0.6));

      // Every corner is on the mesh, and no segment crosses the wall below
      // its opening.
      for (final point in path.points) {
        expect(query.mesh.findPolygon(point), isNot(navNoPolygon));
      }
      for (var i = 1; i < path.points.length; i++) {
        final a = path.points[i - 1];
        final b = path.points[i];
        if ((a.x - 10).sign == (b.x - 10).sign) continue;
        final t = (10 - a.x) / (b.x - a.x);
        final crossingZ = a.z + (b.z - a.z) * t;
        expect(
          crossingZ,
          greaterThan(15),
          reason: 'the path crossed the wall instead of going around it',
        );
      }
    });

    test('an unreachable destination gives a partial path, not nothing', () {
      final builder = NavGeometryBuilder();
      addFloor(builder, 0, 0, 10, 10);
      addFloor(builder, 30, 0, 40, 10);
      final query = NavMeshQuery(buildNavMesh(builder.build(), config)!);

      final path = query.findPath(Vector3(5, 0, 5), Vector3(35, 0, 5));
      expect(path.status, NavPathStatus.partial);
      expect(path.points, isNotEmpty);
      // It heads the right way: toward the far island's side of the first.
      expect(path.points.last.x, greaterThan(path.points.first.x));
    });

    test('a path off the mesh entirely fails cleanly', () {
      final builder = NavGeometryBuilder();
      addFloor(builder, 0, 0, 10, 10);
      final query = NavMeshQuery(buildNavMesh(builder.build(), config)!);

      final path = query.findPath(Vector3(5, 0, 5), Vector3(500, 0, 500));
      expect(path.status, NavPathStatus.failed);
      expect(path.isEmpty, isTrue);
    });

    test('start and end in one polygon needs no search', () {
      final builder = NavGeometryBuilder();
      addFloor(builder, 0, 0, 20, 20);
      final query = NavMeshQuery(buildNavMesh(builder.build(), config)!);

      final path = query.findPath(Vector3(10, 0, 10), Vector3(10.5, 0, 10.5));
      expect(path.status, NavPathStatus.complete);
      expect(path.polygons, hasLength(1));
    });

    test('area costs steer a path around expensive ground', () {
      // A corridor whose middle third is marked slow. Going around costs
      // distance; going through costs the multiplier.
      final builder = NavGeometryBuilder();
      addFloor(builder, 0, 0, 30, 6, area: NavArea.walkable);
      addFloor(builder, 0, 6, 30, 14, area: NavArea.slow, y: 0);
      final mesh = buildNavMesh(builder.build(), config)!;

      final cheap = NavMeshQuery(mesh)..areaCosts[NavArea.slow] = 1.0;
      final expensive = NavMeshQuery(mesh)..areaCosts[NavArea.slow] = 50.0;

      final start = Vector3(2, 0, 12);
      final end = Vector3(28, 0, 12);
      final cheapPath = cheap.findPath(start, end);
      final expensivePath = expensive.findPath(start, end);

      expect(cheapPath.status, NavPathStatus.complete);
      expect(expensivePath.status, NavPathStatus.complete);
      // The expensive run should spend fewer of its polygons in the slow area.
      int slowPolys(NavPath path) =>
          path.polygons.where((p) => mesh.areas[p] == NavArea.slow).length;
      expect(slowPolys(expensivePath), lessThanOrEqualTo(slowPolys(cheapPath)));
    });
  });

  group('awkward shapes', () {
    test('a pillar in the middle of a room becomes a hole, not a lie', () {
      // The region wraps the pillar, so its trace is two loops and the hole
      // has to be spliced into the outline before anything can triangulate it.
      final builder = NavGeometryBuilder();
      addFloor(builder, 0, 0, 20, 20);
      addWall(builder, 9, 9, 11, 9);
      addWall(builder, 11, 9, 11, 11);
      addWall(builder, 11, 11, 9, 11);
      addWall(builder, 9, 11, 9, 9);
      final mesh = buildNavMesh(builder.build(), config)!;

      expectConsistentAdjacency(mesh);
      // The pillar's own footprint must not be walkable.
      expect(
        mesh.findPolygon(
          Vector3(10, 0, 10),
          halfExtents: Vector3(0.05, 0.5, 0.05),
        ),
        navNoPolygon,
        reason: 'the mesh should have a hole where the pillar is',
      );

      // And a path from one side to the other must go round it.
      final query = NavMeshQuery(mesh);
      final path = query.findPath(Vector3(4, 0, 10), Vector3(16, 0, 10));
      expect(path.status, NavPathStatus.complete);
      expect(
        path.length,
        greaterThan(12.2),
        reason: 'a straight line would pass through the pillar',
      );
      for (final point in path.points) {
        final insidePillar =
            point.x > 8.4 && point.x < 11.6 && point.z > 8.4 && point.z < 11.6;
        expect(insidePillar, isFalse);
      }
    });

    test('a ramp connects two levels and a path uses it', () {
      // A low floor, a high floor, and a ramp between them. Nothing else
      // joins the two, so a complete path proves the climb was walkable.
      final builder = NavGeometryBuilder();
      addFloor(builder, 0, 0, 10, 10);
      addFloor(builder, 16, 0, 26, 10, y: 3);
      builder.addMesh(
        positions: [10, 0, 2, 16, 3, 2, 16, 3, 8, 10, 0, 8],
        triangleIndices: const [0, 2, 1, 0, 3, 2],
      );
      final query = NavMeshQuery(buildNavMesh(builder.build(), config)!);

      final path = query.findPath(Vector3(5, 0, 5), Vector3(21, 3, 5));
      expect(path.status, NavPathStatus.complete);
      expect(path.points.first.y, closeTo(0, 0.6));
      expect(path.points.last.y, closeTo(3, 0.6));
    });

    test('a step taller than the agent can climb is not connected', () {
      final builder = NavGeometryBuilder();
      addFloor(builder, 0, 0, 10, 10);
      // Flush against it, but 3 units up: far beyond agentMaxClimb.
      addFloor(builder, 10, 0, 20, 10, y: 3);
      final query = NavMeshQuery(buildNavMesh(builder.build(), config)!);

      final path = query.findPath(Vector3(5, 0, 5), Vector3(15, 3, 5));
      expect(
        path.status,
        NavPathStatus.partial,
        reason: 'an agent that cannot climb 3 units must not path up one',
      );
    });
  });

  group('raycast', () {
    test('an unobstructed line reaches its destination', () {
      final builder = NavGeometryBuilder();
      addFloor(builder, 0, 0, 20, 20);
      final query = NavMeshQuery(buildNavMesh(builder.build(), config)!);

      final (point, reached) = query.raycast(
        Vector3(3, 0, 10),
        Vector3(17, 0, 10),
      );
      expect(reached, isTrue);
      expect(point.x, closeTo(17, 0.01));
    });

    test('a line into a wall stops at it', () {
      final builder = NavGeometryBuilder();
      addFloor(builder, 0, 0, 20, 20);
      addWall(builder, 10, 0, 10, 20);
      final query = NavMeshQuery(buildNavMesh(builder.build(), config)!);

      final (point, reached) = query.raycast(
        Vector3(3, 0, 10),
        Vector3(17, 0, 10),
      );
      expect(reached, isFalse);
      expect(
        point.x,
        lessThan(10),
        reason: 'it must stop on this side of the wall',
      );
      expect(point.x, greaterThan(3));
    });
  });

  group('serialization', () {
    test('a mesh round-trips through its binary form', () {
      final builder = NavGeometryBuilder();
      addFloor(builder, 0, 0, 20, 20);
      addWall(builder, 10, 0, 10, 15);
      final original = buildNavMesh(builder.build(), config)!;

      final restored = decodeNavMesh(encodeNavMesh(original));

      expect(restored.polygonCount, original.polygonCount);
      expect(restored.vertices, original.vertices);
      expect(restored.polygonVertices, original.polygonVertices);
      expect(restored.polygonStart, original.polygonStart);
      expect(restored.neighbours, original.neighbours);
      expect(restored.areas, original.areas);
      expect(restored.regions, original.regions);
      expect(restored.config.agentRadius, config.agentRadius);
      expect(restored.config.cellSize, config.cellSize);
      expectConsistentAdjacency(restored);

      // And it answers the same question the same way.
      final before = NavMeshQuery(
        original,
      ).findPath(Vector3(4, 0, 5), Vector3(16, 0, 5));
      final after = NavMeshQuery(
        restored,
      ).findPath(Vector3(4, 0, 5), Vector3(16, 0, 5));
      expect(after.status, before.status);
      expect(after.length, closeTo(before.length, 1e-3));
    });

    test('a wrong magic or version is rejected, not misread', () {
      final builder = NavGeometryBuilder();
      addFloor(builder, 0, 0, 10, 10);
      final bytes = encodeNavMesh(buildNavMesh(builder.build(), config)!);

      final badMagic = Uint8List.fromList(bytes)..[0] = 0;
      expect(() => decodeNavMesh(badMagic), throwsFormatException);

      final badVersion = Uint8List.fromList(bytes)..[4] = 99;
      expect(() => decodeNavMesh(badVersion), throwsFormatException);

      expect(
        () => decodeNavMesh(Uint8List.fromList(bytes.sublist(0, 40))),
        throwsFormatException,
      );
    });
  });
}
