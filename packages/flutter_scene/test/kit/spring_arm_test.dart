import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

class _TestBlockGeometry extends Geometry {
  _TestBlockGeometry({double halfSize = 1.0}) {
    primitiveType = gpu.PrimitiveType.triangle;
    setCpuPositionsForTesting(
      Float32List.fromList([
        -halfSize,
        -halfSize,
        0,
        halfSize,
        -halfSize,
        0,
        halfSize,
        halfSize,
        0,
        -halfSize,
        -halfSize,
        0,
        halfSize,
        halfSize,
        0,
        -halfSize,
        halfSize,
        0,
      ]),
      bounds: vm.Aabb3.minMax(
        vm.Vector3(-halfSize, -halfSize, -halfSize),
        vm.Vector3(halfSize, halfSize, halfSize),
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

  group('SpringArmComponent', () {
    test('computes unoccluded socket transform at target length', () {
      final node = Node()..position = vm.Vector3(10, 0, 10);
      final arm = SpringArmComponent(
        targetLength: 5.0,
        targetOffset: vm.Vector3(0, 2, 0),
        socketOffset: vm.Vector3(1, 0, 0),
      );
      node.addComponent(arm);
      arm.onMount();

      final xform = arm.socketTransform;
      final pos = (xform * vm.Vector4(0, 0, 0, 1)).xyz;

      expect(pos.x, closeTo(11.0, 0.001));
      expect(pos.y, closeTo(2.0, 0.001));
      expect(pos.z, closeTo(5.0, 0.001));
    });

    test('drives camera node under parent transform without drift', () {
      final root = Node();
      final parentNode = Node()
        ..localTransform = (vm.Matrix4.identity()
          ..setTranslation(vm.Vector3(10.0, 0.0, 0.0))
          ..scaleByVector3(vm.Vector3(1.0, 1.0, -1.0)));
      root.add(parentNode);

      final characterNode = Node()..position = vm.Vector3(0, 0, 5);
      parentNode.add(characterNode);

      final cameraNode = Node();
      parentNode.add(cameraNode);

      final arm = SpringArmComponent(
        targetLength: 4.0,
        targetOffset: vm.Vector3(0, 1, 0),
        cameraNode: cameraNode,
      );
      characterNode.addComponent(arm);

      arm.update(0.1);

      final expectedWorldPos =
          (arm.socketTransform * vm.Vector4(0, 0, 0, 1)).xyz;
      final actualWorldPos =
          (cameraNode.globalTransform * vm.Vector4(0, 0, 0, 1)).xyz;

      expect(actualWorldPos.x, closeTo(expectedWorldPos.x, 0.001));
      expect(actualWorldPos.y, closeTo(expectedWorldPos.y, 0.001));
      expect(actualWorldPos.z, closeTo(expectedWorldPos.z, 0.001));
    });

    test('excludes character node itself from raycast occlusion', () {
      final root = Node();
      final characterNode = Node(
        mesh: Mesh(_TestBlockGeometry(halfSize: 2.0), UnlitMaterial()),
      )..position = vm.Vector3.zero();
      root.add(characterNode);

      final arm = SpringArmComponent(
        targetLength: 5.0,
        targetOffset: vm.Vector3(0, 0.5, 0),
      );
      characterNode.addComponent(arm);

      arm.update(0.1);

      expect(arm.currentLength, closeTo(5.0, 0.01));
    });

    test('supports independent yaw and pitch boom rotation', () {
      final characterNode = Node()..position = vm.Vector3(5, 0, 5);
      // Turn character by 90 degrees
      characterNode.rotation = vm.Quaternion.axisAngle(
        vm.Vector3(0, 1, 0),
        math.pi / 2,
      );

      final arm = SpringArmComponent(
        targetLength: 4.0,
        inheritYaw: false,
        inheritPitch: false,
        yaw: 0.0,
        pitch: 0.0,
      );
      characterNode.addComponent(arm);

      arm.update(0.1);

      final socketPos = (arm.socketTransform * vm.Vector4(0, 0, 0, 1)).xyz;
      // Socket should be offset by -Z (behind character along world forward), not +X
      expect(socketPos.x, closeTo(5.0, 0.01));
      expect(socketPos.y, closeTo(1.5, 0.01));
      expect(socketPos.z, closeTo(1.0, 0.01));
    });
  });
}
