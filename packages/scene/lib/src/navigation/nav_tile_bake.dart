/// Cutting a world into tiles and baking each one.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'package:scene/src/navigation/nav_config.dart';
import 'package:scene/src/navigation/nav_geometry.dart';
import 'package:scene/src/navigation/nav_mesh.dart';
import 'package:scene/src/navigation/nav_mesh_builder.dart';
import 'package:scene/src/navigation/nav_tiles.dart';

/// Everything one tile's bake needs, with its geometry already clipped to it.
///
/// Self-contained on purpose: it crosses an isolate boundary when tiles are
/// baked in parallel, so it must carry no reference to the world it came from.
/// {@category Navigation}
class NavTileJob {
  NavTileJob({
    required this.key,
    required this.geometry,
    required this.config,
    required this.bounds,
    required this.interior,
    required this.volumes,
  });

  final NavTileKey key;

  /// The world's triangles clipped to this tile plus its border.
  final NavGeometry geometry;

  final NavMeshConfig config;

  /// The extent the voxel field covers: the tile plus its border, snapped to
  /// the global cell grid.
  ///
  /// Explicit rather than derived from [geometry], because a tile at the edge
  /// of the world holds less geometry than its own square and a field sized
  /// to that would sit off the grid its neighbours are on. Two tiles whose
  /// grids disagree produce boundary vertices a fraction of a cell apart, and
  /// nothing links.
  final (Vector3, Vector3) bounds;

  /// Which columns of the voxel field are the tile rather than its border.
  final NavInterior interior;

  final List<NavVolume> volumes;
}

/// What a tiled bake produced.
/// {@category Navigation}
class NavTiledBakeResult {
  NavTiledBakeResult({
    required this.tiles,
    required this.duration,
    required this.emptyTiles,
  });

  /// The linked tile set.
  final NavTileSet tiles;

  final Duration duration;

  /// Tiles that baked to nothing walkable: open air, water, or solid rock.
  /// Not an error, and worth reporting so a world that baked to nothing
  /// everywhere is distinguishable from one that never ran.
  final int emptyTiles;

  String describe() {
    if (tiles.tileCount == 0) {
      return 'Nothing walkable across $emptyTiles tiles. Check the agent size '
          'and what the include filter is letting through.';
    }
    return '${tiles.polygonCount} polygons across ${tiles.tileCount} tiles '
        '($emptyTiles empty), in ${duration.inMilliseconds} ms.';
  }
}

/// The tile grid [geometry] spans, given the tiling and the origin.
///
/// Returns null when the geometry is empty.
/// {@category Navigation}
({int minX, int minZ, int maxX, int maxZ})? navTileRange(
  NavGeometry geometry,
  NavMeshConfig config,
  NavTileConfig tiling, {
  Vector3? origin,
}) {
  final bounds = geometry.bounds;
  if (bounds == null || geometry.triangleCount == 0) return null;
  final start = origin ?? Vector3.zero();
  final size = tiling.tileSize(config);
  return (
    minX: ((bounds.$1.x - start.x) / size).floor(),
    minZ: ((bounds.$1.z - start.z) / size).floor(),
    maxX: ((bounds.$2.x - start.x) / size).ceil(),
    maxZ: ((bounds.$2.z - start.z) / size).ceil(),
  );
}

