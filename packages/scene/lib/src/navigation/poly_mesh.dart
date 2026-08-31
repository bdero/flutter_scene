import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'package:scene/src/navigation/contours.dart';
import 'package:scene/src/navigation/nav_config.dart';
import 'package:scene/src/navigation/poly_math.dart';

/// The neighbour slot value meaning "this edge is a wall".
const int polyNoNeighbour = 0xffff;

/// Convex polygons covering the walkable surface, with shared edges linked.
///
/// This is the last voxel-space stage. Vertices are still in cell coordinates
/// relative to [min]; [NavMesh] converts them once and keeps world units from
/// then on.
class PolyMesh {
  PolyMesh({
    required this.vertices,
    required this.polygons,
    required this.regions,
    required this.areas,
    required this.polygonCount,
    required this.maxVertsPerPolygon,
    required this.min,
    required this.max,
    required this.cellSize,
    required this.cellHeight,
  });

  /// Vertex coordinates in voxels, three per vertex: cell X, height, cell Z.
  final Uint16List vertices;

  /// Two rows of [maxVertsPerPolygon] per polygon: the vertex indices, padded
  /// with [polyNoNeighbour], then the neighbouring polygon of each edge, also
  /// [polyNoNeighbour] where the edge is a wall.
  final Uint16List polygons;

  final Uint16List regions;
  final Uint8List areas;

  final int polygonCount;
  final int maxVertsPerPolygon;

  final Vector3 min;
  final Vector3 max;
  final double cellSize;
  final double cellHeight;

  int get vertexCount => vertices.length ~/ 3;

  /// The number of vertices polygon [poly] actually has.
  int vertexCountOf(int poly) {
    final base = poly * 2 * maxVertsPerPolygon;
    for (var i = 0; i < maxVertsPerPolygon; i++) {
      if (polygons[base + i] == polyNoNeighbour) return i;
    }
    return maxVertsPerPolygon;
  }

  int vertexOf(int poly, int corner) =>
      polygons[poly * 2 * maxVertsPerPolygon + corner];

  int neighbourOf(int poly, int edge) =>
      polygons[poly * 2 * maxVertsPerPolygon + maxVertsPerPolygon + edge];
}

/// Turns region outlines into convex polygons.
///
/// Each contour is triangulated, then adjacent triangles are merged back
/// together while the result stays convex and within the vertex budget.
/// Triangulating first and merging after is not a detour: it is what makes the
/// result robust for a concave outline, which is most of them.
PolyMesh buildPolyMesh(ContourSet contourSet, NavMeshConfig config) {
  final maxVertsPerPoly = config.maxVertsPerPolygon;

  var maxVertices = 0;
  var maxTriangles = 0;
  var maxContourVertices = 0;
  for (final contour in contourSet.contours) {
    if (contour.vertexCount < 3) continue;
    maxVertices += contour.vertexCount;
    maxTriangles += contour.vertexCount - 2;
    if (contour.vertexCount > maxContourVertices) {
      maxContourVertices = contour.vertexCount;
    }
  }

  final vertices = Uint16List(maxVertices * 3);
  final polygons = Uint16List(maxTriangles * maxVertsPerPoly * 2)
    ..fillRange(0, maxTriangles * maxVertsPerPoly * 2, polyNoNeighbour);
  final regions = Uint16List(maxTriangles);
  final areas = Uint8List(maxTriangles);

  // Vertices are shared between contours wherever two regions meet, so that
  // the polygons either side of a portal reference the same two endpoints. A
  // spatial hash keyed on the cell coordinate is what finds them again.
  final vertexTable = <int, List<int>>{};
  var vertexCount = 0;
  var polygonCount = 0;

  final indices = List<int>.filled(maxContourVertices, 0);
  final triangles = List<int>.filled(maxContourVertices * 3, 0);
  final contourPolys = Uint16List((maxContourVertices + 1) * maxVertsPerPoly);
  final mergeScratch = Uint16List(maxVertsPerPoly);

  for (final contour in contourSet.contours) {
    final count = contour.vertexCount;
    if (count < 3) continue;

    for (var i = 0; i < count; i++) {
      indices[i] = i;
    }
    final triangleCount = _triangulate(
      count,
      contour.vertices,
      indices,
      triangles,
    );
    if (triangleCount <= 0) {
      // A contour that will not triangulate is one simplification folded over
      // itself. Dropping it leaves a hole in the mesh rather than a broken
      // polygon, which is the failure that can at least be seen.
      continue;
    }

    // Map this contour's vertices into the shared table.
    final localToGlobal = List<int>.filled(count, 0);
    for (var i = 0; i < count; i++) {
      localToGlobal[i] = _addVertex(
        vertexTable,
        vertices,
        contour.vertices[i * 4],
        contour.vertices[i * 4 + 1],
        contour.vertices[i * 4 + 2],
        () => vertexCount++,
      );
    }

    contourPolys.fillRange(0, contourPolys.length, polyNoNeighbour);
    var contourPolyCount = 0;
    for (var t = 0; t < triangleCount; t++) {
      final a = triangles[t * 3];
      final b = triangles[t * 3 + 1];
      final c = triangles[t * 3 + 2];
      if (a == b || a == c || b == c) continue;
      contourPolys[contourPolyCount * maxVertsPerPoly] = localToGlobal[a];
      contourPolys[contourPolyCount * maxVertsPerPoly + 1] = localToGlobal[b];
      contourPolys[contourPolyCount * maxVertsPerPoly + 2] = localToGlobal[c];
      contourPolyCount++;
    }
    if (contourPolyCount == 0) continue;

    if (maxVertsPerPoly > 3) {
      contourPolyCount = _mergePolygons(
        contourPolys,
        contourPolyCount,
        vertices,
        maxVertsPerPoly,
        mergeScratch,
      );
    }

    for (var p = 0; p < contourPolyCount; p++) {
      final destination = polygonCount * maxVertsPerPoly * 2;
      for (var i = 0; i < maxVertsPerPoly; i++) {
        polygons[destination + i] = contourPolys[p * maxVertsPerPoly + i];
      }
      regions[polygonCount] = contour.region;
      areas[polygonCount] = contour.area;
      polygonCount++;
    }
  }

  final mesh = PolyMesh(
    vertices: Uint16List.sublistView(vertices, 0, vertexCount * 3),
    polygons: polygons,
    regions: regions,
    areas: areas,
    polygonCount: polygonCount,
    maxVertsPerPolygon: maxVertsPerPoly,
    min: contourSet.min,
    max: contourSet.max,
    cellSize: contourSet.cellSize,
    cellHeight: contourSet.cellHeight,
  );
  _buildAdjacency(mesh);
  return mesh;
}

