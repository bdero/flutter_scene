// Stage 4 commit E tests: rigid body lifecycle and gravity integration
// through the native FFI. Bodies are exercised without colliders, so
// each test sets an additional mass explicitly (a body with no
// colliders has zero mass otherwise and gravity has no effect).
//
// ignore_for_file: invalid_use_of_internal_member
//
// Component.mount/unmount are intentionally internal to flutter_scene;
// these tests drive them directly because the test root is not part of
// a live RenderScene (constructing one requires a Flutter GPU
// context).

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

Node _bootWorld({Vector3? gravity}) {
  final root = Node();
  final world = RapierWorld(gravity: gravity);
  root.addComponent(world);
  world.mount();
  return root;
}

void main() {
  test('dynamic body falls along world gravity', () {
    final root = _bootWorld();
    final world = root.getComponent<RapierWorld>()!;

    final body = Node(localTransform: Matrix4.translation(Vector3(0, 10, 0)));
    final rb = RapierRigidBody(type: BodyType.dynamic_, mass: 1.0);
    body.addComponent(rb);
    root.add(body);
    rb.mount();

    for (var i = 0; i < 60; i++) {
      world.step(1.0 / 60.0);
    }

    final p = rb.readNativeTranslation();
    expect(p.y, lessThan(9.0));
    // 1g over 1s should drop ~4.9m, so ~5.1 is the floor (and Rapier's
    // semi-implicit integrator overshoots a touch).
    expect(p.y, greaterThan(3.5));
  });

  test('fixed body holds position under gravity', () {
    final root = _bootWorld();
    final world = root.getComponent<RapierWorld>()!;

    final body = Node(localTransform: Matrix4.translation(Vector3(1, 2, 3)));
    final rb = RapierRigidBody(type: BodyType.fixed);
    body.addComponent(rb);
    root.add(body);
    rb.mount();

    for (var i = 0; i < 60; i++) {
      world.step(1.0 / 60.0);
    }

    final p = rb.readNativeTranslation();
    expect(p.x, closeTo(1.0, 1e-5));
    expect(p.y, closeTo(2.0, 1e-5));
    expect(p.z, closeTo(3.0, 1e-5));
  });

  test('onUnmount removes the body from the native world', () {
    final root = _bootWorld();
    final body = Node();
    final rb = RapierRigidBody(type: BodyType.dynamic_, mass: 1.0);
    body.addComponent(rb);
    root.add(body);
    rb.mount();
    expect(rb.nativeHandle, isNotNull);

    rb.unmount();
    expect(rb.nativeHandle, isNull);
    expect(rb.readNativeTranslation, throwsStateError);
  });

  test('zero gravity leaves a dynamic body suspended', () {
    final root = _bootWorld(gravity: Vector3.zero());
    final world = root.getComponent<RapierWorld>()!;

    final body = Node(localTransform: Matrix4.translation(Vector3(0, 5, 0)));
    final rb = RapierRigidBody(type: BodyType.dynamic_, mass: 1.0);
    body.addComponent(rb);
    root.add(body);
    rb.mount();

    for (var i = 0; i < 30; i++) {
      world.step(1.0 / 60.0);
    }

    final p = rb.readNativeTranslation();
    expect(p.y, closeTo(5.0, 1e-4));
  });
}
