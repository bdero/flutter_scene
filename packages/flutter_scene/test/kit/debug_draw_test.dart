import 'dart:typed_data';

import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/physics.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DebugDraw', () {
    setUp(() {
      DebugDraw.clear();
    });

    test('accumulates lines, rays, boxes, and axes', () {
      expect(DebugDraw.vertexCount, equals(0));

      DebugDraw.line(vm.Vector3.zero(), vm.Vector3(1, 0, 0));
      expect(DebugDraw.vertexCount, equals(2));

      DebugDraw.ray(vm.Vector3.zero(), vm.Vector3(0, 1, 0), length: 2.0);
      expect(DebugDraw.vertexCount, equals(4));

      DebugDraw.box(vm.Aabb3.minMax(vm.Vector3(0, 0, 0), vm.Vector3(1, 1, 1)));
      expect(DebugDraw.vertexCount, equals(4 + 24));

      DebugDraw.clear();
      expect(DebugDraw.vertexCount, equals(0));
    });

    test('draws a shape per collider in the subtree', () {
      final root = Node();
      final child = Node(
        localTransform: vm.Matrix4.translation(vm.Vector3(0, 5, 0)),
      );
      child.addComponent(
        Collider(shape: BoxShape(halfExtents: vm.Vector3.all(1))),
      );
      root.add(child);

      DebugDraw.colliders(root);
      expect(DebugDraw.vertexCount, equals(24)); // 12 box edges.

      // A second collider on the same node draws too.
      child.addComponent(
        Collider(shape: BoxShape(halfExtents: vm.Vector3.all(2))),
      );
      DebugDraw.clear();
      DebugDraw.colliders(root);
      expect(DebugDraw.vertexCount, equals(48));
    });

    test('draws every shape kind', () {
      final xf = vm.Matrix4.identity();
      final counts = <Shape, int>{
        SphereShape(radius: 1): 96, // 3 rings of 16 segments.
        BoxShape(halfExtents: vm.Vector3.all(1)): 24,
        CylinderShape(radius: 1, halfHeight: 1): 72, // 2 rings, 4 seams.
        CapsuleShape(radius: 1, halfHeight: 1): 136, // Rings, caps, seams.
        TriMeshShape(
          vertices: Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]),
          indices: Uint32List.fromList([0, 1, 2]),
        ): 6,
        ConvexHullShape(points: Float32List.fromList([0, 0, 0, 1, 1, 1])): 12,
        HeightFieldShape(
          width: 2,
          depth: 2,
          heights: Float32List(4),
          scale: vm.Vector3.all(1),
        ): 0,
      };

      for (final MapEntry(key: shape, value: expected) in counts.entries) {
        DebugDraw.clear();
        DebugDraw.shape(shape, xf);
        expect(DebugDraw.vertexCount, equals(expected), reason: '$shape');
      }
    });

    test('draws each child of a compound shape', () {
      final child = BoxShape(halfExtents: vm.Vector3.all(1));
      DebugDraw.shape(
        CompoundShape(
          children: [
            CompoundChild(shape: child, localPose: vm.Matrix4.identity()),
            CompoundChild(
              shape: child,
              localPose: vm.Matrix4.translation(vm.Vector3(3, 0, 0)),
            ),
          ],
        ),
        vm.Matrix4.identity(),
      );
      expect(DebugDraw.vertexCount, equals(48));
    });
  });
}