/// Interns a vertex, returning the index of an existing one at the same cell.
///
/// The bucket compares all three coordinates, so a bridge deck and the road
/// under it do not collapse onto each other despite sharing a column.
int _addVertex(
  Map<int, List<int>> table,
  Uint16List vertices,
  int x,
  int y,
  int z,
  int Function() allocate,
) {
  final key = (x * 73856093) ^ (z * 19349663);
  final bucket = table[key];
  if (bucket != null) {
    for (final candidate in bucket) {
      if (vertices[candidate * 3] == x &&
          vertices[candidate * 3 + 2] == z &&
          (vertices[candidate * 3 + 1] - y).abs() <= 2) {
        return candidate;
      }
    }
  }
  final index = allocate();
  vertices[index * 3] = x;
  vertices[index * 3 + 1] = y;
  vertices[index * 3 + 2] = z;
  (table[key] ??= []).add(index);
  return index;
}

int _vx(List<int> verts, int i) => verts[i * 4];
int _vz(List<int> verts, int i) => verts[i * 4 + 2];

/// Ear clipping over a simple polygon given as contour vertices.
///
/// Each step removes the shortest legal ear rather than the first one, which
/// keeps the triangles as fat as possible; long slivers are what make a path
/// through them zig-zag.
int _triangulate(
  int count,
  List<int> contourVertices,
  List<int> indices,
  List<int> triangles,
) {
  var n = count;
  var triangleCount = 0;
  // The high bit of an index marks "removing this vertex leaves a valid
  // diagonal", recomputed only for the two vertices a clip disturbs.
  const earFlag = 0x40000000;
  const indexMask = 0x0fffffff;

  for (var i = 0; i < n; i++) {
    final next = (i + 1) % n;
    final afterNext = (next + 1) % n;
    if (_isDiagonal(i, afterNext, n, contourVertices, indices, indexMask)) {
      indices[next] |= earFlag;
    }
  }

  while (n > 3) {
    var shortest = -1;
    var best = -1;
    for (var i = 0; i < n; i++) {
      final next = (i + 1) % n;
      if (indices[next] & earFlag == 0) continue;
      final p0 = indices[i] & indexMask;
      final p2 = indices[(next + 1) % n] & indexMask;
      final dx = _vx(contourVertices, p2) - _vx(contourVertices, p0);
      final dz = _vz(contourVertices, p2) - _vz(contourVertices, p0);
      final length = dx * dx + dz * dz;
      if (shortest < 0 || length < shortest) {
        shortest = length;
        best = i;
      }
    }

    if (best == -1) {
      // No ear at all means the outline touches itself, which simplification
      // can produce. Relax the cone test, which allows an ear across a
      // coincident vertex pair; that is exactly the seam a merged hole leaves.
      for (var i = 0; i < n; i++) {
        final next = (i + 1) % n;
        final afterNext = (next + 1) % n;
        if (!_isDiagonalLoose(
          i,
          afterNext,
          n,
          contourVertices,
          indices,
          indexMask,
        )) {
          continue;
        }
        final p0 = indices[i] & indexMask;
        final p2 = indices[(afterNext + 1) % n] & indexMask;
        final dx = _vx(contourVertices, p2) - _vx(contourVertices, p0);
        final dz = _vz(contourVertices, p2) - _vz(contourVertices, p0);
        final length = dx * dx + dz * dz;
        if (shortest < 0 || length < shortest) {
          shortest = length;
          best = i;
        }
      }
      if (best == -1) return -triangleCount;
    }

    var i = best;
    var next = (i + 1) % n;
    final afterNext = (next + 1) % n;

    triangles[triangleCount * 3] = indices[i] & indexMask;
    triangles[triangleCount * 3 + 1] = indices[next] & indexMask;
    triangles[triangleCount * 3 + 2] = indices[afterNext] & indexMask;
    triangleCount++;

    n--;
    for (var k = next; k < n; k++) {
      indices[k] = indices[k + 1];
    }
    if (next >= n) next = 0;
    i = (next + n - 1) % n;

    if (_isDiagonal(
      (i + n - 1) % n,
      next,
      n,
      contourVertices,
      indices,
      indexMask,
    )) {
      indices[i] |= earFlag;
    } else {
      indices[i] &= indexMask;
    }
    if (_isDiagonal(
      i,
      (next + 1) % n,
      n,
      contourVertices,
      indices,
      indexMask,
    )) {
      indices[next] |= earFlag;
    } else {
      indices[next] &= indexMask;
    }
  }

  triangles[triangleCount * 3] = indices[0] & indexMask;
  triangles[triangleCount * 3 + 1] = indices[1] & indexMask;
  triangles[triangleCount * 3 + 2] = indices[2] & indexMask;
  triangleCount++;
  return triangleCount;
}

