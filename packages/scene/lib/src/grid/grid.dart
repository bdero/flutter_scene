import 'package:vector_math/vector_math.dart';

import 'package:scene/src/grid/grid_coord.dart';

/// Maps between integer cell addresses and world positions on the horizontal
/// plane.
///
/// A grid is the shared vocabulary a tile-based game needs: where a cell is in
/// the world, which cell a world position falls in, which cells are adjacent,
/// and how far apart two cells are in steps. Everything above it — placement,
/// pathfinding, area of effect, fog of war — is written against this interface
/// rather than against a particular tiling, so a game can change from squares
/// to hexes without touching its rules.
///
/// Cells live on the world's **XZ plane** at [elevation], matching the
/// engine's convention that Y is up. Cell `(0, 0)` is *centred* on [origin],
/// so a map built around the world origin is symmetric.
///
/// The two built-in tilings are [SquareGrid] and [HexGrid]. There is no
/// isometric grid: an isometric game is a square grid seen from an isometric
/// camera (`RtsCameraController.isometric` in `package:flutter_scene`), and
/// the tiling itself is unchanged.
abstract class Grid {
  /// Creates a grid whose cell `(0, 0)` is centred at [origin] on the XZ
  /// plane, [elevation] units above the ground.
  const Grid({
    required this.cellSize,
    this.origin = const (x: 0.0, z: 0.0),
    this.elevation = 0.0,
  }) : assert(cellSize > 0, 'A grid cell must have a positive size.');

  /// The size of one cell. Its exact meaning is the tiling's: the edge length
  /// of a square, the centre-to-corner radius of a hexagon.
  final double cellSize;

  /// The world XZ position that cell `(0, 0)` is centred on.
  final ({double x, double z}) origin;

  /// The height of the grid plane, in world units.
  final double elevation;

  /// How many cells touch a cell's edges (or corners, where the tiling counts
  /// those): four or eight for a square grid, six for a hex grid.
  int get neighborCount;

  /// The world-space centre of [cell].
  Vector3 center(GridCoord cell);

  /// The cell containing the world XZ position ([x], [z]). The Y coordinate
  /// plays no part: a point above or below the plane still lands in a cell.
  GridCoord cellAtXZ(double x, double z);

  /// The cell containing [worldPoint], ignoring its height.
  GridCoord cellAt(Vector3 worldPoint) => cellAtXZ(worldPoint.x, worldPoint.z);

  /// The corners of [cell]'s outline in world space, counter-clockwise seen
  /// from above. For drawing the cell, or hit-testing it exactly.
  List<Vector3> corners(GridCoord cell);

  /// The cells adjacent to [cell], in a stable order.
  List<GridCoord> neighborsOf(GridCoord cell);

  /// The number of steps from [a] to [b] across adjacent cells, ignoring
  /// anything blocking the way.
  ///
  /// This is the natural heuristic for [findGridPath], and it is admissible
  /// so long as no single step costs less than one.
  int distance(GridCoord a, GridCoord b);

  /// Every cell within [radius] steps of [center], the centre included.
  ///
  /// The shape follows the tiling: a square (or diamond, without diagonals)
  /// on a square grid, a hexagon on a hex grid.
  Iterable<GridCoord> cellsWithin(GridCoord center, int radius);

  /// The cells exactly [radius] steps from [center]. A radius of zero is the
  /// centre itself.
  Iterable<GridCoord> ring(GridCoord center, int radius) => radius <= 0
      ? <GridCoord>[center]
      : cellsWithin(
          center,
          radius,
        ).where((cell) => distance(center, cell) == radius);

  /// The cells a straight world-space line from [from] to [to] passes
  /// through, both ends included.
  ///
  /// Walks the line in world space and samples it, so it works the same on
  /// any tiling. Use it for line of sight, for a beam weapon, or for dragging
  /// out a wall.
  List<GridCoord> lineTo(GridCoord from, GridCoord to) {
    if (from == to) return <GridCoord>[from];
    final start = center(from);
    final end = center(to);
    // Two samples per cell of separation is enough that the walk cannot step
    // over a cell, whatever the tiling.
    final steps = distance(from, to) * 2;
    final cells = <GridCoord>[from];
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      final cell = cellAtXZ(
        start.x + (end.x - start.x) * t,
        start.z + (end.z - start.z) * t,
      );
      if (cell != cells.last) cells.add(cell);
    }
    if (cells.last != to) cells.add(to);
    return cells;
  }

  /// The block of cells covering the world-space rectangle from
  /// ([minX], [minZ]) to ([maxX], [maxZ]).
  ///
  /// Every cell whose centre falls inside the rectangle is included, which is
  /// what a drag-selection wants.
  GridRect cellsInXZRect(double minX, double minZ, double maxX, double maxZ) {
    final a = cellAtXZ(minX, minZ);
    final b = cellAtXZ(maxX, maxZ);
    return GridRect(
      GridCoord(a.x < b.x ? a.x : b.x, a.y < b.y ? a.y : b.y),
      GridCoord(a.x > b.x ? a.x : b.x, a.y > b.y ? a.y : b.y),
    );
  }

  /// Snaps [worldPoint] to the centre of the cell it falls in, keeping the
  /// grid's [elevation]. The one-liner behind placing a building on a tile.
  Vector3 snap(Vector3 worldPoint) => center(cellAt(worldPoint));
}