/// Splits [geometry] into one job per tile it covers.
///
/// Triangles are bucketed by their own XZ bounds in a single pass and then
/// clipped to each tile they reach, so a ground plane spanning the world does
/// not put the whole world into every tile's job. Clipping rather than
/// selecting is what bounds a tile's voxel field to the tile.
/// {@category Navigation}
List<NavTileJob> planNavTileBake(
  NavGeometry geometry,
  NavMeshConfig config, {
  NavTileConfig tiling = const NavTileConfig(),
  List<NavVolume> volumes = const [],
  Vector3? origin,
}) {
  final range = navTileRange(geometry, config, tiling, origin: origin);
  if (range == null) return const [];
  final start = origin ?? Vector3.zero();
  final size = tiling.tileSize(config);
  final border = tiling.borderFor(config);
  final margin = border * config.cellSize;

  // Bucket first: one pass over the triangles, each landing in the tiles its
  // own bounds reach. Without this every tile would test every triangle,
  // which for a big world is the tiling's whole cost.
  final buckets = <NavTileKey, List<int>>{};
  final vertices = geometry.vertices;
  final indices = geometry.indices;
  for (var t = 0; t < geometry.triangleCount; t++) {
    var minX = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity, maxZ = -double.infinity;
    for (var corner = 0; corner < 3; corner++) {
      final v = indices[t * 3 + corner] * 3;
      final x = vertices[v], z = vertices[v + 2];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (z < minZ) minZ = z;
      if (z > maxZ) maxZ = z;
    }
    // The margin widens the reach: a triangle just outside a tile still has
    // to be in its border.
    final loX = ((minX - margin - start.x) / size).floor();
    final hiX = ((maxX + margin - start.x) / size).floor();
    final loZ = ((minZ - margin - start.z) / size).floor();
    final hiZ = ((maxZ + margin - start.z) / size).floor();
    for (
      var z = math.max(loZ, range.minZ);
      z <= math.min(hiZ, range.maxZ);
      z++
    ) {
      for (
        var x = math.max(loX, range.minX);
        x <= math.min(hiX, range.maxX);
        x++
      ) {
        buckets.putIfAbsent((x: x, z: z), () => []).add(t);
      }
    }
  }

  final jobs = <NavTileJob>[];
  for (final entry in buckets.entries) {
    final key = entry.key;
    final tileMinX = start.x + key.x * size;
    final tileMinZ = start.z + key.z * size;
    final clipped = _clipToBox(
      geometry,
      entry.value,
      tileMinX - margin,
      tileMinZ - margin,
      tileMinX + size + margin,
      tileMinZ + size + margin,
    );
    if (clipped.triangleCount == 0) continue;

    // The field spans the tile plus its border exactly, whatever the geometry
    // happens to reach. Every term is a whole number of cells from the
    // origin, so every tile's grid is the same grid, and the boundary between
    // two tiles is a cell line in both.
    final heights = clipped.bounds!;
    final fieldBounds = (
      Vector3(tileMinX - margin, heights.$1.y, tileMinZ - margin),
      Vector3(tileMinX + size + margin, heights.$2.y, tileMinZ + size + margin),
    );

    // forBounds pads by a whole number of cells, so the tile's own edge is
    // that many cells plus the border in from the field's edge. Counted
    // rather than measured: rounding a world coordinate back into a column is
    // what put the boundary a third of a cell out.
    final inset = border + config.agentRadiusCells + 1;
    jobs.add(
      NavTileJob(
        key: key,
        geometry: clipped,
        config: config,
        bounds: fieldBounds,
        interior: (
          minX: inset,
          minZ: inset,
          maxX: inset + tiling.tileCells,
          maxZ: inset + tiling.tileCells,
        ),
        volumes: volumes,
      ),
    );
  }
  jobs.sort((a, b) {
    final byZ = a.key.z.compareTo(b.key.z);
    return byZ != 0 ? byZ : a.key.x.compareTo(b.key.x);
  });
  return jobs;
}

/// Bakes one planned tile. Pure, and safe to run on another isolate.
/// {@category Navigation}
NavMesh? bakeNavTile(NavTileJob job) => buildNavMesh(
  job.geometry,
  job.config,
  volumes: job.volumes,
  interior: job.interior,
  bounds: job.bounds,
);

