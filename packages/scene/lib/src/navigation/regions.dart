import 'dart:typed_data';

import 'package:scene/src/navigation/compact_heightfield.dart';
import 'package:scene/src/navigation/nav_geometry.dart';

/// One cell queued for region assignment, kept as three parallel ints rather
/// than an object because the watershed pushes millions of them.
class _LevelStack {
  final List<int> _x = [];
  final List<int> _z = [];
  final List<int> _span = [];

  int get length => _span.length;
  bool get isEmpty => _span.isEmpty;

  void clear() {
    _x.clear();
    _z.clear();
    _span.clear();
  }

  void push(int x, int z, int span) {
    _x.add(x);
    _z.add(z);
    _span.add(span);
  }

  int xAt(int i) => _x[i];
  int zAt(int i) => _z[i];
  int spanAt(int i) => _span[i];

  /// Marks entry [i] consumed. The stacks are swept rather than compacted, so
  /// removing an entry is cheaper as a tombstone than as a shift.
  void consume(int i) => _span[i] = -1;

  void pop() {
    _x.removeLast();
    _z.removeLast();
    _span.removeLast();
  }

  int get lastX => _x.last;
  int get lastZ => _z.last;
  int get lastSpan => _span.last;
}

class _Region {
  _Region(this.id);

  int id;
  int spanCount = 0;
  int areaType = NavArea.nonWalkable;
  bool remap = false;
  bool visited = false;

  /// Whether two spans of this region sit in the same column, one above the
  /// other. Such a region cannot be merged, because the merged result would
  /// not trace to a simple contour.
  bool overlap = false;

  /// Neighbouring region ids in contour order, which is what makes the
  /// "do we touch in exactly one place" test possible.
  final List<int> connections = [];

  /// Region ids sharing a column with this one.
  final List<int> floors = [];
}

/// Partitions the walkable surface into regions by watershed.
///
/// The distance field is treated as a terrain and flooded from its peaks
/// downward: each local maximum, the middle of an open space, seeds a region,
/// and regions grow until they meet. The seams land where the distance field
/// has ridges, which is to say in doorways and at the narrow points, which is
/// exactly where a human would draw them. Partitioning by rows instead is
/// cheaper and gives long thin strips that make worse polygons.
///
/// Fills [CompactHeightfield.regions] and [CompactHeightfield.maxRegions].
void buildRegions(CompactHeightfield compact) {
  if (compact.distances == null) buildDistanceField(compact);
  final distances = compact.distances!;

  final regions = Uint16List(compact.spanCount);
  final regionDistances = Uint16List(compact.spanCount);

  // Eight stacks, each covering two distance levels. Recomputing the full
  // level sort every step is the dominant cost; sorting once per eight levels
  // and carrying the leftovers forward is the standard trade.
  const stackCount = 8;
  const levelsPerStackLog = 1;
  final levelStacks = List<_LevelStack>.generate(
    stackCount,
    (_) => _LevelStack(),
  );
  final floodStack = _LevelStack();

  var regionId = 1;
  var level = (compact.maxDistance + 1) & ~1;
  const expandIterations = 8;

  var stackIndex = -1;
  while (level > 0) {
    level = level >= 2 ? level - 2 : 0;
    stackIndex = (stackIndex + 1) & (stackCount - 1);

    if (stackIndex == 0) {
      _sortCellsByLevel(
        compact,
        distances,
        regions,
        level,
        levelStacks,
        levelsPerStackLog,
      );
    } else {
      _appendStack(
        levelStacks[stackIndex - 1],
        levelStacks[stackIndex],
        regions,
      );
    }

    _expandRegions(
      compact,
      distances,
      regions,
      regionDistances,
      levelStacks[stackIndex],
      maxIterations: expandIterations,
      level: level,
      fillStack: false,
    );

    // Anything the expansion could not reach starts a region of its own: it is
    // a new basin, separated from every existing one by a ridge.
    final stack = levelStacks[stackIndex];
    for (var j = 0; j < stack.length; j++) {
      final span = stack.spanAt(j);
      if (span < 0 || regions[span] != 0) continue;
      final seeded = _floodRegion(
        compact,
        distances,
        regions,
        regionDistances,
        floodStack,
        stack.xAt(j),
        stack.zAt(j),
        span,
        level,
        regionId,
      );
      if (seeded) {
        regionId++;
        if (regionId >= 0xffff) {
          throw StateError(
            'Nav mesh bake produced more than 65534 regions. The cell size is '
            'almost certainly far too small for the world being baked.',
          );
        }
      }
    }
  }

  // A final unbounded expansion mops up everything the level sweep left, which
  // is every cell whose distance was below the last level considered.
  _expandRegions(
    compact,
    distances,
    regions,
    regionDistances,
    floodStack,
    maxIterations: expandIterations * 8,
    level: 0,
    fillStack: true,
  );

  compact.maxRegions = _mergeAndFilterRegions(
    compact,
    regions,
    // regionId is the next id that would have been handed out, so the highest
    // one actually in use is one below it. Passing regionId itself leaves an
    // empty region in the table that survives compaction as a phantom.
    regionId - 1,
    minRegionArea: compact.minRegionSpans,
    mergeRegionArea: compact.mergeRegionSpans,
  );
  compact.regions.setAll(0, regions);
}

