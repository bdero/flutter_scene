import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'package:scene/src/grid/grid.dart';
import 'package:scene/src/grid/grid_coord.dart';

/// Which way a hexagon's points face.
///
/// The choice is a layout decision, not a gameplay one: the coordinates and
/// the distances are identical either way, only the world positions differ.
/// Pointy-top hexes tile into horizontal rows and are the usual choice for a
/// wargame map; flat-top hexes tile into vertical columns and suit a board
/// that scrolls up and down.
enum HexOrientation {
  /// A vertex at the top. Rows run east-west.
  pointyTop,

  /// An edge at the top. Columns run north-south.
  flatTop,
}

/// A grid of hexagonal cells, addressed in axial coordinates.
///
/// Hexes are worth the arithmetic when movement should not favour the compass
/// directions: every one of a cell's six neighbours is the same distance away,
/// so there is no diagonal to exploit and no need to fudge the cost of one.
///
/// [cellSize] is the hexagon's **circumradius**, the distance from its centre
/// to any corner (equivalently, the length of one edge). A hexagon's width and
/// height differ, and both follow from it:
///
///  * pointy-top: `sqrt(3) * cellSize` wide, `2 * cellSize` tall.
///  * flat-top: `2 * cellSize` wide, `sqrt(3) * cellSize` tall.
///
/// Coordinates are axial ([GridCoord.x] is `q`, [GridCoord.y] is `r`), so
/// adding and subtracting them behaves; the third cube coordinate is
/// [GridCoord.z]. Distance is the standard cube distance, which counts steps
/// exactly with no special cases.
///
/// ```dart
/// final grid = HexGrid(cellSize: 1.0);
/// for (final cell in grid.cellsWithin(origin, 2)) {
///   // every tile within two moves
/// }
/// ```
class HexGrid extends Grid {
  /// Creates a hex grid whose cells have a circumradius of [cellSize].
  const HexGrid({
    required super.cellSize,
    this.orientation = HexOrientation.pointyTop,
    super.origin,
    super.elevation,
  });

  /// Which way the hexagons point.
  final HexOrientation orientation;

  static final double _sqrt3 = math.sqrt(3.0);

  /// The six axial steps, starting east and running counter-clockwise seen
  /// from above.
  static const List<GridCoord> directions = <GridCoord>[
    GridCoord(1, 0),
    GridCoord(1, -1),
    GridCoord(0, -1),
    GridCoord(-1, 0),
    GridCoord(-1, 1),
    GridCoord(0, 1),
  ];

  @override
  int get neighborCount => 6;

  /// The width of one hexagon, in world units.
  double get cellWidth => orientation == HexOrientation.pointyTop
      ? _sqrt3 * cellSize
      : 2 * cellSize;

  /// The height of one hexagon, in world units.
  double get cellHeight => orientation == HexOrientation.pointyTop
      ? 2 * cellSize
      : _sqrt3 * cellSize;

  @override
  Vector3 center(GridCoord cell) {
    final q = cell.x.toDouble();
    final r = cell.y.toDouble();
    final double x;
    final double z;
    if (orientation == HexOrientation.pointyTop) {
      x = cellSize * (_sqrt3 * q + _sqrt3 / 2 * r);
      z = cellSize * (1.5 * r);
    } else {
      x = cellSize * (1.5 * q);
      z = cellSize * (_sqrt3 / 2 * q + _sqrt3 * r);
    }
    return Vector3(origin.x + x, elevation, origin.z + z);
  }

  @override
  GridCoord cellAtXZ(double x, double z) {
    final px = (x - origin.x) / cellSize;
    final pz = (z - origin.z) / cellSize;
    final double q;
    final double r;
    if (orientation == HexOrientation.pointyTop) {
      q = (_sqrt3 / 3 * px) - (1 / 3 * pz);
      r = 2 / 3 * pz;
    } else {
      q = 2 / 3 * px;
      r = (-1 / 3 * px) + (_sqrt3 / 3 * pz);
    }
    return _roundAxial(q, r);
  }

  /// Rounds fractional axial coordinates to the nearest cell.
  ///
  /// Rounding each axis on its own would land outside the hexagon near its
  /// corners, so this rounds all three cube coordinates and then repairs
  /// whichever moved furthest, restoring the invariant that they sum to zero.
  static GridCoord _roundAxial(double q, double r) {
    final s = -q - r;
    var rq = q.roundToDouble();
    var rr = r.roundToDouble();
    var rs = s.roundToDouble();

    final dq = (rq - q).abs();
    final dr = (rr - r).abs();
    final ds = (rs - s).abs();

    if (dq > dr && dq > ds) {
      rq = -rr - rs;
    } else if (dr > ds) {
      rr = -rq - rs;
    } else {
      rs = -rq - rr;
    }
    return GridCoord(rq.toInt(), rr.toInt());
  }

  @override
  List<Vector3> corners(GridCoord cell) {
    final middle = center(cell);
    // A pointy-top hexagon has a corner straight up the +Z axis; a flat-top
    // one is the same ring turned by 30 degrees.
    final offset = orientation == HexOrientation.pointyTop ? math.pi / 6 : 0.0;
    return <Vector3>[
      for (var i = 0; i < 6; i++)
        () {
          final angle = offset + i * math.pi / 3;
          return Vector3(
            middle.x + cellSize * math.cos(angle),
            elevation,
            middle.z + cellSize * math.sin(angle),
          );
        }(),
    ];
  }

  @override
  List<GridCoord> neighborsOf(GridCoord cell) => <GridCoord>[
    for (final step in directions) cell + step,
  ];

  @override
  int distance(GridCoord a, GridCoord b) {
    final dq = a.x - b.x;
    final dr = a.y - b.y;
    final ds = a.z - b.z;
    return (dq.abs() + dr.abs() + ds.abs()) ~/ 2;
  }

  @override
  Iterable<GridCoord> cellsWithin(GridCoord center, int radius) sync* {
    if (radius < 0) return;
    for (var dq = -radius; dq <= radius; dq++) {
      final low = math.max(-radius, -dq - radius);
      final high = math.min(radius, -dq + radius);
      for (var dr = low; dr <= high; dr++) {
        yield GridCoord(center.x + dq, center.y + dr);
      }
    }
  }

  @override
  Iterable<GridCoord> ring(GridCoord center, int radius) sync* {
    if (radius <= 0) {
      yield center;
      return;
    }
    // Walk to one corner of the ring, then follow its six sides.
    var cell = center + directions[4] * radius;
    for (var side = 0; side < 6; side++) {
      for (var step = 0; step < radius; step++) {
        yield cell;
        cell += directions[side];
      }
    }
  }
}
