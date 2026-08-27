import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'package:scene/src/navigation/heightfield.dart';
import 'package:scene/src/navigation/nav_config.dart';
import 'package:scene/src/navigation/nav_geometry.dart';

/// The neighbour offsets the whole bake walks in, in order: -X, +Z, +X, -Z.
///
/// Every stage from connectivity to contour tracing depends on this being a
/// consistent counter-clockwise rotation, because "turn left" is expressed as
/// `(dir + 3) & 3` and "turn right" as `(dir + 1) & 3`.
const List<int> navDirOffsetX = [-1, 0, 1, 0];
const List<int> navDirOffsetZ = [0, 1, 0, -1];

/// The neighbour value meaning "no connection in this direction".
const int navNotConnected = 0x3f;

/// The walkable surfaces of a [Heightfield], with the solid interior thrown
/// away and neighbour links resolved.
///
/// The solid field answers "where is there matter"; this answers "where can
/// the agent stand and where can it step to from there", which is what every
/// stage after it actually needs. One entry per walkable surface rather than
/// per solid voxel, so it is also far smaller.
class CompactHeightfield {
  CompactHeightfield({
    required this.width,
    required this.depth,
    required this.min,
    required this.max,
    required this.cellSize,
    required this.cellHeight,
    required this.walkableHeight,
    required this.walkableClimb,
    required this.minRegionSpans,
    required this.mergeRegionSpans,
    required this.cellIndex,
    required this.cellCount,
    required this.spanY,
    required this.spanHeight,
    required this.spanConnections,
    required this.areas,
  });

  final int width;
  final int depth;
  final Vector3 min;
  final Vector3 max;
  final double cellSize;
  final double cellHeight;

  /// The agent's clearance and step height, in voxels, carried through so the
  /// later stages do not need the config.
  final int walkableHeight;
  final int walkableClimb;

  /// [NavMeshConfig.minRegionArea] and [NavMeshConfig.mergeRegionArea] as span
  /// counts, since a region's size is measured in spans and the config states
  /// it in square world units.
  final int minRegionSpans;
  final int mergeRegionSpans;

  /// The first span index and span count of each column.
  final Uint32List cellIndex;
  final Uint16List cellCount;

  /// Per span: the floor height in voxels, and the clearance above it.
  final Uint16List spanY;
  final Uint16List spanHeight;

  /// Per span, four 6-bit neighbour offsets packed low-to-high in the order of
  /// [navDirOffsetX]. Each is the neighbour's index *within its column*, or
  /// [navNotConnected].
  final Uint32List spanConnections;

  /// Per span [NavArea]. Set to [NavArea.nonWalkable] by erosion and by the
  /// area filters, which is how a span is removed without renumbering.
  final Uint8List areas;

  /// Per span region id, filled in by the region stage.
  late final Uint16List regions = Uint16List(spanCount);

  /// Per span distance to the nearest border, in half-cell units, filled in by
  /// [buildDistanceField].
  Uint16List? distances;

  int maxDistance = 0;
  int maxRegions = 0;

  int get spanCount => spanY.length;

  /// The neighbour index of [span] in [dir], or [navNotConnected].
  int connection(int span, int dir) =>
      (spanConnections[span] >> (dir * 6)) & 0x3f;

  void setConnection(int span, int dir, int neighbour) {
    final shift = dir * 6;
    spanConnections[span] =
        (spanConnections[span] & ~(0x3f << shift)) | (neighbour << shift);
  }

  /// The world-space centre of the floor of [span] in column [x],[z].
  Vector3 spanPosition(int x, int z, int span) => Vector3(
    min.x + (x + 0.5) * cellSize,
    min.y + spanY[span] * cellHeight,
    min.z + (z + 0.5) * cellSize,
  );
}

