import 'package:flutter_scene_input/flutter_scene_input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector2;

import 'test_support.dart';

const jump = ButtonAction('jump');
const sprint = ButtonAction('sprint');
const save = ButtonAction('save');
const back = ButtonAction('back');
const move = VectorAction('move');
const look = DeltaAction('look');
const throttle = AxisAction('throttle', range: AxisRange.unipolar);
const steer = AxisAction('steer');

Matcher _vec(double x, double y) => predicate<Vector2>(
  (v) => (v.x - x).abs() < 1e-6 && (v.y - y).abs() < 1e-6,
  '($x, $y)',
);

void main() {
  group('button edges', () {
    late PlayerInput player;
    late ActionSet set;

    setUp(() {
      (_, player, _) = makeSystem();
      set = ActionSet('gameplay', {
        jump: {
          'keyboard': const ButtonBinding(space),
          'gamepad': const ButtonBinding(GamepadControl.south),
        },
      });
      player.contexts.push(set);
    });

    test('a press is seen once, on the frame after it arrives', () {
      player.advanceFrame(1 / 60);
      player.inject(space, 1);
      expect(player.button(jump).justPressed, isFalse);

      player.advanceFrame(1 / 60);
      expect(player.button(jump).pressed, isTrue);
      expect(player.button(jump).justPressed, isTrue);

      player.advanceFrame(1 / 60);
      expect(player.button(jump).pressed, isTrue);
      expect(player.button(jump).justPressed, isFalse);
    });

    test('a tap inside one frame still reads as pressed and released', () {
      player.advanceFrame(1 / 60);
      player
        ..inject(space, 1)
        ..inject(space, 0);
      player.advanceFrame(1 / 60);
      final state = player.button(jump);
      expect(state.pressed, isFalse);
      expect(state.justPressed, isTrue);
      expect(state.justReleased, isTrue);
      expect(state.pressCount, 1);
    });

    test('a second binding of a held action does not press again', () {
      player.inject(space, 1);
      player.advanceFrame(1 / 60);
      player.inject(GamepadControl.south, 1);
      player.advanceFrame(1 / 60);
      expect(player.button(jump).justPressed, isFalse);
      expect(player.button(jump).pressCount, 1);
    });

    test('the fixed window sees each edge exactly once per step', () {
      player.inject(space, 1);
      // A frame with no fixed steps: the frame window sees the press.
      player.advanceFrame(1 / 120);
      expect(player.button(jump).justPressed, isTrue);

      // The next frame runs two fixed steps. Only the first sees the press.
      player.advanceFrame(1 / 30);
      player.advanceFixedStep(1 / 60);
      expect(player.fixed.button(jump).justPressed, isTrue);
      player.advanceFixedStep(1 / 60);
      expect(player.fixed.button(jump).justPressed, isFalse);
      expect(player.fixed.button(jump).pressed, isTrue);
      expect(player.button(jump).justPressed, isFalse);
    });

    test('an analog press uses hysteresis', () {
      final triggerSet = ActionSet('trigger', {
        sprint: {'gamepad': const ButtonBinding(GamepadControl.rightTrigger)},
      });
      player.contexts.push(triggerSet);
      player.inject(GamepadControl.rightTrigger, 0.55);
      player.inject(GamepadControl.rightTrigger, 0.45);
      player.inject(GamepadControl.rightTrigger, 0.52);
      player.advanceFrame(1 / 60);
      expect(player.button(sprint).pressCount, 1);
      player.inject(GamepadControl.rightTrigger, 0.3);
      player.advanceFrame(1 / 60);
      expect(player.button(sprint).justReleased, isTrue);
    });

    test('heldFor measures the press on the window clock', () {
      final (_, player, clock) = makeSystem();
      player.contexts.push(set);
      player.inject(space, 1);
      clock.seconds = 0.75;
      player.advanceFrame(1 / 60);
      expect(player.button(jump).heldFor, closeTo(0.75, 1e-9));
    });
  });

  group('values', () {
    test('the most actuated binding wins', () {
      final (_, player, _) = makeSystem();
      player.contexts.push(
        ActionSet('gameplay', {
          move: {
            'keyboard': const DpadBinding(
              up: keyW,
              down: keyS,
              left: keyA,
              right: keyD,
            ),
            'gamepad': const StickBinding(GamepadControl.leftStick),
          },
        }),
      );
      player
        ..inject(GamepadControl.leftStickX, 0.3)
        ..inject(keyW, 1);
      player.advanceFrame(1 / 60);
      expect(player.vector(move), _vec(0, 1));

      player.inject(keyW, 0);
      player.advanceFrame(1 / 60);
      expect(player.vector(move), _vec(0.3, 0));
    });

    test('dpad diagonals are unit length', () {
      final (_, player, _) = makeSystem();
      player.contexts.push(
        ActionSet('gameplay', {
          move: {
            'keyboard': const DpadBinding(
              up: keyW,
              down: keyS,
              left: keyA,
              right: keyD,
            ),
          },
        }),
      );
      player
        ..inject(keyW, 1)
        ..inject(keyD, 1);
      player.advanceFrame(1 / 60);
      expect(player.vector(move).length, closeTo(1, 1e-6));
    });

    test('a scaled radial deadzone has no step at the threshold', () {
      final (_, player, _) = makeSystem();
      player.contexts.push(
        ActionSet('gameplay', {
          move: {
            'gamepad': const StickBinding(
              GamepadControl.leftStick,
              processors: [Deadzone(0.2)],
            ),
          },
        }),
      );
      player.inject(GamepadControl.leftStickX, 0.19);
      player.advanceFrame(1 / 60);
      expect(player.vector(move).length, 0);

      player.inject(GamepadControl.leftStickX, 0.21);
      player.advanceFrame(1 / 60);
      expect(player.vector(move).x, closeTo(0.0125, 1e-9));

      player.inject(GamepadControl.leftStickX, 1);
      player.advanceFrame(1 / 60);
      expect(player.vector(move).x, closeTo(1, 1e-9));
    });

    test('a tunable deadzone reads the player setting', () {
      final (_, player, _) = makeSystem();
      player.contexts.push(
        ActionSet('gameplay', {
          move: {
            'gamepad': const StickBinding(
              GamepadControl.leftStick,
              processors: [Deadzone.tunable('deadzone', 0.1)],
            ),
          },
        }),
      );
      player.inject(GamepadControl.leftStickX, 0.3);
      player.advanceFrame(1 / 60);
      expect(player.vector(move).x, greaterThan(0));
      player.overrides.tune('deadzone', 0.4);
      player.advanceFrame(1 / 60);
      expect(player.vector(move).x, 0);
    });

    test('axis pairs and unipolar clamping', () {
      final (_, player, _) = makeSystem();
      player.contexts.push(
        ActionSet('vehicle', {
          steer: {
            'keyboard': const AxisPairBinding(negative: keyA, positive: keyD),
          },
          throttle: {'gamepad': const AxisBinding(GamepadControl.leftStickY)},
        }),
      );
      player
        ..inject(keyA, 1)
        ..inject(GamepadControl.leftStickY, -0.8);
      player.advanceFrame(1 / 60);
      expect(player.axis(steer), -1);
      expect(player.axis(throttle), 0);
    });

    test('tunable scales read the player value', () {
      final (_, player, _) = makeSystem();
      player.contexts.push(
        ActionSet('vehicle', {
          steer: {
            'gamepad': const AxisBinding(
              GamepadControl.leftStickX,
              processors: [Scale.tunable('steerSensitivity', 0.5)],
            ),
          },
        }),
      );
      player.inject(GamepadControl.leftStickX, 1);
      player.advanceFrame(1 / 60);
      expect(player.axis(steer), 0.5);
      player.overrides.tune('steerSensitivity', 0.8);
      player.advanceFrame(1 / 60);
      expect(player.axis(steer), 0.8);
    });
  });

  group('deltas', () {
    late PlayerInput player;

    setUp(() {
      (_, player, _) = makeSystem();
      player.contexts.push(
        ActionSet('gameplay', {
          look: {
            'mouse': const DeltaBinding(
              MouseControl.delta,
              processors: [Scale(2)],
            ),
            'gamepad': const StickBinding(
              GamepadControl.rightStick,
              processors: [PerSecond(600)],
            ),
          },
        }),
      );
    });

    test('mouse movement accumulates per window and keeps magnitude', () {
      player
        ..injectDelta(MouseControl.delta, 30, -4)
        ..injectDelta(MouseControl.delta, 20, 0);
      player.advanceFrame(1 / 60);
      expect(player.delta(look), _vec(100, -8));
      player.advanceFrame(1 / 60);
      expect(player.delta(look), _vec(0, 0));
    });

    test('a stick feeds the same action as a rate over the window', () {
      player.inject(GamepadControl.rightStickX, 0.5);
      player.injectDelta(MouseControl.delta, 5, 0);
      player.advanceFrame(0.1);
      // 0.5 * 600 * 0.1 from the stick plus 5 * 2 from the mouse.
      expect(player.delta(look), _vec(40, 0));
    });

    test('frame and fixed windows each receive all movement', () {
      player.injectDelta(MouseControl.delta, 10, 0);
      player.advanceFixedStep(1 / 60);
      player.injectDelta(MouseControl.delta, 10, 0);
      player.advanceFixedStep(1 / 60);
      player.advanceFrame(1 / 30);
      expect(player.fixed.delta(look), _vec(20, 0));
      expect(player.delta(look), _vec(40, 0));
    });

    test('a gated delta only moves while the modifier is held', () {
      final (_, player, _) = makeSystem();
      player.contexts.push(
        ActionSet('editor', {
          look: {
            'mouse': const GatedBinding([
              MouseControl.right,
            ], DeltaBinding(MouseControl.delta)),
          },
        }),
      );
      player.injectDelta(MouseControl.delta, 10, 0);
      player.advanceFrame(1 / 60);
      expect(player.delta(look), _vec(0, 0));

      player.inject(MouseControl.right, 1);
      player.injectDelta(MouseControl.delta, 10, 0);
      player.advanceFrame(1 / 60);
      expect(player.delta(look), _vec(10, 0));
    });
  });

  group('chords', () {
    test('the longest chord wins over its trigger alone', () {
      final (_, player, _) = makeSystem();
      player.contexts.push(
        ActionSet('editor', {
          back: {'keyboard': const ButtonBinding(keyS)},
          save: {
            'keyboard': const ChordBinding([controlLeft], keyS),
          },
        }),
      );
      player
        ..inject(controlLeft, 1)
        ..inject(keyS, 1);
      player.advanceFrame(1 / 60);
      expect(player.button(save).pressed, isTrue);
      expect(player.button(back).pressed, isFalse);

      player.inject(controlLeft, 0);
      player.advanceFrame(1 / 60);
      expect(player.button(save).pressed, isFalse);
      expect(player.button(back).pressed, isTrue);
    });

    test('a trigger pressed before its modifiers does not fire the chord', () {
      final (_, player, _) = makeSystem();
      player.contexts.push(
        ActionSet('editor', {
          save: {
            'keyboard': const ChordBinding([controlLeft], keyS),
          },
        }),
      );
      player
        ..inject(keyS, 1)
        ..inject(controlLeft, 1);
      player.advanceFrame(1 / 60);
      expect(player.button(save).pressCount, 0);
    });
  });

  group('contexts', () {
    const confirm = ButtonAction('confirm');

    test('a firing binding consumes its controls for lower contexts', () {
      final (_, player, _) = makeSystem();
      player.contexts.push(
        ActionSet('gameplay', {
          jump: {'keyboard': const ButtonBinding(space)},
          sprint: {'keyboard': const ButtonBinding(shiftLeft)},
        }),
      );
      player.contexts.push(
        ActionSet('dialog', {
          confirm: {'keyboard': const ButtonBinding(space)},
        }),
      );
      player
        ..inject(space, 1)
        ..inject(shiftLeft, 1);
      player.advanceFrame(1 / 60);
      expect(player.button(confirm).pressed, isTrue);
      expect(player.button(jump).pressed, isFalse);
      expect(player.button(sprint).pressed, isTrue);
    });

    test('a dpad part engaged above is consumed below', () {
      const pan = VectorAction('pan');
      const strafeLeft = ButtonAction('strafeLeft');
      final (_, player, _) = makeSystem();
      player.contexts.push(
        ActionSet('lower', {
          strafeLeft: {'keyboard': const ButtonBinding(keyA)},
        }),
      );
      player.contexts.push(
        ActionSet('upper', {
          pan: {
            'keyboard': const DpadBinding(
              up: keyW,
              down: keyS,
              left: keyA,
              right: keyD,
            ),
          },
        }),
      );
      player.inject(keyW, 1);
      player.advanceFrame(1 / 60);
      player.inject(keyA, 1);
      player.advanceFrame(1 / 60);
      // A is engaged in the upper dpad now, so it is consumed.
      expect(player.button(strafeLeft).pressed, isFalse);
    });

    test('an opaque context blocks everything below it', () {
      final (_, player, _) = makeSystem();
      player.contexts.push(
        ActionSet('gameplay', {
          jump: {'keyboard': const ButtonBinding(space)},
          sprint: {'keyboard': const ButtonBinding(shiftLeft)},
        }),
      );
      final menu = player.contexts.push(
        ActionSet('menu', {
          confirm: {'keyboard': const ButtonBinding(keyE)},
        }),
        opaque: true,
      );
      player.inject(shiftLeft, 1);
      player.advanceFrame(1 / 60);
      expect(player.button(sprint).pressed, isFalse);

      menu.remove();
      player.advanceFrame(1 / 60);
      expect(player.button(sprint).justPressed, isTrue);
    });

    test('priority orders entries regardless of push order', () {
      final (_, player, _) = makeSystem();
      final high = ActionSet('high', {
        confirm: {'keyboard': const ButtonBinding(space)},
      });
      final low = ActionSet('low', {
        jump: {'keyboard': const ButtonBinding(space)},
      });
      player.contexts.push(high, priority: 10);
      player.contexts.push(low);
      expect(player.contexts.entries.first.set, same(high));
      player.inject(space, 1);
      player.advanceFrame(1 / 60);
      expect(player.button(confirm).pressed, isTrue);
      expect(player.button(jump).pressed, isFalse);
    });

    test('text entry suppresses gameplay and releases held actions', () {
      final (_, player, _) = makeSystem();
      player.contexts.push(
        ActionSet('gameplay', {
          jump: {'keyboard': const ButtonBinding(space)},
        }),
      );
      player.contexts.push(
        ActionSet('chat', {
          confirm: {'keyboard': const ButtonBinding(space)},
        }, allowDuringTextEntry: true),
      );
      player.contexts.entries.first.remove();
      player.inject(space, 1);
      player.advanceFrame(1 / 60);
      expect(player.button(jump).pressed, isTrue);

      player.textEntryActive = true;
      player.advanceFrame(1 / 60);
      expect(player.button(jump).justReleased, isTrue);
    });

    test('pushing a live set twice throws', () {
      final (_, player, _) = makeSystem();
      final set = ActionSet('gameplay', {});
      player.contexts.push(set);
      expect(() => player.contexts.push(set), throwsStateError);
    });
  });

  group('recognizers', () {
    const interact = ButtonAction('interact');
    const interactHold = HoldAction(
      'interactHold',
      source: interact,
      duration: 0.5,
    );
    const crouchToggle = HoldAction(
      'crouchToggle',
      source: interact,
      duration: 0.5,
      toggle: true,
    );
    const dodge = TapAction('dodge', source: interact, maxDuration: 0.2);
    const doubleTap = MultiTapAction('doubleTap', source: interact);

    late PlayerInput player;
    late FakeClock clock;

    setUp(() {
      (_, player, clock) = makeSystem();
      player.contexts.push(
        ActionSet(
          'gameplay',
          {
            interact: {'keyboard': const ButtonBinding(keyE)},
          },
          derived: [interactHold, crouchToggle, dodge, doubleTap],
        ),
      );
    });

    test('hold fires once the duration passes', () {
      player.inject(keyE, 1);
      clock.seconds = 0.4;
      player.advanceFrame(0.4);
      expect(player.button(interactHold).pressed, isFalse);
      clock.seconds = 0.6;
      player.advanceFrame(0.2);
      expect(player.button(interactHold).justPressed, isTrue);
      player.inject(keyE, 0);
      player.advanceFrame(1 / 60);
      expect(player.button(interactHold).justReleased, isTrue);
    });

    test('toggle holds flip on each completed hold', () {
      player.inject(keyE, 1);
      clock.seconds = 0.6;
      player.advanceFrame(0.6);
      player.inject(keyE, 0);
      player.advanceFrame(0.1);
      expect(player.button(crouchToggle).pressed, isTrue);

      clock.seconds = 1.0;
      player.inject(keyE, 1);
      clock.seconds = 1.6;
      player.advanceFrame(0.6);
      expect(player.button(crouchToggle).pressed, isFalse);
    });

    test('tap fires on a short press and not a long one', () {
      player.inject(keyE, 1);
      clock.seconds = 0.1;
      player.inject(keyE, 0);
      player.advanceFrame(0.1);
      expect(player.button(dodge).justPressed, isTrue);
      expect(player.button(dodge).pressed, isFalse);

      clock.seconds = 1;
      player.inject(keyE, 1);
      clock.seconds = 1.5;
      player.inject(keyE, 0);
      player.advanceFrame(0.5);
      expect(player.button(dodge).justPressed, isFalse);
    });

    test('multi-tap needs presses inside the window', () {
      player
        ..inject(keyE, 1)
        ..inject(keyE, 0);
      clock.seconds = 0.2;
      player
        ..inject(keyE, 1)
        ..inject(keyE, 0);
      player.advanceFrame(0.2);
      expect(player.button(doubleTap).pressCount, 1);

      clock.seconds = 1;
      player
        ..inject(keyE, 1)
        ..inject(keyE, 0);
      clock.seconds = 1.5;
      player
        ..inject(keyE, 1)
        ..inject(keyE, 0);
      player.advanceFrame(1.3);
      expect(player.button(doubleTap).pressCount, 1);
    });
  });

  group('devices and pairing', () {
    test('a paired device feeds only its player', () {
      final (system, player, _) = makeSystem();
      final second = system.createPlayer();
      final set = ActionSet('gameplay', {
        jump: {'gamepad': const ButtonBinding(GamepadControl.south)},
      });
      player.contexts.push(set);
      second.contexts.push(set);

      final pad = system.connectDevice(DeviceKind.gamepad, name: 'Pad');
      second.pair(pad);
      system.publish(pad, GamepadControl.south, 1);
      system.advanceFrame(1 / 60);
      expect(second.button(jump).pressed, isTrue);
      expect(player.button(jump).pressed, isFalse);
    });

    test('disconnecting releases held controls and keeps the handle', () {
      final (system, player, _) = makeSystem();
      player.contexts.push(
        ActionSet('gameplay', {
          jump: {'gamepad': const ButtonBinding(GamepadControl.south)},
        }),
      );
      final pad = system.connectDevice(
        DeviceKind.gamepad,
        name: 'Pad',
        identity: 'usb-1',
      );
      system.publish(pad, GamepadControl.south, 1);
      system.disconnectDevice(pad);
      system.advanceFrame(1 / 60);
      expect(player.button(jump).pressed, isFalse);

      final back = system.connectDevice(
        DeviceKind.gamepad,
        name: 'Pad',
        identity: 'usb-1',
      );
      expect(back.handle, pad.handle);
      expect(back.connected, isTrue);
    });

    test('active device kind follows the last meaningful input', () {
      final (_, player, _) = makeSystem();
      var changes = 0;
      player.addActiveDeviceListener(() => changes++);
      player.inject(keyW, 1);
      expect(player.activeDeviceKind, DeviceKind.keyboard);
      player.inject(GamepadControl.leftStickX, 0.2);
      expect(player.activeDeviceKind, DeviceKind.keyboard);
      player.inject(GamepadControl.leftStickX, 0.9);
      expect(player.activeDeviceKind, DeviceKind.gamepad);
      player.injectDelta(MouseControl.delta, 0.5, 0);
      expect(player.activeDeviceKind, DeviceKind.gamepad);
      expect(changes, 2);
    });

    test('sources poll before windows advance', () {
      final (system, player, _) = makeSystem();
      player.contexts.push(
        ActionSet('gameplay', {
          jump: {'gamepad': const ButtonBinding(GamepadControl.south)},
        }),
      );
      final source = _PollingSource();
      system.addSource(source);
      system.advanceFrame(1 / 60);
      expect(player.button(jump).justPressed, isTrue);
      expect(system.removeSource(source), isTrue);
      expect(source.detached, isTrue);
    });
  });

  group('action set validation', () {
    test('rejects bindings that cannot produce the action value', () {
      expect(
        () => ActionSet('bad', {
          jump: {'gamepad': const StickBinding(GamepadControl.leftStick)},
        }),
        throwsArgumentError,
      );
      expect(
        () => ActionSet('bad', {
          look: {'gamepad': const StickBinding(GamepadControl.rightStick)},
        }),
        throwsArgumentError,
      );
      expect(
        () => ActionSet('bad', {
          move: {'keyboard': const StickBinding(GamepadControl.leftStickX)},
        }),
        throwsArgumentError,
      );
    });

    test('rejects a derived action whose source is not in the set', () {
      expect(
        () => ActionSet(
          'bad',
          {},
          derived: [const TapAction('tap', source: jump)],
        ),
        throwsArgumentError,
      );
    });
  });
}

final class _PollingSource extends InputSource {
  InputSink? _sink;
  InputDevice? _pad;
  bool detached = false;

  @override
  void attach(InputSink sink) {
    _sink = sink;
    _pad = sink.connectDevice(DeviceKind.gamepad, name: 'Polled');
  }

  @override
  void detach() => detached = true;

  @override
  void poll(double deltaSeconds) =>
      _sink!.publish(_pad!, GamepadControl.south, 1);
}
