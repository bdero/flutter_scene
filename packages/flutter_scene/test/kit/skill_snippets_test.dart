import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

// Statically compiles all code snippets documented in SKILL.md.
void _skillSnippetsCompilationCheck(Scene scene) {
  // 1. SpringArmComponent
  final characterNode = Node();
  final cameraNode = Node();
  final cameraArm = SpringArmComponent(
    targetLength: 5.0,
    targetOffset: vm.Vector3(0, 1.6, 0),
    socketOffset: vm.Vector3(0.5, 0, 0),
    enablePositionLag: true,
    positionLagSpeed: 8.0,
    cameraNode: cameraNode,
  );

  characterNode.addComponent(cameraArm);
  scene.root.add(characterNode);
  scene.root.add(cameraNode);

  // 2. CameraShake
  final shake = CameraShake(decayRate: 1.2, frequency: 25.0);
  shake.addTrauma(0.6);
  final offset = shake.update(0.016);
  cameraNode.localTransform = vm.Matrix4.identity() * offset.toMatrix4();

  // 3. ThirdPersonControllerComponent
  final playerNode = Node();
  final controller = ThirdPersonControllerComponent(
    walkSpeed: 4.5,
    runMultiplier: 1.8,
    jumpVelocity: 7.0,
    groundPlaneHeight: 0.0,
  );
  playerNode.addComponent(controller);
  controller.setMoveInput(vm.Vector2(0, 1), isRunning: true);
  controller.jump();

  // 4. Steering
  final npcPos = vm.Vector3.zero();
  final npcVel = vm.Vector3.zero();
  final targetPos = vm.Vector3(1, 0, 1);
  final neighborPositions = [vm.Vector3(2, 0, 2)];
  final _ = Steering.seek(npcPos, npcVel, targetPos, maxSpeed: 4.0);
  final _ = Steering.arrive(npcPos, npcVel, targetPos, slowingRadius: 3.0);
  final _ = Steering.separation(
    npcPos,
    npcVel,
    neighborPositions,
    desiredDistance: 1.5,
  );

  // 5. DayNightCycleComponent
  final sunLight = DirectionalLight();
  final sunNode = Node()..addComponent(DirectionalLightComponent(sunLight));
  scene.root.add(sunNode);

  final skyCycle = DayNightCycleComponent(
    timeOfDay: 14.5,
    timeSpeed: 0.1,
    latitude: 34.0,
    sunLightNode: sunNode,
  );
  scene.root.addComponent(skyCycle);

  // 6. WaterSurfaceComponent
  final water = WaterSurfaceComponent();
  final surface = water.evaluateAt(vm.Vector2(0, 0));
  final _ = surface.displacement.y;
  final _ = surface.normal;

  // 7. DebugDraw
  DebugDraw.line(
    vm.Vector3.zero(),
    vm.Vector3.all(1),
    color: vm.Vector4(1, 0, 0, 1),
  );
  DebugDraw.box(vm.Aabb3(), color: vm.Vector4(0, 1, 0, 1));
  DebugDraw.sphere(vm.Vector3.zero(), 1.0, color: vm.Vector4(0, 0, 1, 1));
  DebugDraw.axes(vm.Matrix4.identity(), size: 2.0);

  final debugMesh = DebugDraw.flushMesh();
  if (debugMesh != null) {
    cameraNode.mesh = Mesh(debugMesh, UnlitMaterial());
  }
}

void main() {
  test('SKILL.md snippets compile and type-check cleanly', () {
    expect(_skillSnippetsCompilationCheck, isNotNull);
  });
}