bool _isDiagonal(
  int i,
  int j,
  int n,
  List<int> verts,
  List<int> indices,
  int mask,
) =>
    _inConeAt(i, j, n, verts, indices, mask) &&
    _clearOfEdges(i, j, n, verts, indices, mask);

bool _isDiagonalLoose(
  int i,
  int j,
  int n,
  List<int> verts,
  List<int> indices,
  int mask,
) =>
    _inConeLoose(i, j, n, verts, indices, mask) &&
    _clearOfEdgesLoose(i, j, n, verts, indices, mask);

bool _inConeAt(
  int i,
  int j,
  int n,
  List<int> verts,
  List<int> indices,
  int mask,
) {
  final pi = indices[i] & mask;
  final pj = indices[j] & mask;
  final piNext = indices[(i + 1) % n] & mask;
  final piPrevious = indices[(i + n - 1) % n] & mask;
  return inCone(
    _vx(verts, piPrevious),
    _vz(verts, piPrevious),
    _vx(verts, pi),
    _vz(verts, pi),
    _vx(verts, piNext),
    _vz(verts, piNext),
    _vx(verts, pj),
    _vz(verts, pj),
  );
}

bool _inConeLoose(
  int i,
  int j,
  int n,
  List<int> verts,
  List<int> indices,
  int mask,
) {
  final pi = indices[i] & mask;
  final pj = indices[j] & mask;
  final piNext = indices[(i + 1) % n] & mask;
  final piPrevious = indices[(i + n - 1) % n] & mask;
  final px = _vx(verts, pi), pz = _vz(verts, pi);
  final nx = _vx(verts, piNext), nz = _vz(verts, piNext);
  final bx = _vx(verts, piPrevious), bz = _vz(verts, piPrevious);
  final jx = _vx(verts, pj), jz = _vz(verts, pj);
  // The same split as [inCone], with every strict test relaxed to allow a
  // point exactly on the wedge boundary. That is precisely the seam a merged
  // hole leaves behind, where two coincident vertices make the strict test
  // reject the only diagonal there is.
  if (leftOn(bx, bz, px, pz, nx, nz)) {
    return leftOn(px, pz, jx, jz, bx, bz) && leftOn(jx, jz, px, pz, nx, nz);
  }
  return !(leftOn(px, pz, jx, jz, nx, nz) && leftOn(jx, jz, px, pz, bx, bz));
}

