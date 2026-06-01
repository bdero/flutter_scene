// Scene queries (raycast, raycastAll, overlapSphere, overlapBox,
// shapeCast) run through Rapier's QueryPipeline and resolve hits back
// to the owning RapierCollider / Node.
//
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Node _boot() {
  final root = Node();
  final world = RapierWorld(gravity: Vector3.zero());
  root.addComponent(world);
  world.mount();
  return root;
}

// Attaches a fixed body + collider at [position] and returns the node.
//
// Steps the world once after mounting. Rapier builds its broad-phase
// BVH during a step, and scene queries run against that BVH, so a query
// only sees colliders that existed as of the most recent step. In a
// real app the world steps every frame before queries run; these tests
// step here so the freshly added collider is visible to the query that
// follows. The world has zero gravity, so the static bodies do not move.
Node _addStatic(
  Node root,
  Shape shape,
  Vector3 position, {
  bool isTrigger = false,
}) {
  final node = Node(localTransform: Matrix4.translation(position));
  node.addComponent(RapierRigidBody(type: BodyType.fixed));
  node.addComponent(RapierCollider(shape: shape, isTrigger: isTrigger));
  root.add(node);
  node.getComponents<RapierRigidBody>().first.mount();
  node.getComponents<RapierCollider>().first.mount();
  root.getComponent<RapierWorld>()!.step(1.0 / 60.0);
  return node;
}

void main() {
  test('raycast returns the closest hit and resolves the node', () {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;

    final near = _addStatic(root, SphereShape(radius: 1), Vector3(0, 0, 5));
    _addStatic(root, SphereShape(radius: 1), Vector3(0, 0, 10));

    final hit = world.raycast(
      Ray.originDirection(Vector3.zero(), Vector3(0, 0, 1)),
    );
    expect(hit, isNotNull);
    expect(identical(hit!.node, near), isTrue);
    // Ray enters the near sphere (center z=5, radius 1) at z=4.
    expect(hit.distance, closeTo(4.0, 1e-3));
    expect(hit.worldPoint.z, closeTo(4.0, 1e-3));
    expect(hit.worldNormal.z, closeTo(-1.0, 1e-3));
  });

  test('raycast returns null when nothing is in the path', () {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;
    _addStatic(root, SphereShape(radius: 1), Vector3(0, 0, 5));

    final hit = world.raycast(
      Ray.originDirection(Vector3.zero(), Vector3(0, 1, 0)),
    );
    expect(hit, isNull);
  });

  test('raycast honors maxDistance', () {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;
    _addStatic(root, SphereShape(radius: 1), Vector3(0, 0, 50));

    expect(
      world.raycast(
        Ray.originDirection(Vector3.zero(), Vector3(0, 0, 1)),
        maxDistance: 10,
      ),
      isNull,
    );
    expect(
      world.raycast(
        Ray.originDirection(Vector3.zero(), Vector3(0, 0, 1)),
        maxDistance: 100,
      ),
      isNotNull,
    );
  });

  test('raycastAll returns every hit, sorted by distance', () {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;
    _addStatic(root, SphereShape(radius: 1), Vector3(0, 0, 10));
    _addStatic(root, SphereShape(radius: 1), Vector3(0, 0, 5));
    _addStatic(root, SphereShape(radius: 1), Vector3(0, 0, 15));

    final hits = world.raycastAll(
      Ray.originDirection(Vector3.zero(), Vector3(0, 0, 1)),
    );
    expect(hits.length, 3);
    expect(hits[0].distance, lessThan(hits[1].distance));
    expect(hits[1].distance, lessThan(hits[2].distance));
    expect(hits[0].distance, closeTo(4.0, 1e-3));
  });

  test('overlapSphere finds colliders within the probe', () {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;
    final inside = _addStatic(root, SphereShape(radius: 1), Vector3(1, 0, 0));
    _addStatic(root, SphereShape(radius: 1), Vector3(20, 0, 0));

    final hits = world.overlapSphere(Vector3.zero(), 3);
    expect(hits.length, 1);
    expect(identical(hits.first.node, inside), isTrue);
  });

  test('overlapBox finds colliders within an oriented box', () {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;
    final inside = _addStatic(root, SphereShape(radius: 0.5), Vector3(0, 2, 0));
    _addStatic(root, SphereShape(radius: 0.5), Vector3(0, 20, 0));

    final hits = world.overlapBox(
      Vector3(0, 2, 0),
      Vector3(1, 1, 1),
      Quaternion.identity(),
    );
    expect(hits.length, 1);
    expect(identical(hits.first.node, inside), isTrue);
  });

  test('triggers are excluded unless includeTriggers is set', () {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;
    _addStatic(root, SphereShape(radius: 1), Vector3(0, 0, 5), isTrigger: true);

    final ray = Ray.originDirection(Vector3.zero(), Vector3(0, 0, 1));
    expect(world.raycast(ray), isNull);
    expect(world.raycast(ray, includeTriggers: true), isNotNull);
  });

  test('includeFixed=false skips static colliders', () {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;
    _addStatic(root, SphereShape(radius: 1), Vector3(0, 0, 5));

    final ray = Ray.originDirection(Vector3.zero(), Vector3(0, 0, 1));
    expect(world.raycast(ray, includeFixed: false), isNull);
    expect(world.raycast(ray), isNotNull);
  });

  test('shapeCast sweeps a sphere and finds the first contact', () {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;
    final target = _addStatic(
      root,
      BoxShape(halfExtents: Vector3(2, 2, 2)),
      Vector3(0, 0, 10),
    );

    final hit = world.shapeCast(
      SphereShape(radius: 0.5),
      Matrix4.translation(Vector3.zero()),
      Vector3(0, 0, 1),
      100,
    );
    expect(hit, isNotNull);
    expect(identical(hit!.node, target), isTrue);
    // Box front face at z=8; sphere radius 0.5 contacts at ~7.5.
    expect(hit.distance, closeTo(7.5, 0.1));
  });

  test('shapeCast rejects non-sphere probes', () {
    final root = _boot();
    final world = root.getComponent<RapierWorld>()!;
    expect(
      () => world.shapeCast(
        BoxShape(halfExtents: Vector3(1, 1, 1)),
        Matrix4.identity(),
        Vector3(0, 0, 1),
        10,
      ),
      throwsUnsupportedError,
    );
  });
}
