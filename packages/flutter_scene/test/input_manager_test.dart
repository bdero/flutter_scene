import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_scene/input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A source the tests drive directly, standing in for a device backend.
final class _FakeSource extends InputSource {
  InputSink? sink;

  @override
  void attach(InputSink s) => sink = s;

  @override
  void detach() => sink = null;

  void press(InputControl control) => sink!.publish(control, 1);
  void release(InputControl control) => sink!.publish(control, 0);
  void set(InputControl control, double value) => sink!.publish(control, value);
  void delta(InputControl control, double value) =>
      sink!.publishDelta(control, value);
}

final _w = InputControl.key(LogicalKeyboardKey.keyW);
final _s = InputControl.key(LogicalKeyboardKey.keyS);
final _a = InputControl.key(LogicalKeyboardKey.keyA);
final _d = InputControl.key(LogicalKeyboardKey.keyD);
final _space = InputControl.key(LogicalKeyboardKey.space);

void main() {
  late InputManager input;
  late _FakeSource source;

  setUp(() {
    source = _FakeSource();
    input = InputManager(map: InputMap.defaults(), sources: [source]);
  });

  tearDown(() => input.dispose());

  group('button actions', () {
    test('isPressed follows the bound control', () {
      expect(input.isPressed('jump'), isFalse);
      source.press(_space);
      expect(input.isPressed('jump'), isTrue);
      source.release(_space);
      expect(input.isPressed('jump'), isFalse);
    });

    // The ordering in these tests is the one a real app produces: the platform
    // delivers the event while the app is between ticks, and the tick that
    // follows reads it. An edge query answers for the frame [update] opened,
    // not for whatever has arrived since.
    test('wasPressedThisFrame is true for exactly one frame', () {
      input.update(0.016);
      expect(input.wasPressedThisFrame('jump'), isFalse);

      source.press(_space);
      input.update(0.016);
      expect(input.wasPressedThisFrame('jump'), isTrue);

      input.update(0.016);
      expect(
        input.wasPressedThisFrame('jump'),
        isFalse,
        reason: 'a held key must not re-trigger',
      );
      expect(input.isPressed('jump'), isTrue);
    });

    test('a press arriving between ticks is not dropped', () {
      // The regression this frame model exists for. Clearing the edges at the
      // top of update() instead discards every press that arrived while the
      // app was not ticking, which is when input actually arrives.
      source.press(_space);
      input.update(0.016);
      expect(input.wasPressedThisFrame('jump'), isTrue);
    });

    test('wasReleasedThisFrame is true for exactly one frame', () {
      source.press(_space);
      input.update(0.016);
      source.release(_space);
      input.update(0.016);
      expect(input.wasReleasedThisFrame('jump'), isTrue);
      input.update(0.016);
      expect(input.wasReleasedThisFrame('jump'), isFalse);
    });

    test('a tap inside one frame is not dropped', () {
      // Down and up both land between two updates, so a comparison of the
      // values at each boundary would never see it.
      source.press(_space);
      source.release(_space);
      input.update(0.016);
      expect(input.isPressed('jump'), isFalse);
      expect(input.wasPressedThisFrame('jump'), isTrue);
      expect(input.wasReleasedThisFrame('jump'), isTrue);

      input.update(0.016);
      expect(input.wasPressedThisFrame('jump'), isFalse);
      expect(input.wasReleasedThisFrame('jump'), isFalse);
    });

    test('an analog trigger edges at its own threshold', () {
      final trigger = const InputControl('gamepad0', 'triggerR');
      final map = InputMap([
        InputAction('fireTrigger', InputActionKind.button, [
          ButtonBinding(trigger, threshold: 0.8),
        ]),
      ]);
      final manager = InputManager(map: map, sources: [source]);
      addTearDown(manager.dispose);

      // A pull short of the threshold is not an edge, however far it moves.
      source.set(trigger, 0.5);
      manager.update(0.016);
      expect(manager.wasPressedThisFrame('fireTrigger'), isFalse);

      source.set(trigger, 0.9);
      manager.update(0.016);
      expect(manager.wasPressedThisFrame('fireTrigger'), isTrue);

      source.set(trigger, 0.7);
      manager.update(0.016);
      expect(manager.wasReleasedThisFrame('fireTrigger'), isTrue);
    });

    test('an analog control crosses a custom threshold', () {
      final map = InputMap([
        InputAction('fireTrigger', InputActionKind.button, [
          const ButtonBinding(
            InputControl('gamepad0', 'triggerR'),
            threshold: 0.8,
          ),
        ]),
      ]);
      final manager = InputManager(map: map, sources: [source]);
      addTearDown(manager.dispose);

      source.set(const InputControl('gamepad0', 'triggerR'), 0.5);
      expect(manager.isPressed('fireTrigger'), isFalse);
      source.set(const InputControl('gamepad0', 'triggerR'), 0.9);
      expect(manager.isPressed('fireTrigger'), isTrue);
    });
  });

  group('vector2 actions', () {
    test('WASD resolves with +Y forward', () {
      source.press(_w);
      expect(input.vector2('move'), Vector2(0, 1));
      source.release(_w);
      source.press(_s);
      expect(input.vector2('move'), Vector2(0, -1));
      source.release(_s);
      source.press(_d);
      expect(input.vector2('move'), Vector2(1, 0));
    });

    test('a diagonal is normalized, so it is not faster', () {
      source
        ..press(_w)
        ..press(_d);
      final move = input.vector2('move');
      expect(move.length, closeTo(1.0, 1e-6));
      expect(move.x, closeTo(move.y, 1e-6));
    });

    test('opposite keys cancel', () {
      source
        ..press(_w)
        ..press(_s);
      expect(input.vector2('move'), Vector2.zero());
    });

    test('the strongest binding wins across devices', () {
      final stick = const InputControl('gamepad0', 'leftX');
      final stickY = const InputControl('gamepad0', 'leftY');
      input.map['move']!.bindings.add(
        StickBinding(x: stick, y: stickY, deadzone: 0.1),
      );

      source.press(_d); // keyboard: full deflection on X
      source.set(stick, 0.3); // stick: partial
      expect(
        input.vector2('move').x,
        closeTo(1.0, 1e-6),
        reason: 'keyboard is longer, so it should win',
      );

      source.release(_d);
      expect(input.vector2('move').x, closeTo(0.3, 1e-6));
    });

    test('a radial deadzone rejects drift but keeps near-axis diagonals', () {
      final x = const InputControl('gamepad0', 'leftX');
      final y = const InputControl('gamepad0', 'leftY');
      final map = InputMap([
        InputAction('move', InputActionKind.vector2, [
          StickBinding(x: x, y: y, deadzone: 0.2),
        ]),
      ]);
      final manager = InputManager(map: map, sources: [source]);
      addTearDown(manager.dispose);

      source
        ..set(x, 0.1)
        ..set(y, 0.1);
      expect(manager.vector2('move'), Vector2.zero(), reason: 'inside radius');

      source
        ..set(x, 0.9)
        ..set(y, 0.05);
      expect(
        manager.vector2('move').y,
        closeTo(0.05, 1e-6),
        reason: 'a per-axis deadzone would have snapped this to 0',
      );
    });
  });

  group('delta controls', () {
    test('accumulate within a frame and zero on the next', () {
      source
        ..delta(InputControl.mouseDeltaX, 3)
        ..delta(InputControl.mouseDeltaX, 4);
      input.update(0.016);
      expect(
        input.rawControl(InputControl.mouseDeltaX),
        7,
        reason: 'several pointer events can land in one frame',
      );

      input.update(0.016);
      expect(
        input.rawControl(InputControl.mouseDeltaX),
        0,
        reason: 'a held mouse delta would spin the camera forever',
      );
    });

    test('movement arriving between ticks reaches the tick after it', () {
      // Zeroing deltas at the top of update() instead throws away every pixel
      // that arrived while the app was not ticking, which is all of them.
      source.delta(InputControl.mouseDeltaX, 5);
      input.update(0.016);
      expect(input.rawControl(InputControl.mouseDeltaX), 5);
    });

    test('mouse look inverts Y into the engine convention', () {
      // Flutter screen space grows downward; the engine convention is +Y up.
      source.delta(InputControl.mouseDeltaY, 10);
      input.update(0.016);
      expect(input.vector2('look').y, lessThan(0));
    });
  });

  group('enabled', () {
    test('gates queries without losing device state', () {
      source.press(_space);
      input.enabled = false;
      expect(input.isPressed('jump'), isFalse);
      expect(input.vector2('move'), Vector2.zero());

      input.enabled = true;
      expect(
        input.isPressed('jump'),
        isTrue,
        reason: 're-enabling must not strand a held key',
      );
    });
  });

  group('misuse', () {
    test('an unknown action throws', () {
      expect(() => input.isPressed('nope'), throwsArgumentError);
    });

    test('querying an action as the wrong kind throws', () {
      expect(() => input.axis('jump'), throwsArgumentError);
      expect(() => input.vector2('jump'), throwsArgumentError);
      expect(() => input.isPressed('move'), throwsArgumentError);
    });

    test('a binding of the wrong kind is rejected at construction', () {
      expect(
        () => InputAction('bad', InputActionKind.button, [
          const AxisBinding(
            negative: InputControl('k', 'a'),
            positive: InputControl('k', 'b'),
          ),
        ]),
        throwsArgumentError,
      );
    });
  });

  group('serialization', () {
    test('the default map round-trips through JSON', () {
      final original = InputMap.defaults();
      final restored = InputMap.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, Object?>,
      );

      expect(
        restored.actions.map((a) => a.name),
        original.actions.map((a) => a.name),
      );
      expect(jsonEncode(restored.toJson()), jsonEncode(original.toJson()));
    });

    test('a rebound control survives the round trip', () {
      final map = InputMap.defaults();
      map['jump']!.bindings
        ..clear()
        ..add(ButtonBinding(InputControl.key(LogicalKeyboardKey.keyJ)));

      final restored = InputMap.fromJson(
        jsonDecode(jsonEncode(map.toJson())) as Map<String, Object?>,
      );
      final binding = restored['jump']!.bindings.single as ButtonBinding;
      expect(binding.control, InputControl.key(LogicalKeyboardKey.keyJ));
    });

    test('an unknown binding type is a FormatException', () {
      expect(
        () => InputBinding.fromJson({'type': 'telepathy'}),
        throwsFormatException,
      );
    });

    test('a malformed control path is a FormatException', () {
      expect(
        () => InputBinding.fromJson({'type': 'button', 'control': 'nope'}),
        throwsFormatException,
      );
    });
  });

  group('rebinding support', () {
    test('actionsUsing finds conflicts', () {
      final conflicts = input.map.actionsUsing(_space).map((a) => a.name);
      expect(conflicts, contains('jump'));

      final free = input.map.actionsUsing(
        InputControl.key(LogicalKeyboardKey.f13),
      );
      expect(free, isEmpty);
    });

    test('pressedThisFrame captures a key for a rebinding screen', () {
      input.update(0.016);
      expect(input.pressedThisFrame, isEmpty);
      source.press(_a);
      input.update(0.016);
      expect(input.pressedThisFrame, contains(_a));
      input.update(0.016);
      expect(input.pressedThisFrame, isEmpty);
    });
  });

  group('sources', () {
    test('detach stops publishing', () {
      source.press(_space);
      expect(input.isPressed('jump'), isTrue);
      expect(input.detach(source), isTrue);
      expect(input.detach(source), isFalse);
    });
  });
}