/// Bakes [geometry] tile by tile and links the results.
///
/// Synchronous, so the caller's isolate does the whole world; the win here is
/// bounded memory (one tile's voxel field at a time) and the ability to
/// rebake one tile later. Run [planNavTileBake] and [bakeNavTile] yourself to
/// spread the tiles across isolates.
/// {@category Navigation}
NavTiledBakeResult bakeNavMeshTiled(
  NavGeometry geometry,
  NavMeshConfig config, {
  NavTileConfig tiling = const NavTileConfig(),
  List<NavVolume> volumes = const [],
  Vector3? origin,
  void Function(int done, int total)? onProgress,
}) {
  final watch = Stopwatch()..start();
  final jobs = planNavTileBake(
    geometry,
    config,
    tiling: tiling,
    volumes: volumes,
    origin: origin,
  );
  final set = NavTileSet(config: config, tiling: tiling, origin: origin);
  var empty = 0;
  for (var i = 0; i < jobs.length; i++) {
    final mesh = bakeNavTile(jobs[i]);
    if (mesh == null || mesh.polygonCount == 0) {
      empty++;
    } else {
      set.setTile(jobs[i].key, mesh);
    }
    onProgress?.call(i + 1, jobs.length);
  }
  watch.stop();
  return NavTiledBakeResult(
    tiles: set,
    duration: watch.elapsed,
    emptyTiles: empty,
  );
}

/// Clips the triangles named by [triangles] to an XZ box, fan-triangulating
/// whatever survives.
///
/// Sutherland-Hodgman against the box's four sides. A triangle clipped by two
/// axis planes cannot gain more than four corners, so seven is the bound on
/// the working polygon.
NavGeometry _clipToBox(
  NavGeometry geometry,
  List<int> triangles,
  double minX,
  double minZ,
  double maxX,
  double maxZ,
) {
  final builder = NavGeometryBuilder();
  final vertices = geometry.vertices;
  final indices = geometry.indices;
  final input = Float64List(21);
  final output = Float64List(21);
  final positions = <double>[];
  final triangleIndices = <int>[];

  for (final t in triangles) {
    var count = 3;
    for (var corner = 0; corner < 3; corner++) {
      final v = indices[t * 3 + corner] * 3;
      input[corner * 3] = vertices[v].toDouble();
      input[corner * 3 + 1] = vertices[v + 1].toDouble();
      input[corner * 3 + 2] = vertices[v + 2].toDouble();
    }

    count = _clipAxis(input, count, output, axis: 0, at: minX, keepAbove: true);
    if (count < 3) continue;
    count = _clipAxis(
      output,
      count,
      input,
      axis: 0,
      at: maxX,
      keepAbove: false,
    );
    if (count < 3) continue;
    count = _clipAxis(input, count, output, axis: 2, at: minZ, keepAbove: true);
    if (count < 3) continue;
    count = _clipAxis(
      output,
      count,
      input,
      axis: 2,
      at: maxZ,
      keepAbove: false,
    );
    if (count < 3) continue;

    positions.clear();
    triangleIndices.clear();
    for (var i = 0; i < count; i++) {
      positions
        ..add(input[i * 3])
        ..add(input[i * 3 + 1])
        ..add(input[i * 3 + 2]);
    }
    for (var i = 1; i < count - 1; i++) {
      triangleIndices
        ..add(0)
        ..add(i)
        ..add(i + 1);
    }
    builder.addMesh(
      positions: positions,
      triangleIndices: triangleIndices,
      area: geometry.areas[t],
    );
  }
  return builder.build();
}

/// Clips the polygon in [source] against one axis plane into [target],
/// returning the new corner count.
int _clipAxis(
  Float64List source,
  int count,
  Float64List target, {
  required int axis,
  required double at,
  required bool keepAbove,
}) {
  var written = 0;
  for (var i = 0; i < count; i++) {
    final j = (i + 1) % count;
    final a = source[i * 3 + axis];
    final b = source[j * 3 + axis];
    final aIn = keepAbove ? a >= at : a <= at;
    final bIn = keepAbove ? b >= at : b <= at;

    if (aIn) {
      target[written * 3] = source[i * 3];
      target[written * 3 + 1] = source[i * 3 + 1];
      target[written * 3 + 2] = source[i * 3 + 2];
      written++;
    }
    if (aIn != bIn) {
      final span = b - a;
      final t = span == 0 ? 0.0 : (at - a) / span;
      for (var c = 0; c < 3; c++) {
        target[written * 3 + c] =
            source[i * 3 + c] + (source[j * 3 + c] - source[i * 3 + c]) * t;
      }
      written++;
    }
    // Seven is the bound, but a degenerate input could in principle exceed
    // it; stopping is better than writing past the buffer.
    if (written >= 7) break;
  }
  return written;
}
