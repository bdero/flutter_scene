// ignore_for_file: avoid_print

// Proves the package runs under plain Dart with no Flutter anywhere, the
// native binary arrives through the build hook and the simulation drives
// SimplePoseTargets. Run with `dart run tool/headless_smoke.dart`.
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart';

Future<void> main() async {
  await RapierWorld.ensureInitialized();
  final world = RapierWorld();

  final ground = SimplePoseTarget();
  final groundBody = world.createBody(target: ground, type: BodyType.fixed);
  world.createColliders(
    groundBody,
    BoxShape(halfExtents: Vector3(50, 0.5, 50)),
  );

  final falling = SimplePoseTarget(translation: Vector3(0, 5, 0));
  final fallingBody = world.createBody(
    target: falling,
    type: BodyType.dynamic_,
  );
  world.createColliders(fallingBody, SphereShape(radius: 0.5));

  for (var i = 0; i < 300; i++) {
    world.step(1 / 60);
  }
  world.interpolatePoses(1);

  // Sphere of radius 0.5 resting on the box top at y = 0.5.
  final y = falling.translation.y;
  print('rested at y=${y.toStringAsFixed(3)}');
  world.dispose();
  if (y > 0.8 && y < 1.2) {
    print('HEADLESS SMOKE PASSED');
  } else {
    print('HEADLESS SMOKE FAILED');
    throw StateError('unexpected rest height $y');
  }
}
