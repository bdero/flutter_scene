/// Pathfinding across a [NavTileSet].
///
/// The same A* the single-mesh query runs, over a graph whose nodes are
/// (tile, polygon) pairs. Within a tile it follows the mesh's own neighbour
/// links; between tiles it follows the boundary links the set computed when
/// each tile was installed.
library;

import 'package:vector_math/vector_math.dart';

import 'package:scene/src/navigation/nav_geometry.dart';
import 'package:scene/src/navigation/nav_mesh.dart';
import 'package:scene/src/navigation/nav_query.dart';
import 'package:scene/src/navigation/nav_tiles.dart';

/// A route across tiles.
/// {@category Navigation}
class NavTilePath {
  const NavTilePath({
    required this.status,
    required this.points,
    required this.polygons,
  });

  static const NavTilePath empty = NavTilePath(
    status: NavPathStatus.failed,
    points: [],
    polygons: [],
  );

  final NavPathStatus status;

  /// The route, as world-space corners.
  final List<Vector3> points;

  /// The corridor it runs through, tile by tile.
  final List<NavTilePolygon> polygons;

  bool get isEmpty => points.isEmpty;
}

/// Path queries against a [NavTileSet].
///
/// Holds the search's working maps, so repeated queries against the same set
/// do not reallocate. Not safe to use from two isolates at once; give each
/// one its own.
/// {@category Navigation}
class NavTileMeshQuery {
  NavTileMeshQuery(this.tiles, {NavAreaCosts? areaCosts})
    : areaCosts = areaCosts ?? NavAreaCosts();

  final NavTileSet tiles;
  final NavAreaCosts areaCosts;

  // Keyed maps rather than the single-mesh query's flat arrays: a tile set is
  // sparse and its polygon count changes as tiles come and go, so there is no
  // stable index to size an array by.
  final Map<NavTilePolygon, double> _cost = {};
  final Map<NavTilePolygon, NavTilePolygon?> _parent = {};
  final Map<NavTilePolygon, Vector3> _entry = {};
  final Set<NavTilePolygon> _closed = {};

  /// The polygon containing (or nearest to) [point], searching the tile it
  /// falls in and then that tile's neighbours.
  ///
  /// The neighbours matter at a seam: a point a hair over the boundary is
  /// geometrically in the next tile but standing on this one's polygon.
  NavTilePolygon? findPolygon(Vector3 point, {Vector3? halfExtents}) {
    final home = tiles.tileAt(point.x, point.z);
    for (final key in [
      home,
      (x: home.x - 1, z: home.z),
      (x: home.x + 1, z: home.z),
      (x: home.x, z: home.z - 1),
      (x: home.x, z: home.z + 1),
    ]) {
      final mesh = tiles.tile(key);
      if (mesh == null) continue;
      final poly = mesh.findPolygon(point, halfExtents: halfExtents);
      if (poly != navNoPolygon) return (tile: key, polygon: poly);
    }
    return null;
  }

