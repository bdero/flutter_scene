import 'package:scene/src/navigation/compact_heightfield.dart';
import 'package:scene/src/navigation/heightfield.dart';
import 'package:scene/src/navigation/nav_config.dart';
import 'package:scene/src/navigation/nav_geometry.dart';
import 'package:scene/src/navigation/regions.dart';
import 'package:test/test.dart';

/// An axis-aligned floor quad spanning [min] to [max] on XZ at [y].
void addFloorRect(
  NavGeometryBuilder builder,
  double minX,
  double minZ,
  double maxX,
  double maxZ, {
  double y = 0,
}) {
  builder.addMesh(
    positions: [minX, y, minZ, maxX, y, minZ, maxX, y, maxZ, minX, y, maxZ],
    triangleIndices: const [0, 2, 1, 0, 3, 2],
  );
}

/// A wall tall enough to block, from (x0,z0) to (x1,z1).
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

CompactHeightfield bake(NavGeometry geometry, NavMeshConfig config) {
  final field = rasterizeNavGeometry(geometry, config)!;
  final compact = buildCompactHeightfield(field, config);
  erodeWalkableArea(compact, config.agentRadiusCells);
  buildDistanceField(compact);
  buildRegions(compact);
  return compact;
}

/// Region ids actually present on walkable spans.
Set<int> regionIdsOf(CompactHeightfield compact) {
  final ids = <int>{};
  for (var i = 0; i < compact.spanCount; i++) {
    if (compact.areas[i] == NavArea.nonWalkable) continue;
    if (compact.regions[i] != 0) ids.add(compact.regions[i]);
  }
  return ids;
}

int walkableSpans(CompactHeightfield compact) {
  var count = 0;
  for (var i = 0; i < compact.spanCount; i++) {
    if (compact.areas[i] != NavArea.nonWalkable) count++;
  }
  return count;
}

void main() {
  const config = NavMeshConfig(
    cellSize: 0.3,
    cellHeight: 0.2,
    agentRadius: 0.5,
    agentHeight: 2.0,
  );

  test('one open room is one region', () {
    final builder = NavGeometryBuilder();
    addFloorRect(builder, 0, 0, 10, 10);
    final compact = bake(builder.build(), config);

    expect(walkableSpans(compact), greaterThan(0));
    expect(regionIdsOf(compact), hasLength(1));
    expect(compact.maxRegions, 1);
  });

  test('every walkable span gets a region', () {
    final builder = NavGeometryBuilder();
    addFloorRect(builder, 0, 0, 10, 10);
    final compact = bake(builder.build(), config);

    // A span left at region 0 is a hole the polygon stage would silently drop.
    for (var i = 0; i < compact.spanCount; i++) {
      if (compact.areas[i] == NavArea.nonWalkable) continue;
      expect(compact.regions[i], isNot(0));
    }
  });

  test('erosion pulls the surface back from the walls', () {
    final builder = NavGeometryBuilder();
    addFloorRect(builder, 0, 0, 10, 10);
    final geometry = builder.build();

    final field = rasterizeNavGeometry(geometry, config)!;
    final compact = buildCompactHeightfield(field, config);
    final before = walkableSpans(compact);
    erodeWalkableArea(compact, config.agentRadiusCells);
    final after = walkableSpans(compact);

    expect(after, lessThan(before));
    // A 10x10 floor eroded by 0.5 leaves roughly 9x9, well inside these
    // bounds even allowing for the voxel rounding.
    final cells = (9 * 9) / (config.cellSize * config.cellSize);
    expect(after, closeTo(cells, cells * 0.25));
  });

  test('two rooms joined by a doorway split at the doorway', () {
    // Two rooms, each comfortably larger than mergeRegionArea so the merge
    // step leaves them alone, joined by a 1.5-wide doorway.
    final builder = NavGeometryBuilder();
    addFloorRect(builder, 0, 0, 24, 10);
    addWall(builder, 12, 0, 12, 4.25);
    addWall(builder, 12, 5.75, 12, 10);
    final compact = bake(builder.build(), config);

    final ids = regionIdsOf(compact);
    expect(
      ids.length,
      greaterThanOrEqualTo(2),
      reason: 'the watershed seam belongs at the pinch point',
    );

    // The split has to be near the wall, not somewhere arbitrary: sample the
    // region either side of the doorway and require them to differ.
    expect(regionAt(compact, 3, 5), isNot(regionAt(compact, 21, 5)));
  });

  test('an unreachable speck is filtered out', () {
    final builder = NavGeometryBuilder();
    addFloorRect(builder, 0, 0, 10, 10);
    // A tile far away and much smaller than minRegionArea.
    addFloorRect(builder, 40, 40, 41, 41);
    final compact = bake(builder.build(), config);

    expect(
      regionAt(compact, 40.5, 40.5),
      0,
      reason: 'a speck no agent can reach should not become a polygon',
    );
    expect(regionAt(compact, 5, 5), isNot(0));
  });

  test('a bridge over a floor keeps two regions at the same column', () {
    final builder = NavGeometryBuilder();
    addFloorRect(builder, 0, 0, 10, 10);
    addFloorRect(builder, 3, 0, 7, 10, y: 4);
    final compact = bake(builder.build(), config);

    final lower = regionAt(compact, 5, 5, y: 0);
    final upper = regionAt(compact, 5, 5, y: 4);
    expect(lower, isNot(0));
    expect(upper, isNot(0));
    expect(
      lower,
      isNot(upper),
      reason: 'the deck and the road below it are different surfaces',
    );
  });
}

/// The region id of the walkable span nearest [y] at world position [x],[z].
int regionAt(CompactHeightfield compact, double x, double z, {double y = 0}) {
  final cx = ((x - compact.min.x) / compact.cellSize).floor();
  final cz = ((z - compact.min.z) / compact.cellSize).floor();
  if (cx < 0 || cz < 0 || cx >= compact.width || cz >= compact.depth) return 0;
  final column = cx + cz * compact.width;
  final start = compact.cellIndex[column];
  final end = start + compact.cellCount[column];
  var best = 0;
  var bestDelta = double.infinity;
  for (var i = start; i < end; i++) {
    if (compact.areas[i] == NavArea.nonWalkable) continue;
    final spanY = compact.min.y + compact.spanY[i] * compact.cellHeight;
    final delta = (spanY - y).abs();
    if (delta < bestDelta) {
      bestDelta = delta;
      best = compact.regions[i];
    }
  }
  return bestDelta <= 1.0 ? best : 0;
}
