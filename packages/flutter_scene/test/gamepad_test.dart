// Covers the gamepad contract: the standard control vocabulary, the source
// base class's change-tracking and disconnect handling, and the gamepad half
// of InputMap.defaults.

import 'package:flutter/services.dart';
import 'package:flutter_scene/input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A gamepad backend whose "platform" is whatever the test sets.
final class _FakeGamepadSource extends GamepadInputSource {
  List<double> buttons = const [];
  List<double> axes = const [];
  bool connected = true;
  int polls = 0;

  @override
  void poll(double deltaSeconds) {
    polls++;
    if (connected) {
      publishPad(0, buttons: buttons, axes: axes);
    } else {
      disconnectPad(0);
    }
  }
}

/// Records every publish, to pin down what actually reaches the manager.
final class _RecordingSink implements InputSink {
  final List<(InputControl, double)> published = [];

  @override
  void publish(InputControl control, double value) =>
      published.add((control, value));

  @override
  void publishDelta(InputControl control, double value) =>
      published.add((control, value));
}

void main() {
  group('control vocabulary', () {
    test('the standard order matches the W3C mapping', () {
      // Index is the contract: a source hands over a flat array and these
      // positions are what the names mean.
      expect(GamepadButton.standardOrder[0], GamepadButton.south);
      expect(GamepadButton.standardOrder[3], GamepadButton.north);
      expect(GamepadButton.standardOrder[6], GamepadButton.leftTrigger);
      expect(GamepadButton.standardOrder[12], GamepadButton.dpadUp);
      expect(GamepadAxis.standardOrder, [
        GamepadAxis.leftX,
        GamepadAxis.leftY,
        GamepadAxis.rightX,
        GamepadAxis.rightY,
      ]);
    });

    test('a control names its pad, and round-trips through its path', () {
      final first = InputControl.gamepad(GamepadButton.south);
      final second = InputControl.gamepad(GamepadButton.south, pad: 1);
      expect(first.device, 'gamepad0');
      expect(second.device, 'gamepad1');
      expect(first, isNot(second));
      expect(InputControl.tryParse(second.path), second);
    });
  });

  group('GamepadInputSource', () {
    test('publishes only what changed', () {
      final sink = _RecordingSink();
      final source = _FakeGamepadSource()
        ..attach(sink)
        ..buttons = [1, 0]
        ..axes = [0.5, 0];

      source.poll(0.016);
      expect(sink.published, hasLength(4));

      // The pad reports its whole state every poll; an unchanged frame must
      // not republish it.
      sink.published.clear();
      source.poll(0.016);
      expect(sink.published, isEmpty);

      source.buttons = [1, 1];
      source.poll(0.016);
      expect(sink.published, [(InputControl.gamepad(GamepadButton.east), 1.0)]);
    });

    test('names controls past the standard mapping by index', () {
      final sink = _RecordingSink();
      final source = _FakeGamepadSource()
        ..attach(sink)
        ..buttons = List<double>.filled(GamepadButton.standardOrder.length, 0)
        ..axes = const [0, 0, 0, 0, 0.4];
      source.buttons = [...source.buttons, 1];

      source.poll(0.016);
      final ids = sink.published.map((p) => p.$1.id).toSet();
      expect(ids, contains('button${GamepadButton.standardOrder.length}'));
      expect(ids, contains('axis4'));
    });

    test('a pad that vanishes releases its controls', () {
      final sink = _RecordingSink();
      final source = _FakeGamepadSource()
        ..attach(sink)
        ..buttons = [1]
        ..axes = [0.9];
      source.poll(0.016);
      expect(source.connectedPads, [0]);

      sink.published.clear();
      source.connected = false;
      source.poll(0.016);

      // Anything still held has to be zeroed, or it stays held forever.
      expect(sink.published, hasLength(2));
      expect(sink.published.every((p) => p.$2 == 0), isTrue);
      expect(source.connectedPads, isEmpty);
    });

    test('detaching releases held controls too', () {
      final sink = _RecordingSink();
      final source = _FakeGamepadSource()
        ..attach(sink)
        ..buttons = [1];
      source.poll(0.016);

      sink.published.clear();
      source.detach();
      expect(sink.published, [
        (InputControl.gamepad(GamepadButton.south), 0.0),
      ]);
    });
  });

  group('through an InputManager', () {
    late _FakeGamepadSource pad;
    late InputManager input;

    setUp(() {
      pad = _FakeGamepadSource();
      input = InputManager(sources: [pad]);
    });

    tearDown(() => input.dispose());

    test('update polls the source', () {
      input.update(0.016);
      input.update(0.016);
      expect(pad.polls, 2);
    });

    test('the left stick drives move, with +Y forward', () {
      // Pushed forward: a pad reports that as negative Y.
      pad.axes = const [0, -1, 0, 0];
      input.update(0.016);
      expect(input.vector2('move').y, closeTo(1, 1e-6));

      pad.axes = const [1, 0, 0, 0];
      input.update(0.016);
      expect(input.vector2('move').x, closeTo(1, 1e-6));
    });

    test('the d-pad drives move as well as the stick', () {
      pad.buttons = List<double>.filled(16, 0);
      pad.buttons[GamepadButton.standardOrder.indexOf(GamepadButton.dpadUp)] =
          1;
      input.update(0.016);
      expect(input.vector2('move').y, closeTo(1, 1e-6));
    });

    test('a face button edges on the frame after the press', () {
      pad.buttons = const [1];
      input.update(0.016);
      expect(input.wasPressedThisFrame('jump'), isTrue);
      expect(input.isPressed('jump'), isTrue);

      input.update(0.016);
      expect(input.wasPressedThisFrame('jump'), isFalse);
    });

    test('the right trigger fires at its own threshold, not at 1', () {
      pad.buttons = List<double>.filled(16, 0);
      final trigger = GamepadButton.standardOrder.indexOf(
        GamepadButton.rightTrigger,
      );

      pad.buttons[trigger] = 0.2;
      input.update(0.016);
      expect(input.isPressed('fire'), isFalse);

      pad.buttons[trigger] = 0.5;
      input.update(0.016);
      expect(input.isPressed('fire'), isTrue);
      expect(input.wasPressedThisFrame('fire'), isTrue);
    });

    test('keyboard and pad share an action without fighting', () {
      final keyboard = _KeySource();
      input.attach(keyboard);

      // The keyboard says full forward while the stick is pushed half a turn
      // the other way. The action takes the strongest binding, so the answer
      // is full forward: not summed to a half, and not cancelled to nothing.
      keyboard.press(InputControl.key(LogicalKeyboardKey.keyW));
      pad.axes = const [0, 0.5, 0, 0];
      input.update(0.016);
      expect(input.vector2('move'), Vector2(0, 1));

      // With the key released the stick is the only binding with any
      // magnitude, and it keeps its analog value.
      keyboard.release(InputControl.key(LogicalKeyboardKey.keyW));
      input.update(0.016);
      expect(input.vector2('move').y, closeTo(-0.5, 1e-6));
    });

    test('the whole map still round-trips with gamepad bindings in it', () {
      final restored = InputMap.fromJson(InputMap.defaults().toJson());
      final manager = InputManager(map: restored, sources: [pad]);
      addTearDown(manager.dispose);

      pad.buttons = List<double>.filled(16, 0);
      pad.buttons[GamepadButton.standardOrder.indexOf(
            GamepadButton.rightTrigger,
          )] =
          0.5;
      manager.update(0.016);
      expect(
        manager.isPressed('fire'),
        isTrue,
        reason: 'the analog threshold must survive serialization',
      );
    });
  });
}

final class _KeySource extends InputSource {
  InputSink? _sink;

  @override
  void attach(InputSink sink) => _sink = sink;

  @override
  void detach() => _sink = null;

  void press(InputControl control) => _sink!.publish(control, 1);
  void release(InputControl control) => _sink!.publish(control, 0);
}