void _sortCellsByLevel(
  CompactHeightfield compact,
  Uint16List distances,
  Uint16List regions,
  int startLevel,
  List<_LevelStack> stacks,
  int levelsPerStackLog,
) {
  final shifted = startLevel >> levelsPerStackLog;
  for (final stack in stacks) {
    stack.clear();
  }
  for (var z = 0; z < compact.depth; z++) {
    for (var x = 0; x < compact.width; x++) {
      final column = x + z * compact.width;
      final start = compact.cellIndex[column];
      final end = start + compact.cellCount[column];
      for (var i = start; i < end; i++) {
        if (compact.areas[i] == NavArea.nonWalkable || regions[i] != 0) {
          continue;
        }
        final level = distances[i] >> levelsPerStackLog;
        var slot = shifted - level;
        if (slot >= stacks.length) continue;
        if (slot < 0) slot = 0;
        stacks[slot].push(x, z, i);
      }
    }
  }
}

void _appendStack(_LevelStack source, _LevelStack target, Uint16List regions) {
  for (var j = 0; j < source.length; j++) {
    final span = source.spanAt(j);
    if (span < 0 || regions[span] != 0) continue;
    target.push(source.xAt(j), source.zAt(j), span);
  }
}

/// Grows every existing region outward by one ring at a time, each cell
/// joining whichever neighbouring region reaches it along the shortest path.
void _expandRegions(
  CompactHeightfield compact,
  Uint16List distances,
  Uint16List regions,
  Uint16List regionDistances,
  _LevelStack stack, {
  required int maxIterations,
  required int level,
  required bool fillStack,
}) {
  if (fillStack) {
    stack.clear();
    for (var z = 0; z < compact.depth; z++) {
      for (var x = 0; x < compact.width; x++) {
        final column = x + z * compact.width;
        final start = compact.cellIndex[column];
        final end = start + compact.cellCount[column];
        for (var i = start; i < end; i++) {
          if (distances[i] >= level &&
              regions[i] == 0 &&
              compact.areas[i] != NavArea.nonWalkable) {
            stack.push(x, z, i);
          }
        }
      }
    }
  } else {
    for (var j = 0; j < stack.length; j++) {
      final span = stack.spanAt(j);
      if (span >= 0 && regions[span] != 0) stack.consume(j);
    }
  }

  // Assignments are collected and applied in a batch, so that within one
  // iteration every cell sees the same state and the result does not depend
  // on the order the stack happens to be in.
  final dirtySpans = <int>[];
  final dirtyRegions = <int>[];
  final dirtyDistances = <int>[];

  var iteration = 0;
  while (!stack.isEmpty) {
    var failed = 0;
    dirtySpans.clear();
    dirtyRegions.clear();
    dirtyDistances.clear();

    for (var j = 0; j < stack.length; j++) {
      final span = stack.spanAt(j);
      if (span < 0) {
        failed++;
        continue;
      }
      final x = stack.xAt(j);
      final z = stack.zAt(j);
      final area = compact.areas[span];

      var bestRegion = regions[span];
      var bestDistance = 0xffff;
      for (var dir = 0; dir < 4; dir++) {
        final neighbour = neighbourSpanIndex(compact, x, z, span, dir);
        if (neighbour < 0 || compact.areas[neighbour] != area) continue;
        if (regions[neighbour] > 0 &&
            regionDistances[neighbour] + 2 < bestDistance) {
          bestRegion = regions[neighbour];
          bestDistance = regionDistances[neighbour] + 2;
        }
      }
      if (bestRegion != 0) {
        stack.consume(j);
        dirtySpans.add(span);
        dirtyRegions.add(bestRegion);
        dirtyDistances.add(bestDistance);
      } else {
        failed++;
      }
    }

    for (var i = 0; i < dirtySpans.length; i++) {
      regions[dirtySpans[i]] = dirtyRegions[i];
      regionDistances[dirtySpans[i]] = dirtyDistances[i];
    }

    if (failed == stack.length) break;
    if (level > 0) {
      iteration++;
      if (iteration >= maxIterations) break;
    }
  }
}

