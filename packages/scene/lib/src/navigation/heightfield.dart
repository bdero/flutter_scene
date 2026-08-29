import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'package:scene/src/navigation/nav_config.dart';
import 'package:scene/src/navigation/nav_geometry.dart';

/// One run of solid voxels in a heightfield column.
///
/// A column holds a sorted linked list of these, so a bridge over a road is
/// two spans in the same column and the bake keeps both surfaces. That is the
/// whole reason for voxelizing rather than sampling a heightmap: a heightmap
/// has one surface per column and cannot describe an overpass.
class HeightSpan {
  HeightSpan(this.min, this.max, this.area);

  /// The first and last solid voxel of the run, in cell-height units above
  /// the field's minimum Y. [max] is exclusive.
  int min;
  int max;

  /// The [NavArea] of the surface at [max].
  int area;

  HeightSpan? next;
}

/// A column-major grid of solid voxel runs, the first stage of the bake.
///
/// Triangles are rasterized into this, then filtered, and only then is
/// anything asked about walkability. Working in voxels is what makes the
/// filters expressible at all: "is there two metres of clearance above this
/// surface" is a subtraction here and a mess of raycasts otherwise.
class Heightfield {
  Heightfield({
    required this.width,
    required this.depth,
    required this.min,
    required this.max,
    required this.cellSize,
    required this.cellHeight,
  }) : _columns = List<HeightSpan?>.filled(width * depth, null);

  /// Grid size along X and Z.
  final int width;
  final int depth;

  /// World-space bounds the grid covers.
  final Vector3 min;
  final Vector3 max;

  final double cellSize;
  final double cellHeight;

  final List<HeightSpan?> _columns;

  /// Spans in the column at [x],[z], lowest first.
  HeightSpan? spanAt(int x, int z) => _columns[x + z * width];

  /// Every column's spans, for the compact stage to walk.
  int get columnCount => _columns.length;

  HeightSpan? columnAt(int index) => _columns[index];

  /// Sizes a field to hold [bounds], padded by [config]'s agent radius so a
  /// surface flush with the edge still has room to erode.
  factory Heightfield.forBounds(
    Vector3 boundsMin,
    Vector3 boundsMax,
    NavMeshConfig config,
  ) {
    // Recast pads by 1 cell; the radius padding matters more here, because a
    // floor whose edge is the world edge would otherwise erode to nothing on
    // that side and the agent could not reach it.
    final pad = config.cellSize * (config.agentRadiusCells + 1);
    final paddedMin = Vector3(
      boundsMin.x - pad,
      boundsMin.y - config.cellHeight,
      boundsMin.z - pad,
    );
    final paddedMax = Vector3(
      boundsMax.x + pad,
      boundsMax.y + config.cellHeight,
      boundsMax.z + pad,
    );
    return Heightfield(
      width: math.max(
        1,
        ((paddedMax.x - paddedMin.x) / config.cellSize).ceil(),
      ),
      depth: math.max(
        1,
        ((paddedMax.z - paddedMin.z) / config.cellSize).ceil(),
      ),
      min: paddedMin,
      max: paddedMax,
      cellSize: config.cellSize,
      cellHeight: config.cellHeight,
    );
  }

  /// Inserts a run into the column at [x],[z], merging it with any run it
  /// touches.
  ///
  /// [mergeThreshold] is the agent's climb in voxels: when two runs merge and
  /// their tops are within it, the merged run takes the higher area, so a thin
  /// walkable surface resting on unwalkable geometry (a rug on a slope) stays
  /// walkable rather than being swallowed.
  void addSpan(
    int x,
    int z,
    int spanMin,
    int spanMax,
    int area,
    int mergeThreshold,
  ) {
    final index = x + z * width;
    final inserted = HeightSpan(spanMin, spanMax, area);

    HeightSpan? previous;
    var current = _columns[index];
    while (current != null) {
      if (current.min > inserted.max) {
        // Entirely above the new span: nothing left to merge.
        break;
      }
      if (current.max < inserted.min) {
        // Entirely below: keep walking up the column.
        previous = current;
        current = current.next;
        continue;
      }
      // They touch or overlap, so absorb the existing run and keep going, in
      // case the new span bridges several of them.
      if (current.min < inserted.min) inserted.min = current.min;
      if (current.max > inserted.max) inserted.max = current.max;
      if ((current.max - inserted.max).abs() <= mergeThreshold) {
        inserted.area = math.max(inserted.area, current.area);
      }
      final removed = current;
      current = current.next;
      if (previous != null) {
        previous.next = current;
      } else {
        _columns[index] = current;
      }
      removed.next = null;
    }

    inserted.next = current;
    if (previous != null) {
      previous.next = inserted;
    } else {
      _columns[index] = inserted;
    }
  }
}

