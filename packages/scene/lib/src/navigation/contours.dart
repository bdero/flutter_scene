import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'package:scene/src/navigation/compact_heightfield.dart';
import 'package:scene/src/navigation/nav_config.dart';
import 'package:scene/src/navigation/nav_geometry.dart';
import 'package:scene/src/navigation/poly_math.dart';

/// Set on a contour vertex whose outward neighbour is another region rather
/// than empty space. A polygon edge built from such a vertex is a portal, and
/// a polygon edge built from a vertex without it is a wall.
const int contourPortalMask = 0xffff;

/// The closed outline of one region, in voxel coordinates.
///
/// Both the raw trace and the simplified outline are kept: the raw one is what
/// the simplification measures its error against, and it is also what the
/// hole-merging step needs when a region wraps an obstacle.
class Contour {
  Contour(this.region, this.area);

  /// The region this outline encloses, and its [NavArea].
  final int region;
  final int area;

  /// The simplified outline: x, y, z, and the neighbouring region across the
  /// edge leaving this vertex (0 for a wall), four ints per vertex.
  List<int> vertices = [];

  /// The unsimplified trace, same layout.
  List<int> raw = [];

  int get vertexCount => vertices.length ~/ 4;
  int get rawCount => raw.length ~/ 4;
}

/// Every region's outline, plus the bounds needed to turn voxels back into
/// world space.
class ContourSet {
  ContourSet({
    required this.contours,
    required this.min,
    required this.max,
    required this.width,
    required this.depth,
    required this.cellSize,
    required this.cellHeight,
    required this.maxRegions,
  });

  final List<Contour> contours;
  final Vector3 min;
  final Vector3 max;
  final int width;
  final int depth;
  final double cellSize;
  final double cellHeight;
  final int maxRegions;
}

/// Traces each region's border into a simplified polygon outline.
///
/// This is the step that turns a field of cells into geometry. Every edge
/// between two different regions becomes a shared portal, and every edge
/// against nothing becomes a wall, which is the distinction the query needs
/// later to know where an agent may cross from one polygon into the next.
ContourSet buildContours(CompactHeightfield compact, NavMeshConfig config) {
  final maxError = config.maxSimplificationError;
  final maxEdgeLength = (config.maxEdgeLength / config.cellSize).round();

  // One bit per direction marking "the neighbour across this edge is a
  // different region", which is to say the edge is on the outline.
  final flags = Uint8List(compact.spanCount);
  for (var z = 0; z < compact.depth; z++) {
    for (var x = 0; x < compact.width; x++) {
      final column = x + z * compact.width;
      final start = compact.cellIndex[column];
      final end = start + compact.cellCount[column];
      for (var i = start; i < end; i++) {
        if (compact.regions[i] == 0 ||
            compact.areas[i] == NavArea.nonWalkable) {
          flags[i] = 0;
          continue;
        }
        var edges = 0;
        for (var dir = 0; dir < 4; dir++) {
          final neighbour = neighbourSpanIndex(compact, x, z, i, dir);
          final neighbourRegion = neighbour < 0
              ? 0
              : compact.regions[neighbour];
          if (neighbourRegion != compact.regions[i]) edges |= 1 << dir;
        }
        flags[i] = edges;
      }
    }
  }

  final contours = <Contour>[];
  final raw = <int>[];
  final simplified = <int>[];

  for (var z = 0; z < compact.depth; z++) {
    for (var x = 0; x < compact.width; x++) {
      final column = x + z * compact.width;
      final start = compact.cellIndex[column];
      final end = start + compact.cellCount[column];
      for (var i = start; i < end; i++) {
        if (flags[i] == 0 || flags[i] == 0xf) {
          // No border edges, or completely surrounded by other regions: this
          // span is not on an outline that has yet to be walked.
          flags[i] = 0;
          continue;
        }
        final region = compact.regions[i];
        if (region == 0) continue;
        final area = compact.areas[i];

        raw.clear();
        simplified.clear();
        _walkContour(compact, flags, x, z, i, raw);
        _simplifyContour(raw, simplified, maxError, maxEdgeLength);
        _removeDegenerateSegments(simplified);

        if (simplified.length ~/ 4 < 3) continue;
        contours.add(
          Contour(region, area)
            ..vertices = List<int>.of(simplified)
            ..raw = List<int>.of(raw),
        );
      }
    }
  }

  _mergeHoles(contours);

  return ContourSet(
    contours: contours,
    min: compact.min,
    max: compact.max,
    width: compact.width,
    depth: compact.depth,
    cellSize: compact.cellSize,
    cellHeight: compact.cellHeight,
    maxRegions: compact.maxRegions,
  );
}

