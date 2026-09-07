// Tiled nav baking. The load-bearing property is the seam: a tiled bake has
// to be crossable where a single-shot bake would have been, or tiling is a
// way of producing a world that looks navigable and is not.

import 'dart:typed_data';

import 'package:scene/navigation.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const _config = NavMeshConfig(
  cellSize: 0.3,
  cellHeight: 0.2,
  agentRadius: 0.4,
  agentHeight: 1.8,
);

/// A flat floor spanning [size] x [size], centred on the origin.
NavGeometry floor(double size) {
  final half = size / 2;
  final builder = NavGeometryBuilder();
  builder.addMesh(
    positions: [
      -half, 0, -half, //
      half, 0, -half, //
      half, 0, half, //
      -half, 0, half,
    ],
    triangleIndices: [0, 2, 1, 0, 3, 2],
    area: NavArea.walkable,
  );
  return builder.build();
}

/// A floor with a wall across the middle, leaving a gap at the centre.
NavGeometry floorWithWall(double size, {double gap = 4}) {
  final half = size / 2;
  final builder = NavGeometryBuilder();
  builder.addMesh(
    positions: [
      -half, 0, -half, //
      half, 0, -half, //
      half, 0, half, //
      -half, 0, half,
    ],
    triangleIndices: [0, 2, 1, 0, 3, 2],
    area: NavArea.walkable,
  );
  for (final side in [-1.0, 1.0]) {
    final from = side < 0 ? -half : gap / 2;
    final to = side < 0 ? -gap / 2 : half;
    builder.addMesh(
      positions: [0, 0, from, 0, 0, to, 0, 3, to, 0, 3, from],
      triangleIndices: [0, 1, 2, 0, 2, 3],
    );
  }
  return builder.build();
}

/// The walkable area a mesh covers, by the shoelace formula over its
/// polygons. Tiling must preserve this even though it changes the polygons.
double areaOf(NavMesh mesh) {
  var total = 0.0;
  for (var poly = 0; poly < mesh.polygonCount; poly++) {
    final corners = mesh.vertexCountOf(poly);
    var sum = 0.0;
    for (var i = 0; i < corners; i++) {
      final a = mesh.vertexOf(poly, i) * 3;
      final b = mesh.vertexOf(poly, (i + 1) % corners) * 3;
      sum +=
          mesh.vertices[a] * mesh.vertices[b + 2] -
          mesh.vertices[b] * mesh.vertices[a + 2];
    }
    total += sum.abs() * 0.5;
  }
  return total;
}