  /// Finds a route from [start] to [end].
  ///
  /// As with the single-mesh query, an unreachable destination gives a
  /// [NavPathStatus.partial] path ending at the closest reachable point,
  /// because an agent told to go somewhere impossible should still set off
  /// the right way.
  NavTilePath findPath(Vector3 start, Vector3 end, {Vector3? halfExtents}) {
    final startPoly = findPolygon(start, halfExtents: halfExtents);
    final endPoly = findPolygon(end, halfExtents: halfExtents);
    if (startPoly == null || endPoly == null) return NavTilePath.empty;

    final startPoint = _closestOn(startPoly, start);
    final endPoint = _closestOn(endPoly, end);

    if (startPoly == endPoly) {
      return NavTilePath(
        status: NavPathStatus.complete,
        points: [startPoint, endPoint],
        polygons: [startPoly],
      );
    }

    _cost.clear();
    _parent.clear();
    _entry.clear();
    _closed.clear();

    final open = HeapPriorityQueue<_TileNode>();
    _cost[startPoly] = 0;
    _entry[startPoly] = startPoint;
    _parent[startPoly] = null;
    open.add(_TileNode(startPoly, startPoint.distanceTo(endPoint)));

    var best = startPoly;
    var bestHeuristic = startPoint.distanceTo(endPoint);
    var reached = false;

    while (open.isNotEmpty) {
      final node = open.removeFirst();
      final poly = node.polygon;
      if (!_closed.add(poly)) continue;

      if (poly == endPoly) {
        reached = true;
        best = endPoly;
        break;
      }

      final from = _entry[poly]!;
      for (final step in _neighboursOf(poly)) {
        if (_closed.contains(step.to)) continue;
        final mesh = tiles.tile(step.to.tile);
        if (mesh == null) continue;
        final area = mesh.areas[step.to.polygon];
        if (area == NavArea.nonWalkable) continue;

        final crossing = step.crossing;
        final cost = _cost[poly]! + from.distanceTo(crossing) * areaCosts[area];
        final known = _cost[step.to];
        if (known != null && known <= cost) continue;

        _cost[step.to] = cost;
        _parent[step.to] = poly;
        _entry[step.to] = crossing;
        final heuristic = crossing.distanceTo(endPoint);
        if (heuristic < bestHeuristic) {
          bestHeuristic = heuristic;
          best = step.to;
        }
        open.add(_TileNode(step.to, cost + heuristic));
      }
    }

    final corridor = <NavTilePolygon>[];
    NavTilePolygon? walk = best;
    while (walk != null) {
      corridor.add(walk);
      walk = _parent[walk];
    }
    final route = corridor.reversed.toList();
    if (route.isEmpty) return NavTilePath.empty;

    // The corner-by-corner string pull the single-mesh query does needs
    // portals that are shared edges; across a tile seam the two polygons only
    // overlap, so the route is reported through the entry points the search
    // already found. They are on the portals, so the path is walkable, just
    // not funnel-tightened across seams.
    final points = <Vector3>[startPoint];
    for (var i = 1; i < route.length; i++) {
      final entry = _entry[route[i]];
      if (entry != null) points.add(entry);
    }
    points.add(reached ? endPoint : _closestOn(route.last, endPoint));

    return NavTilePath(
      status: reached ? NavPathStatus.complete : NavPathStatus.partial,
      points: points,
      polygons: route,
    );
  }

  Vector3 _closestOn(NavTilePolygon poly, Vector3 point) =>
      tiles.tile(poly.tile)!.closestPointOn(poly.polygon, point);

  /// Every polygon reachable in one step from [poly]: its own tile's
  /// neighbours across shared edges, then the boundary links to other tiles.
  Iterable<_TileStep> _neighboursOf(NavTilePolygon poly) sync* {
    final mesh = tiles.tile(poly.tile);
    if (mesh == null) return;
    final corners = mesh.vertexCountOf(poly.polygon);
    for (var edge = 0; edge < corners; edge++) {
      final neighbour = mesh.neighbourOf(poly.polygon, edge);
      if (neighbour == navNoPolygon) continue;
      final (left, right) = mesh.portalOf(poly.polygon, edge);
      yield _TileStep(
        to: (tile: poly.tile, polygon: neighbour),
        crossing: (left + right)..scale(0.5),
      );
    }
    for (final link in tiles.linksFrom(poly.tile)) {
      if (link.from.polygon != poly.polygon) continue;
      final corners = mesh.vertexCountOf(poly.polygon);
      final a = mesh.vertexOf(poly.polygon, link.fromEdge) * 3;
      final b = mesh.vertexOf(poly.polygon, (link.fromEdge + 1) % corners) * 3;
      yield _TileStep(
        to: link.to,
        crossing: Vector3(
          (mesh.vertices[a] + mesh.vertices[b]) * 0.5,
          (mesh.vertices[a + 1] + mesh.vertices[b + 1]) * 0.5,
          (mesh.vertices[a + 2] + mesh.vertices[b + 2]) * 0.5,
        ),
      );
    }
  }
}

class _TileStep {
  _TileStep({required this.to, required this.crossing});

  final NavTilePolygon to;
  final Vector3 crossing;
}

class _TileNode implements Comparable<_TileNode> {
  _TileNode(this.polygon, this.total);

  final NavTilePolygon polygon;
  final double total;

  @override
  int compareTo(_TileNode other) => total.compareTo(other.total);
}