/// The height to place a contour corner at.
///
/// A corner is shared by up to four cells, and taking the highest of them is
/// what keeps a contour from sinking into the floor at the top of a step: the
/// polygon has to sit at the level an agent standing there would be at.
int _cornerHeight(CompactHeightfield compact, int x, int z, int span, int dir) {
  var height = compact.spanY[span];
  final nextDir = (dir + 1) & 3;

  final side = neighbourSpanIndex(compact, x, z, span, dir);
  if (side >= 0) {
    height = math.max(height, compact.spanY[side]);
    final sideX = x + navDirOffsetX[dir];
    final sideZ = z + navDirOffsetZ[dir];
    final diagonal = neighbourSpanIndex(compact, sideX, sideZ, side, nextDir);
    if (diagonal >= 0) height = math.max(height, compact.spanY[diagonal]);
  }
  final ahead = neighbourSpanIndex(compact, x, z, span, nextDir);
  if (ahead >= 0) {
    height = math.max(height, compact.spanY[ahead]);
    final aheadX = x + navDirOffsetX[nextDir];
    final aheadZ = z + navDirOffsetZ[nextDir];
    final diagonal = neighbourSpanIndex(compact, aheadX, aheadZ, ahead, dir);
    if (diagonal >= 0) height = math.max(height, compact.spanY[diagonal]);
  }
  return height;
}

/// Walks one closed outline, consuming the border flags as it goes.
///
/// The rule is the standard one for tracing a 4-connected blob: while the edge
/// ahead is on the border, emit its corner and turn right; otherwise step onto
/// the neighbour and turn left. It terminates when it comes back to the
/// starting cell *facing the starting direction*, which is what makes it a
/// closed loop rather than a path.
void _walkContour(
  CompactHeightfield compact,
  Uint8List flags,
  int startX,
  int startZ,
  int startSpan,
  List<int> points,
) {
  var dir = 0;
  while ((flags[startSpan] & (1 << dir)) == 0) {
    dir++;
  }
  final firstDir = dir;
  var x = startX;
  var z = startZ;
  var span = startSpan;

  // Bounded as a guard against a malformed field, not as an expected exit.
  for (var iteration = 0; iteration < 200000; iteration++) {
    if ((flags[span] & (1 << dir)) != 0) {
      var px = x;
      var pz = z;
      final py = _cornerHeight(compact, x, z, span, dir);
      // The corner is the one at the far end of this edge, walking the cell
      // boundary counter-clockwise.
      switch (dir) {
        case 0:
          pz++;
        case 1:
          px++;
          pz++;
        case 2:
          px++;
      }
      final neighbour = neighbourSpanIndex(compact, x, z, span, dir);
      final neighbourRegion = neighbour < 0 ? 0 : compact.regions[neighbour];
      points
        ..add(px)
        ..add(py)
        ..add(pz)
        ..add(neighbourRegion);

      flags[span] &= ~(1 << dir);
      dir = (dir + 1) & 3;
    } else {
      final neighbour = neighbourSpanIndex(compact, x, z, span, dir);
      if (neighbour < 0) return;
      x += navDirOffsetX[dir];
      z += navDirOffsetZ[dir];
      span = neighbour;
      dir = (dir + 3) & 3;
    }
    if (span == startSpan && dir == firstDir) break;
  }
}

