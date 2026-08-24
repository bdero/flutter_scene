import 'dart:typed_data';
import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

class _TestFloorGeometry extends Geometry {
  _TestFloorGeometry({double halfSize = 50.0}) {
    primitiveType = gpu.PrimitiveType.triangle;
    setCpuPositionsForTesting(
      Float32List.fromList([
        -halfSize,
        0,
        -halfSize,
        halfSize,
        0,
        -halfSize,
        halfSize,
        0,
        halfSize,
        -halfSize,
        0,
        -halfSize,
        halfSize,
        0,
        halfSize,
        -halfSize,
        0,
        halfSize,
      ]),
      bounds: vm.Aabb3.minMax(
        vm.Vector3(-halfSize, -0.1, -halfSize),
        vm.Vector3(halfSize, 0.1, halfSize),
      ),
    );
  }

  @override
  void bind(
    gpu.RenderPass pass,
    TransientWriter transientsBuffer,
    vm.Matrix4 modelTransform,
    vm.Matrix4 cameraTransform,
    vm.Vector3 cameraPosition, {
    gpu.Shader? shaderOverride,
    double depthBias = 0.0,
  }) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThirdPersonControllerComponent', () {
    test('accelerates when input is provided and stops on release', () {
      final node = Node()..position = vm.Vector3(0, 0, 0);
      final controller = ThirdPersonControllerComponent(
        walkSpeed: 5.0,
        groundPlaneHeight: 0.0,
      );
      node.addComponent(controller);

      controller.setMoveInput(vm.Vector2(0, 1));
      controller.fixedUpdate(0.1);

      expect(controller.velocity.z, greaterThan(0.0));

      controller.setMoveInput(vm.Vector2.zero());
      for (var i = 0; i < 20; i++) {
        controller.fixedUpdate(0.1);
      }

      expect(controller.velocity.z, closeTo(0.0, 0.05));
    });

    test('jump applies vertical impulse', () {
      final node = Node()..position = vm.Vector3(0, 0, 0);
      final controller = ThirdPersonControllerComponent(
        jumpVelocity: 6.0,
        groundPlaneHeight: 0.0,
      );
      node.addComponent(controller);

      controller.fixedUpdate(0.016);
      expect(controller.isGrounded, isTrue);

      controller.jump();
      controller.fixedUpdate(0.016);

      expect(controller.velocity.y, greaterThan(4.0));
      expect(controller.isGrounded, isFalse);
    });

    test('does not teleport when under parent with offset and Z-flip', () {
      final root = Node();
      final parent = Node()
        ..localTransform = (vm.Matrix4.identity()
          ..setTranslation(vm.Vector3(0.0, 0.0, 20.0))
          ..scaleByVector3(vm.Vector3(1.0, 1.0, -1.0)));
      root.add(parent);

      final player = Node()..position = vm.Vector3.zero();
      parent.add(player);

      final controller = ThirdPersonControllerComponent(
        walkSpeed: 4.0,
        groundPlaneHeight: 0.0,
      );
      player.addComponent(controller);

      final initialWorldPos =
          (player.globalTransform * vm.Vector4(0, 0, 0, 1)).xyz;
      expect(initialWorldPos.z, closeTo(20.0, 0.001));

      controller.fixedUpdate(0.1);

      final newWorldPos = (player.globalTransform * vm.Vector4(0, 0, 0, 1)).xyz;
      expect(newWorldPos.z, closeTo(20.0, 0.1));
    });

    test('snaps ground against actual scene floor mesh', () {
      final root = Node();
      final floorNode = Node(mesh: Mesh(_TestFloorGeometry(), UnlitMaterial()))
        ..position = vm.Vector3(0, -2.0, 0);
      root.add(floorNode);

      final player = Node()..position = vm.Vector3(0, -1.8, 0);
      root.add(player);

      final controller = ThirdPersonControllerComponent(walkSpeed: 4.0);
      player.addComponent(controller);

      controller.fixedUpdate(0.016);

      expect(controller.isGrounded, isTrue);
      expect(player.position.y, closeTo(-2.0, 0.05));
    });

    test('rotates movement direction by cameraHeadingYaw', () {
      final player = Node()..position = vm.Vector3.zero();
      final controller = ThirdPersonControllerComponent(
        walkSpeed: 5.0,
        groundPlaneHeight: 0.0,
      );
      player.addComponent(controller);

      // Forward input (+Y) with 90 degree camera heading yaw should steer along +X
      controller.setMoveInput(
        vm.Vector2(0, 1),
        cameraHeadingYaw: 3.141592653589793 / 2,
      );
      controller.fixedUpdate(0.1);

      expect(controller.velocity.x, greaterThan(0.5));
      expect(controller.velocity.z, closeTo(0.0, 0.1));
    });

    test('maintains footOffset height above ground plane', () {
      final player = Node()..position = vm.Vector3(0, 5.0, 0);
      final controller = ThirdPersonControllerComponent(
        walkSpeed: 4.0,
        groundPlaneHeight: 0.0,
        footOffset: 0.9,
      );
      player.addComponent(controller);

      for (var i = 0; i < 60; i++) {
        controller.fixedUpdate(0.016);
      }

      expect(controller.isGrounded, isTrue);
      expect(player.position.y, closeTo(0.9, 0.01));
    });
  });
}
