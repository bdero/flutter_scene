import 'package:fake_async/fake_async.dart';
import 'package:flutter_scene_input/flutter_scene_input.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

const jump = ButtonAction('jump');
const interact = ButtonAction('interact');
const save = ButtonAction('save');
const move = VectorAction('move');
const look = DeltaAction('look');
const crouch = HoldAction('crouch', source: interact, duration: 0.5);
const escape = KeyControl(0x00070029);
const keyQ = KeyControl(0x00070014);

ActionSet gameplaySet({String? conflictGroup}) => ActionSet(
  'gameplay',
  {
    jump: {
      'keyboard': const ButtonBinding(space),
      'gamepad': const ButtonBinding(GamepadControl.south),
    },
    interact: {'keyboard': const ButtonBinding(keyE)},
    save: {
      'keyboard': const ChordBinding([controlLeft], keyS),
    },
    move: {
      'keyboard': const DpadBinding(
        up: keyW,
        down: keyS,
        left: keyA,
        right: keyD,
      ),
      'gamepad': const StickBinding(GamepadControl.leftStick),
    },
    look: {
      'gamepad': const StickBinding(
        GamepadControl.rightStick,
        processors: [PerSecond(100), Invert.tunable('invertLookY')],
      ),
    },
  },
  derived: [crouch],
  conflictGroup: conflictGroup,
);

