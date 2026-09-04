import 'package:scene/src/grid/grid_coord.dart';

/// Sparse per-cell storage: what is on each tile.
///
/// A grid says where cells are; a [GridMap] says what is in them. It is sparse
/// rather than a dense array, so a map can be unbounded, most of it empty, and
/// still cost only what is actually stored — which is what a procedurally
/// generated or streamed world needs.
///
/// ```dart
/// final terrain = GridMap<TerrainKind>();
/// terrain[GridCoord(3, -2)] = TerrainKind.water;
///
/// // Later, in a movement cost function:
/// final kind = terrain[cell] ?? TerrainKind.grass;
/// ```
class GridMap<T> {
  /// Creates an empty map.
  GridMap();

  /// Creates a map with [value] in every cell of [region].
  factory GridMap.filled(GridRect region, T value) {
    final map = GridMap<T>();
    for (final cell in region.cells) {
      map[cell] = value;
    }
    return map;
  }

  /// Creates a map from existing entries.
  factory GridMap.from(Map<GridCoord, T> entries) {
    final map = GridMap<T>();
    entries.forEach((cell, value) => map[cell] = value);
    return map;
  }

  final Map<GridCoord, T> _cells = <GridCoord, T>{};

  // Invalidated on every write, recomputed on demand: callers ask for the
  // bounds far less often than they fill cells in.
  GridRect? _bounds;
  bool _boundsValid = true;

  /// The value at [cell], or null when nothing is stored there.
  T? operator [](GridCoord cell) => _cells[cell];

  /// Stores [value] at [cell].
  void operator []=(GridCoord cell, T value) {
    final isNew = !_cells.containsKey(cell);
    _cells[cell] = value;
    if (isNew) _growBounds(cell);
  }

  /// The value at [cell], or [fallback] when nothing is stored there.
  T valueAt(GridCoord cell, T fallback) => _cells[cell] ?? fallback;

  /// Removes [cell]'s value and returns it, or null when it had none.
  T? remove(GridCoord cell) {
    final removed = _cells.remove(cell);
    // The removed cell may have been on the boundary.
    if (removed != null) _boundsValid = false;
    return removed;
  }

  /// Whether [cell] holds a value.
  bool contains(GridCoord cell) => _cells.containsKey(cell);

  /// How many cells hold a value.
  int get length => _cells.length;

  /// Whether no cell holds a value.
  bool get isEmpty => _cells.isEmpty;

  /// Whether any cell holds a value.
  bool get isNotEmpty => _cells.isNotEmpty;

  /// The cells that hold a value.
  Iterable<GridCoord> get cells => _cells.keys;

  /// The stored values.
  Iterable<T> get values => _cells.values;

  /// The stored cell-value pairs.
  Iterable<MapEntry<GridCoord, T>> get entries => _cells.entries;

  /// Empties the map.
  void clear() {
    _cells.clear();
    _bounds = null;
    _boundsValid = true;
  }

  /// The smallest [GridRect] containing every filled cell, or null when the
  /// map is empty.
  GridRect? get bounds {
    if (!_boundsValid) {
      _bounds = GridRect.bounding(_cells.keys);
      _boundsValid = true;
    }
    return _bounds;
  }

  /// The cells whose values satisfy [test].
  Iterable<GridCoord> where(bool Function(GridCoord cell, T value) test) =>
      _cells.entries
          .where((entry) => test(entry.key, entry.value))
          .map((entry) => entry.key);

  /// A new map with every value passed through [convert].
  GridMap<R> mapValues<R>(R Function(GridCoord cell, T value) convert) {
    final result = GridMap<R>();
    _cells.forEach((cell, value) => result[cell] = convert(cell, value));
    return result;
  }

  /// Calls [action] for every filled cell.
  void forEach(void Function(GridCoord cell, T value) action) =>
      _cells.forEach(action);

  void _growBounds(GridCoord cell) {
    if (!_boundsValid) return;
    final current = _bounds;
    if (current == null) {
      _bounds = GridRect(cell, cell);
      return;
    }
    if (current.contains(cell)) return;
    _bounds = GridRect(
      GridCoord(
        cell.x < current.min.x ? cell.x : current.min.x,
        cell.y < current.min.y ? cell.y : current.min.y,
      ),
      GridCoord(
        cell.x > current.max.x ? cell.x : current.max.x,
        cell.y > current.max.y ? cell.y : current.max.y,
      ),
    );
  }

  @override
  String toString() => 'GridMap($length cells)';
}