/// Douglas-Peucker simplification, anchored so that portals survive.
///
/// The anchors matter more than the smoothing: a vertex where the neighbouring
/// region changes is a portal endpoint, and moving it would leave two adjacent
/// polygons disagreeing about where their shared edge is. So every such vertex
/// is kept exactly, and only the stretches between them are simplified.
void _simplifyContour(
  List<int> points,
  List<int> simplified,
  double maxError,
  int maxEdgeLength,
) {
  final pointCount = points.length ~/ 4;
  if (pointCount == 0) return;

  var hasPortal = false;
  for (var i = 0; i < pointCount; i++) {
    if (points[i * 4 + 3] != 0) {
      hasPortal = true;
      break;
    }
  }

  if (hasPortal) {
    for (var i = 0; i < pointCount; i++) {
      final next = (i + 1) % pointCount;
      if (points[i * 4 + 3] != points[next * 4 + 3]) {
        simplified
          ..add(points[i * 4])
          ..add(points[i * 4 + 1])
          ..add(points[i * 4 + 2])
          ..add(i);
      }
    }
  }

  if (simplified.isEmpty) {
    // A contour with no portals at all is a closed island, so there is no
    // anchor to start from. Its extreme corners serve instead: any two points
    // guaranteed to be on the hull work, and the recursion finds the rest.
    var lowX = points[0], lowY = points[1], lowZ = points[2], lowIndex = 0;
    var highX = points[0], highY = points[1], highZ = points[2], highIndex = 0;
    for (var i = 0; i < pointCount; i++) {
      final x = points[i * 4], y = points[i * 4 + 1], z = points[i * 4 + 2];
      if (x < lowX || (x == lowX && z < lowZ)) {
        lowX = x;
        lowY = y;
        lowZ = z;
        lowIndex = i;
      }
      if (x > highX || (x == highX && z > highZ)) {
        highX = x;
        highY = y;
        highZ = z;
        highIndex = i;
      }
    }
    simplified
      ..add(lowX)
      ..add(lowY)
      ..add(lowZ)
      ..add(lowIndex)
      ..add(highX)
      ..add(highY)
      ..add(highZ)
      ..add(highIndex);
  }

  final errorSquared = maxError * maxError;
  var i = 0;
  while (i < simplified.length ~/ 4) {
    final next = (i + 1) % (simplified.length ~/ 4);

    var ax = simplified[i * 4];
    var az = simplified[i * 4 + 2];
    final ai = simplified[i * 4 + 3];
    var bx = simplified[next * 4];
    var bz = simplified[next * 4 + 2];
    final bi = simplified[next * 4 + 3];

    // Walk the raw points in lexicographic order, so the two polygons sharing
    // this stretch measure the same deviation and insert the same vertex.
    // Traversing it in trace order instead lets them disagree and crack.
    int cursor;
    int step;
    int stop;
    if (bx > ax || (bx == ax && bz > az)) {
      step = 1;
      cursor = (ai + step) % pointCount;
      stop = bi;
    } else {
      step = pointCount - 1;
      cursor = (bi + step) % pointCount;
      stop = ai;
      final swapX = ax;
      ax = bx;
      bx = swapX;
      final swapZ = az;
      az = bz;
      bz = swapZ;
    }

    var worst = 0.0;
    var worstIndex = -1;
    // Only a wall is tessellated. A portal's shape is dictated by the region
    // on the other side, and refining it here would break the match.
    if (points[cursor * 4 + 3] == 0) {
      while (cursor != stop) {
        final deviation = _pointSegmentDistanceSquared(
          points[cursor * 4].toDouble(),
          points[cursor * 4 + 2].toDouble(),
          ax.toDouble(),
          az.toDouble(),
          bx.toDouble(),
          bz.toDouble(),
        );
        if (deviation > worst) {
          worst = deviation;
          worstIndex = cursor;
        }
        cursor = (cursor + step) % pointCount;
      }
    }

    if (worstIndex != -1 && worst > errorSquared) {
      simplified.insertAll((i + 1) * 4, [
        points[worstIndex * 4],
        points[worstIndex * 4 + 1],
        points[worstIndex * 4 + 2],
        worstIndex,
      ]);
    } else {
      i++;
    }
  }

  if (maxEdgeLength > 0) _splitLongEdges(points, simplified, maxEdgeLength);

  // Rewrite the stored index into the neighbour region of the edge *leaving*
  // each vertex, which is what the polygon stage reads.
  for (var v = 0; v < simplified.length ~/ 4; v++) {
    final rawIndex = simplified[v * 4 + 3];
    simplified[v * 4 + 3] = points[((rawIndex + 1) % pointCount) * 4 + 3];
  }
}

