/// Baking a nav mesh in tiles.
///
/// A single-shot bake voxelizes the whole world at once, which for an open
/// world means a voxel field that does not fit in memory and a wall-clock
/// time measured in minutes. Tiling cuts the world into a grid, bakes each
/// square on its own, and links the results, which bounds peak memory to one
/// tile, lets tiles bake in parallel, and makes editing one corner of a world
/// a rebake of one tile instead of all of it.
///
/// The hard part is the seam. Each tile is voxelized with a border of extra
/// cells so erosion and region growing see across the boundary and reach the
/// same answer its neighbour does; the border is then cut before contours are
/// traced, so a tile's polygons stop exactly at its edge. Tiles are linked by
/// matching boundary edges that *overlap* along the shared line rather than
/// by matching vertices exactly, because each tile simplifies its own
/// contours and two independent simplifications of the same line do not land
/// on the same points.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'package:scene/src/navigation/nav_config.dart';
import 'package:scene/src/navigation/nav_mesh.dart';

/// How a world is cut into tiles.
/// {@category Navigation}
class NavTileConfig {
  const NavTileConfig({this.tileCells = 128, this.borderCells})
    : assert(tileCells >= 8),
      assert(borderCells == null || borderCells >= 0);

  /// Cells along each side of a tile. At the default cell size of 0.3 this is
  /// a tile about 38 units across.
  ///
  /// Smaller tiles bake faster individually and rebake more cheaply, but the
  /// border is a fixed cost per tile, so past a point most of the work is
  /// border. A tile under about 32 cells spends more time on its margins than
  /// its middle.
  final int tileCells;

  /// Cells of margin voxelized around each tile and thrown away.
  ///
  /// Null derives it from the agent: erosion reaches the agent's radius, and
  /// region growing a little further, so the border has to cover both or a
  /// tile's edge would erode against nothing and disagree with its neighbour.
  final int? borderCells;

  /// The border this config uses for [config].
  int borderFor(NavMeshConfig config) =>
      borderCells ?? config.agentRadiusCells + 3;

  /// The world size of one tile's side.
  double tileSize(NavMeshConfig config) => tileCells * config.cellSize;
}

/// Where a tile sits in the world grid.
/// {@category Navigation}
typedef NavTileKey = ({int x, int z});

/// One polygon of a tiled mesh: which tile, and which polygon in it.
/// {@category Navigation}
typedef NavTilePolygon = ({NavTileKey tile, int polygon});

/// A link across a tile boundary: an edge of one tile's polygon that opens
/// onto another tile's polygon.
/// {@category Navigation}
class NavTileLink {
  const NavTileLink({
    required this.from,
    required this.fromEdge,
    required this.to,
  });

  /// The polygon the link leaves.
  final NavTilePolygon from;

  /// Which of its edges, as an index into its corners.
  final int fromEdge;

  /// The polygon it arrives at.
  final NavTilePolygon to;
}

/// A world's nav mesh, as a grid of independently baked tiles.
///
/// Tiles can be added, replaced, and removed one at a time; the links to
/// their neighbours are recomputed for just the tiles involved, so editing
/// one corner of a world costs one tile's bake rather than the world's.
/// {@category Navigation}
class NavTileSet {
  NavTileSet({required this.config, required this.tiling, Vector3? origin})
    : origin = origin ?? Vector3.zero();

  /// The agent this whole set was baked for.
  final NavMeshConfig config;

  final NavTileConfig tiling;

  /// The world point tile (0, 0) starts at. Every tile's bounds derive from
  /// this, so two tiles baked in different runs still land on the same grid.
  final Vector3 origin;

  final Map<NavTileKey, NavMesh> _tiles = {};
  final Map<NavTileKey, List<NavTileLink>> _links = {};

  /// The tiles present, in no particular order.
  Iterable<NavTileKey> get tiles => _tiles.keys;

  int get tileCount => _tiles.length;

  /// The total polygons across every tile.
  int get polygonCount =>
      _tiles.values.fold(0, (sum, mesh) => sum + mesh.polygonCount);

  NavMesh? tile(NavTileKey key) => _tiles[key];

  /// The links leaving [key]'s polygons for other tiles.
  List<NavTileLink> linksFrom(NavTileKey key) => _links[key] ?? const [];

  /// The world-space XZ bounds of tile [key], excluding its border.
  (Vector2, Vector2) boundsOf(NavTileKey key) {
    final size = tiling.tileSize(config);
    final minX = origin.x + key.x * size;
    final minZ = origin.z + key.z * size;
    return (Vector2(minX, minZ), Vector2(minX + size, minZ + size));
  }

  /// The tile a world-space XZ position falls in.
  NavTileKey tileAt(double x, double z) {
    final size = tiling.tileSize(config);
    return (
      x: ((x - origin.x) / size).floor(),
      z: ((z - origin.z) / size).floor(),
    );
  }

