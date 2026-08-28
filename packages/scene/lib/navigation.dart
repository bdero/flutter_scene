/// Navigation meshes: baking walkable surface out of level geometry, and
/// pathfinding across it.
///
/// A nav mesh is not a property of a level, it is a property of a level plus
/// an agent: [NavMeshConfig] says how tall the agent is, how wide, how steep a
/// slope it manages and how tall a step, and [buildNavMesh] answers where that
/// agent can go. Bake one per agent size.
///
/// The baker is a Recast-style pipeline: voxelize the triangles, filter to the
/// surfaces an agent can stand on, shrink them by the agent's radius, partition
/// into regions, trace and simplify their outlines, and merge the result into
/// convex polygons linked across shared edges. It is pure Dart and synchronous,
/// so it runs in an editor, in a build step, on a server, or in an isolate at
/// load time; [encodeNavMesh] stores the result so a runtime need not re-bake.
///
/// [NavMeshQuery] answers path requests with A* over the polygons followed by
/// funnel string-pulling, so a path is the shortest route through the corridor
/// rather than a tour of polygon centres.
///
/// Pure Dart, optional; import it only when a build needs navigation.
library;

export 'src/navigation/compact_heightfield.dart'
    show CompactHeightfield, buildCompactHeightfield, erodeWalkableArea;
export 'src/navigation/contours.dart' show Contour, ContourSet, buildContours;
export 'src/navigation/heightfield.dart'
    show Heightfield, HeightSpan, applyNavVolumes, rasterizeNavGeometry;
export 'src/navigation/nav_config.dart' show NavMeshConfig;
export 'src/navigation/nav_geometry.dart'
    show NavArea, NavGeometry, NavGeometryBuilder, NavVolume;
export 'src/navigation/nav_mesh.dart'
    show NavMesh, navMeshFromPolyMesh, navNoPolygon;
export 'src/navigation/nav_mesh_builder.dart' show NavBakeStage, buildNavMesh;
export 'src/navigation/nav_mesh_codec.dart'
    show decodeNavMesh, encodeNavMesh, navMeshVersion;
export 'src/navigation/nav_query.dart'
    show NavAreaCosts, NavMeshQuery, NavPath, NavPathStatus;
export 'src/navigation/poly_mesh.dart' show PolyMesh, buildPolyMesh;
export 'src/navigation/regions.dart' show buildRegions;
