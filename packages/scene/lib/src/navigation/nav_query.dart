import 'package:vector_math/vector_math.dart';

import 'package:scene/src/navigation/nav_geometry.dart';
import 'package:scene/src/navigation/nav_mesh.dart';

/// Why a path search ended.
enum NavPathStatus {
  /// The path reaches the requested destination.
  complete,

  /// The destination is unreachable; the path ends at the closest point the
  /// search could get to. An agent should still walk it, and a game should
  /// still treat the goal as failed.
  partial,

  /// Neither endpoint could be placed on the mesh at all.
  failed,
}

/// A route across a [NavMesh].
class NavPath {
  const NavPath({
    required this.status,
    required this.points,
    required this.polygons,
  });

  static const NavPath empty = NavPath(
    status: NavPathStatus.failed,
    points: [],
    polygons: [],
  );

  final NavPathStatus status;

  /// The corners to walk, start first and destination last. Already
  /// string-pulled, so consecutive points are in line of sight of each other
  /// across the mesh.
  final List<Vector3> points;

  /// The polygons crossed, for a caller that needs the area types along the
  /// route (playing a wading sound through water, opening a door).
  final List<int> polygons;

  bool get isEmpty => points.isEmpty;
  double get length {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += points[i].distanceTo(points[i - 1]);
    }
    return total;
  }
}

/// Per-area movement costs, so a path can prefer the road to the swamp.
///
/// A cost is a multiplier on distance: 1 is neutral, 4 means an agent would
/// rather walk four metres around than one metre through.
class NavAreaCosts {
  NavAreaCosts([Map<int, double>? costs]) {
    if (costs != null) {
      for (final entry in costs.entries) {
        this.costs[entry.key] = entry.value;
      }
    }
  }

  final List<double> costs = List<double>.filled(NavArea.max + 1, 1.0);

  double operator [](int area) => costs[area];
  void operator []=(int area, double cost) => costs[area] = cost;
}

/// Path queries against one [NavMesh].
///
/// Holds the search's working arrays, so repeated queries against the same
/// mesh do not reallocate. Not safe to use from two isolates at once; give
/// each one its own.
class NavMeshQuery {
  NavMeshQuery(this.mesh, {NavAreaCosts? areaCosts})
    : areaCosts = areaCosts ?? NavAreaCosts(),
      _cost = List<double>.filled(mesh.polygonCount, 0),
      _total = List<double>.filled(mesh.polygonCount, 0),
      _parent = List<int>.filled(mesh.polygonCount, navNoPolygon),
      _state = List<int>.filled(mesh.polygonCount, 0),
      _entry = List<Vector3?>.filled(mesh.polygonCount, null);

  final NavMesh mesh;
  final NavAreaCosts areaCosts;

  final List<double> _cost;
  final List<double> _total;
  final List<int> _parent;

  // 0 unvisited, 1 open, 2 closed.
  final List<int> _state;

  /// Where the search entered each polygon, which is what makes the cost a
  /// real distance rather than a sum of centre-to-centre hops. Two adjacent
  /// long polygons are a short walk if you cross near their shared corner.
  final List<Vector3?> _entry;

  final List<int> _touched = [];

  /// Finds a route from [start] to [end].
  ///
  /// Returns a [NavPathStatus.partial] path when the destination cannot be
  /// reached, ending at the reachable point nearest to it, because an agent
  /// told to go somewhere impossible should still set off in the right
  /// direction rather than stand still.
  NavPath findPath(Vector3 start, Vector3 end, {Vector3? halfExtents}) {
    final startPoly = mesh.findPolygon(start, halfExtents: halfExtents);
    final endPoly = mesh.findPolygon(end, halfExtents: halfExtents);
    if (startPoly == navNoPolygon || endPoly == navNoPolygon) {
      return NavPath.empty;
    }

    final startPoint = mesh.closestPointOn(startPoly, start);
    final endPoint = mesh.closestPointOn(endPoly, end);

    if (startPoly == endPoly) {
      return NavPath(
        status: NavPathStatus.complete,
        points: [startPoint, endPoint],
        polygons: [startPoly],
      );
    }

    final corridor = _search(startPoly, endPoly, startPoint, endPoint);
    if (corridor == null) return NavPath.empty;
    final (polygons, reachedGoal) = corridor;

    final goal = reachedGoal
        ? endPoint
        : mesh.closestPointOn(polygons.last, endPoint);
    final points = _stringPull(polygons, startPoint, goal);
    return NavPath(
      status: reachedGoal ? NavPathStatus.complete : NavPathStatus.partial,
      points: points,
      polygons: polygons,
    );
  }

  void _resetTouched() {
    for (final poly in _touched) {
      _state[poly] = 0;
      _parent[poly] = navNoPolygon;
      _entry[poly] = null;
    }
    _touched.clear();
  }