/// Floods a new region from one seed cell, stopping at the current level.
///
/// Returns false when the seed turned out to touch an existing region, in
/// which case nothing was claimed and the region id is not spent.
bool _floodRegion(
  CompactHeightfield compact,
  Uint16List distances,
  Uint16List regions,
  Uint16List regionDistances,
  _LevelStack stack,
  int startX,
  int startZ,
  int startSpan,
  int level,
  int regionId,
) {
  final area = compact.areas[startSpan];
  stack.clear();
  stack.push(startX, startZ, startSpan);
  regions[startSpan] = regionId;
  regionDistances[startSpan] = 0;

  final floor = level >= 2 ? level - 2 : 0;
  var claimed = 0;

  while (!stack.isEmpty) {
    final x = stack.lastX;
    final z = stack.lastZ;
    final span = stack.lastSpan;
    stack.pop();

    // A cell touching a *different* region is on a ridge, so it is given up
    // rather than claimed: it will be assigned by expansion later, from
    // whichever side is genuinely closer.
    var adjacentRegion = 0;
    for (var dir = 0; dir < 4; dir++) {
      final neighbour = neighbourSpanIndex(compact, x, z, span, dir);
      if (neighbour < 0 || compact.areas[neighbour] != area) continue;
      final neighbourRegion = regions[neighbour];
      if (neighbourRegion != 0 && neighbourRegion != regionId) {
        adjacentRegion = neighbourRegion;
        break;
      }
      // The diagonal too, so two regions touching only at a corner are still
      // seen as touching. Without this a region can leak through a diagonal
      // pinch that no agent could actually walk.
      final nx = x + navDirOffsetX[dir];
      final nz = z + navDirOffsetZ[dir];
      final diagonal = neighbourSpanIndex(
        compact,
        nx,
        nz,
        neighbour,
        (dir + 1) & 3,
      );
      if (diagonal < 0 || compact.areas[diagonal] != area) continue;
      final diagonalRegion = regions[diagonal];
      if (diagonalRegion != 0 && diagonalRegion != regionId) {
        adjacentRegion = diagonalRegion;
        break;
      }
    }
    if (adjacentRegion != 0) {
      regions[span] = 0;
      continue;
    }

    claimed++;

    for (var dir = 0; dir < 4; dir++) {
      final neighbour = neighbourSpanIndex(compact, x, z, span, dir);
      if (neighbour < 0 || compact.areas[neighbour] != area) continue;
      if (distances[neighbour] >= floor && regions[neighbour] == 0) {
        regions[neighbour] = regionId;
        regionDistances[neighbour] = 0;
        stack.push(x + navDirOffsetX[dir], z + navDirOffsetZ[dir], neighbour);
      }
    }
  }

  return claimed > 0;
}

/// Whether [span]'s neighbour in [dir] belongs to a different region, which is
/// what makes this a region border.
bool _isRegionEdge(
  CompactHeightfield compact,
  Uint16List regions,
  int x,
  int z,
  int span,
  int dir,
) {
  final neighbour = neighbourSpanIndex(compact, x, z, span, dir);
  final neighbourRegion = neighbour < 0 ? 0 : regions[neighbour];
  return neighbourRegion != regions[span];
}