void main() {
  group('planning', () {
    test('a world is cut into the tiles it spans', () {
      const tiling = NavTileConfig(tileCells: 32);
      final jobs = planNavTileBake(floor(40), _config, tiling: tiling);
      final xs = {for (final job in jobs) job.key.x};
      final zs = {for (final job in jobs) job.key.z};
      expect(jobs.length, greaterThan(9));
      expect(xs.length, inInclusiveRange(4, 8));
      expect(zs.length, inInclusiveRange(4, 8));
    });

    test('a ground plane is clipped, not copied, into every tile', () {
      const tiling = NavTileConfig(tileCells: 32);
      final jobs = planNavTileBake(floor(60), _config, tiling: tiling);
      final tileSize = tiling.tileSize(_config);
      final margin = tiling.borderFor(_config) * _config.cellSize;
      for (final job in jobs) {
        final bounds = job.geometry.bounds!;
        expect(
          bounds.$2.x - bounds.$1.x,
          lessThan(tileSize + margin * 2 + _config.cellSize),
          reason: 'tile ${job.key} pulled in more than its own square',
        );
      }
    });

    test('empty geometry plans nothing rather than throwing', () {
      final empty = NavGeometryBuilder().build();
      expect(planNavTileBake(empty, _config), isEmpty);
      expect(navTileRange(empty, _config, const NavTileConfig()), isNull);
    });

    test('the origin shifts the grid, so two runs agree on it', () {
      final shifted = planNavTileBake(
        floor(40),
        _config,
        tiling: const NavTileConfig(tileCells: 32),
        origin: Vector3(100, 0, 100),
      );
      expect(shifted, isNotEmpty);
      expect(
        shifted.every((job) => job.key.x < 0 && job.key.z < 0),
        isTrue,
        reason: 'a world at the origin lands in negative tiles, not shifted',
      );
    });
  });

  group('a tiled bake', () {
    test('covers the floor and reports what it did', () {
      final result = bakeNavMeshTiled(
        floor(30),
        _config,
        tiling: const NavTileConfig(tileCells: 32),
      );
      expect(result.tiles.tileCount, greaterThan(1));
      expect(result.tiles.polygonCount, greaterThan(0));
      expect(result.describe(), contains('polygons across'));
    });

    test('reports progress tile by tile', () {
      final seen = <int>[];
      var total = 0;
      bakeNavMeshTiled(
        floor(30),
        _config,
        tiling: const NavTileConfig(tileCells: 32),
        onProgress: (done, all) {
          seen.add(done);
          total = all;
        },
      );
      expect(seen, List.generate(total, (i) => i + 1));
    });

    test('every tile links to the neighbours it shares ground with', () {
      final set = bakeNavMeshTiled(
        floor(30),
        _config,
        tiling: const NavTileConfig(tileCells: 32),
      ).tiles;
      var linked = 0;
      for (final key in set.tiles) {
        if (set.linksFrom(key).isNotEmpty) linked++;
      }
      expect(
        linked,
        set.tileCount,
        reason: 'flat open ground: every tile borders another',
      );
    });

    test('links point at tiles that exist and are reciprocated', () {
      final set = bakeNavMeshTiled(
        floor(30),
        _config,
        tiling: const NavTileConfig(tileCells: 32),
      ).tiles;
      for (final key in set.tiles) {
        for (final link in set.linksFrom(key)) {
          expect(set.tile(link.to.tile), isNotNull);
          expect(link.from.tile, key);
          expect(
            set.linksFrom(link.to.tile).any((back) => back.to.tile == key),
            isTrue,
            reason: '$key -> ${link.to.tile} has no return',
          );
        }
      }
    });
  });

  group('crossing a seam', () {
    test('a path runs corner to corner across many tiles', () {
      final set = bakeNavMeshTiled(
        floor(40),
        _config,
        tiling: const NavTileConfig(tileCells: 24),
      ).tiles;
      final path = NavTileMeshQuery(
        set,
      ).findPath(Vector3(-17, 0, -17), Vector3(17, 0, 17));

      expect(path.status, NavPathStatus.complete);
      expect(
        {for (final poly in path.polygons) poly.tile}.length,
        greaterThan(2),
        reason: 'the route should pass through several tiles',
      );
      expect(path.points.last.x, closeTo(17, 2));
      expect(path.points.last.z, closeTo(17, 2));
    });

    test('the route is continuous: no jumps between corners', () {
      final set = bakeNavMeshTiled(
        floor(40),
        _config,
        tiling: const NavTileConfig(tileCells: 24),
      ).tiles;
      final path = NavTileMeshQuery(
        set,
      ).findPath(Vector3(-17, 0, -17), Vector3(17, 0, 17));
      for (var i = 1; i < path.points.length; i++) {
        expect(
          path.points[i].distanceTo(path.points[i - 1]),
          lessThan(_config.cellSize * 40),
          reason: 'corner $i teleports; a seam link is wrong',
        );
      }
    });

    test('a gap in a wall is still walkable through', () {
      final set = bakeNavMeshTiled(
        floorWithWall(30),
        _config,
        tiling: const NavTileConfig(tileCells: 24),
      ).tiles;
      final path = NavTileMeshQuery(
        set,
      ).findPath(Vector3(-12, 0, 0), Vector3(12, 0, 0));
      expect(path.status, NavPathStatus.complete);
      expect(path.points, isNotEmpty);
    });

    test('a solid wall is not crossable, and the path reports partial', () {
      final builder = NavGeometryBuilder();
      builder.addMesh(
        positions: [-15, 0, -15, 15, 0, -15, 15, 0, 15, -15, 0, 15],
        triangleIndices: [0, 2, 1, 0, 3, 2],
        area: NavArea.walkable,
      );
      builder.addMesh(
        positions: [0, 0, -15, 0, 0, 15, 0, 4, 15, 0, 4, -15],
        triangleIndices: [0, 1, 2, 0, 2, 3],
      );
      final set = bakeNavMeshTiled(
        builder.build(),
        _config,
        tiling: const NavTileConfig(tileCells: 24),
      ).tiles;
      final path = NavTileMeshQuery(
        set,
      ).findPath(Vector3(-12, 0, 0), Vector3(12, 0, 0));
      expect(
        path.status,
        NavPathStatus.partial,
        reason: 'a wall spanning the world cannot be walked through',
      );
    });

    test('a point exactly on a seam still finds a polygon', () {
      const tiling = NavTileConfig(tileCells: 24);
      final set = bakeNavMeshTiled(floor(30), _config, tiling: tiling).tiles;
      final query = NavTileMeshQuery(set);
      final size = tiling.tileSize(_config);
      for (var i = -1; i <= 1; i++) {
        expect(
          query.findPolygon(Vector3(size * i, 0, 0)),
          isNotNull,
          reason: 'nothing found on the boundary at x=${size * i}',
        );
      }
    });
  });

  group('editing one tile', () {
    test('replacing a tile relinks it without disturbing the others', () {
      const tiling = NavTileConfig(tileCells: 24);
      final set = bakeNavMeshTiled(floor(30), _config, tiling: tiling).tiles;
      final key = set.tiles.first;
      final before = set.polygonCount;
      final mesh = set.tile(key)!;

      set.removeTile(key);
      expect(set.tile(key), isNull);
      expect(set.polygonCount, lessThan(before));
      for (final other in set.tiles) {
        for (final link in set.linksFrom(other)) {
          expect(
            link.to.tile,
            isNot(key),
            reason: 'a link survived into a removed tile',
          );
        }
      }

      set.setTile(key, mesh);
      expect(set.polygonCount, before);
      expect(set.linksFrom(key), isNotEmpty);
    });

    test('a tile that bakes to nothing is simply absent', () {
      final set = NavTileSet(config: _config, tiling: const NavTileConfig());
      set.setTile((x: 0, z: 0), null);
      expect(set.tileCount, 0);
      expect(set.linksFrom((x: 0, z: 0)), isEmpty);
    });
  });

  group('tile geometry', () {
    test('bounds and lookup agree on where a tile is', () {
      const tiling = NavTileConfig(tileCells: 32);
      final set = NavTileSet(config: _config, tiling: tiling);
      final size = tiling.tileSize(_config);
      final (min, max) = set.boundsOf((x: 2, z: -1));
      // Vector2 stores float32, so a tile origin tens of cells out carries a
      // little slop; a thousandth of a cell is well inside what matters.
      expect(min.x, closeTo(2 * size, 1e-4));
      expect(min.y, closeTo(-size, 1e-4));
      expect(max.x - min.x, closeTo(size, 1e-4));
      expect(set.tileAt(min.x + size / 2, min.y + size / 2), (x: 2, z: -1));
    });

    test('the border scales with the agent, since erosion has to reach', () {
      const tiling = NavTileConfig();
      expect(
        tiling.borderFor(const NavMeshConfig(agentRadius: 2, cellSize: 0.3)),
        greaterThan(
          tiling.borderFor(
            const NavMeshConfig(agentRadius: 0.2, cellSize: 0.3),
          ),
        ),
      );
    });
  });

  group('serialization', () {
    NavTileSet bakedSet() => bakeNavMeshTiled(
      floorWithWall(30),
      _config,
      tiling: const NavTileConfig(tileCells: 24),
    ).tiles;

    test('a tile set round-trips through its binary form', () {
      final original = bakedSet();
      final restored = decodeNavTileSet(encodeNavTileSet(original));

      expect(restored.tileCount, original.tileCount);
      expect(restored.polygonCount, original.polygonCount);
      expect(restored.tiling.tileCells, original.tiling.tileCells);
      expect(restored.config.agentRadius, original.config.agentRadius);
      expect(restored.origin, original.origin);
      for (final key in original.tiles) {
        expect(
          restored.tile(key)!.polygonCount,
          original.tile(key)!.polygonCount,
        );
      }
    });

    test('the restored set is linked, so it still paths across seams', () {
      final restored = decodeNavTileSet(encodeNavTileSet(bakedSet()));
      final path = NavTileMeshQuery(
        restored,
      ).findPath(Vector3(-13, 0, -13), Vector3(13, 0, 13));
      expect(path.status, NavPathStatus.complete);
    });

    test('encoding twice gives the same bytes', () {
      final set = bakedSet();
      expect(encodeNavTileSet(set), encodeNavTileSet(set));
    });

    test('a wrong magic or version is rejected, not misread', () {
      final bytes = encodeNavTileSet(bakedSet());
      final wrongMagic = Uint8List.fromList(bytes)..[0] = 0;
      expect(() => decodeNavTileSet(wrongMagic), throwsFormatException);

      final wrongVersion = Uint8List.fromList(bytes)
        ..buffer.asByteData().setInt32(4, 99, Endian.little);
      expect(() => decodeNavTileSet(wrongVersion), throwsFormatException);

      expect(
        () => decodeNavTileSet(Uint8List.sublistView(bytes, 0, 8)),
        throwsFormatException,
      );
    });
  });

  test('a tiled bake finds as much ground as a single-shot one', () {
    // Not polygon for polygon, and it should not be: each tile simplifies its
    // own contours. What has to hold is that the walkable area survives.
    final geometry = floor(30);
    final single = buildNavMesh(geometry, _config)!;
    final tiled = bakeNavMeshTiled(
      geometry,
      _config,
      tiling: const NavTileConfig(tileCells: 24),
    ).tiles;

    final singleArea = areaOf(single);
    var tiledArea = 0.0;
    for (final key in tiled.tiles) {
      tiledArea += areaOf(tiled.tile(key)!);
    }
    expect(singleArea, greaterThan(100));
    expect(
      tiledArea,
      closeTo(singleArea, singleArea * 0.12),
      reason: 'tiling lost or gained more than a tenth of the walkable area',
    );
  });

  group('incremental rebake', () {
    /// A floor with a block sitting on it at [at], the crate that gets moved.
    NavGeometry floorWithBlock(double size, Vector2 at) {
      final half = size / 2;
      final builder = NavGeometryBuilder();
      builder.addMesh(
        positions: [
          -half, 0, -half, //
          half, 0, -half, //
          half, 0, half, //
          -half, 0, half,
        ],
        triangleIndices: [0, 2, 1, 0, 3, 2],
        area: NavArea.walkable,
      );
      // A tall thin box, steep enough on every side to read as an obstacle.
      const w = 2.0;
      const h = 3.0;
      builder.addMesh(
        positions: [
          at.x - w, 0, at.y - w, //
          at.x + w, 0, at.y - w, //
          at.x + w, h, at.y - w, //
          at.x - w, h, at.y - w, //
          at.x - w, 0, at.y + w, //
          at.x + w, 0, at.y + w, //
          at.x + w, h, at.y + w, //
          at.x - w, h, at.y + w,
        ],
        triangleIndices: [
          0, 1, 2, 0, 2, 3, //
          4, 6, 5, 4, 7, 6, //
          0, 3, 7, 0, 7, 4, //
          1, 5, 6, 1, 6, 2,
        ],
        area: NavArea.walkable,
      );
      return builder.build();
    }

    const tiling = NavTileConfig(tileCells: 24);

    test('an unchanged world changes no tiles', () {
      final geometry = floor(40);
      final before = fingerprintNavTiles(geometry, _config, tiling: tiling);
      final after = fingerprintNavTiles(geometry, _config, tiling: tiling);
      expect(changedNavTiles(before, after), isEmpty);
    });

    test('moving one block changes the tiles it left and arrived in', () {
      final before = fingerprintNavTiles(
        floorWithBlock(60, Vector2(-20, -20)),
        _config,
        tiling: tiling,
      );
      final after = fingerprintNavTiles(
        floorWithBlock(60, Vector2(20, 20)),
        _config,
        tiling: tiling,
      );
      final changed = changedNavTiles(before, after);

      expect(changed, isNotEmpty);
      expect(
        changed.length,
        lessThan(before.tileCount),
        reason: 'a local edit must not invalidate the world',
      );
      final size = tiling.tileSize(_config);
      bool touches(double x, double z) => changed.any(
        (key) => key.x == (x / size).floor() && key.z == (z / size).floor(),
      );
      expect(touches(-20, -20), isTrue, reason: 'the tile it left');
      expect(touches(20, 20), isTrue, reason: 'the tile it arrived in');
    });

    test('a fingerprint does not depend on the order triangles arrive', () {
      final builder = NavGeometryBuilder();
      final reversed = NavGeometryBuilder();
      const quads = [-10.0, 0.0, 10.0];
      for (final x in quads) {
        builder.addMesh(
          positions: [x, 0, -5, x + 8, 0, -5, x + 8, 0, 5, x, 0, 5],
          triangleIndices: [0, 2, 1, 0, 3, 2],
          area: NavArea.walkable,
        );
      }
      for (final x in quads.reversed) {
        reversed.addMesh(
          positions: [x, 0, -5, x + 8, 0, -5, x + 8, 0, 5, x, 0, 5],
          triangleIndices: [0, 2, 1, 0, 3, 2],
          area: NavArea.walkable,
        );
      }
      expect(
        changedNavTiles(
          fingerprintNavTiles(builder.build(), _config, tiling: tiling),
          fingerprintNavTiles(reversed.build(), _config, tiling: tiling),
        ),
        isEmpty,
      );
    });

    test('a different tiling is not comparable, so everything changes', () {
      final geometry = floor(40);
      final changed = changedNavTiles(
        fingerprintNavTiles(geometry, _config, tiling: tiling),
        fingerprintNavTiles(
          geometry,
          _config,
          tiling: const NavTileConfig(tileCells: 32),
        ),
      );
      expect(changed, isNotEmpty);
    });

    test('a rebake of the changed tiles matches a full bake of the world', () {
      final before = floorWithBlock(60, Vector2(-20, -20));
      final after = floorWithBlock(60, Vector2(20, 20));

      final incremental = bakeNavMeshTiled(
        before,
        _config,
        tiling: tiling,
      ).tiles;
      final changed = changedNavTiles(
        fingerprintNavTiles(before, _config, tiling: tiling),
        fingerprintNavTiles(after, _config, tiling: tiling),
      );
      rebakeNavTiles(incremental, after, changed);

      final full = bakeNavMeshTiled(after, _config, tiling: tiling).tiles;
      expect(incremental.tileCount, full.tileCount);
      for (final key in full.tiles) {
        expect(
          incremental.tile(key)?.polygonCount,
          full.tile(key)!.polygonCount,
          reason: 'tile $key differs from a full bake',
        );
      }
    });

    test('a rebake keeps the set crossable', () {
      final tiles = bakeNavMeshTiled(floor(60), _config, tiling: tiling).tiles;
      final moved = floorWithBlock(60, Vector2(0, 0));
      rebakeNavTiles(
        tiles,
        moved,
        changedNavTiles(
          fingerprintNavTiles(floor(60), _config, tiling: tiling),
          fingerprintNavTiles(moved, _config, tiling: tiling),
        ),
      );

      final path = NavTileMeshQuery(
        tiles,
      ).findPath(Vector3(-25, 0, -25), Vector3(25, 0, 25));
      expect(path.status, NavPathStatus.complete);
    });

    test('rebaking nothing is not a rebake of everything', () {
      final tiles = bakeNavMeshTiled(floor(40), _config, tiling: tiling).tiles;
      final polygons = tiles.polygonCount;
      final result = rebakeNavTiles(tiles, floor(40), const {});
      expect(result.tiles.polygonCount, polygons);
      expect(result.tiles.tileCount, greaterThan(0));
    });

    test('a tile whose geometry is gone is cleared, not left stale', () {
      final tiles = bakeNavMeshTiled(floor(60), _config, tiling: tiling).tiles;
      expect(tiles.tileCount, greaterThan(1));

      // The world shrinks to a corner; every tile the old floor covered and
      // the new one does not has to empty out.
      final shrunk = floor(10);
      final changed = changedNavTiles(
        fingerprintNavTiles(floor(60), _config, tiling: tiling),
        fingerprintNavTiles(shrunk, _config, tiling: tiling),
      );
      rebakeNavTiles(tiles, shrunk, changed);

      final full = bakeNavMeshTiled(shrunk, _config, tiling: tiling).tiles;
      expect(tiles.tileCount, full.tileCount);
    });
  });
}
