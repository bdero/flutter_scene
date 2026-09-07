import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'package:scene/src/navigation/nav_config.dart';
import 'package:scene/src/navigation/nav_geometry.dart';
import 'package:scene/src/navigation/poly_mesh.dart';

/// The value in [NavMesh.neighbours] meaning "this edge is a wall".
const int navNoPolygon = -1;

/// A baked navigation mesh: convex polygons in world space, linked across
/// shared edges.
///
/// This is the query-time form. Everything voxel about the bake is gone by
/// here, which is what lets it serialize compactly and be loaded by a runtime
/// that never links the baker.
class NavMesh {
  NavMesh({
    required this.vertices,
    required this.polygonVertices,
    required this.polygonStart,
    required this.polygonCount,
    required this.neighbours,
    required this.areas,
    required this.regions,
    required this.config,
  }) : _centres = Float32List(polygonCount * 3),
       _bounds = Float32List(polygonCount * 6) {
    _computeDerived();
  }

  /// Vertex positions in world space, three floats per vertex.
  final Float32List vertices;

  /// Vertex indices of every polygon, laid end to end.
  final Uint16List polygonVertices;

  /// Where each polygon's indices start in [polygonVertices], with one extra
  /// entry at the end so a polygon's length is the difference of two.
  final Uint32List polygonStart;

  final int polygonCount;

  /// The polygon across each edge, parallel to [polygonVertices], or
  /// [navNoPolygon] where the edge is a wall.
  final Int32List neighbours;

  /// Per polygon [NavArea] and source region.
  final Uint8List areas;
  final Uint16List regions;

  /// The agent this mesh was baked for. A path is only valid for that agent,
  /// so the mesh carries the description with it.
  final NavMeshConfig config;

  final Float32List _centres;
  final Float32List _bounds;

  int vertexCountOf(int polygon) =>
      polygonStart[polygon + 1] - polygonStart[polygon];

  int vertexOf(int polygon, int corner) =>
      polygonVertices[polygonStart[polygon] + corner];

  int neighbourOf(int polygon, int edge) =>
      neighbours[polygonStart[polygon] + edge];

  /// The centroid of [polygon], the point a search treats it as being at.
  Vector3 centreOf(int polygon) => Vector3(
    _centres[polygon * 3],
    _centres[polygon * 3 + 1],
    _centres[polygon * 3 + 2],
  );

  void _computeDerived() {
    for (var poly = 0; poly < polygonCount; poly++) {
      final count = vertexCountOf(poly);
      var cx = 0.0, cy = 0.0, cz = 0.0;
      var minX = double.infinity,
          minY = double.infinity,
          minZ = double.infinity;
      var maxX = -double.infinity,
          maxY = -double.infinity,
          maxZ = -double.infinity;
      for (var i = 0; i < count; i++) {
        final v = vertexOf(poly, i) * 3;
        final x = vertices[v], y = vertices[v + 1], z = vertices[v + 2];
        cx += x;
        cy += y;
        cz += z;
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (z < minZ) minZ = z;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
        if (z > maxZ) maxZ = z;
      }
      _centres[poly * 3] = cx / count;
      _centres[poly * 3 + 1] = cy / count;
      _centres[poly * 3 + 2] = cz / count;
      _bounds[poly * 6] = minX;
      _bounds[poly * 6 + 1] = minY;
      _bounds[poly * 6 + 2] = minZ;
      _bounds[poly * 6 + 3] = maxX;
      _bounds[poly * 6 + 4] = maxY;
      _bounds[poly * 6 + 5] = maxZ;
    }
  }

  /// Whether [point] is inside [polygon] when viewed from above.
  bool containsXZ(int polygon, double x, double z) {
    final count = vertexCountOf(polygon);
    var inside = false;
    for (var i = 0, j = count - 1; i < count; j = i, i++) {
      final vi = vertexOf(polygon, i) * 3;
      final vj = vertexOf(polygon, j) * 3;
      final iz = vertices[vi + 2];
      final jz = vertices[vj + 2];
      if ((iz > z) == (jz > z)) continue;
      final ix = vertices[vi];
      final jx = vertices[vj];
      if (x < (jx - ix) * (z - iz) / (jz - iz) + ix) inside = !inside;
    }
    return inside;
  }

  /// The height of [polygon]'s plane at [x],[z], for placing an agent on it.
  double heightAt(int polygon, double x, double z) {
    // The polygon is planar only approximately, so this is the average of the
    // corners weighted by inverse distance rather than a plane solve: it is
    // stable for a fan-shaped polygon where a plane fit is not.
    final count = vertexCountOf(polygon);
    var weightSum = 0.0;
    var heightSum = 0.0;
    for (var i = 0; i < count; i++) {
      final v = vertexOf(polygon, i) * 3;
      final dx = vertices[v] - x;
      final dz = vertices[v + 2] - z;
      final distanceSquared = dx * dx + dz * dz;
      if (distanceSquared < 1e-9) return vertices[v + 1];
      final weight = 1.0 / distanceSquared;
      weightSum += weight;
      heightSum += vertices[v + 1] * weight;
    }
    return weightSum == 0 ? 0 : heightSum / weightSum;
  }