/// Rasterizes [geometry] into a new heightfield sized to hold it.
///
/// A triangle's walkability is decided here, from its normal against
/// [NavMeshConfig.walkableSlopeCosine], unless the geometry names an area for
/// it. Returns null when the geometry is empty.
Heightfield? rasterizeNavGeometry(
  NavGeometry geometry,
  NavMeshConfig config, {
  (Vector3, Vector3)? bounds,
}) {
  // An explicit extent is what a tiled bake needs: every tile's field has to
  // sit on one global cell grid, or the boundary between two tiles lands part
  // of a cell apart in each and their edges never line up.
  final extent = bounds ?? geometry.bounds;
  if (extent == null || geometry.triangleCount == 0) return null;
  final field = Heightfield.forBounds(extent.$1, extent.$2, config);

  final vertices = geometry.vertices;
  final indices = geometry.indices;
  final walkableCosine = config.walkableSlopeCosine;
  final climb = config.agentMaxClimbCells;

  // One triangle's vertices plus the four clipping buffers, reused across the
  // whole rasterization. This loop runs once per triangle per covered cell and
  // is where a bake spends most of its time, so it allocates nothing.
  //
  // Seven vertices is the bound: a triangle clipped by two axis planes cannot
  // gain more than four corners.
  final tri = Float64List(9);
  final scratch = _ClipScratch();

  for (var t = 0; t < geometry.triangleCount; t++) {
    for (var corner = 0; corner < 3; corner++) {
      final v = indices[t * 3 + corner] * 3;
      tri[corner * 3] = vertices[v].toDouble();
      tri[corner * 3 + 1] = vertices[v + 1].toDouble();
      tri[corner * 3 + 2] = vertices[v + 2].toDouble();
    }

    var area = geometry.areas[t];
    if (area == NavArea.nonWalkable) {
      area = _isWalkableSlope(tri, walkableCosine)
          ? NavArea.walkable
          : NavArea.nonWalkable;
    }
    // An unwalkable triangle is still rasterized. It has to be: a wall is what
    // stops the floor beside it from having clearance, and the ledge filter can
    // only see a drop if the geometry below it exists.
    _rasterizeTriangle(field, tri, area, climb, scratch);
  }
  return field;
}

bool _isWalkableSlope(Float64List tri, double walkableCosine) {
  final e0x = tri[3] - tri[0];
  final e0y = tri[4] - tri[1];
  final e0z = tri[5] - tri[2];
  final e1x = tri[6] - tri[0];
  final e1y = tri[7] - tri[1];
  final e1z = tri[8] - tri[2];
  final nx = e0y * e1z - e0z * e1y;
  final ny = e0z * e1x - e0x * e1z;
  final nz = e0x * e1y - e0y * e1x;
  final length = math.sqrt(nx * nx + ny * ny + nz * nz);
  if (length == 0) return false;
  // Only an upward-facing triangle can be stood on; a ceiling at the same
  // slope is not a floor.
  return ny / length >= walkableCosine;
}

/// The four interchangeable clipping buffers, swapped rather than copied.
class _ClipScratch {
  Float64List a = Float64List(21);
  Float64List b = Float64List(21);
  Float64List c = Float64List(21);
  Float64List d = Float64List(21);
  final Float64List distances = Float64List(8);
}

