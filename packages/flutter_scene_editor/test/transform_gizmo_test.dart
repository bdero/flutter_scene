import 'dart:math';

import 'package:flutter_scene_editor/src/viewport/transform_gizmo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  test('global space axes remain aligned to the scene', () {
    final transform = vm.Matrix4.compose(
      vm.Vector3(4, 5, 6),
      vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), pi / 2),
      vm.Vector3.all(3),
    );

    final axes = transformSpaceAxes(TransformSpace.global, transform);

    expect(axes[0], vm.Vector3(1, 0, 0));
    expect(axes[1], vm.Vector3(0, 1, 0));
    expect(axes[2], vm.Vector3(0, 0, 1));
  });

  test('local space axes follow the node global transform', () {
    final transform = vm.Matrix4.compose(
      vm.Vector3(4, 5, 6),
      vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), pi / 2),
      vm.Vector3(2, 3, 4),
    );

    final axes = transformSpaceAxes(TransformSpace.local, transform);
    final origin = transform.getTranslation();
    for (var axis = 0; axis < 3; axis++) {
      final local = vm.Vector3.zero()..[axis] = 1;
      final expected = transform.transformed3(local) - origin;
      expected.normalize();
      expect(axes[axis].x, closeTo(expected.x, 1e-6));
      expect(axes[axis].y, closeTo(expected.y, 1e-6));
      expect(axes[axis].z, closeTo(expected.z, 1e-6));
    }
  });

  test('global translation solves through a transformed parent', () {
    final parent =
        vm.Matrix4.diagonal3Values(1, 1, -1) *
        vm.Matrix4.compose(
          vm.Vector3(3, -2, 7),
          vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), pi / 2),
          vm.Vector3.all(0.016),
        );
    final parentBefore = parent.clone();
    final startLocal = vm.Matrix4.compose(
      vm.Vector3(10, 20, 30),
      vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 0.4),
      vm.Vector3(1, 2, 3),
    );
    final desiredGlobal = parent * startLocal;
    desiredGlobal.setTranslation(
      desiredGlobal.getTranslation() + vm.Vector3(2, 0, 0),
    );
    final parentInverse = vm.Matrix4.identity();
    parentInverse.copyInverse(parent);

    final solvedLocal = globalToLocalTransform(desiredGlobal, parentInverse);
    final recoveredGlobal = parent * solvedLocal;

    _expectMatrixNear(parent, parentBefore);
    _expectMatrixNear(recoveredGlobal, desiredGlobal);
    expect(solvedLocal.getTranslation().y, isNot(closeTo(20, 1e-6)));
  });

  test('local rotation follows a regular global basis', () {
    expect(
      localAxisRotationAngle(0.4, vm.Matrix4.identity()),
      closeTo(0.4, 1e-9),
    );
  });

  test('local rotation reverses through a mirrored global basis', () {
    final mirrored = vm.Matrix4.diagonal3Values(1, 1, -1);

    expect(localAxisRotationAngle(0.4, mirrored), closeTo(-0.4, 1e-9));
  });
}

void _expectMatrixNear(vm.Matrix4 actual, vm.Matrix4 expected) {
  for (var row = 0; row < 4; row++) {
    for (var column = 0; column < 4; column++) {
      expect(
        actual.entry(row, column),
        closeTo(expected.entry(row, column), 1e-6),
      );
    }
  }
}
