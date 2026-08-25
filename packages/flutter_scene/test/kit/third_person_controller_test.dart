import 'dart:typed_data';
import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

class _TestFloorGeometry extends Geometry {
  _TestFloorGeometry({double halfSize = 50.0}) {
    primitiveType = gpu.PrimitiveType.triangle;
    _positions = Float32List.fromList([
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
    ]);
    setLocalBounds(
      vm.Aabb3.minMax(
        vm.Vector3(-halfSize, -0.1, -halfSize),
        vm.Vector3(halfSize, 0.1, halfSize),
      ),
      null,
    );
  }

  late final Float32List _positions;

  @override
  ({
    ByteData? vertices,
    Float32List? positions,
    Float32List? texCoords,
    ByteData? indices,
    gpu.IndexType indexType,
    int vertexCount,
    int indexCount,
  })
  get cpuMeshData => (
    vertices: null,
    positions: _positions,
    texCoords: null,
    indices: null,
    indexType: gpu.IndexType.int16,
    vertexCount: _positions.length ~/ 3,
    indexCount: 0,
  );

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

class _TestWallGeometry extends Geometry {
  _TestWallGeometry({double xPos = 1.0, double halfSize = 10.0}) {
    primitiveType = gpu.PrimitiveType.triangle;
    _positions = Float32List.fromList([
      xPos,
      -halfSize,
      -halfSize,
      xPos,
      halfSize,
      -halfSize,
      xPos,
      halfSize,
      halfSize,
      xPos,
      -halfSize,
      -halfSize,
      xPos,
      halfSize,
      halfSize,
      xPos,
      -halfSize,
      halfSize,
    ]);
    setLocalBounds(
      vm.Aabb3.minMax(
        vm.Vector3(xPos - 0.1, -halfSize, -halfSize),
        vm.Vector3(xPos + 0.1, halfSize, halfSize),
      ),
      null,
    );
  }

  late final Float32List _positions;

  @override
  ({
    ByteData? vertices,
    Float32List? positions,
    Float32List? texCoords,
    ByteData? indices,
    gpu.IndexType indexType,
    int vertexCount,
    int indexCount,
  })
  get cpuMeshData => (
    vertices: null,
    positions: _positions,
    texCoords: null,
    indices: null,
    indexType: gpu.IndexType.int16,
    vertexCount: _positions.length ~/ 3,
    indexCount: 0,
  );

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

    test(
      'single jump request produces multi-frame ascent and eventual landing',
      () {
        final node = Node()..position = vm.Vector3(0, 0, 0);
        final controller = ThirdPersonControllerComponent(
          jumpVelocity: 6.0,
          groundPlaneHeight: 0.0,
        );
        node.addComponent(controller);

        controller.fixedUpdate(0.016);
        expect(controller.isGrounded, isTrue);

        controller.jump();

        // Over next 10 frames (~160ms), character should remain airborne and ascend
        for (var i = 0; i < 10; i++) {
          controller.fixedUpdate(0.016);
          expect(controller.isGrounded, isFalse);
          expect(node.position.y, greaterThan(0.0));
        }

        // After 60 frames (~1s), character should have fallen back down and landed
        for (var i = 0; i < 50; i++) {
          controller.fixedUpdate(0.016);
        }
        expect(controller.isGrounded, isTrue);
        expect(node.position.y, closeTo(0.0, 0.05));
      },
    );

    test('delays subsequent jump until landing delay elapses', () {
      final node = Node()..position = vm.Vector3(0, 0, 0);
      final controller = ThirdPersonControllerComponent(
        jumpVelocity: 6.0,
        groundPlaneHeight: 0.0,
        landingJumpDelay: 0.20,
      );
      node.addComponent(controller);

      // Settle on ground
      controller.fixedUpdate(0.016);
      expect(controller.isGrounded, isTrue);

      // Perform first jump
      controller.jump();
      controller.fixedUpdate(0.016);
      expect(controller.isGrounded, isFalse);

      // Step until landing touchdown
      while (!controller.isGrounded) {
        controller.fixedUpdate(0.016);
      }
      expect(controller.isGrounded, isTrue);

      // Immediately request another jump 50ms after landing
      controller.jump();
      controller.fixedUpdate(0.05);

      // Should still be grounded during the 200ms landing window
      expect(controller.isGrounded, isTrue);
      expect(controller.velocity.y, equals(0.0));

      // Advance through the remainder of the 200ms landing delay
      for (var i = 0; i < 15; i++) {
        controller.fixedUpdate(0.016);
      }

      // Subsequent jump now initiates cleanly
      controller.jump();
      controller.fixedUpdate(0.016);
      expect(controller.isGrounded, isFalse);
      expect(controller.velocity.y, greaterThan(4.0));
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

    test('wide collision capsule stops penetration into wall', () {
      final root = Node();
      final wallNode = Node(
        mesh: Mesh(_TestWallGeometry(xPos: 1.0), UnlitMaterial()),
      );
      root.add(wallNode);

      final player = Node()..position = vm.Vector3(0.0, 0.9, 0.0);
      root.add(player);

      final controller = ThirdPersonControllerComponent(
        walkSpeed: 4.0,
        groundPlaneHeight: 0.0,
        footOffset: 0.9,
        obstacleRadius: 0.85,
        obstacleHeight: 1.8,
      );
      player.addComponent(controller);

      // Move forward (+X) toward the wall at x = 1.0
      controller.setMoveInput(vm.Vector2(1, 0));
      for (var i = 0; i < 30; i++) {
        controller.fixedUpdate(0.016);
      }

      // Wall is at x = 1.0. Character with radius 0.85 cannot exceed x = 0.25.
      expect(player.position.x, lessThanOrEqualTo(0.3));
    });
  });
}