void _rasterizeTriangle(
  Heightfield field,
  Float64List tri,
  int area,
  int mergeThreshold,
  _ClipScratch scratch,
) {
  final fieldMin = field.min;
  final cellSize = field.cellSize;
  final inverseCellSize = 1.0 / cellSize;
  final inverseCellHeight = 1.0 / field.cellHeight;
  final fieldHeight = field.max.y - field.min.y;

  final triMinY = math.min(tri[1], math.min(tri[4], tri[7]));
  final triMaxY = math.max(tri[1], math.max(tri[4], tri[7]));
  if (triMaxY < fieldMin.y || triMinY > field.max.y) return;

  final triMinZ = math.min(tri[2], math.min(tri[5], tri[8]));
  final triMaxZ = math.max(tri[2], math.max(tri[5], tri[8]));
  var z0 = ((triMinZ - fieldMin.z) * inverseCellSize).floor();
  var z1 = ((triMaxZ - fieldMin.z) * inverseCellSize).floor();
  if (z1 < 0 || z0 >= field.depth) return;
  // The low clamp is -1, not 0: a triangle that starts off the grid still has
  // to be cut at the first row boundary, or the slice handed to row 0 would be
  // everything below it as well.
  z0 = z0.clamp(-1, field.depth - 1);
  z1 = z1.clamp(0, field.depth - 1);

  var remaining = scratch.a;
  var row = scratch.b;
  var first = scratch.c;
  var second = scratch.d;
  for (var i = 0; i < 9; i++) {
    remaining[i] = tri[i];
  }
  var remainingCount = 3;

  for (var z = z0; z <= z1; z++) {
    // Cut off everything at or below this row's far edge; what is left carries
    // into the next row, so each row gets exactly its own slice.
    final rowSplit = _dividePoly(
      remaining,
      remainingCount,
      row,
      first,
      fieldMin.z + (z + 1) * cellSize,
      2,
      scratch.distances,
    );
    var rowCount = rowSplit.$1;
    remainingCount = rowSplit.$2;
    final swappedRemaining = remaining;
    remaining = first;
    first = swappedRemaining;
    if (rowCount < 3 || z < 0) continue;

    var stripMinX = row[0];
    var stripMaxX = row[0];
    for (var i = 1; i < rowCount; i++) {
      final x = row[i * 3];
      if (x < stripMinX) stripMinX = x;
      if (x > stripMaxX) stripMaxX = x;
    }
    var x0 = ((stripMinX - fieldMin.x) * inverseCellSize).floor();
    var x1 = ((stripMaxX - fieldMin.x) * inverseCellSize).floor();
    if (x1 < 0 || x0 >= field.width) continue;
    x0 = x0.clamp(-1, field.width - 1);
    x1 = x1.clamp(0, field.width - 1);

    for (var x = x0; x <= x1; x++) {
      final columnSplit = _dividePoly(
        row,
        rowCount,
        first,
        second,
        fieldMin.x + (x + 1) * cellSize,
        0,
        scratch.distances,
      );
      final cellCount = columnSplit.$1;
      rowCount = columnSplit.$2;
      final swappedRow = row;
      row = second;
      second = swappedRow;
      if (cellCount < 3 || x < 0) continue;

      var cellMinY = first[1];
      var cellMaxY = first[1];
      for (var i = 1; i < cellCount; i++) {
        final y = first[i * 3 + 1];
        if (y < cellMinY) cellMinY = y;
        if (y > cellMaxY) cellMaxY = y;
      }
      cellMinY -= fieldMin.y;
      cellMaxY -= fieldMin.y;
      if (cellMaxY < 0 || cellMinY > fieldHeight) continue;
      if (cellMinY < 0) cellMinY = 0;
      if (cellMaxY > fieldHeight) cellMaxY = fieldHeight;

      final spanMin = (cellMinY * inverseCellHeight).floor().clamp(0, 1 << 20);
      // At least one voxel tall: a perfectly flat floor lands on a voxel
      // boundary and would otherwise rasterize to nothing at all.
      final spanMax = (cellMaxY * inverseCellHeight).ceil().clamp(
        spanMin + 1,
        1 << 20,
      );
      field.addSpan(x, z, spanMin, spanMax, area, mergeThreshold);
    }
  }
}