/// Walks the border of a region, recording the regions met along the way in
/// order.
///
/// The order is what matters: two regions that touch along one stretch appear
/// once in this list, and two that touch in two separate places appear twice,
/// which is how the merge step knows a merge would produce a region with a
/// hole in it.
void _walkRegionContour(
  CompactHeightfield compact,
  Uint16List regions,
  int startX,
  int startZ,
  int startSpan,
  int startDir,
  List<int> found,
) {
  var x = startX;
  var z = startZ;
  var span = startSpan;
  var dir = startDir;

  var current = 0;
  final firstNeighbour = neighbourSpanIndex(compact, x, z, span, dir);
  if (firstNeighbour >= 0) current = regions[firstNeighbour];
  found.add(current);

  // The walk is bounded because it follows a closed border; the cap is a
  // guard against a malformed field rather than an expected exit.
  for (var iteration = 0; iteration < 40000; iteration++) {
    if (_isRegionEdge(compact, regions, x, z, span, dir)) {
      final neighbour = neighbourSpanIndex(compact, x, z, span, dir);
      final region = neighbour < 0 ? 0 : regions[neighbour];
      if (region != current) {
        current = region;
        found.add(current);
      }
      dir = (dir + 1) & 3;
    } else {
      final neighbour = neighbourSpanIndex(compact, x, z, span, dir);
      if (neighbour < 0) return;
      x += navDirOffsetX[dir];
      z += navDirOffsetZ[dir];
      span = neighbour;
      dir = (dir + 3) & 3;
    }
    if (span == startSpan && dir == startDir) break;
  }

  _removeAdjacentDuplicates(found);
}

void _removeAdjacentDuplicates(List<int> values) {
  var i = 0;
  while (i < values.length && values.length > 1) {
    final next = (i + 1) % values.length;
    if (values[i] == values[next]) {
      values.removeAt(i);
    } else {
      i++;
    }
  }
}

/// Discards regions too small to be worth a polygon and merges the merely
/// small ones into a neighbour. Returns the new region count.
int _mergeAndFilterRegions(
  CompactHeightfield compact,
  Uint16List regions,
  int regionCount, {
  required int minRegionArea,
  required int mergeRegionArea,
}) {
  final all = List<_Region>.generate(regionCount + 1, _Region.new);

  for (var z = 0; z < compact.depth; z++) {
    for (var x = 0; x < compact.width; x++) {
      final column = x + z * compact.width;
      final start = compact.cellIndex[column];
      final end = start + compact.cellCount[column];
      for (var i = start; i < end; i++) {
        final id = regions[i];
        if (id == 0 || id > regionCount) continue;
        final region = all[id];
        region.spanCount++;

        // Other regions in the same column, which is how a region learns it
        // sits above or below another one.
        for (var j = start; j < end; j++) {
          if (i == j) continue;
          final floorId = regions[j];
          if (floorId == 0 || floorId > regionCount) continue;
          if (floorId == id) region.overlap = true;
          if (!region.floors.contains(floorId)) region.floors.add(floorId);
        }

        if (region.connections.isNotEmpty) continue;
        region.areaType = compact.areas[i];

        var edgeDir = -1;
        for (var dir = 0; dir < 4; dir++) {
          if (_isRegionEdge(compact, regions, x, z, i, dir)) {
            edgeDir = dir;
            break;
          }
        }
        if (edgeDir != -1) {
          _walkRegionContour(
            compact,
            regions,
            x,
            z,
            i,
            edgeDir,
            region.connections,
          );
        }
      }
    }
  }

  // Drop whole connected groups that are too small. Grouping first matters:
  // three tiny regions that together form a reachable ledge should survive,
  // while one tiny region alone on a windowsill should not.
  final stack = <int>[];
  final trace = <int>[];
  for (var i = 1; i <= regionCount; i++) {
    final region = all[i];
    if (region.id == 0 || region.spanCount == 0 || region.visited) continue;

    var groupSpans = 0;
    stack
      ..clear()
      ..add(i);
    trace.clear();
    region.visited = true;

    while (stack.isNotEmpty) {
      final currentId = stack.removeLast();
      final current = all[currentId];
      groupSpans += current.spanCount;
      trace.add(currentId);
      for (final connection in current.connections) {
        if (connection == 0 || connection > regionCount) continue;
        final neighbour = all[connection];
        if (neighbour.visited || neighbour.id == 0) continue;
        neighbour.visited = true;
        stack.add(neighbour.id);
      }
    }

    if (groupSpans < minRegionArea) {
      for (final id in trace) {
        all[id]
          ..spanCount = 0
          ..id = 0;
      }
    }
  }

  // Merge the small survivors into their smallest mergeable neighbour, which
  // keeps the result balanced rather than growing one region without bound.
  var merged = 0;
  do {
    merged = 0;
    for (var i = 1; i <= regionCount; i++) {
      final region = all[i];
      if (region.id == 0 || region.overlap || region.spanCount == 0) continue;
      if (region.spanCount > mergeRegionArea &&
          region.connections.contains(0)) {
        continue;
      }

      var smallest = 1 << 30;
      var targetId = region.id;
      for (final connection in region.connections) {
        if (connection == 0 || connection > regionCount) continue;
        final candidate = all[connection];
        if (candidate.id == 0 || candidate.overlap) continue;
        if (candidate.spanCount < smallest &&
            _canMerge(region, candidate) &&
            _canMerge(candidate, region)) {
          smallest = candidate.spanCount;
          targetId = candidate.id;
        }
      }
      if (targetId == region.id) continue;

      final oldId = region.id;
      if (!_mergeRegions(all[targetId], region)) continue;
      for (var j = 1; j <= regionCount; j++) {
        final other = all[j];
        if (other.id == 0) continue;
        if (other.id == oldId) other.id = targetId;
        _replaceNeighbour(other, oldId, targetId);
      }
      merged++;
    }
  } while (merged > 0);

  // Compact the ids so the polygon stage can index by region.
  for (var i = 1; i <= regionCount; i++) {
    all[i].remap = all[i].id != 0;
  }
  var nextId = 0;
  for (var i = 1; i <= regionCount; i++) {
    if (!all[i].remap) continue;
    final oldId = all[i].id;
    final newId = ++nextId;
    for (var j = i; j <= regionCount; j++) {
      if (all[j].id == oldId) {
        all[j].id = newId;
        all[j].remap = false;
      }
    }
  }

  for (var i = 0; i < compact.spanCount; i++) {
    final id = regions[i];
    regions[i] = id <= regionCount ? all[id].id : 0;
  }
  return nextId;
}