  /// A* over the polygon graph. Returns the corridor and whether it reaches
  /// [endPoly].
  (List<int>, bool)? _search(
    int startPoly,
    int endPoly,
    Vector3 startPoint,
    Vector3 endPoint,
  ) {
    _resetTouched();

    final open = HeapPriorityQueue<_Node>();
    _cost[startPoly] = 0;
    _total[startPoly] = startPoint.distanceTo(endPoint);
    _entry[startPoly] = startPoint;
    _state[startPoly] = 1;
    _touched.add(startPoly);
    open.add(_Node(startPoly, _total[startPoly]));

    var bestPoly = startPoly;
    var bestHeuristic = _total[startPoly];

    while (open.isNotEmpty) {
      final node = open.removeFirst();
      final poly = node.polygon;
      if (_state[poly] == 2) continue;
      _state[poly] = 2;

      if (poly == endPoly) return (_corridorTo(endPoly), true);

      final from = _entry[poly]!;
      final count = mesh.vertexCountOf(poly);
      for (var edge = 0; edge < count; edge++) {
        final neighbour = mesh.neighbourOf(poly, edge);
        if (neighbour == navNoPolygon) continue;
        if (_state[neighbour] == 2) continue;
        final area = mesh.areas[neighbour];
        if (area == NavArea.nonWalkable) continue;

        // Enter the neighbour at the middle of the shared portal, which is
        // where the string pull will end up putting the corner anyway.
        final (left, right) = mesh.portalOf(poly, edge);
        final crossing = (left + right)..scale(0.5);

        final step = from.distanceTo(crossing) * areaCosts[area];
        final cost = _cost[poly] + step;
        final heuristic = crossing.distanceTo(endPoint);
        final total = cost + heuristic;

        if (_state[neighbour] != 0 && cost >= _cost[neighbour]) continue;
        if (_state[neighbour] == 0) _touched.add(neighbour);
        _cost[neighbour] = cost;
        _total[neighbour] = total;
        _parent[neighbour] = poly;
        _entry[neighbour] = crossing;
        _state[neighbour] = 1;
        open.add(_Node(neighbour, total));

        if (heuristic < bestHeuristic) {
          bestHeuristic = heuristic;
          bestPoly = neighbour;
        }
      }
    }

    // Exhausted without reaching the goal: hand back the corridor to whatever
    // got closest.
    return (_corridorTo(bestPoly), false);
  }

  List<int> _corridorTo(int poly) {
    final reversed = <int>[];
    var current = poly;
    while (current != navNoPolygon) {
      reversed.add(current);
      current = _parent[current];
    }
    return reversed.reversed.toList();
  }

  /// The simple stupid funnel algorithm.
  ///
  /// A corridor of polygons is not a path; walking their centres gives the
  /// wobble everyone recognises as bad pathfinding. The funnel narrows the
  /// left and right bounds of what is still visible from the current corner
  /// and only emits a corner when they cross, which yields the shortest route
  /// through the corridor.
  List<Vector3> _stringPull(List<int> corridor, Vector3 start, Vector3 end) {
    final points = <Vector3>[start];
    if (corridor.length < 2) {
      points.add(end);
      return points;
    }

    // The portals to squeeze through, plus a degenerate one at the goal so the
    // final corner falls out of the same loop.
    final leftEdge = <Vector3>[];
    final rightEdge = <Vector3>[];
    for (var i = 0; i < corridor.length - 1; i++) {
      final edge = mesh.edgeTo(corridor[i], corridor[i + 1]);
      if (edge < 0) continue;
      final (a, b) = mesh.portalOf(corridor[i], edge);
      // Orient the portal consistently: the polygon's winding decides which
      // endpoint is on the left as the path passes through it.
      leftEdge.add(a);
      rightEdge.add(b);
    }
    leftEdge.add(end);
    rightEdge.add(end);

    var apex = start;
    var left = apex;
    var right = apex;
    var apexIndex = 0;
    var leftIndex = 0;
    var rightIndex = 0;

    for (var i = 0; i < leftEdge.length; i++) {
      final nextLeft = leftEdge[i];
      final nextRight = rightEdge[i];

      // Tighten the right bound if it does not overshoot the left one.
      if (_triangleArea(apex, right, nextRight) <= 0) {
        if (_samePoint(apex, right) ||
            _triangleArea(apex, left, nextRight) > 0) {
          right = nextRight;
          rightIndex = i;
        } else {
          // The bounds crossed: the left bound is a corner of the path.
          points.add(left);
          apex = left;
          apexIndex = leftIndex;
          left = apex;
          right = apex;
          leftIndex = apexIndex;
          rightIndex = apexIndex;
          i = apexIndex;
          continue;
        }
      }

      if (_triangleArea(apex, left, nextLeft) >= 0) {
        if (_samePoint(apex, left) ||
            _triangleArea(apex, right, nextLeft) < 0) {
          left = nextLeft;
          leftIndex = i;
        } else {
          points.add(right);
          apex = right;
          apexIndex = rightIndex;
          left = apex;
          right = apex;
          leftIndex = apexIndex;
          rightIndex = apexIndex;
          i = apexIndex;
          continue;
        }
      }
    }

    if (points.isEmpty || !_samePoint(points.last, end)) points.add(end);
    return points;
  }

