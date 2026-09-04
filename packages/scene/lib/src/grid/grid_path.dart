import 'package:scene/src/grid/grid.dart';
import 'package:scene/src/grid/grid_coord.dart';

/// The result of a [findGridPath] search.
class GridPath {
  /// Creates a result.
  const GridPath({
    required this.cells,
    required this.cost,
    required this.reachedGoal,
  });

  /// A search that found nothing at all.
  static const GridPath none = GridPath(
    cells: <GridCoord>[],
    cost: 0.0,
    reachedGoal: false,
  );

  /// The route, starting at the start cell and ending at the goal (or at the
  /// closest reachable cell, when [reachedGoal] is false).
  final List<GridCoord> cells;

  /// The total cost of the route, summed from the step costs.
  final double cost;

  /// Whether the route actually arrives.
  ///
  /// Check it. A unit ordered somewhere it cannot reach should usually still
  /// walk as far as it can — but the *game* needs to know the order failed,
  /// and this is the only thing that says so.
  final bool reachedGoal;

  /// How many cells the route passes through, the start included.
  int get length => cells.length;

  /// Whether the search produced no route at all (not even a partial one).
  bool get isEmpty => cells.isEmpty;
}

/// Finds the cheapest route from [start] to [goal] across [grid].
///
/// [stepCost] is asked what it costs to move from one cell to an adjacent
/// one, and returning **null means impassable**. Everything about the terrain
/// lives in that function, so the search itself needs to know nothing about
/// the game:
///
/// ```dart
/// final path = findGridPath(grid, from, to, stepCost: (from, to) {
///   final tile = terrain[to];
///   if (tile == null || tile.blocked) return null;   // wall, or off the map
///   return tile.movementCost;                        // 1 road, 2 mud, ...
/// });
/// ```
///
/// The search is A* with the grid's own [Grid.distance] as its heuristic. That
/// heuristic is admissible — and so the route is genuinely the cheapest — as
/// long as no single step costs less than [minStepCost]. Lower [minStepCost]
/// if some terrain is cheaper than one; the search stays correct and gets
/// slower. Raise it above the true minimum and the search gets faster but may
/// return a route that is not the cheapest.
///
/// [maxVisited] bounds the work so a request into a sealed-off region cannot
/// stall a frame. On hitting it, or when the goal is genuinely unreachable,
/// the search returns the route to the closest cell it reached when
/// [allowPartial] is set, and [GridPath.none] otherwise.
GridPath findGridPath(
  Grid grid,
  GridCoord start,
  GridCoord goal, {
  required double? Function(GridCoord from, GridCoord to) stepCost,
  double minStepCost = 1.0,
  int maxVisited = 20000,
  bool allowPartial = true,
}) {
  assert(
    minStepCost > 0,
    'A step must cost something, or A* cannot terminate.',
  );
  if (start == goal) {
    return GridPath(cells: <GridCoord>[start], cost: 0.0, reachedGoal: true);
  }

  final cameFrom = <GridCoord, GridCoord>{};
  final costSoFar = <GridCoord, double>{start: 0.0};
  final closed = <GridCoord>{};
  final open = _Heap()..add(start, grid.distance(start, goal) * minStepCost);

  // Tracked so an unreachable goal still yields the best effort rather than
  // nothing: the reached cell with the smallest remaining distance, ties
  // broken by the cheaper route to it.
  var closest = start;
  var closestDistance = grid.distance(start, goal);
  var closestCost = 0.0;
  var visited = 0;

  while (!open.isEmpty) {
    final current = open.removeFirst();
    if (!closed.add(current)) continue;

    if (current == goal) {
      return _reconstruct(cameFrom, start, goal, costSoFar[goal]!, true);
    }

    if (++visited > maxVisited) break;

    final currentCost = costSoFar[current]!;
    for (final next in grid.neighborsOf(current)) {
      if (closed.contains(next)) continue;
      final step = stepCost(current, next);
      if (step == null) continue;
      assert(step >= 0, 'A step cost cannot be negative.');

      final tentative = currentCost + step;
      final known = costSoFar[next];
      if (known != null && tentative >= known) continue;

      costSoFar[next] = tentative;
      cameFrom[next] = current;
      final remaining = grid.distance(next, goal);
      open.add(next, tentative + remaining * minStepCost);

      if (remaining < closestDistance ||
          (remaining == closestDistance && tentative < closestCost)) {
        closest = next;
        closestDistance = remaining;
        closestCost = tentative;
      }
    }
  }

  if (!allowPartial || closest == start) return GridPath.none;
  return _reconstruct(cameFrom, start, closest, closestCost, false);
}

GridPath _reconstruct(
  Map<GridCoord, GridCoord> cameFrom,
  GridCoord start,
  GridCoord end,
  double cost,
  bool reachedGoal,
) {
  final cells = <GridCoord>[end];
  var walk = end;
  while (walk != start) {
    final previous = cameFrom[walk];
    if (previous == null) break;
    walk = previous;
    cells.add(walk);
  }
  return GridPath(
    cells: cells.reversed.toList(growable: false),
    cost: cost,
    reachedGoal: reachedGoal,
  );
}

/// A binary min-heap over cells keyed by their A* priority.
///
/// Entries are never updated in place: a cell reached more cheaply is pushed
/// again and the stale entry is skipped when it surfaces (the closed set
/// catches it). That is the standard trade — a few redundant entries in
/// exchange for never having to find and re-sort an existing one.
class _Heap {
  final List<GridCoord> _cells = <GridCoord>[];
  final List<double> _priorities = <double>[];

  bool get isEmpty => _cells.isEmpty;

  void add(GridCoord cell, double priority) {
    _cells.add(cell);
    _priorities.add(priority);
    var index = _cells.length - 1;
    while (index > 0) {
      final parent = (index - 1) >> 1;
      if (_priorities[parent] <= _priorities[index]) break;
      _swap(parent, index);
      index = parent;
    }
  }

  GridCoord removeFirst() {
    final first = _cells.first;
    final lastIndex = _cells.length - 1;
    _cells[0] = _cells[lastIndex];
    _priorities[0] = _priorities[lastIndex];
    _cells.removeLast();
    _priorities.removeLast();

    var index = 0;
    final length = _cells.length;
    while (true) {
      final left = index * 2 + 1;
      if (left >= length) break;
      final right = left + 1;
      var smallest = left;
      if (right < length && _priorities[right] < _priorities[left]) {
        smallest = right;
      }
      if (_priorities[index] <= _priorities[smallest]) break;
      _swap(index, smallest);
      index = smallest;
    }
    return first;
  }

  void _swap(int a, int b) {
    final cell = _cells[a];
    _cells[a] = _cells[b];
    _cells[b] = cell;
    final priority = _priorities[a];
    _priorities[a] = _priorities[b];
    _priorities[b] = priority;
  }
}
