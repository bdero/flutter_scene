import 'package:flutter/foundation.dart' show compute;
import 'package:scene/navigation.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/instanced_mesh_component.dart';
import 'package:flutter_scene/src/components/mesh_component.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/node.dart';

/// What a collection pass could and could not read.
///
/// A nav bake silently missing a floor is a bug that shows up much later as an
/// agent refusing to walk somewhere obvious, so what was skipped is reported
/// rather than swallowed.
class NavCollectReport {
  /// Nodes contributing triangles, and the triangle count they contributed.
  int nodesIncluded = 0;
  int trianglesIncluded = 0;

  /// Nodes skipped because [NavCollectOptions.include] rejected them.
  int nodesExcluded = 0;

  /// Nodes whose geometry could not be read back: a caller-managed vertex
  /// buffer (`Geometry.isReadable` is false), or a primitive that is not a
  /// triangle list. These are the ones worth looking at.
  final List<String> unreadableNodes = [];

  @override
  String toString() =>
      'NavCollectReport($nodesIncluded nodes, $trianglesIncluded triangles, '
      '$nodesExcluded excluded, ${unreadableNodes.length} unreadable)';
}

/// How a scene graph is turned into nav geometry.
class NavCollectOptions {
  const NavCollectOptions({
    this.include,
    this.areaOf,
    this.includeInstances = true,
  });

  /// Whether a node's geometry contributes. Returning false skips the node's
  /// own meshes but still descends into its children, so a marker node does
  /// not remove the props parented under it.
  ///
  /// The usual filter is a naming or tagging convention for the static level
  /// geometry, since a bake should see the floor and the walls but not the
  /// characters walking on them.
  final bool Function(Node node)? include;

  /// The [NavArea] to mark a node's triangles with. Returning
  /// [NavArea.nonWalkable], the default, leaves the slope test to decide, which
  /// is what most geometry wants; return a value to paint water, a door, or a
  /// no-go zone.
  final int Function(Node node)? areaOf;

  /// Whether instanced meshes contribute one copy of their geometry per
  /// instance.
  ///
  /// On by default, because a scattered forest is exactly the obstacle an
  /// agent must path around. It is also where a bake gets expensive: ten
  /// thousand trees is ten thousand meshes' worth of triangles, so turn it off
  /// and add coarse blockers instead when the instances are decoration.
  final bool includeInstances;
}

/// Collects world-space triangles for a nav bake from the subtree at [root].
///
/// Geometry it cannot read is skipped and counted in [report] rather than
/// throwing, unlike `Node.extractMeshData`: a bake should produce the best
/// mesh it can from a scene that also contains particles, skinned characters,
/// and caller-managed buffers.
NavGeometry collectNavGeometry(
  Node root, {
  NavCollectOptions options = const NavCollectOptions(),
  Matrix4? transform,
  NavCollectReport? report,
}) {
  final builder = NavGeometryBuilder();
  _collect(root, transform ?? Matrix4.identity(), options, builder, report);
  return builder.build();
}

void _collect(
  Node node,
  Matrix4 parentTransform,
  NavCollectOptions options,
  NavGeometryBuilder builder,
  NavCollectReport? report,
) {
  final worldTransform = parentTransform * node.localTransform;

  if (options.include?.call(node) ?? true) {
    final area = options.areaOf?.call(node) ?? NavArea.nonWalkable;
    var triangles = 0;
    var contributed = false;

    for (final component in node.getComponents<MeshComponent>()) {
      for (final primitive in component.mesh.primitives) {
        final added = _addPrimitiveGeometry(
          node,
          primitive.geometry,
          worldTransform,
          area,
          builder,
          report,
        );
        if (added > 0) {
          triangles += added;
          contributed = true;
        }
      }
    }

    if (options.includeInstances) {
      for (final component in node.getComponents<InstancedMeshComponent>()) {
        final instanced = component.instancedMesh;
        for (final instance in instanced.instances) {
          final added = _addPrimitiveGeometry(
            node,
            instanced.geometry,
            worldTransform * instance,
            area,
            builder,
            report,
          );
          if (added > 0) {
            triangles += added;
            contributed = true;
          }
        }
      }
    }

    if (contributed && report != null) {
      report.nodesIncluded++;
      report.trianglesIncluded += triangles;
    }
  } else {
    report?.nodesExcluded++;
  }

  for (final child in node.children) {
    _collect(child, worldTransform, options, builder, report);
  }
}

/// Appends one primitive's triangles, returning how many were added.
int _addPrimitiveGeometry(
  Node node,
  Geometry geometry,
  Matrix4 transform,
  int area,
  NavGeometryBuilder builder,
  NavCollectReport? report,
) {
  if (!geometry.isReadable ||
      geometry.primitiveType != gpu.PrimitiveType.triangle) {
    report?.unreadableNodes.add(node.name);
    return 0;
  }
  final data = geometry.extractMeshData();
  final positions = data.positions;
  final indices = data.indices;
  // Unindexed geometry is a triangle list in vertex order.
  final triangleIndices =
      indices ?? List<int>.generate(positions.length ~/ 3, (i) => i);
  if (triangleIndices.length < 3) return 0;

  builder.addMesh(
    positions: positions,
    triangleIndices: triangleIndices,
    transform: transform,
    area: area,
  );
  return triangleIndices.length ~/ 3;
}

/// Bakes a nav mesh from the subtree at [root].
///
/// The convenience spelling of [collectNavGeometry] followed by
/// [buildNavMesh]. Synchronous, and a large world takes seconds; prefer
/// [bakeSceneNavMeshAsync] anywhere a frame is being drawn.
NavMesh? bakeSceneNavMesh(
  Node root, {
  NavMeshConfig config = const NavMeshConfig(),
  NavCollectOptions options = const NavCollectOptions(),
  NavCollectReport? report,
  void Function(NavBakeStage stage)? onStage,
}) => buildNavMesh(
  collectNavGeometry(root, options: options, report: report),
  config,
  onStage: onStage,
);

/// [bakeSceneNavMesh] with the bake itself moved off the calling isolate.
///
/// The geometry is collected on the caller's isolate, because it reads the
/// live scene graph, and only the flat triangle soup crosses over. On web
/// there are no isolates and this runs inline, so it still yields the same
/// answer but does not spare the frame.
Future<NavMesh?> bakeSceneNavMeshAsync(
  Node root, {
  NavMeshConfig config = const NavMeshConfig(),
  NavCollectOptions options = const NavCollectOptions(),
  NavCollectReport? report,
}) {
  final geometry = collectNavGeometry(root, options: options, report: report);
  return compute(_bakeEntry, (geometry, config));
}

NavMesh? _bakeEntry((NavGeometry, NavMeshConfig) input) =>
    buildNavMesh(input.$1, input.$2);