/// Subdivides wall runs longer than [maxEdgeLength] voxels.
///
/// Long edges are cheap but make coarse polygons, and a coarse polygon next to
/// a wall is what pushes a path away from it. Only walls are split, for the
/// same reason only walls are simplified.
void _splitLongEdges(
  List<int> points,
  List<int> simplified,
  int maxEdgeLength,
) {
  final pointCount = points.length ~/ 4;
  var i = 0;
  while (i < simplified.length ~/ 4) {
    final count = simplified.length ~/ 4;
    final next = (i + 1) % count;
    final ax = simplified[i * 4];
    final az = simplified[i * 4 + 2];
    final ai = simplified[i * 4 + 3];
    final bi = simplified[next * 4 + 3];

    var inserted = -1;
    // Only a stretch whose raw points are wall, and only when it is long.
    if (points[((ai + 1) % pointCount) * 4 + 3] == 0) {
      final dx = simplified[next * 4] - ax;
      final dz = simplified[next * 4 + 2] - az;
      if (dx * dx + dz * dz > maxEdgeLength * maxEdgeLength) {
        final span = bi < ai ? (bi + pointCount - ai) : (bi - ai);
        if (span > 1) {
          inserted =
              (ax > simplified[next * 4] ||
                  (ax == simplified[next * 4] && az > simplified[next * 4 + 2]))
              ? (ai + span ~/ 2) % pointCount
              : (ai + (span + 1) ~/ 2) % pointCount;
        }
      }
    }

    if (inserted >= 0) {
      simplified.insertAll((i + 1) * 4, [
        points[inserted * 4],
        points[inserted * 4 + 1],
        points[inserted * 4 + 2],
        inserted,
      ]);
    } else {
      i++;
    }
  }
}

/// Drops zero-length segments, which a trace produces wherever the outline
/// doubles back on itself around a one-cell spur.
void _removeDegenerateSegments(List<int> simplified) {
  var i = 0;
  while (i < simplified.length ~/ 4) {
    final count = simplified.length ~/ 4;
    final next = (i + 1) % count;
    if (simplified[i * 4] == simplified[next * 4] &&
        simplified[i * 4 + 2] == simplified[next * 4 + 2]) {
      simplified.removeRange(i * 4, i * 4 + 4);
    } else {
      i++;
    }
  }
}

double _pointSegmentDistanceSquared(
  double px,
  double pz,
  double ax,
  double az,
  double bx,
  double bz,
) {
  final dx = bx - ax;
  final dz = bz - az;
  var toX = px - ax;
  var toZ = pz - az;
  final lengthSquared = dx * dx + dz * dz;
  if (lengthSquared > 0) {
    var t = (dx * toX + dz * toZ) / lengthSquared;
    if (t < 0) {
      t = 0;
    } else if (t > 1) {
      t = 1;
    }
    toX = px - (ax + dx * t);
    toZ = pz - (az + dz * t);
  }
  return toX * toX + toZ * toZ;
}