/// Whether [from] may absorb [into] without producing a region that traces to
/// something other than a simple ring.
bool _canMerge(_Region from, _Region into) {
  if (from.areaType != into.areaType) return false;
  // Touching in two separate places means merging would enclose whatever lies
  // between the two contacts, leaving a hole no contour walk can describe.
  var contacts = 0;
  for (final connection in from.connections) {
    if (connection == into.id) contacts++;
  }
  if (contacts > 1) return false;
  // Sharing a column means one is above the other, so the merged region would
  // be two surfaces at different heights claiming the same ground.
  return !from.floors.contains(into.id);
}

bool _mergeRegions(_Region target, _Region source) {
  final targetConnections = List<int>.of(target.connections);
  final sourceConnections = source.connections;

  final targetSeam = targetConnections.indexOf(source.id);
  if (targetSeam == -1) return false;
  final sourceSeam = sourceConnections.indexOf(target.id);
  if (sourceSeam == -1) return false;

  // Splice one contour into the other at the seam where they meet, so the
  // merged connection list is still in contour order.
  target.connections.clear();
  for (var i = 0; i < targetConnections.length - 1; i++) {
    target.connections.add(
      targetConnections[(targetSeam + 1 + i) % targetConnections.length],
    );
  }
  for (var i = 0; i < sourceConnections.length - 1; i++) {
    target.connections.add(
      sourceConnections[(sourceSeam + 1 + i) % sourceConnections.length],
    );
  }
  _removeAdjacentDuplicates(target.connections);

  for (final floor in source.floors) {
    if (!target.floors.contains(floor)) target.floors.add(floor);
  }
  target.spanCount += source.spanCount;
  // The source keeps its id. The caller rewrites every region carrying that
  // id to the target's, which is also how the *spans* still numbered with it
  // are remapped at the end; clearing it here strands them at region 0.
  source
    ..spanCount = 0
    ..connections.clear();
  return true;
}

void _replaceNeighbour(_Region region, int oldId, int newId) {
  var changed = false;
  for (var i = 0; i < region.connections.length; i++) {
    if (region.connections[i] == oldId) {
      region.connections[i] = newId;
      changed = true;
    }
  }
  for (var i = 0; i < region.floors.length; i++) {
    if (region.floors[i] == oldId) region.floors[i] = newId;
  }
  if (changed) _removeAdjacentDuplicates(region.connections);
}
