/// A bakeable nav mesh, as a scene component.
///
/// The baker and the query are engine-agnostic and take a triangle soup; this
/// is the piece that makes a nav mesh something a scene *has*. It holds the
/// bake settings, knows which of the scene's geometry to collect, keeps the
/// result, and serializes both, so a level ships with its nav mesh rather than
/// rebuilding it at load.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:scene/navigation.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/kit/environment/water_component.dart';
import 'package:flutter_scene/src/navigation/scene_nav_geometry.dart';
import 'package:flutter_scene/src/node.dart';

/// What a bake did, for the UI that ran it.
/// {@category Navigation}
class NavBakeResult {
  NavBakeResult({
    required this.mesh,
    required this.report,
    required this.duration,
    required this.volumeCount,
  });

  /// The baked mesh, or null when the geometry produced nothing walkable.
  final NavMesh? mesh;

  /// What the collection pass could and could not read.
  final NavCollectReport report;

  /// How long the whole bake took.
  final Duration duration;

  /// How many volumes were carved or painted.
  final int volumeCount;

  /// Whether anything walkable came out.
  bool get isEmpty => mesh == null || mesh!.polygonCount == 0;

  /// A one-line summary for a status row.
  String describe() {
    if (isEmpty) {
      return 'No walkable surface from ${report.trianglesIncluded} triangles. '
          'Check the agent size and what the include filter is letting '
          'through.';
    }
    return '${mesh!.polygonCount} polygons from '
        '${report.trianglesIncluded} triangles across '
        '${report.nodesIncluded} nodes, in '
        '${duration.inMilliseconds} ms.';
  }
}

/// Holds a nav mesh and the settings it is baked with.
///
/// Attach it to the node whose subtree the mesh covers, usually the level
/// root. [bake] collects that subtree's world-space triangles, carves the
/// volumes any blocked water asks for, builds the mesh, and keeps it.
///
/// A nav mesh is baked for one agent size, so a scene serving both a rat and
/// a tank wants two of these on two nodes rather than one mesh trying to
/// serve both.
/// {@category Navigation}
class NavMeshSurfaceComponent extends Component {
  NavMeshSurfaceComponent({
    this.config = const NavMeshConfig(),
    this.includePattern = '',
    this.includeInstances = true,
    this.includeWaterVolumes = true,
    this.blockedWaterDepth = 50.0,
    List<NavVolume>? volumes,
    NavMesh? mesh,
  }) : volumes = volumes ?? [],
       _mesh = mesh;

  /// The bake settings: agent size, voxel resolution, and the region and
  /// contour tuning.
  NavMeshConfig config;

  /// A substring a node's name must contain to contribute geometry, or empty
  /// to take everything.
  ///
  /// The usual convention for separating the level from what walks on it: a
  /// bake should see the floor and the walls, not the characters.
  String includePattern;

  /// Whether instanced meshes contribute one copy of their geometry per
  /// instance. On by default, because a scattered forest is exactly the
  /// obstacle an agent must path around, and off is how a bake of ten
  /// thousand decorative trees stops taking minutes.
  bool includeInstances;

  /// Whether blocked water under the baked subtree carves its volume.
  bool includeWaterVolumes;

  /// How far below a blocked water surface its carve reaches, which has to
  /// clear the bed underneath or an agent paths along the bottom.
  double blockedWaterDepth;

  /// Extra volumes carved or painted after voxelization: a no-go zone, a
  /// costly area, a doorway worth marking.
  final List<NavVolume> volumes;

  NavMesh? _mesh;

  /// The baked mesh, or null before the first bake.
  NavMesh? get mesh => _mesh;
  set mesh(NavMesh? value) {
    _mesh = value;
    _query = null;
  }

  NavMeshQuery? _query;

  /// A query over [mesh], built on first use and kept, or null when nothing
  /// is baked.
  ///
  /// The query holds the search's working arrays, so reusing this one is what
  /// keeps repeated pathfinding from reallocating. It is not safe to share
  /// across isolates; give each its own.
  NavMeshQuery? get query {
    final baked = _mesh;
    if (baked == null) return null;
    return _query ??= NavMeshQuery(baked);
  }

  /// The collection options this component's settings describe.
  NavCollectOptions collectOptions() => NavCollectOptions(
    include: includePattern.isEmpty
        ? null
        : (node) => node.name.contains(includePattern),
    // Water paints its own area, so swimmable water costs more to cross than
    // ground without anything else being wired up.
    areaOf: WaterComponent.navAreaOf,
    includeInstances: includeInstances,
  );