void main() {
  group('overrides', () {
    late PlayerInput player;
    late ActionSet set;

    setUp(() {
      (_, player, _) = makeSystem();
      set = gameplaySet();
      player.contexts.push(set);
    });

    test('a rebound slot answers to the new control only', () {
      player.overrides.bind(jump, keyF, slot: 'keyboard');
      player.inject(space, 1);
      player.advanceFrame(1 / 60);
      expect(player.button(jump).pressed, isFalse);
      player.inject(keyF, 1);
      player.advanceFrame(1 / 60);
      expect(player.button(jump).pressed, isTrue);
    });

    test('composite parts rebind and clear individually', () {
      player.overrides.bind(move, keyQ, slot: 'keyboard', part: 'up');
      player.overrides.clear(move, slot: 'keyboard', part: 'right');
      player
        ..inject(keyQ, 1)
        ..inject(keyD, 1);
      player.advanceFrame(1 / 60);
      expect(player.vector(move).y, closeTo(1, 1e-6));
      expect(player.vector(move).x, 0);
    });

    test('a cleared slot never actuates', () {
      player.overrides.clear(jump, slot: 'keyboard');
      player.inject(space, 1);
      player.advanceFrame(1 / 60);
      expect(player.button(jump).pressed, isFalse);
      player.inject(GamepadControl.south, 1);
      player.advanceFrame(1 / 60);
      expect(player.button(jump).pressed, isTrue);
    });

    test('bad rebinds throw', () {
      expect(
        () => player.overrides.bind(
          jump,
          GamepadControl.leftStick,
          slot: 'keyboard',
        ),
        throwsArgumentError,
      );
      expect(
        () => player.overrides.bind(
          move,
          keyQ,
          slot: 'keyboard',
          part: 'diagonal',
        ),
        throwsArgumentError,
      );
      expect(
        () => player.overrides.bind(jump, keyQ, slot: 'nope'),
        throwsArgumentError,
      );
    });

    test('reset restores authored bindings', () {
      player.overrides
        ..bind(jump, keyF, slot: 'keyboard')
        ..bind(interact, keyF, slot: 'keyboard');
      player.overrides.reset(jump);
      expect(player.overrides.records.single.action, 'interact');
      player.overrides.resetAll();
      expect(player.overrides.records, isEmpty);
    });

    test('tunable inversion and recognizer toggles', () {
      player.inject(GamepadControl.rightStickY, 1);
      player.advanceFrame(0.1);
      expect(player.delta(look).y, closeTo(10, 1e-6));
      player.overrides.tune('invertLookY', 1);
      player.advanceFrame(0.1);
      expect(player.delta(look).y, closeTo(-10, 1e-6));

      final (_, held, clock) = makeSystem();
      held.contexts.push(gameplaySet());
      held.overrides.setToggle(crouch, true);
      held.inject(keyE, 1);
      clock.seconds = 0.6;
      held.advanceFrame(0.6);
      held.inject(keyE, 0);
      held.advanceFrame(0.1);
      expect(held.button(crouch).pressed, isTrue);
    });
  });

  group('profiles', () {
    late PlayerInput player;

    setUp(() {
      (_, player, _) = makeSystem();
      player.contexts.push(gameplaySet());
      player.overrides
        ..bind(move, keyQ, slot: 'keyboard', part: 'up')
        ..bind(jump, keyF, slot: 'keyboard')
        ..clear(jump, slot: 'gamepad')
        ..tune('mouseSensitivity', 1.4)
        ..setToggle(crouch, true);
    });

    test('serialize to the golden document', () {
      expect(player.overrides.toJsonString(), r'''{
  "format": "flutter_scene_input.profile",
  "version": 1,
  "name": "default",
  "bindings": [
    {
      "set": "gameplay",
      "action": "jump",
      "slot": "gamepad",
      "control": null
    },
    {
      "set": "gameplay",
      "action": "jump",
      "slot": "keyboard",
      "control": "keyboard/KeyF"
    },
    {
      "set": "gameplay",
      "action": "move",
      "slot": "keyboard",
      "part": "up",
      "control": "keyboard/KeyQ"
    }
  ],
  "tunables": {
    "mouseSensitivity": 1.4
  },
  "recognizers": {
    "gameplay/crouch": {
      "toggle": true
    }
  }
}''');
    });

    test('round-trip into another player', () {
      final (_, other, _) = makeSystem();
      other.contexts.push(gameplaySet());
      other.overrides.loadJsonString(player.overrides.toJsonString());
      expect(other.overrides.toJsonString(), player.overrides.toJsonString());
      other.inject(keyF, 1);
      other.advanceFrame(1 / 60);
      expect(other.button(jump).pressed, isTrue);
    });

    test('renames and migrations rewrite old records', () {
      final old = player.overrides.toJson()
        ..['bindings'] = [
          {
            'set': 'play',
            'action': 'hop',
            'slot': 'keyboard',
            'control': 'keyboard/KeyF',
          },
          {
            'set': 'play',
            'action': 'wave',
            'slot': 'keyboard',
            'control': 'keyboard/KeyG',
          },
        ];
      final (_, other, _) = makeSystem();
      other.contexts.push(gameplaySet());
      other.overrides.loadJson(
        old,
        renames: {'play': 'gameplay', 'play/hop': 'gameplay/jump'},
        migrate: (record) => record.action == 'wave' ? null : record,
      );
      expect(other.overrides.records.map((r) => r.toString()), [
        'gameplay/jump/keyboard -> keyboard/KeyF',
      ]);
    });

    test('unknown records survive a load and are reported', () {
      final json = player.overrides.toJson();
      (json['bindings'] as List).add({
        'set': 'vehicle',
        'action': 'honk',
        'slot': 'keyboard',
        'control': 'keyboard/KeyH',
      });
      (json['bindings'] as List).add({
        'set': 'gameplay',
        'action': 'interact',
        'slot': 'keyboard',
        'control': 'keyboard/FutureKey',
      });
      final (_, other, _) = makeSystem();
      other.contexts.push(gameplaySet());
      other.overrides.loadJson(json);
      final unmatched = other.overrides.unmatched([gameplaySet()]);
      expect(unmatched.map((r) => r.action), ['honk', 'interact']);
      expect(other.overrides.toJson()['bindings'], hasLength(5));

      // The unparsable control keeps the authored binding.
      other.inject(keyE, 1);
      other.advanceFrame(1 / 60);
      expect(other.button(interact).pressed, isTrue);
    });

    test('bool tunables load as 1 and 0', () {
      player.overrides.loadJson({
        'format': PlayerOverrides.format,
        'version': 1,
        'tunables': {'invertLookY': true},
      });
      expect(player.overrides.tunable('invertLookY', 0), 1);
    });

    test('a newer version or another format is refused', () {
      expect(
        () => player.overrides.loadJson({
          'format': PlayerOverrides.format,
          'version': 2,
        }),
        throwsFormatException,
      );
      expect(
        () => player.overrides.loadJson({'format': 'other', 'version': 1}),
        throwsFormatException,
      );
    });
  });

  group('listen for binding', () {
    late PlayerInput player;

    setUp(() {
      (_, player, _) = makeSystem();
      player.contexts.push(gameplaySet());
    });

    test('binds the pressed key and suppresses actions until release', () {
      fakeAsync((async) {
        RebindResult? result;
        player
            .listenForBinding(jump, slot: 'keyboard')
            .result
            .then((r) => result = r);

        player.inject(keyE, 1);
        player.advanceFrame(1 / 60);
        expect(player.button(interact).pressed, isFalse);

        async.elapse(const Duration(milliseconds: 200));
        expect(result!.status, RebindStatus.bound);
        expect(result!.control, keyE);
        expect(result!.conflicts.single.location.action, interact);

        // Still suppressed while the key that chose the binding is held.
        result!.apply();
        player.advanceFrame(1 / 60);
        expect(player.button(jump).pressed, isFalse);

        player.inject(keyE, 0);
        player.inject(keyE, 1);
        player.advanceFrame(1 / 60);
        expect(player.button(jump).pressed, isTrue);
        expect(player.button(interact).pressed, isFalse);
      });
    });

    test('escape cancels and a timeout ends the listen', () {
      fakeAsync((async) {
        final results = <RebindResult>[];
        player
            .listenForBinding(jump, slot: 'keyboard')
            .result
            .then(results.add);
        player.inject(escape, 1);
        async.flushMicrotasks();
        expect(results.single.status, RebindStatus.cancelled);
        player.inject(escape, 0);

        player
            .listenForBinding(
              jump,
              slot: 'keyboard',
              timeout: const Duration(seconds: 2),
            )
            .result
            .then(results.add);
        async.elapse(const Duration(seconds: 3));
        expect(results.last.status, RebindStatus.timedOut);

        player.inject(space, 1);
        player.advanceFrame(1 / 60);
        expect(player.button(jump).pressed, isTrue);
      });
    });

    test('a stick slot takes the stick whose axis moved most', () {
      fakeAsync((async) {
        RebindResult? result;
        player
            .listenForBinding(move, slot: 'gamepad')
            .result
            .then((r) => result = r);
        player.inject(GamepadControl.leftStickX, 0.6);
        player.inject(GamepadControl.rightStickY, 0.95);
        player.inject(south, 1);
        async.elapse(const Duration(milliseconds: 200));
        expect(result!.control, GamepadControl.rightStick);
      });
    });

    test('keys already held when the listen starts cannot win', () {
      fakeAsync((async) {
        player.inject(keyF, 1);
        RebindResult? result;
        player
            .listenForBinding(jump, slot: 'keyboard')
            .result
            .then((r) => result = r);
        player.inject(keyF, 0.9);
        async.elapse(const Duration(milliseconds: 200));
        expect(result, isNull);
        player.inject(keyA, 1);
        async.elapse(const Duration(milliseconds: 200));
        expect(result!.control, keyA);
      });
    });
  });

  group('conflicts', () {
    test('swap gives the conflicting slot the previous control', () {
      fakeAsync((async) {
        final (_, player, _) = makeSystem();
        player.contexts.push(gameplaySet());
        RebindResult? result;
        player
            .listenForBinding(jump, slot: 'keyboard')
            .result
            .then((r) => result = r);
        player.inject(keyE, 1);
        async.elapse(const Duration(milliseconds: 200));
        result!.apply(resolution: ConflictResolution.swap);
        expect(
          player.overrides.records.map((r) => r.toString()),
          containsAll([
            'gameplay/jump/keyboard -> keyboard/KeyE',
            'gameplay/interact/keyboard -> keyboard/Space',
          ]),
        );
      });
    });

    test('a chord does not conflict with its trigger alone', () {
      final (_, player, _) = makeSystem();
      final set = gameplaySet();
      player.contexts.push(set);
      final conflicts = player.conflictsFor(
        BindingLocation(set, save, 'keyboard', 'trigger'),
        keyS,
        [set],
      );
      expect(conflicts, isEmpty);
    });

    test('sets sharing a conflict group are checked together', () {
      final (_, player, _) = makeSystem();
      final gameplay = gameplaySet(conflictGroup: 'onFoot');
      const emote = ButtonAction('emote');
      final emotes = ActionSet('emotes', {
        emote: {'keyboard': const ButtonBinding(keyF)},
      }, conflictGroup: 'onFoot');
      final menu = ActionSet('menu', {
        emote: {'keyboard': const ButtonBinding(keyE)},
      });
      final all = [gameplay, emotes, menu];
      expect(
        player
            .conflictsFor(
              BindingLocation(gameplay, jump, 'keyboard'),
              keyF,
              all,
            )
            .single
            .location
            .set,
        emotes,
      );
      player.contexts.push(gameplay);
      player.overrides.bind(interact, keyF, slot: 'keyboard', set: gameplay);
      final pairs = player.findConflicts(all).map((c) => '${c.$1} ${c.$2}');
      expect(pairs, ['gameplay/interact/keyboard emotes/emote/keyboard']);
    });
  });

  group('display', () {
    test('labels follow slots, parts, and chords', () {
      final (_, player, _) = makeSystem();
      player.contexts.push(gameplaySet());
      expect(player.bindingDisplay(move)!.label, 'W/A/S/D');
      expect(player.bindingDisplay(save)!.label, 'Left Ctrl + S');
      player.overrides.bind(move, keyQ, slot: 'keyboard', part: 'up');
      expect(player.bindingDisplay(move)!.label, 'Q/A/S/D');
      player.overrides.clear(jump, slot: 'keyboard');
      expect(player.bindingDisplay(jump, slot: 'keyboard')!.label, 'Unbound');
    });

    test('gamepad labels follow the last pad style', () {
      final (system, player, _) = makeSystem();
      player.contexts.push(gameplaySet());
      expect(
        player.bindingDisplay(jump, device: DeviceKind.gamepad)!.label,
        'South',
      );
      final pad = system.connectDevice(
        DeviceKind.gamepad,
        name: 'Pro Controller',
      );
      var notified = 0;
      player.addBindingsListener(() => notified++);
      system.publish(pad, GamepadControl.south, 1);
      expect(notified, greaterThan(0));
      expect(player.bindingDisplay(jump)!.label, 'B');
    });

    test('resolvers supply layout labels and glyphs', () {
      final (system, player, _) = makeSystem();
      player.contexts.push(gameplaySet());
      system
        ..keyLabelResolver = ((key) => key == keyW ? 'Z' : null)
        ..glyphResolver = ((control, style) => 'glyphs/${control.path}.png');
      final display = player.bindingDisplay(move)!;
      expect(display.label, 'Z/A/S/D');
      expect(display.controls.first.glyph, 'glyphs/keyboard/KeyW.png');
    });
  });
}

const south = GamepadControl.south;
