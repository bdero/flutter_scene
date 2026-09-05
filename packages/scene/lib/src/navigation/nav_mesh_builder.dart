import 'package:scene/src/navigation/compact_heightfield.dart';
import 'package:scene/src/navigation/contours.dart';
import 'package:scene/src/navigation/heightfield.dart';
import 'package:vector_math/vector_math.dart';

import 'package:scene/src/navigation/nav_config.dart';
import 'package:scene/src/navigation/nav_geometry.dart';
import 'package:scene/src/navigation/nav_mesh.dart';
import 'package:scene/src/navigation/poly_mesh.dart';
import 'package:scene/src/navigation/regions.dart';

/// The stages of a bake, for a progress report or a debug view.
enum NavBakeStage {
  voxelize,
  filterAndCompact,
  erode,
  partition,
  trace,
  buildPolygons,
}

/// Bakes a [NavMesh] from world-space triangles.
///
/// The pipeline is Recast's, and each stage exists because the one before it
/// cannot answer the next question:
///
///  1. **Voxelize** the triangles into solid spans, so an overpass is two
///     surfaces rather than one ambiguous height.
///  2. **Filter and compact** to just the surfaces an agent can stand on, with
///     the steps it can take between them resolved.
///  3. **Erode** by the agent's radius, so every remaining point is somewhere
///     the agent's centre may legally be and a path never clips a corner.
///  4. **Partition** into regions at the natural pinch points.
///  5. **Trace** each region's outline and simplify it.
///  6. **Build polygons**, merging triangles back into convex polygons and
///     linking shared edges into portals.
///
/// Pure Dart and synchronous. A large world takes seconds, so run it in an
/// isolate or at build time rather than on the frame that needs it; [onStage]
/// reports progress for a caller that shows one.
/// The interior a tiled bake keeps, as column indices into the voxel field.
///
/// A tile is voxelized with a border of extra cells so erosion and region
/// growing see across the seam and agree with the neighbouring tile; this
/// says which part of the result is actually the tile's.
/// {@category Navigation}
typedef NavInterior = ({int minX, int minZ, int maxX, int maxZ});

NavMesh? buildNavMesh(
  NavGeometry geometry,
  NavMeshConfig config, {
  List<NavVolume> volumes = const [],
  NavInterior? interior,
  (Vector3, Vector3)? bounds,
  void Function(NavBakeStage stage)? onStage,
}) {
  onStage?.call(NavBakeStage.voxelize);
  final field = rasterizeNavGeometry(geometry, config, bounds: bounds);
  if (field == null) return null;
  // Between voxelize and compact: the surfaces are spans, and a span erased
  // here never reaches the mesh at all.
  applyNavVolumes(field, volumes);

  onStage?.call(NavBakeStage.filterAndCompact);
  final compact = buildCompactHeightfield(field, config);

  onStage?.call(NavBakeStage.erode);
  erodeWalkableArea(compact, config.agentRadiusCells);
  // After erosion, before the partition: the border has done its job of
  // making this tile agree with its neighbours, and must go before any
  // contour is traced over it.
  if (interior != null) {
    cutToInterior(
      compact,
      interior.minX,
      interior.minZ,
      interior.maxX,
      interior.maxZ,
    );
  }

  onStage?.call(NavBakeStage.partition);
  buildDistanceField(compact);
  buildRegions(compact);

  onStage?.call(NavBakeStage.trace);
  final contours = buildContours(compact, config);

  onStage?.call(NavBakeStage.buildPolygons);
  final polyMesh = buildPolyMesh(contours, config);
  if (polyMesh.polygonCount == 0) return null;

  return navMeshFromPolyMesh(polyMesh, config);
}
