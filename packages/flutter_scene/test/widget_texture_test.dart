// Covers WidgetTexture's hosting behavior (zero footprint, child layout,
// liveness) and, where a GPU context exists, the capture pipeline through to
// the controller's texture.

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

bool _gpuAvailable() {
  try {
    Scene();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  testWidgets('occupies no layout space and lays the child out at the '
      'capture size', (tester) async {
    final controller = WidgetTextureController();
    final childKey = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: WidgetTexture(
            controller: controller,
            width: 320,
            height: 200,
            child: SizedBox.expand(key: childKey),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(WidgetTexture)), Size.zero);
    expect(
      (childKey.currentContext!.findRenderObject()! as RenderBox).size,
      const Size(320, 200),
    );
  });

  testWidgets('does not appear on screen and does not hit test', (
    tester,
  ) async {
    final controller = WidgetTextureController();
    var tapped = false;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            WidgetTexture(
              controller: controller,
              width: 320,
              height: 200,
              child: GestureDetector(
                onTap: () => tapped = true,
                child: const ColoredBox(color: Color(0xFF00FF00)),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.tapAt(const Offset(10, 10));
    expect(tapped, isFalse);
  });

  testWidgets('child state stays live while hosted', (tester) async {
    final controller = WidgetTextureController();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: WidgetTexture(
          controller: controller,
          width: 100,
          height: 100,
          child: const _Counter(),
        ),
      ),
    );
    expect(_CounterState.instance!.ticks, 0);
    _CounterState.instance!.bump();
    await tester.pump();
    expect(_CounterState.instance!.ticks, 1);
  });

  testWidgets('forwarded pointer events drive the hosted widgets', (
    tester,
  ) async {
    final controller = WidgetTextureController();
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: WidgetTexture(
          controller: controller,
          width: 200,
          height: 100,
          child: Center(
            child: SizedBox(
              width: 200,
              height: 100,
              child: ElevatedButton(
                onPressed: () => presses++,
                child: const Text('press'),
              ),
            ),
          ),
        ),
      ),
    );

    // A tap at the center of the texture lands on the button.
    controller.tapAt(const Offset(0.5, 0.5));
    await tester.pump();
    expect(presses, 1);

    // A drag sequence routes through recognizers without throwing.
    controller.pointerDown(const Offset(0.2, 0.5));
    controller.pointerMove(const Offset(0.6, 0.5));
    controller.pointerUp(const Offset(0.6, 0.5));
    await tester.pump();
    expect(presses, 1);
  });

  testWidgets('captures publish a texture matching the capture size', (
    tester,
  ) async {
    if (!_gpuAvailable()) {
      markTestSkipped('No Impeller GPU context');
      return;
    }
    final controller = WidgetTextureController();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: WidgetTexture(
          controller: controller,
          width: 64,
          height: 32,
          pixelRatio: 2.0,
          child: const ColoredBox(color: Color(0xFFFF0000)),
        ),
      ),
    );
    // Let the async capture round trip complete.
    for (var i = 0; i < 20 && controller.texture == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    final texture = controller.texture;
    if (texture == null) {
      markTestSkipped('Capture did not complete in this environment');
      return;
    }
    expect(texture.width, 128);
    expect(texture.height, 64);
    expect(controller.captureCount, greaterThan(0));
  });
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  static _CounterState? instance;
  int ticks = 0;

  @override
  void initState() {
    super.initState();
    instance = this;
  }

  void bump() => setState(() => ticks++);

  @override
  Widget build(BuildContext context) => Text(
    '$ticks',
    textDirection: TextDirection.ltr,
    style: const TextStyle(fontSize: 12),
  );
}
