import 'package:example_app/quake_camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  test('look smoothing eases toward the requested rotation', () {
    final camera = QuakeCamera(position: vm.Vector3.zero())
      ..lookSmoothing = 18.0;

    camera.look(const Offset(100, 0));
    expect(camera.yaw, 0);

    camera.move(0.1);
    expect(camera.yaw, greaterThan(0));
    expect(camera.yaw, lessThan(0.5));

    camera.move(0.2);
    expect(camera.yaw, greaterThan(0.4));
    expect(camera.yaw, lessThan(0.5));
  });

  test('movement smoothing eases acceleration and deceleration', () {
    final camera = QuakeCamera(position: vm.Vector3.zero())
      ..speed = 10.0
      ..movementSmoothing = 10.0;
    final focus = FocusNode();
    addTearDown(focus.dispose);

    camera.onKeyEvent(
      focus,
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyW,
        logicalKey: LogicalKeyboardKey.keyW,
        timeStamp: Duration.zero,
      ),
    );
    camera.move(0.1);
    final firstDistance = -camera.position.z;
    expect(firstDistance, greaterThan(0));
    expect(firstDistance, lessThan(1.0));

    camera.onKeyEvent(
      focus,
      const KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.keyW,
        logicalKey: LogicalKeyboardKey.keyW,
        timeStamp: Duration(milliseconds: 100),
      ),
    );
    camera.move(0.2);
    final coastDistance = -camera.position.z - firstDistance;
    expect(coastDistance, greaterThan(0));
    expect(coastDistance, lessThan(firstDistance));
  });
}
