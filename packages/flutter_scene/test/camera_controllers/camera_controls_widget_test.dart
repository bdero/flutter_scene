// Covers the CameraControls widget forwarding pointer and keyboard input to a
// controller.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingController extends CameraController {
  Offset dragTotal = Offset.zero;
  final List<LogicalKeyboardKey> keysDown = [];
  bool released = false;

  @override
  void handleDragUpdate(Offset delta) => dragTotal += delta;

  @override
  bool handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) keysDown.add(event.logicalKey);
    return true;
  }

  @override
  void releaseInput() => released = true;
}

void main() {
  testWidgets('forwards a drag to the controller', (tester) async {
    final controller = _RecordingController();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CameraControls(
          controller: controller,
          child: const SizedBox.expand(),
        ),
      ),
    );

    await tester.drag(find.byType(CameraControls), const Offset(40, 0));
    await tester.pump();

    expect(controller.dragTotal.dx, greaterThan(0));
    expect(controller.viewportSize.width, greaterThan(0));
  });

  testWidgets('forwards keys while focused', (tester) async {
    final controller = _RecordingController();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CameraControls(
          controller: controller,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump(); // let autofocus settle

    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    expect(controller.keysDown, contains(LogicalKeyboardKey.keyW));
  });

  testWidgets('ignores input when disabled', (tester) async {
    final controller = _RecordingController();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CameraControls(
          controller: controller,
          enabled: false,
          child: const SizedBox.expand(),
        ),
      ),
    );

    await tester.drag(find.byType(CameraControls), const Offset(40, 0));
    await tester.pump();

    expect(controller.dragTotal, Offset.zero);
  });
}
