import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('InputScope routes keyboard through focus into the manager', (
    tester,
  ) async {
    final input = InputManager();
    addTearDown(input.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: InputScope(manager: input, child: const SizedBox.expand()),
      ),
    );
    await tester.pump();

    expect(input.isPressed('jump'), isFalse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    expect(input.isPressed('jump'), isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    expect(input.isPressed('jump'), isFalse);
  });

  testWidgets('InputScope exposes the manager to descendants', (tester) async {
    final input = InputManager();
    addTearDown(input.dispose);
    InputManager? seen;

    await tester.pumpWidget(
      MaterialApp(
        home: InputScope(
          manager: input,
          child: Builder(
            builder: (context) {
              seen = InputScope.of(context);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    expect(seen, same(input));
  });

  testWidgets('InputScope.maybeOf is null with no scope above', (tester) async {
    InputManager? seen;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            seen = InputScope.maybeOf(context);
            return const SizedBox.expand();
          },
        ),
      ),
    );
    expect(seen, isNull);
  });

  testWidgets('InputScope feeds pointer buttons and movement', (tester) async {
    final input = InputManager();
    addTearDown(input.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: InputScope(manager: input, child: const SizedBox.expand()),
      ),
    );
    await tester.pump();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(100, 100));
    addTearDown(() => gesture.removePointer());

    await gesture.down(const Offset(100, 100));
    await tester.pump();
    expect(input.isPressed('fire'), isTrue);

    await gesture.moveTo(const Offset(120, 100));
    await tester.pump();
    // A delta belongs to the frame the next update opens, so the tick has to
    // run before the movement is readable.
    input.update(0.016);
    expect(input.rawControl(InputControl.mouseDeltaX), closeTo(20, 1e-6));

    await gesture.up();
    await tester.pump();
    expect(input.isPressed('fire'), isFalse);
  });

  testWidgets('detaching on dispose stops publishing', (tester) async {
    final input = InputManager();
    addTearDown(input.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: InputScope(manager: input, child: const SizedBox.expand()),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.expand()));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    expect(input.isPressed('jump'), isFalse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
  });
}