  /// Every volume this bake should apply: the authored ones plus whatever
  /// blocked water under [root] asks to have carved.
  List<NavVolume> volumesFor(Node root) => [
    ...volumes,
    if (includeWaterVolumes)
      ...WaterComponent.collectNavVolumes(root, depth: blockedWaterDepth),
  ];

  /// Bakes the mesh from the subtree at [root], or from this component's own
  /// node when [root] is omitted.
  ///
  /// Synchronous, so a large world blocks the frame. [bakeAsync] moves the
  /// build itself off the calling isolate.
  NavBakeResult bake({Node? root, void Function(NavBakeStage stage)? onStage}) {
    final target = root ?? node;
    final watch = Stopwatch()..start();
    final report = NavCollectReport();
    final geometry = collectNavGeometry(
      target,
      options: collectOptions(),
      report: report,
    );
    final applied = volumesFor(target);
    final baked = buildNavMesh(
      geometry,
      config,
      volumes: applied,
      onStage: onStage,
    );
    watch.stop();
    mesh = baked;
    return NavBakeResult(
      mesh: baked,
      report: report,
      duration: watch.elapsed,
      volumeCount: applied.length,
    );
  }

  /// [bake] with the build moved off the calling isolate.
  ///
  /// The geometry is collected here, because it reads the live scene graph,
  /// and only the flat triangle soup crosses over. On web there are no
  /// isolates and this runs inline, so it still answers the same but does not
  /// spare the frame.
  Future<NavBakeResult> bakeAsync({Node? root}) async {
    final target = root ?? node;
    final watch = Stopwatch()..start();
    final report = NavCollectReport();
    final geometry = collectNavGeometry(
      target,
      options: collectOptions(),
      report: report,
    );
    final applied = volumesFor(target);
    final baked = await compute(_bakeEntry, (geometry, config, applied));
    watch.stop();
    mesh = baked;
    return NavBakeResult(
      mesh: baked,
      report: report,
      duration: watch.elapsed,
      volumeCount: applied.length,
    );
  }

  /// Throws the baked mesh away.
  void clear() => mesh = null;

  /// The baked mesh as bytes, for a document payload, or null when nothing is
  /// baked.
  Uint8List? encode() {
    final baked = _mesh;
    return baked == null ? null : encodeNavMesh(baked);
  }

  /// Restores a mesh from [encodeNavMesh] output.
  void decode(Uint8List bytes) => mesh = decodeNavMesh(bytes);

  /// The baked mesh's polygon outlines as line segments, for a debug overlay.
  ///
  /// Emitted as flat `[x, y, z]` pairs so a caller can push them straight
  /// into a line geometry without walking the mesh itself. [lift] raises them
  /// off the floor, since a nav mesh sits exactly on the ground it was baked
  /// from and would z-fight with it.
  List<vm.Vector3> outlineSegments({double lift = 0.02}) {
    final baked = _mesh;
    if (baked == null) return const [];
    final out = <vm.Vector3>[];
    for (var poly = 0; poly < baked.polygonCount; poly++) {
      final corners = baked.vertexCountOf(poly);
      for (var i = 0; i < corners; i++) {
        final a = baked.vertexOf(poly, i) * 3;
        final b = baked.vertexOf(poly, (i + 1) % corners) * 3;
        out
          ..add(
            vm.Vector3(
              baked.vertices[a],
              baked.vertices[a + 1] + lift,
              baked.vertices[a + 2],
            ),
          )
          ..add(
            vm.Vector3(
              baked.vertices[b],
              baked.vertices[b + 1] + lift,
              baked.vertices[b + 2],
            ),
          );
      }
    }
    return out;
  }

  @override
  Component? cloneFor(Node cloneOwner) => NavMeshSurfaceComponent(
    config: config,
    includePattern: includePattern,
    includeInstances: includeInstances,
    includeWaterVolumes: includeWaterVolumes,
    blockedWaterDepth: blockedWaterDepth,
    volumes: List.of(volumes),
    // The baked mesh is shared rather than copied: it is immutable, and a
    // clone of a level wants the same navigation, not a second copy of a
    // megabyte of polygons.
    mesh: _mesh,
  );
}

NavMesh? _bakeEntry((NavGeometry, NavMeshConfig, List<NavVolume>) input) =>
    buildNavMesh(input.$1, input.$2, volumes: input.$3);
