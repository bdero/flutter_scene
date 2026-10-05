// Drop a box onto a floor with the Rapier backend.
import 'package:flutter_scene/physics.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:vector_math/vector_math.dart';

Future<void> main() async {
  await RapierWorld.ensureInitialized();

  final scene = Scene();
  final world = PhysicsWorld(RapierWorld(gravity: Vector3(0, -9.81, 0)));
  scene.root.addComponent(world);

  // A static floor.
  final floor = Node(localTransform: Matrix4.translation(Vector3(0, -0.5, 0)));
  floor.addComponent(RigidBody(type: BodyType.fixed));
  floor.addComponent(
    Collider(shape: BoxShape(halfExtents: Vector3(10, 0.5, 10))),
  );
  scene.add(floor);

  // A falling dynamic box. The body goes on before the collider.
  final box = Node(localTransform: Matrix4.translation(Vector3(0, 5, 0)));
  box.addComponent(RigidBody(type: BodyType.dynamic_, mass: 1));
  box.addComponent(Collider(shape: BoxShape(halfExtents: Vector3.all(0.5))));
  scene.add(box);

  world.collisions.listen((event) {
    // CollisionBegan, CollisionEnded, TriggerEntered, or TriggerExited.
  });

  // Each frame, scene.update(deltaSeconds) steps physics on a fixed
  // timestep and interpolates node transforms before rendering.
}
