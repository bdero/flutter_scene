// Covers reading nav geometry back out of a live scene graph: what is
// collected, what is skipped, and that the result bakes into a usable mesh.

import 'dart:typed_data';

import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/navigation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Geometry that retains CPU positions without touching a GPU context, the
/// same stand-in the mesh-readback tests use.
class _StubGeometry extends Geometry {
  _StubGeometry(Float32List positions) {
    setRaycastAttributes(positions: positions);
    setVertexStreams(const [], positions.length ~/ 3);
  }

  /// Geometry retaining nothing, standing in for a caller-managed buffer.
  _StubGeometry.unreadable();

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Matrix4 modelTransform,
    Matrix4 cameraTransform,
    Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
    double depthBias = 0.0,
  }) {
    throw UnsupportedError('Stub geometry is not renderable');
  }
}

class _StubMaterial extends Material {
  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    Lighting lighting,
  ) {
    throw UnsupportedError('Stub material is not renderable');
  }
}

/// Two unindexed triangles forming a flat quad [size] across, centred on the
/// origin of its node.
Float32List quad(double size) {
  final half = size / 2;
  return Float32List.fromList([
    -half, 0, -half, half, 0, half, half, 0, -half, //
    -half, 0, -half, -half, 0, half, half, 0, half,
  ]);
}

Node floorNode(String name, double size, {Vector3? at}) {
  final node = Node(name: name)
    ..mesh = Mesh(_StubGeometry(quad(size)), _StubMaterial());
  if (at != null) node.position = at;
  return node;
}