/// Twice the signed area of a contour, positive when it winds
/// counter-clockwise.
///
/// The sign is how a hole is recognized: an outline traced around solid ground
/// winds one way, and one traced around an obstacle inside that ground winds
/// the other.
int contourSignedArea(Contour contour) {
  var area = 0;
  final count = contour.vertexCount;
  for (var i = 0, j = count - 1; i < count; j = i, i++) {
    final ax = contour.vertices[i * 4];
    final az = contour.vertices[i * 4 + 2];
    final bx = contour.vertices[j * 4];
    final bz = contour.vertices[j * 4 + 2];
    area += ax * bz - bx * az;
  }
  return area;
}

/// Splices each hole contour into the outline of the region that encloses it.
///
/// A region that wraps an obstacle, a pillar in the middle of a room, traces
/// two closed loops: the outer boundary and the hole, distinguishable by their
/// winding. A triangulator cannot work with two loops, so the hole is cut into
/// the outline along a diagonal, producing one loop that runs in, around the
/// obstacle, and back out. The seam is degenerate by construction and the
/// polygons on either side of it are correct.
void _mergeHoles(List<Contour> contours) {
  if (contours.isEmpty) return;

  final outlines = <int, Contour>{};
  final holes = <int, List<Contour>>{};
  for (final contour in contours) {
    if (contourSignedArea(contour) < 0) {
      (holes[contour.region] ??= []).add(contour);
    } else {
      // A second outline for one region means simplification folded the
      // contour over itself, which is a settings problem rather than a shape
      // the merge can express. Keep the first and drop the rest.
      outlines.putIfAbsent(contour.region, () => contour);
    }
  }
  if (holes.isEmpty) return;

  for (final entry in holes.entries) {
    final outline = outlines[entry.key];
    if (outline == null) continue;
    // Left to right, so an already-merged hole never sits between the outline
    // and the next hole's chosen diagonal.
    final ordered = entry.value.toList()
      ..sort((a, b) {
        final aLeft = _leftmostVertex(a);
        final bLeft = _leftmostVertex(b);
        final ax = a.vertices[aLeft * 4];
        final bx = b.vertices[bLeft * 4];
        if (ax != bx) return ax.compareTo(bx);
        return a.vertices[aLeft * 4 + 2].compareTo(b.vertices[bLeft * 4 + 2]);
      });

    for (var h = 0; h < ordered.length; h++) {
      final hole = ordered[h];
      if (hole.vertexCount == 0) continue;
      final remaining = ordered.sublist(h);
      final merged = _mergeOneHole(outline, hole, remaining);
      if (!merged) {
        // No diagonal could be found without crossing something. Dropping the
        // hole is wrong but bounded: the polygon covers the obstacle rather
        // than the mesh being malformed. It takes a pathological shape.
        hole.vertices = [];
      }
    }
  }

  // A spliced-in hole is left empty, and a contour still wound backwards is
  // one no outline claimed; neither can be triangulated.
  contours.removeWhere(
    (contour) => contour.vertexCount < 3 || contourSignedArea(contour) < 0,
  );
}

int _leftmostVertex(Contour contour) {
  var best = 0;
  for (var i = 1; i < contour.vertexCount; i++) {
    final x = contour.vertices[i * 4];
    final bestX = contour.vertices[best * 4];
    if (x < bestX ||
        (x == bestX &&
            contour.vertices[i * 4 + 2] < contour.vertices[best * 4 + 2])) {
      best = i;
    }
  }
  return best;
}

