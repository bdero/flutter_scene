import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_scene_editor/src/viewport/free_look_camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  const wDown = KeyDownEvent(
    physicalKey: PhysicalKeyboardKey.keyW,
    logicalKey: LogicalKeyboardKey.keyW,
    timeStamp: Duration.zero,
  );
  const wUp = KeyUpEvent(
    physicalKey: PhysicalKeyboardKey.keyW,
    logicalKey: LogicalKeyboardKey.keyW,
    timeStamp: Duration.zero,
  );

  test('W moves forward until released', () {
    final camera = FreeLookCamera(position: vm.Vector3.zero())..speed = 5;

    expect(camera.onKeyEvent(wDown), KeyEventResult.handled);
    expect(camera.move(0.1), isTrue);
    expect(camera.position.z, closeTo(-0.5, 1e-9));

    camera.onKeyEvent(wUp);
    expect(camera.move(0.1), isFalse);
    expect(camera.position.z, closeTo(-0.5, 1e-9));
  });

  test('A and D strafe left and right', () {
    final left = FreeLookCamera(position: vm.Vector3.zero())..speed = 5;
    final right = FreeLookCamera(position: vm.Vector3.zero())..speed = 5;

    left.onKeyEvent(
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyA,
        logicalKey: LogicalKeyboardKey.keyA,
        timeStamp: Duration.zero,
      ),
    );
    right.onKeyEvent(
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyD,
        logicalKey: LogicalKeyboardKey.keyD,
        timeStamp: Duration.zero,
      ),
    );
    left.move(0.1);
    right.move(0.1);

    expect(left.position.x, closeTo(0.5, 1e-9));
    expect(right.position.x, closeTo(-0.5, 1e-9));
  });
}