/// Marks a non-walkable span walkable when the walkable surface directly below
/// it is within one step.
///
/// This is what lets an agent walk over a curb, a rug, or a rail lying on the
/// floor. Without it the thin obstacle's own span shadows the floor and the
/// bake carves a hole where the agent could plainly walk.
void filterLowHangingWalkableObstacles(Heightfield field, int walkableClimb) {
  for (var z = 0; z < field.depth; z++) {
    for (var x = 0; x < field.width; x++) {
      HeightSpan? previous;
      var previousWasWalkable = false;
      var previousArea = NavArea.nonWalkable;
      for (var span = field.spanAt(x, z); span != null; span = span.next) {
        final walkable = span.area != NavArea.nonWalkable;
        if (!walkable &&
            previousWasWalkable &&
            previous != null &&
            (span.max - previous.max).abs() <= walkableClimb) {
          span.area = previousArea;
        }
        previousWasWalkable = walkable;
        previousArea = span.area;
        previous = span;
      }
    }
  }
}

/// Clears the walkable flag from spans at the edge of a drop the agent cannot
/// survive stepping off.
///
/// A span sitting at the lip of a cliff is walkable by slope and by clearance,
/// and an agent standing on it is fine, but a path routed along it would hug
/// the edge. More importantly, the drop makes the surface's neighbourhood
/// discontinuous, and the polygon stage assumes it is not.
void filterLedgeSpans(Heightfield field, int walkableHeight, int climb) {
  const maxHeight = 0xffff;
  for (var z = 0; z < field.depth; z++) {
    for (var x = 0; x < field.width; x++) {
      for (var span = field.spanAt(x, z); span != null; span = span.next) {
        if (span.area == NavArea.nonWalkable) continue;

        final floor = span.max;
        final ceiling = span.next?.min ?? maxHeight;

        // The largest step down to any neighbour, and the range of heights the
        // reachable neighbours sit at.
        var minimumDrop = maxHeight;
        var lowestReachable = floor;
        var highestReachable = floor;

        for (var dir = 0; dir < 4; dir++) {
          final nx = x + navDirOffsetX[dir];
          final nz = z + navDirOffsetZ[dir];
          if (nx < 0 || nz < 0 || nx >= field.width || nz >= field.depth) {
            // Off the grid is an infinite drop.
            minimumDrop = math.min(minimumDrop, -climb - floor);
            continue;
          }

          // The gap below the neighbour column's first span is reachable too,
          // which is what makes a drop off a platform onto the floor visible.
          var neighbour = field.spanAt(nx, nz);
          var neighbourFloor = -climb;
          var neighbourCeiling = neighbour?.min ?? maxHeight;
          if (math.min(ceiling, neighbourCeiling) - floor >= walkableHeight) {
            minimumDrop = math.min(minimumDrop, neighbourFloor - floor);
          }

          for (; neighbour != null; neighbour = neighbour.next) {
            neighbourFloor = neighbour.max;
            neighbourCeiling = neighbour.next?.min ?? maxHeight;
            if (math.min(ceiling, neighbourCeiling) -
                    math.max(floor, neighbourFloor) <
                walkableHeight) {
              continue;
            }
            final drop = neighbourFloor - floor;
            minimumDrop = math.min(minimumDrop, drop);
            if (drop.abs() <= climb) {
              lowestReachable = math.min(lowestReachable, neighbourFloor);
              highestReachable = math.max(highestReachable, neighbourFloor);
            }
          }
        }

        if (minimumDrop < -climb) {
          // The span overlooks a drop taller than the agent can climb back up.
          span.area = NavArea.nonWalkable;
        } else if (highestReachable - lowestReachable > climb) {
          // Its neighbours straddle more than one step, so the surface is not
          // locally flat enough to stand on.
          span.area = NavArea.nonWalkable;
        }
      }
    }
  }
}