  /// The polygon containing [point], preferring the one whose surface is
  /// nearest in height. Returns [navNoPolygon] when none is within [halfExtents].
  ///
  /// Height matters as much as the XZ test: standing on a bridge, the road
  /// below contains the same XZ point, and returning it would path the agent
  /// through the deck.
  int findPolygon(Vector3 point, {Vector3? halfExtents}) {
    final extents = halfExtents ?? Vector3(2, config.agentHeight, 2);
    var best = navNoPolygon;
    var bestDelta = double.infinity;
    for (var poly = 0; poly < polygonCount; poly++) {
      if (point.x < _bounds[poly * 6] - extents.x ||
          point.x > _bounds[poly * 6 + 3] + extents.x ||
          point.z < _bounds[poly * 6 + 2] - extents.z ||
          point.z > _bounds[poly * 6 + 5] + extents.z) {
        continue;
      }
      if (!containsXZ(poly, point.x, point.z)) continue;
      final delta = (heightAt(poly, point.x, point.z) - point.y).abs();
      if (delta > extents.y) continue;
      if (delta < bestDelta) {
        bestDelta = delta;
        best = poly;
      }
    }
    if (best != navNoPolygon) return best;

    // Nothing contains the point, so fall back to the nearest polygon whose
    // bounds overlap the search box. An agent pushed slightly off the mesh by
    // physics should still be able to ask for a path.
    var bestDistance = double.infinity;
    for (var poly = 0; poly < polygonCount; poly++) {
      final closest = closestPointOn(poly, point);
      final distance = closest.distanceToSquared(point);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = poly;
      }
    }
    final limit = math.max(extents.x, extents.z);
    return bestDistance <= limit * limit ? best : navNoPolygon;
  }

  /// The point on [polygon] closest to [point].
  Vector3 closestPointOn(int polygon, Vector3 point) {
    if (containsXZ(polygon, point.x, point.z)) {
      return Vector3(point.x, heightAt(polygon, point.x, point.z), point.z);
    }
    final count = vertexCountOf(polygon);
    var best = Vector3.zero();
    var bestDistance = double.infinity;
    for (var i = 0, j = count - 1; i < count; j = i, i++) {
      final vi = vertexOf(polygon, i) * 3;
      final vj = vertexOf(polygon, j) * 3;
      final candidate = _closestOnSegment(
        point,
        Vector3(vertices[vj], vertices[vj + 1], vertices[vj + 2]),
        Vector3(vertices[vi], vertices[vi + 1], vertices[vi + 2]),
      );
      final distance = candidate.distanceToSquared(point);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
    }
    return best;
  }

  /// The two endpoints of the edge between [polygon] and its neighbour across
  /// [edge], the portal a path passes through.
  (Vector3, Vector3) portalOf(int polygon, int edge) {
    final count = vertexCountOf(polygon);
    final a = vertexOf(polygon, edge) * 3;
    final b = vertexOf(polygon, (edge + 1) % count) * 3;
    return (
      Vector3(vertices[a], vertices[a + 1], vertices[a + 2]),
      Vector3(vertices[b], vertices[b + 1], vertices[b + 2]),
    );
  }

  /// The edge index of [polygon] that leads to [neighbour], or -1.
  int edgeTo(int polygon, int neighbour) {
    final count = vertexCountOf(polygon);
    for (var edge = 0; edge < count; edge++) {
      if (neighbourOf(polygon, edge) == neighbour) return edge;
    }
    return -1;
  }
}

Vector3 _closestOnSegment(Vector3 point, Vector3 a, Vector3 b) {
  final abx = b.x - a.x, aby = b.y - a.y, abz = b.z - a.z;
  final lengthSquared = abx * abx + aby * aby + abz * abz;
  if (lengthSquared < 1e-12) return a.clone();
  var t =
      ((point.x - a.x) * abx + (point.y - a.y) * aby + (point.z - a.z) * abz) /
      lengthSquared;
  t = t.clamp(0.0, 1.0);
  return Vector3(a.x + abx * t, a.y + aby * t, a.z + abz * t);
}

/// Converts the voxel-space [PolyMesh] into a world-space [NavMesh].
NavMesh navMeshFromPolyMesh(PolyMesh mesh, NavMeshConfig config) {
  final nvp = mesh.maxVertsPerPolygon;

  final vertices = Float32List(mesh.vertexCount * 3);
  for (var i = 0; i < mesh.vertexCount; i++) {
    vertices[i * 3] = mesh.min.x + mesh.vertices[i * 3] * mesh.cellSize;
    vertices[i * 3 + 1] =
        mesh.min.y + mesh.vertices[i * 3 + 1] * mesh.cellHeight;
    vertices[i * 3 + 2] = mesh.min.z + mesh.vertices[i * 3 + 2] * mesh.cellSize;
  }

  var totalCorners = 0;
  for (var poly = 0; poly < mesh.polygonCount; poly++) {
    totalCorners += mesh.vertexCountOf(poly);
  }

  final polygonVertices = Uint16List(totalCorners);
  final neighbours = Int32List(totalCorners);
  final polygonStart = Uint32List(mesh.polygonCount + 1);
  final areas = Uint8List(mesh.polygonCount);
  final regions = Uint16List(mesh.polygonCount);

  var cursor = 0;
  for (var poly = 0; poly < mesh.polygonCount; poly++) {
    polygonStart[poly] = cursor;
    final count = mesh.vertexCountOf(poly);
    for (var i = 0; i < count; i++) {
      polygonVertices[cursor] = mesh.polygons[poly * 2 * nvp + i];
      final neighbour = mesh.polygons[poly * 2 * nvp + nvp + i];
      neighbours[cursor] = neighbour == polyNoNeighbour
          ? navNoPolygon
          : neighbour;
      cursor++;
    }
    areas[poly] = mesh.areas[poly];
    regions[poly] = mesh.regions[poly];
  }
  polygonStart[mesh.polygonCount] = cursor;

  return NavMesh(
    vertices: vertices,
    polygonVertices: polygonVertices,
    polygonStart: polygonStart,
    polygonCount: mesh.polygonCount,
    neighbours: neighbours,
    areas: areas,
    regions: regions,
    config: config,
  );
}
