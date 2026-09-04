import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'package:scene/src/grid/grid.dart';
import 'package:scene/src/grid/grid_coord.dart';

/// A grid of square cells: the tiling behind most strategy games, city
/// builders, tactics games, roguelikes, and puzzle boards.
///
/// [cellSize] is the edge length. Cell `(0, 0)` is centred on the grid's
/// origin and spans half a cell in each direction, so `x` grows east and `y`
/// grows toward `+Z`.
///
/// [allowDiagonals] decides the whole feel of movement on the grid. With it
/// off, a cell has four neighbours and distance is measured in city blocks
/// (Manhattan), which is what a game wants when a diagonal move should not be
/// a shortcut. With it on, a cell has eight neighbours and distance is the
/// larger of the two axis differences (Chebyshev), so a diagonal step costs
/// the same as a straight one — cheap and fast, but it makes diagonal travel
/// about 40% faster across open ground. Charge `sqrt(2)` for diagonal steps in
/// the cost function passed to [findGridPath] if that matters.
///
/// ```dart
/// final grid = SquareGrid(cellSize: 2.0);
/// final cell = grid.cellAt(hit.point);       // which tile was clicked
/// building.position = grid.center(cell);     // snap onto it
/// ```
class SquareGrid extends Grid {
  /// Creates a square grid of [cellSize]-wide cells.
  const SquareGrid({
    required super.cellSize,
    this.allowDiagonals = false,
    super.origin,
    super.elevation,
  });

  /// Whether the four diagonal cells count as neighbours.
  final bool allowDiagonals;

  static const List<GridCoord> _orthogonal = <GridCoord>[
    GridCoord(1, 0),
    GridCoord(0, 1),
    GridCoord(-1, 0),
    GridCoord(0, -1),
  ];

  static const List<GridCoord> _diagonal = <GridCoord>[
    GridCoord(1, 1),
    GridCoord(-1, 1),
    GridCoord(-1, -1),
    GridCoord(1, -1),
  ];

  /// The four orthogonal steps, then the four diagonals when
  /// [allowDiagonals] is set. Handy for walking outward from a cell without
  /// allocating a neighbour list per cell.
  List<GridCoord> get directions =>
      allowDiagonals ? <GridCoord>[..._orthogonal, ..._diagonal] : _orthogonal;

  @override
  int get neighborCount => allowDiagonals ? 8 : 4;

  @override
  Vector3 center(GridCoord cell) => Vector3(
    origin.x + cell.x * cellSize,
    elevation,
    origin.z + cell.y * cellSize,
  );

  @override
  GridCoord cellAtXZ(double x, double z) => GridCoord(
    ((x - origin.x) / cellSize).round(),
    ((z - origin.z) / cellSize).round(),
  );

  @override
  List<Vector3> corners(GridCoord cell) {
    final middle = center(cell);
    final half = cellSize * 0.5;
    return <Vector3>[
      Vector3(middle.x - half, elevation, middle.z - half),
      Vector3(middle.x + half, elevation, middle.z - half),
      Vector3(middle.x + half, elevation, middle.z + half),
      Vector3(middle.x - half, elevation, middle.z + half),
    ];
  }

  @override
  List<GridCoord> neighborsOf(GridCoord cell) => <GridCoord>[
    for (final step in directions) cell + step,
  ];

  @override
  int distance(GridCoord a, GridCoord b) {
    final dx = (a.x - b.x).abs();
    final dy = (a.y - b.y).abs();
    // Chebyshev when a diagonal is one step, Manhattan when it is two.
    return allowDiagonals ? math.max(dx, dy) : dx + dy;
  }

  @override
  Iterable<GridCoord> cellsWithin(GridCoord center, int radius) sync* {
    if (radius < 0) return;
    for (var y = center.y - radius; y <= center.y + radius; y++) {
      for (var x = center.x - radius; x <= center.x + radius; x++) {
        final cell = GridCoord(x, y);
        // A square when diagonals are steps, a diamond when they are not.
        if (allowDiagonals || distance(center, cell) <= radius) yield cell;
      }
    }
  }
}