/// Clears the walkable flag from any span without the agent's headroom.
void filterWalkableLowHeightSpans(Heightfield field, int walkableHeight) {
  const maxHeight = 0xffff;
  for (var z = 0; z < field.depth; z++) {
    for (var x = 0; x < field.width; x++) {
      for (var span = field.spanAt(x, z); span != null; span = span.next) {
        final ceiling = span.next?.min ?? maxHeight;
        if (ceiling - span.max < walkableHeight) {
          span.area = NavArea.nonWalkable;
        }
      }
    }
  }
}

/// Runs every filter and compacts [field] into walkable surfaces with
/// neighbour links resolved.
CompactHeightfield buildCompactHeightfield(
  Heightfield field,
  NavMeshConfig config,
) {
  final walkableHeight = config.agentHeightCells;
  final walkableClimb = config.agentMaxClimbCells;

  // Order matters. Low-hanging obstacles are promoted before the ledge test,
  // so a curb reads as part of the floor rather than as the floor's edge, and
  // the clearance filter runs last so nothing it clears can be promoted again.
  filterLowHangingWalkableObstacles(field, walkableClimb);
  filterLedgeSpans(field, walkableHeight, walkableClimb);
  filterWalkableLowHeightSpans(field, walkableHeight);

  const maxHeight = 0xffff;
  final columns = field.width * field.depth;
  final cellIndex = Uint32List(columns);
  final cellCount = Uint16List(columns);

  var spanCount = 0;
  for (var i = 0; i < columns; i++) {
    for (var span = field.columnAt(i); span != null; span = span.next) {
      if (span.area != NavArea.nonWalkable) spanCount++;
    }
  }

  final spanY = Uint16List(spanCount);
  final spanHeight = Uint16List(spanCount);
  final areas = Uint8List(spanCount);
  final connections = Uint32List(spanCount);

  var next = 0;
  for (var z = 0; z < field.depth; z++) {
    for (var x = 0; x < field.width; x++) {
      final column = x + z * field.width;
      cellIndex[column] = next;
      var count = 0;
      for (var span = field.spanAt(x, z); span != null; span = span.next) {
        if (span.area == NavArea.nonWalkable) continue;
        spanY[next] = span.max.clamp(0, maxHeight);
        // The clearance above this floor, capped: an outdoor surface has
        // effectively unbounded headroom and there is no point storing it.
        spanHeight[next] = ((span.next?.min ?? maxHeight) - span.max).clamp(
          0,
          maxHeight,
        );
        areas[next] = span.area;
        connections[next] = 0x3fffffff;
        next++;
        count++;
      }
      cellCount[column] = count;
    }
  }

  final compact = CompactHeightfield(
    width: field.width,
    depth: field.depth,
    min: field.min,
    max: field.max,
    cellSize: field.cellSize,
    cellHeight: field.cellHeight,
    walkableHeight: walkableHeight,
    walkableClimb: walkableClimb,
    minRegionSpans: (config.minRegionArea / (config.cellSize * config.cellSize))
        .round(),
    mergeRegionSpans:
        (config.mergeRegionArea / (config.cellSize * config.cellSize)).round(),
    cellIndex: cellIndex,
    cellCount: cellCount,
    spanY: spanY,
    spanHeight: spanHeight,
    spanConnections: connections,
    areas: areas,
  );
  _linkNeighbours(compact);
  return compact;
}