  /// Installs [mesh] as tile [key], replacing whatever was there, and relinks
  /// it to its four neighbours.
  ///
  /// A null or empty mesh removes the tile, which is what a tile of pure
  /// water or empty air bakes to.
  void setTile(NavTileKey key, NavMesh? mesh) {
    if (mesh == null || mesh.polygonCount == 0) {
      _tiles.remove(key);
    } else {
      _tiles[key] = mesh;
    }
    _relink(key);
  }

  void removeTile(NavTileKey key) => setTile(key, null);

  /// Recomputes the links between [key] and its neighbours, both directions.
  void _relink(NavTileKey key) {
    for (final neighbour in _neighboursOf(key)) {
      _linkPair(key, neighbour);
      _linkPair(neighbour, key);
    }
    if (!_tiles.containsKey(key)) _links.remove(key);
  }

  Iterable<NavTileKey> _neighboursOf(NavTileKey key) => [
    (x: key.x - 1, z: key.z),
    (x: key.x + 1, z: key.z),
    (x: key.x, z: key.z - 1),
    (x: key.x, z: key.z + 1),
  ];

  /// Rebuilds the links from [a] to [b], dropping any stale ones first.
  void _linkPair(NavTileKey a, NavTileKey b) {
    final existing = _links[a];
    if (existing != null) existing.removeWhere((link) => link.to.tile == b);

    final meshA = _tiles[a];
    final meshB = _tiles[b];
    if (meshA == null || meshB == null) return;

    // The two tiles share exactly one line: a vertical one when they differ
    // in x, a horizontal one when they differ in z.
    final size = tiling.tileSize(config);
    final horizontal = a.z == b.z;
    final shared = horizontal
        ? origin.x + math.max(a.x, b.x) * size
        : origin.z + math.max(a.z, b.z) * size;

    final edgesB = _boundaryEdges(meshB, b, horizontal: horizontal, at: shared);
    if (edgesB.isEmpty) return;
    final edgesA = _boundaryEdges(meshA, a, horizontal: horizontal, at: shared);

    final links = _links.putIfAbsent(a, () => []);
    for (final edge in edgesA) {
      for (final other in edgesB) {
        // Overlap along the shared line, and close enough in height that an
        // agent could step between them. Exact vertex equality would fail:
        // each tile simplified its own contour and they do not agree on where
        // the intermediate points went.
        final overlap =
            math.min(edge.high, other.high) - math.max(edge.low, other.low);
        if (overlap <= _linkEpsilon) continue;
        if ((edge.y - other.y).abs() > config.agentMaxClimb) continue;
        links.add(
          NavTileLink(
            from: (tile: a, polygon: edge.polygon),
            fromEdge: edge.edge,
            to: (tile: b, polygon: other.polygon),
          ),
        );
      }
    }
    if (links.isEmpty) _links.remove(a);
  }

  /// A hair of overlap is a shared corner, not a doorway.
  static const double _linkEpsilon = 1e-4;

  /// Every wall edge of [mesh] lying on the line [at], as an interval along
  /// the other axis plus its height.
  List<_BoundaryEdge> _boundaryEdges(
    NavMesh mesh,
    NavTileKey key, {
    required bool horizontal,
    required double at,
  }) {
    // The boundary is a cell line, and a contour vertex sits on it exactly,
    // but only to float precision; a fraction of a cell is the right
    // tolerance.
    final tolerance = config.cellSize * 0.25;
    final out = <_BoundaryEdge>[];
    for (var poly = 0; poly < mesh.polygonCount; poly++) {
      final corners = mesh.vertexCountOf(poly);
      for (var edge = 0; edge < corners; edge++) {
        // Only a wall can open onto another tile; an edge with a neighbour is
        // already interior.
        if (mesh.neighbourOf(poly, edge) != navNoPolygon) continue;
        final a = mesh.vertexOf(poly, edge) * 3;
        final b = mesh.vertexOf(poly, (edge + 1) % corners) * 3;
        final ax = mesh.vertices[a], az = mesh.vertices[a + 2];
        final bx = mesh.vertices[b], bz = mesh.vertices[b + 2];
        final onLine = horizontal
            ? (ax - at).abs() <= tolerance && (bx - at).abs() <= tolerance
            : (az - at).abs() <= tolerance && (bz - at).abs() <= tolerance;
        if (!onLine) continue;
        final low = horizontal ? math.min(az, bz) : math.min(ax, bx);
        final high = horizontal ? math.max(az, bz) : math.max(ax, bx);
        out.add(
          _BoundaryEdge(
            polygon: poly,
            edge: edge,
            low: low,
            high: high,
            y: (mesh.vertices[a + 1] + mesh.vertices[b + 1]) * 0.5,
          ),
        );
      }
    }
    return out;
  }
}

class _BoundaryEdge {
  _BoundaryEdge({
    required this.polygon,
    required this.edge,
    required this.low,
    required this.high,
    required this.y,
  });

  final int polygon;
  final int edge;
  final double low;
  final double high;
  final double y;
}
