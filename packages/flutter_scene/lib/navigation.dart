/// Navigation for flutter_scene: baking a nav mesh out of a scene, and
/// pathfinding across it.
///
/// The baker and the query live in `package:scene/navigation.dart`, engine
/// agnostic and pure Dart, and this library re-exports them alongside the
/// piece that needs the renderer: reading world-space triangles back out of a
/// live scene graph.
///
/// ```dart
/// final navMesh = await bakeSceneNavMeshAsync(
///   level,
///   config: const NavMeshConfig(agentRadius: 0.4, agentHeight: 1.8),
///   options: NavCollectOptions(
///     include: (node) => node.name.startsWith('static_'),
///   ),
/// );
/// final query = NavMeshQuery(navMesh!);
/// final path = query.findPath(enemy.position, player.position);
/// ```
///
/// A nav mesh is baked for one agent size, so bake one per size rather than
/// trying to serve a rat and a tank from the same mesh. Baking is seconds of
/// work on a large world: do it in the editor and ship the result through
/// [encodeNavMesh], or take the async spelling at load time.
///
/// Import this only when a build needs navigation; the core
/// `package:flutter_scene/scene.dart` does not carry it.
library;

export 'package:scene/navigation.dart';

export 'src/navigation/nav_mesh_debug.dart'
    show
        Color4,
        NavDebugGeometry,
        NavDebugPalette,
        buildNavDebugGeometry,
        navDebugNode,
        navMeshDebugNode,
        navTileSetDebugNode;
export 'src/navigation/nav_tile_bake_async.dart'
    show bakeNavMeshTiledAsync, defaultNavBakeConcurrency, rebakeNavTilesAsync;
export 'src/navigation/nav_mesh_surface_component.dart'
    show NavBakeResult, NavMeshSurfaceComponent;
export 'src/navigation/scene_nav_geometry.dart'
    show
        NavCollectOptions,
        NavCollectReport,
        bakeSceneNavMesh,
        bakeSceneNavMeshAsync,
        collectNavGeometry;