/// Resolves, for each span and direction, which span in the neighbouring
/// column the agent can step to.
///
/// The two conditions are the whole definition of connectivity in a nav mesh:
/// the floors must be within one step of each other, and the two surfaces must
/// share enough vertical overlap for the agent to fit through the transition.
void _linkNeighbours(CompactHeightfield compact) {
  for (var z = 0; z < compact.depth; z++) {
    for (var x = 0; x < compact.width; x++) {
      final column = x + z * compact.width;
      final start = compact.cellIndex[column];
      final end = start + compact.cellCount[column];
      for (var i = start; i < end; i++) {
        for (var dir = 0; dir < 4; dir++) {
          compact.setConnection(i, dir, navNotConnected);
          final nx = x + navDirOffsetX[dir];
          final nz = z + navDirOffsetZ[dir];
          if (nx < 0 || nz < 0 || nx >= compact.width || nz >= compact.depth) {
            continue;
          }
          final neighbourColumn = nx + nz * compact.width;
          final neighbourStart = compact.cellIndex[neighbourColumn];
          final neighbourEnd =
              neighbourStart + compact.cellCount[neighbourColumn];
          for (var k = neighbourStart; k < neighbourEnd; k++) {
            final overlap =
                math.min(
                  compact.spanY[i] + compact.spanHeight[i],
                  compact.spanY[k] + compact.spanHeight[k],
                ) -
                math.max(compact.spanY[i], compact.spanY[k]);
            if (overlap < compact.walkableHeight) continue;
            if ((compact.spanY[k] - compact.spanY[i]).abs() >
                compact.walkableClimb) {
              continue;
            }
            final offset = k - neighbourStart;
            // Six bits per direction is the packing budget, so a column with
            // more than 62 walkable surfaces above one another cannot be
            // addressed. That is a pathological input, not a real level.
            if (offset >= 0 && offset < navNotConnected) {
              compact.setConnection(i, dir, offset);
            }
            break;
          }
        }
      }
    }
  }
}

/// Clears every span whose centre is closer to a border than the agent's
/// radius.
///
/// This is why a baked path never clips a corner: rather than inflating the
/// agent at query time, the walkable surface is shrunk once at bake time, and
/// every point on it is then somewhere the agent's centre may legally be.
void erodeWalkableArea(CompactHeightfield compact, int radius) {
  if (radius <= 0) return;
  final distance = _borderDistance(compact);
  final threshold = radius * 2;
  for (var i = 0; i < compact.spanCount; i++) {
    if (distance[i] < threshold) compact.areas[i] = NavArea.nonWalkable;
  }
}

/// Builds the distance-to-border field used by region partitioning.
void buildDistanceField(CompactHeightfield compact) {
  final distance = _borderDistance(compact);
  var maximum = 0;
  for (final value in distance) {
    if (value > maximum) maximum = value;
  }
  compact.maxDistance = maximum;
  compact.distances = _blurDistance(compact, distance);
}

/// A chamfer distance transform to the nearest non-walkable span or grid edge.
///
/// Distances are in half-cells, so the diagonal step can be 3 against the
/// axial step's 2 and approximate Euclidean distance far better than a plain
/// Manhattan count would.
Uint16List _borderDistance(CompactHeightfield compact) {
  final distance = Uint16List(compact.spanCount)
    ..fillRange(0, compact.spanCount, 0xffff);

  // Seed: anything on a border is at zero.
  for (var z = 0; z < compact.depth; z++) {
    for (var x = 0; x < compact.width; x++) {
      final column = x + z * compact.width;
      final start = compact.cellIndex[column];
      final end = start + compact.cellCount[column];
      for (var i = start; i < end; i++) {
        if (compact.areas[i] == NavArea.nonWalkable) {
          distance[i] = 0;
          continue;
        }
        var open = 0;
        for (var dir = 0; dir < 4; dir++) {
          final neighbour = _neighbourSpan(compact, x, z, i, dir);
          if (neighbour >= 0 &&
              compact.areas[neighbour] != NavArea.nonWalkable) {
            open++;
          }
        }
        if (open != 4) distance[i] = 0;
      }
    }
  }

  // Two sweeps, forward then backward, is all a chamfer transform needs.
  _sweepDistance(compact, distance, forward: true);
  _sweepDistance(compact, distance, forward: false);
  return distance;
}

