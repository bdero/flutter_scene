import 'dart:math' as math;

/// A cell address on a [Grid]: a pair of integers, whatever the grid's shape.
///
/// On a square grid [x] and [y] are the column and row. On a hex grid they are
/// the *axial* coordinates, the two-number scheme that makes hex arithmetic
/// work like square arithmetic: adding two coordinates, subtracting them, and
/// scaling them all mean what they look like they mean, and the third cube
/// coordinate (`-x - y`) is implied rather than stored.
///
/// A coordinate is a value: two coordinates with the same numbers are the same
/// coordinate, and it can be a map key. It carries no reference to the grid it
/// belongs to, so a coordinate from a square grid used against a hex grid is a
/// silent mistake rather than an error; keep one grid per coordinate space.
class GridCoord {
  /// Creates a coordinate.
  const GridCoord(this.x, this.y);

  /// The cell at the grid's origin.
  static const GridCoord origin = GridCoord(0, 0);

  /// The column, or the axial `q` on a hex grid.
  final int x;

  /// The row, or the axial `r` on a hex grid.
  final int y;

  /// The implied third cube coordinate of a hex cell, `-x - y`.
  ///
  /// The three cube coordinates always sum to zero, which is what makes hex
  /// distance and rounding straightforward. Meaningless on a square grid.
  int get z => -x - y;

  /// Component-wise addition, for stepping by a direction.
  GridCoord operator +(GridCoord other) => GridCoord(x + other.x, y + other.y);

  /// Component-wise subtraction, for the offset between two cells.
  GridCoord operator -(GridCoord other) => GridCoord(x - other.x, y - other.y);

  /// Scales both components, for stepping several cells along a direction.
  GridCoord operator *(int factor) => GridCoord(x * factor, y * factor);

  /// The coordinate mirrored through the origin.
  GridCoord operator -() => GridCoord(-x, -y);

  @override
  bool operator ==(Object other) =>
      other is GridCoord && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'GridCoord($x, $y)';
}

/// A rectangular block of cells, in coordinate space.
///
/// On a square grid this is a rectangle on the map. On a hex grid it is a
/// rhombus, because axial coordinates are not perpendicular; use it for
/// bounds and storage rather than for anything the player sees as a shape.
class GridRect {
  /// Creates the block spanning [min] to [max] inclusive.
  GridRect(this.min, this.max)
    : assert(max.x >= min.x && max.y >= min.y, 'GridRect max is below min.');

  /// The block covering [width] by [height] cells with [min] at its corner.
  GridRect.sized(GridCoord min, int width, int height)
    : this(min, GridCoord(min.x + width - 1, min.y + height - 1));

  /// The smallest block containing every coordinate in [cells], or null when
  /// there are none.
  static GridRect? bounding(Iterable<GridCoord> cells) {
    var minX = 0;
    var minY = 0;
    var maxX = 0;
    var maxY = 0;
    var seen = false;
    for (final cell in cells) {
      if (!seen) {
        minX = maxX = cell.x;
        minY = maxY = cell.y;
        seen = true;
        continue;
      }
      minX = math.min(minX, cell.x);
      minY = math.min(minY, cell.y);
      maxX = math.max(maxX, cell.x);
      maxY = math.max(maxY, cell.y);
    }
    return seen ? GridRect(GridCoord(minX, minY), GridCoord(maxX, maxY)) : null;
  }

  /// The lowest corner, inclusive.
  final GridCoord min;

  /// The highest corner, inclusive.
  final GridCoord max;

  /// Cells across.
  int get width => max.x - min.x + 1;

  /// Cells down.
  int get height => max.y - min.y + 1;

  /// The number of cells in the block.
  int get length => width * height;

  /// Whether [cell] is inside.
  bool contains(GridCoord cell) =>
      cell.x >= min.x && cell.x <= max.x && cell.y >= min.y && cell.y <= max.y;

  /// Every cell, row by row.
  Iterable<GridCoord> get cells sync* {
    for (var y = min.y; y <= max.y; y++) {
      for (var x = min.x; x <= max.x; x++) {
        yield GridCoord(x, y);
      }
    }
  }

  /// [cell] clamped inside this block.
  GridCoord clamp(GridCoord cell) =>
      GridCoord(cell.x.clamp(min.x, max.x), cell.y.clamp(min.y, max.y));

  /// This block grown by [amount] cells on every side.
  GridRect expanded(int amount) => GridRect(
    GridCoord(min.x - amount, min.y - amount),
    GridCoord(max.x + amount, max.y + amount),
  );

  @override
  bool operator ==(Object other) =>
      other is GridRect && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => 'GridRect($min..$max)';
}