void main() {
  const config = NavMeshConfig(
    cellSize: 0.3,
    cellHeight: 0.2,
    agentRadius: 0.5,
    agentHeight: 2.0,
  );

  test('collects world-space triangles from a subtree', () {
    final root = Node(name: 'level')..add(floorNode('ground', 20));
    final report = NavCollectReport();
    final geometry = collectNavGeometry(root, report: report);

    expect(geometry.triangleCount, 2);
    expect(report.nodesIncluded, 1);
    expect(report.trianglesIncluded, 2);
    expect(report.unreadableNodes, isEmpty);
  });

  test('a parent transform lands the geometry in world space', () {
    final root = Node(name: 'level')
      ..position = Vector3(100, 5, -20)
      ..add(floorNode('ground', 10));

    final bounds = collectNavGeometry(root).bounds!;
    expect(bounds.$1.x, closeTo(95, 1e-4));
    expect(bounds.$1.y, closeTo(5, 1e-4));
    expect(bounds.$2.z, closeTo(-15, 1e-4));
  });

  test('include skips a node but keeps its children', () {
    final marker = Node(name: 'dynamic')..add(floorNode('static_floor', 10));
    final root = Node(name: 'level')..add(marker);

    final report = NavCollectReport();
    final geometry = collectNavGeometry(
      root,
      options: NavCollectOptions(
        include: (node) => !node.name.startsWith('dynamic'),
      ),
      report: report,
    );

    // The marker itself has no mesh, so what matters is that its child was
    // still reached: excluding a node must not disinherit the props under it.
    expect(geometry.triangleCount, 2);
    expect(report.nodesExcluded, 1);
  });

  test('areaOf paints a node with an area the slope test would not', () {
    final water = floorNode('water', 10);
    final root = Node(name: 'level')..add(water);

    final geometry = collectNavGeometry(
      root,
      options: NavCollectOptions(
        areaOf: (node) =>
            node.name == 'water' ? NavArea.slow : NavArea.walkable,
      ),
    );
    expect(geometry.areas.every((area) => area == NavArea.slow), isTrue);
  });

  test('instanced meshes contribute one copy per instance', () {
    final geometry = _StubGeometry(
      Float32List.fromList([0, 0, 0, 1, 0, 0, 1, 0, 1]),
    );
    final instanced =
        InstancedMesh(geometry: geometry, material: _StubMaterial())
          ..addInstance(Matrix4.translationValues(0, 0, 0))
          ..addInstance(Matrix4.translationValues(50, 0, 0))
          ..addInstance(Matrix4.translationValues(100, 0, 0));
    final root = Node(name: 'trees')
      ..addComponent(InstancedMeshComponent(instanced));

    expect(collectNavGeometry(root).triangleCount, 3);
    // A forest is an obstacle worth baking, but it is also where a bake gets
    // expensive, so it can be turned off.
    expect(
      collectNavGeometry(
        root,
        options: const NavCollectOptions(includeInstances: false),
      ).triangleCount,
      0,
    );
    // Every instance landed where its transform put it.
    final bounds = collectNavGeometry(root).bounds!;
    expect(bounds.$2.x, closeTo(101, 1e-4));
  });

  test('a scene bakes end to end into a queryable mesh', () {
    final root = Node(name: 'level')..add(floorNode('ground', 20));
    final mesh = bakeSceneNavMesh(root, config: config)!;
    final query = NavMeshQuery(mesh);

    final path = query.findPath(Vector3(-8, 0, 0), Vector3(8, 0, 0));
    expect(path.status, NavPathStatus.complete);
    expect(path.length, closeTo(16, 1.0));
  });

  test('the async bake gives the same answer', () async {
    final root = Node(name: 'level')..add(floorNode('ground', 20));
    final sync = bakeSceneNavMesh(root, config: config)!;
    final async = await bakeSceneNavMeshAsync(root, config: config);

    expect(async, isNotNull);
    expect(async!.polygonCount, sync.polygonCount);
    expect(async.vertices.length, sync.vertices.length);
  });

  test('geometry it cannot read is reported, not thrown on', () {
    // A caller-managed vertex buffer has no CPU data to read back. A bake
    // should still produce the best mesh it can from the rest of the scene,
    // and say what it could not see: a nav bake quietly missing a floor shows
    // up much later as an agent refusing to walk somewhere obvious.
    final opaque = Node(name: 'particles')
      ..mesh = Mesh(_StubGeometry.unreadable(), _StubMaterial());
    final root = Node(name: 'level')
      ..add(floorNode('ground', 20))
      ..add(opaque);

    final report = NavCollectReport();
    final geometry = collectNavGeometry(root, report: report);

    expect(geometry.triangleCount, 2);
    expect(report.unreadableNodes, ['particles']);
    expect(report.nodesIncluded, 1);
  });

  test('an empty scene bakes to null rather than throwing', () {
    expect(bakeSceneNavMesh(Node(name: 'empty'), config: config), isNull);
  });

  group('NavMeshSurfaceComponent', () {
    Node level() => Node(name: 'level')..add(floorNode('ground_floor', 20));

    test('bakes the subtree it is attached to', () {
      final root = level();
      final surface = NavMeshSurfaceComponent(config: config);
      root.addComponent(surface);

      expect(surface.mesh, isNull, reason: 'nothing before the first bake');
      final result = surface.bake();
      expect(result.isEmpty, isFalse);
      expect(surface.mesh, isNotNull);
      expect(result.report.trianglesIncluded, 2);
      expect(result.describe(), contains('polygons'));
    });

    test('the include pattern is what keeps characters out of the bake', () {
      final root = level()..add(floorNode('enemy', 4, at: Vector3(0, 6, 0)));

      final everything = NavMeshSurfaceComponent(config: config);
      root.addComponent(everything);
      expect(everything.bake().report.nodesIncluded, 2);

      final staticOnly = NavMeshSurfaceComponent(
        config: config,
        includePattern: 'floor',
      );
      root.addComponent(staticOnly);
      expect(staticOnly.bake().report.nodesIncluded, 1);
    });

    test('blocked water carves the ground under it', () {
      final root = level();
      final pool = Node(name: 'pool')
        ..addComponent(
          WaterComponent(size: 30, traversal: WaterTraversal.blocked),
        );
      root.add(pool);

      final carving = NavMeshSurfaceComponent(config: config);
      root.addComponent(carving);
      final carved = carving.bake();
      expect(carved.volumeCount, 1);
      expect(
        carved.isEmpty,
        isTrue,
        reason: 'the pool covers the whole floor, so nothing is walkable',
      );

      final ignoring = NavMeshSurfaceComponent(
        config: config,
        includeWaterVolumes: false,
      );
      root.addComponent(ignoring);
      final ignored = ignoring.bake();
      expect(ignored.volumeCount, 0);
      expect(ignored.isEmpty, isFalse);
    });

    test('swimmable water paints its area instead of carving', () {
      final root = level();
      root.add(
        Node(name: 'pond')
          ..addComponent(
            WaterComponent(size: 30, traversal: WaterTraversal.swimmable),
          ),
      );
      final surface = NavMeshSurfaceComponent(config: config);
      root.addComponent(surface);
      final result = surface.bake();
      expect(result.volumeCount, 0, reason: 'nothing to carve');
      expect(result.isEmpty, isFalse, reason: 'still crossable');
    });

    test('the query is built once and dropped when the mesh changes', () {
      final root = level();
      final surface = NavMeshSurfaceComponent(config: config);
      root.addComponent(surface);
      expect(surface.query, isNull);

      surface.bake();
      final query = surface.query;
      expect(query, isNotNull);
      expect(surface.query, same(query), reason: 'kept across calls');

      surface.clear();
      expect(surface.query, isNull);
      expect(surface.mesh, isNull);
    });

    test('the baked mesh round-trips through its encoded form', () {
      final root = level();
      final surface = NavMeshSurfaceComponent(config: config);
      root.addComponent(surface);
      surface.bake();
      final polygons = surface.mesh!.polygonCount;

      final bytes = surface.encode()!;
      surface.clear();
      expect(surface.encode(), isNull);

      surface.decode(bytes);
      expect(surface.mesh!.polygonCount, polygons);
      expect(surface.mesh!.config.agentRadius, config.agentRadius);
    });

    test('outline segments trace every polygon edge, lifted off the floor', () {
      final root = level();
      final surface = NavMeshSurfaceComponent(config: config);
      root.addComponent(surface);
      surface.bake();

      final flat = surface.outlineSegments(lift: 0);
      final lifted = surface.outlineSegments(lift: 0.5);
      expect(flat, isNotEmpty);
      expect(flat.length.isEven, isTrue, reason: 'emitted as pairs');
      expect(lifted, hasLength(flat.length));
      // The lift is relative to the mesh's own vertices, which sit at the
      // voxel height above the floor rather than exactly on it. An overlay
      // that assumed y = 0 would z-fight on any surface but a flat one.
      for (var i = 0; i < flat.length; i++) {
        expect(lifted[i].y - flat[i].y, closeTo(0.5, 1e-4));
        expect(lifted[i].x, flat[i].x);
        expect(lifted[i].z, flat[i].z);
      }
    });

    test('an empty bake says why rather than reporting success', () {
      final root = Node(name: 'level');
      final surface = NavMeshSurfaceComponent(config: config);
      root.addComponent(surface);
      final result = surface.bake();
      expect(result.isEmpty, isTrue);
      expect(result.describe(), contains('No walkable surface'));
    });

    test('a clone shares the baked mesh rather than copying it', () {
      final root = level();
      final surface = NavMeshSurfaceComponent(config: config);
      root.addComponent(surface);
      surface.bake();

      final clone = surface.cloneFor(Node())! as NavMeshSurfaceComponent;
      expect(clone.mesh, same(surface.mesh));
      expect(clone.config.agentRadius, config.agentRadius);
    });
  });
}