void _sweepDistance(
  CompactHeightfield compact,
  Uint16List distance, {
  required bool forward,
}) {
  // The forward pass reads the two directions already visited (-X and -Z) and
  // their diagonals; the backward pass reads the other two. Together they
  // propagate a distance across the whole field.
  final first = forward ? 0 : 3;
  final second = forward ? 3 : 2;
  final zStart = forward ? 0 : compact.depth - 1;
  final zEnd = forward ? compact.depth : -1;
  final zStep = forward ? 1 : -1;
  final xStart = forward ? 0 : compact.width - 1;
  final xEnd = forward ? compact.width : -1;
  final xStep = forward ? 1 : -1;

  for (var z = zStart; z != zEnd; z += zStep) {
    for (var x = xStart; x != xEnd; x += xStep) {
      final column = x + z * compact.width;
      final start = compact.cellIndex[column];
      final end = start + compact.cellCount[column];
      for (var i = start; i < end; i++) {
        _relax(compact, distance, x, z, i, first, forward);
        _relax(compact, distance, x, z, i, second, forward);
      }
    }
  }
}

void _relax(
  CompactHeightfield compact,
  Uint16List distance,
  int x,
  int z,
  int span,
  int dir,
  bool forward,
) {
  final neighbour = _neighbourSpan(compact, x, z, span, dir);
  if (neighbour < 0) return;
  if (distance[neighbour] + 2 < distance[span]) {
    distance[span] = distance[neighbour] + 2;
  }
  // The diagonal, reached by turning from the neighbour: 3 half-cells away,
  // against 2 for the axial step.
  final diagonalDir = forward ? (dir + 3) & 3 : (dir + 1) & 3;
  final nx = x + navDirOffsetX[dir];
  final nz = z + navDirOffsetZ[dir];
  final diagonal = _neighbourSpan(compact, nx, nz, neighbour, diagonalDir);
  if (diagonal < 0) return;
  if (distance[diagonal] + 3 < distance[span]) {
    distance[span] = distance[diagonal] + 3;
  }
}

/// A 3x3 box blur over the distance field.
///
/// Watershed partitioning is exquisitely sensitive to noise in the distance
/// field: one voxel of jitter along a wall becomes a spurious region and then
/// a spurious polygon. Smoothing first costs one pass and removes most of it.
Uint16List _blurDistance(CompactHeightfield compact, Uint16List distance) {
  const threshold = 2;
  final blurred = Uint16List.fromList(distance);
  for (var z = 0; z < compact.depth; z++) {
    for (var x = 0; x < compact.width; x++) {
      final column = x + z * compact.width;
      final start = compact.cellIndex[column];
      final end = start + compact.cellCount[column];
      for (var i = start; i < end; i++) {
        final centre = distance[i];
        if (centre <= threshold) {
          blurred[i] = centre;
          continue;
        }
        var total = centre;
        for (var dir = 0; dir < 4; dir++) {
          final neighbour = _neighbourSpan(compact, x, z, i, dir);
          if (neighbour < 0) {
            total += centre * 2;
            continue;
          }
          total += distance[neighbour];
          final nx = x + navDirOffsetX[dir];
          final nz = z + navDirOffsetZ[dir];
          final diagonal = _neighbourSpan(
            compact,
            nx,
            nz,
            neighbour,
            (dir + 1) & 3,
          );
          total += diagonal < 0 ? centre : distance[diagonal];
        }
        blurred[i] = ((total + 5) ~/ 9);
      }
    }
  }
  return blurred;
}

/// The span index reached from [span] in [dir], or -1 when unconnected.
int neighbourSpanIndex(
  CompactHeightfield compact,
  int x,
  int z,
  int span,
  int dir,
) => _neighbourSpan(compact, x, z, span, dir);

int _neighbourSpan(
  CompactHeightfield compact,
  int x,
  int z,
  int span,
  int dir,
) {
  final offset = compact.connection(span, dir);
  if (offset == navNotConnected) return -1;
  final nx = x + navDirOffsetX[dir];
  final nz = z + navDirOffsetZ[dir];
  return compact.cellIndex[nx + nz * compact.width] + offset;
}