bool _mergeOneHole(Contour outline, Contour hole, List<Contour> obstacles) {
  var holeVertex = _leftmostVertex(hole);

  for (var attempt = 0; attempt < hole.vertexCount; attempt++) {
    final cornerX = hole.vertices[holeVertex * 4];
    final cornerZ = hole.vertices[holeVertex * 4 + 2];

    // Every outline vertex whose interior wedge contains the hole corner, by
    // increasing distance: the shortest workable diagonal makes the least mess
    // of the triangulation that follows.
    final candidates = <int>[];
    final outlineCount = outline.vertexCount;
    for (var j = 0; j < outlineCount; j++) {
      final previous = (j + outlineCount - 1) % outlineCount;
      final next = (j + 1) % outlineCount;
      if (!inCone(
        outline.vertices[previous * 4],
        outline.vertices[previous * 4 + 2],
        outline.vertices[j * 4],
        outline.vertices[j * 4 + 2],
        outline.vertices[next * 4],
        outline.vertices[next * 4 + 2],
        cornerX,
        cornerZ,
      )) {
        continue;
      }
      candidates.add(j);
    }
    candidates.sort((a, b) {
      final adx = outline.vertices[a * 4] - cornerX;
      final adz = outline.vertices[a * 4 + 2] - cornerZ;
      final bdx = outline.vertices[b * 4] - cornerX;
      final bdz = outline.vertices[b * 4 + 2] - cornerZ;
      return (adx * adx + adz * adz).compareTo(bdx * bdx + bdz * bdz);
    });

    for (final candidate in candidates) {
      final px = outline.vertices[candidate * 4];
      final pz = outline.vertices[candidate * 4 + 2];
      if (_crossesContour(outline, candidate, px, pz, cornerX, cornerZ)) {
        continue;
      }
      var blocked = false;
      for (final obstacle in obstacles) {
        if (obstacle.vertexCount == 0) continue;
        if (_crossesContour(obstacle, -1, px, pz, cornerX, cornerZ)) {
          blocked = true;
          break;
        }
      }
      if (blocked) continue;
      _spliceContours(outline, hole, candidate, holeVertex);
      return true;
    }

    holeVertex = (holeVertex + 1) % hole.vertexCount;
  }
  return false;
}

/// Whether the segment from (ax,az) to (bx,bz) crosses any edge of [contour],
/// ignoring the edges that touch vertex [skip] and any shared endpoint.
bool _crossesContour(
  Contour contour,
  int skip,
  int ax,
  int az,
  int bx,
  int bz,
) {
  final count = contour.vertexCount;
  for (var k = 0; k < count; k++) {
    final next = (k + 1) % count;
    if (skip == k || skip == next) continue;
    final p0x = contour.vertices[k * 4];
    final p0z = contour.vertices[k * 4 + 2];
    final p1x = contour.vertices[next * 4];
    final p1z = contour.vertices[next * 4 + 2];
    // A diagonal is allowed to land on a vertex; that is a touch, not a cross.
    if ((ax == p0x && az == p0z) ||
        (bx == p0x && bz == p0z) ||
        (ax == p1x && az == p1z) ||
        (bx == p1x && bz == p1z)) {
      continue;
    }
    if (intersects(ax, az, bx, bz, p0x, p0z, p1x, p1z)) return true;
  }
  return false;
}

/// Rewrites [outline] as itself cut open at [outlineVertex], the whole hole
/// walked from [holeVertex], and back.
void _spliceContours(
  Contour outline,
  Contour hole,
  int outlineVertex,
  int holeVertex,
) {
  final merged = <int>[];
  final outlineCount = outline.vertexCount;
  final holeCount = hole.vertexCount;

  // Both loops are closed by repeating their entry vertex, which is what
  // leaves the seam as a pair of coincident edges rather than a gap.
  for (var i = 0; i <= outlineCount; i++) {
    final v = (outlineVertex + i) % outlineCount;
    merged.addAll(outline.vertices.sublist(v * 4, v * 4 + 4));
  }
  for (var i = 0; i <= holeCount; i++) {
    final v = (holeVertex + i) % holeCount;
    merged.addAll(hole.vertices.sublist(v * 4, v * 4 + 4));
  }

  outline.vertices = merged;
  hole.vertices = [];
}