/// Splits the convex polygon [poly] by the axis-aligned plane at
/// [axisOffset] on [axis], writing the part on the low side into [low] and the
/// part on the high side into [high]. Returns their vertex counts.
///
/// Sutherland-Hodgman, specialized to an axis plane. Both outputs are convex,
/// a polygon entirely on one side comes back whole on that side, and a vertex
/// exactly on the plane joins both.
(int, int) _dividePoly(
  Float64List poly,
  int count,
  Float64List low,
  Float64List high,
  double axisOffset,
  int axis,
  Float64List distances,
) {
  for (var i = 0; i < count; i++) {
    distances[i] = axisOffset - poly[i * 3 + axis];
  }

  var lowCount = 0;
  var highCount = 0;
  for (var i = 0, j = count - 1; i < count; j = i, i++) {
    final previousInside = distances[j] >= 0;
    final inside = distances[i] >= 0;
    if (previousInside != inside) {
      // This edge crosses the plane, so both halves take the crossing point.
      final t = distances[j] / (distances[j] - distances[i]);
      for (var k = 0; k < 3; k++) {
        final value = poly[j * 3 + k] + (poly[i * 3 + k] - poly[j * 3 + k]) * t;
        low[lowCount * 3 + k] = value;
        high[highCount * 3 + k] = value;
      }
      lowCount++;
      highCount++;
      // The vertex this edge ends on joins only its own half.
      if (inside) {
        for (var k = 0; k < 3; k++) {
          low[lowCount * 3 + k] = poly[i * 3 + k];
        }
        lowCount++;
      } else {
        for (var k = 0; k < 3; k++) {
          high[highCount * 3 + k] = poly[i * 3 + k];
        }
        highCount++;
      }
      continue;
    }
    if (inside) {
      for (var k = 0; k < 3; k++) {
        low[lowCount * 3 + k] = poly[i * 3 + k];
      }
      lowCount++;
      if (distances[i] != 0) continue;
      // Exactly on the plane: it belongs to the high half as well, or the cut
      // loses a vertex and the polygon opens up.
      for (var k = 0; k < 3; k++) {
        high[highCount * 3 + k] = poly[i * 3 + k];
      }
      highCount++;
      continue;
    }
    for (var k = 0; k < 3; k++) {
      high[highCount * 3 + k] = poly[i * 3 + k];
    }
    highCount++;
  }
  return (lowCount, highCount);
}

/// Stamps each of [volumes] onto the spans of [field] whose walkable surface
/// falls inside it, later volumes winning over earlier ones.
///
/// Runs between voxelization and the compact build, which is the one moment
/// where the surfaces exist as spans but nothing has been filtered or eroded
/// yet: a span set to [NavArea.nonWalkable] here is dropped rather than
/// stored, so a carved volume costs nothing downstream.
///
/// A span's *top* is what is tested, since that is the surface an agent would
/// stand on. A volume that only clips the underside of a floor leaves it
/// walkable, which is what anyone drawing a box around a pool expects.
void applyNavVolumes(Heightfield field, List<NavVolume> volumes) {
  if (volumes.isEmpty) return;
  for (var z = 0; z < field.depth; z++) {
    for (var x = 0; x < field.width; x++) {
      final worldX = field.min.x + (x + 0.5) * field.cellSize;
      final worldZ = field.min.z + (z + 0.5) * field.cellSize;
      var span = field.spanAt(x, z);
      while (span != null) {
        final worldY = field.min.y + span.max * field.cellHeight;
        for (final volume in volumes) {
          if (volume.contains(worldX, worldY, worldZ)) span.area = volume.area;
        }
        span = span.next;
      }
    }
  }
}