bool _clearOfEdges(
  int i,
  int j,
  int n,
  List<int> verts,
  List<int> indices,
  int mask, {
  bool loose = false,
}) {
  final d0 = indices[i] & mask;
  final d1 = indices[j] & mask;
  for (var k = 0; k < n; k++) {
    final k1 = (k + 1) % n;
    if (k == i || k1 == i || k == j || k1 == j) continue;
    final p0 = indices[k] & mask;
    final p1 = indices[k1] & mask;
    if (_sameXZ(verts, d0, p0) ||
        _sameXZ(verts, d1, p0) ||
        _sameXZ(verts, d0, p1) ||
        _sameXZ(verts, d1, p1)) {
      continue;
    }
    final hit = loose
        ? intersectProper(
            _vx(verts, d0),
            _vz(verts, d0),
            _vx(verts, d1),
            _vz(verts, d1),
            _vx(verts, p0),
            _vz(verts, p0),
            _vx(verts, p1),
            _vz(verts, p1),
          )
        : intersects(
            _vx(verts, d0),
            _vz(verts, d0),
            _vx(verts, d1),
            _vz(verts, d1),
            _vx(verts, p0),
            _vz(verts, p0),
            _vx(verts, p1),
            _vz(verts, p1),
          );
    if (hit) return false;
  }
  return true;
}

bool _clearOfEdgesLoose(
  int i,
  int j,
  int n,
  List<int> verts,
  List<int> indices,
  int mask,
) => _clearOfEdges(i, j, n, verts, indices, mask, loose: true);

bool _sameXZ(List<int> verts, int a, int b) =>
    _vx(verts, a) == _vx(verts, b) && _vz(verts, a) == _vz(verts, b);

/// Merges adjacent polygons while the result stays convex and inside the
/// vertex budget, taking the longest shared edge first.
int _mergePolygons(
  Uint16List polys,
  int count,
  Uint16List vertices,
  int maxVertsPerPoly,
  Uint16List scratch,
) {
  var polyCount = count;
  while (true) {
    var bestScore = 0;
    var bestA = -1;
    var bestB = -1;
    var bestEdgeA = 0;
    var bestEdgeB = 0;

    for (var a = 0; a < polyCount - 1; a++) {
      for (var b = a + 1; b < polyCount; b++) {
        final result = _mergeValue(polys, a, b, vertices, maxVertsPerPoly);
        if (result.$1 > bestScore) {
          bestScore = result.$1;
          bestA = a;
          bestB = b;
          bestEdgeA = result.$2;
          bestEdgeB = result.$3;
        }
      }
    }

    if (bestScore <= 0) break;

    _mergeInto(
      polys,
      bestA,
      bestB,
      bestEdgeA,
      bestEdgeB,
      maxVertsPerPoly,
      scratch,
    );
    // The merged-away polygon is replaced by the last one rather than shifting
    // everything down.
    final last = polyCount - 1;
    for (var i = 0; i < maxVertsPerPoly; i++) {
      polys[bestB * maxVertsPerPoly + i] = polys[last * maxVertsPerPoly + i];
    }
    polyCount--;
  }
  return polyCount;
}

int _polyVertexCount(Uint16List polys, int poly, int maxVertsPerPoly) {
  for (var i = 0; i < maxVertsPerPoly; i++) {
    if (polys[poly * maxVertsPerPoly + i] == polyNoNeighbour) return i;
  }
  return maxVertsPerPoly;
}