  static double _triangleArea(Vector3 a, Vector3 b, Vector3 c) =>
      (c.x - a.x) * (b.z - a.z) - (b.x - a.x) * (c.z - a.z);

  static bool _samePoint(Vector3 a, Vector3 b) =>
      (a.x - b.x).abs() < 1e-4 && (a.z - b.z).abs() < 1e-4;

  /// Walks from [start] toward [end] across the mesh, stopping at the first
  /// wall.
  ///
  /// The nav-mesh answer to "can I just go straight there", used to shortcut a
  /// path request and to let an agent cut a corner it can see past. Returns
  /// the point reached and whether it is [end].
  (Vector3, bool) raycast(Vector3 start, Vector3 end, {Vector3? halfExtents}) {
    var poly = mesh.findPolygon(start, halfExtents: halfExtents);
    if (poly == navNoPolygon) return (start.clone(), false);

    var current = mesh.closestPointOn(poly, start);
    // Bounded by the polygon count: a straight line cannot re-enter a convex
    // polygon it has left.
    for (var step = 0; step < mesh.polygonCount + 1; step++) {
      if (mesh.containsXZ(poly, end.x, end.z)) {
        return (Vector3(end.x, mesh.heightAt(poly, end.x, end.z), end.z), true);
      }

      final count = mesh.vertexCountOf(poly);
      var exitEdge = -1;
      var exitT = double.infinity;
      Vector3? exitPoint;
      for (var edge = 0; edge < count; edge++) {
        final (a, b) = mesh.portalOf(poly, edge);
        final hit = _segmentIntersectionT(start, end, a, b);
        if (hit == null) continue;
        // Strictly forward, so the edge just crossed is not chosen again.
        if (hit <= 1e-6 || hit >= exitT) continue;
        exitT = hit;
        exitEdge = edge;
        exitPoint = Vector3(
          start.x + (end.x - start.x) * hit,
          0,
          start.z + (end.z - start.z) * hit,
        );
      }
      if (exitEdge == -1 || exitPoint == null) return (current, false);

      exitPoint.y = mesh.heightAt(poly, exitPoint.x, exitPoint.z);
      final neighbour = mesh.neighbourOf(poly, exitEdge);
      if (neighbour == navNoPolygon ||
          mesh.areas[neighbour] == NavArea.nonWalkable) {
        return (exitPoint, false);
      }
      current = exitPoint;
      poly = neighbour;
    }
    return (current, false);
  }
}

/// Where along a-b the segments cross, or null when they do not, on XZ.
double? _segmentIntersectionT(Vector3 a, Vector3 b, Vector3 c, Vector3 d) {
  final rx = b.x - a.x, rz = b.z - a.z;
  final sx = d.x - c.x, sz = d.z - c.z;
  final denominator = rx * sz - rz * sx;
  if (denominator.abs() < 1e-12) return null;
  final qpx = c.x - a.x, qpz = c.z - a.z;
  final t = (qpx * sz - qpz * sx) / denominator;
  final u = (qpx * rz - qpz * rx) / denominator;
  if (t < 0 || t > 1 || u < 0 || u > 1) return null;
  return t;
}

class _Node implements Comparable<_Node> {
  _Node(this.polygon, this.total);

  final int polygon;
  final double total;

  @override
  int compareTo(_Node other) => total.compareTo(other.total);
}

/// A binary heap, so the open set is a real priority queue rather than a
/// linear scan. A* over a large mesh is dominated by this.
class HeapPriorityQueue<E extends Comparable<E>> {
  final List<E> _items = [];

  bool get isNotEmpty => _items.isNotEmpty;
  int get length => _items.length;

  void add(E value) {
    _items.add(value);
    var child = _items.length - 1;
    while (child > 0) {
      final parent = (child - 1) >> 1;
      if (_items[child].compareTo(_items[parent]) >= 0) break;
      final swap = _items[child];
      _items[child] = _items[parent];
      _items[parent] = swap;
      child = parent;
    }
  }

  E removeFirst() {
    final first = _items.first;
    final last = _items.removeLast();
    if (_items.isEmpty) return first;
    _items[0] = last;
    var parent = 0;
    while (true) {
      final left = parent * 2 + 1;
      if (left >= _items.length) break;
      final right = left + 1;
      var smallest = left;
      if (right < _items.length && _items[right].compareTo(_items[left]) < 0) {
        smallest = right;
      }
      if (_items[parent].compareTo(_items[smallest]) <= 0) break;
      final swap = _items[parent];
      _items[parent] = _items[smallest];
      _items[smallest] = swap;
      parent = smallest;
    }
    return first;
  }
}