/// The length of the shared edge when [a] and [b] may merge, or 0 when they
/// may not. Returns the edge index within each polygon alongside it.
(int, int, int) _mergeValue(
  Uint16List polys,
  int a,
  int b,
  Uint16List vertices,
  int maxVertsPerPoly,
) {
  final na = _polyVertexCount(polys, a, maxVertsPerPoly);
  final nb = _polyVertexCount(polys, b, maxVertsPerPoly);
  if (na + nb - 2 > maxVertsPerPoly) return (0, 0, 0);

  var edgeA = -1;
  var edgeB = -1;
  for (var i = 0; i < na && edgeA == -1; i++) {
    var a0 = polys[a * maxVertsPerPoly + i];
    var a1 = polys[a * maxVertsPerPoly + (i + 1) % na];
    if (a0 > a1) {
      final swap = a0;
      a0 = a1;
      a1 = swap;
    }
    for (var j = 0; j < nb; j++) {
      var b0 = polys[b * maxVertsPerPoly + j];
      var b1 = polys[b * maxVertsPerPoly + (j + 1) % nb];
      if (b0 > b1) {
        final swap = b0;
        b0 = b1;
        b1 = swap;
      }
      if (a0 == b0 && a1 == b1) {
        edgeA = i;
        edgeB = j;
        break;
      }
    }
  }
  if (edgeA == -1 || edgeB == -1) return (0, 0, 0);

  // Both corners the merge would create must still turn the same way, or the
  // result is concave and the query's "am I inside this polygon" test breaks.
  if (!_turnsLeft(
    vertices,
    polys[a * maxVertsPerPoly + (edgeA + na - 1) % na],
    polys[a * maxVertsPerPoly + edgeA],
    polys[b * maxVertsPerPoly + (edgeB + 2) % nb],
  )) {
    return (0, 0, 0);
  }
  if (!_turnsLeft(
    vertices,
    polys[b * maxVertsPerPoly + (edgeB + nb - 1) % nb],
    polys[b * maxVertsPerPoly + edgeB],
    polys[a * maxVertsPerPoly + (edgeA + 2) % na],
  )) {
    return (0, 0, 0);
  }

  final v0 = polys[a * maxVertsPerPoly + edgeA];
  final v1 = polys[a * maxVertsPerPoly + (edgeA + 1) % na];
  final dx = vertices[v0 * 3] - vertices[v1 * 3];
  final dz = vertices[v0 * 3 + 2] - vertices[v1 * 3 + 2];
  // Zero-length shared edges would merge for free and produce degenerate
  // polygons, so a positive score is required.
  final score = dx * dx + dz * dz;
  return (score > 0 ? score : 1, edgeA, edgeB);
}

bool _turnsLeft(Uint16List vertices, int a, int b, int c) =>
    (vertices[b * 3] - vertices[a * 3]) *
            (vertices[c * 3 + 2] - vertices[a * 3 + 2]) -
        (vertices[c * 3] - vertices[a * 3]) *
            (vertices[b * 3 + 2] - vertices[a * 3 + 2]) <
    0;

void _mergeInto(
  Uint16List polys,
  int a,
  int b,
  int edgeA,
  int edgeB,
  int maxVertsPerPoly,
  Uint16List scratch,
) {
  final na = _polyVertexCount(polys, a, maxVertsPerPoly);
  final nb = _polyVertexCount(polys, b, maxVertsPerPoly);
  scratch.fillRange(0, maxVertsPerPoly, polyNoNeighbour);
  var n = 0;
  // Walk out of A from the far end of the shared edge, all the way round, then
  // do the same through B; the shared edge itself is what is left out.
  for (var i = 0; i < na - 1; i++) {
    scratch[n++] = polys[a * maxVertsPerPoly + (edgeA + 1 + i) % na];
  }
  for (var i = 0; i < nb - 1; i++) {
    scratch[n++] = polys[b * maxVertsPerPoly + (edgeB + 1 + i) % nb];
  }
  for (var i = 0; i < maxVertsPerPoly; i++) {
    polys[a * maxVertsPerPoly + i] = scratch[i];
  }
}

/// Links polygons that share an edge, filling the neighbour half of each
/// polygon's record.
void _buildAdjacency(PolyMesh mesh) {
  final nvp = mesh.maxVertsPerPolygon;
  // Every undirected edge, keyed by its two vertex indices. The second polygon
  // to claim an edge links to the first, which is what turns the soup of
  // polygons into a graph the search can walk.
  final edges = <int, (int, int)>{};
  for (var poly = 0; poly < mesh.polygonCount; poly++) {
    final count = mesh.vertexCountOf(poly);
    for (var edge = 0; edge < count; edge++) {
      final v0 = mesh.polygons[poly * 2 * nvp + edge];
      final v1 = mesh.polygons[poly * 2 * nvp + (edge + 1) % count];
      final low = v0 < v1 ? v0 : v1;
      final high = v0 < v1 ? v1 : v0;
      final key = low * 65536 + high;
      final existing = edges[key];
      if (existing == null) {
        edges[key] = (poly, edge);
        continue;
      }
      final (otherPoly, otherEdge) = existing;
      mesh.polygons[poly * 2 * nvp + nvp + edge] = otherPoly;
      mesh.polygons[otherPoly * 2 * nvp + nvp + otherEdge] = poly;
      // An edge shared by more than two polygons is degenerate geometry; the
      // first pairing wins and the rest stay walls.
      edges.remove(key);
    }
  }
}
