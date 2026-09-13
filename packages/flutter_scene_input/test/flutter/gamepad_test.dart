import 'dart:async';

import 'package:flutter_scene_input/flutter_scene_input.dart';
// ignore: implementation_imports
import 'package:flutter_scene_input/src/sources/gamepad_mappings.dart';
// ignore: implementation_imports
import 'package:flutter_scene_input/src/sources/hid_backend_base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamepads/gamepads.dart' as pads;

const jump = ButtonAction('jump');
const move = VectorAction('move');
const menu = ButtonAction('menu');

final class FakeBackend implements GamepadBackend {
  List<({String id, String name})> pads_ = [];
  final StreamController<pads.GamepadEvent> controller =
      StreamController.broadcast(sync: true);

  @override
  Future<List<({String id, String name})>> list() async => List.of(pads_);

  @override
  Stream<pads.GamepadEvent> get events => controller.stream;

  void send(String id, String key, double value, {pads.KeyType? type}) =>
      controller.add(
        pads.GamepadEvent(
          gamepadId: id,
          timestamp: 0,
          type:
              type ??
              (key.startsWith('button')
                  ? pads.KeyType.button
                  : pads.KeyType.analog),
          key: key,
          value: value,
        ),
      );
}

final class FakeHid implements HidGamepadBackend {
  void Function(int device, bool connected)? onDevice;
  void Function(int device, int code, double value)? onValue;
  final Map<int, String> names = {};

  @override
  bool start({
    required void Function(int device, bool connected) onDevice,
    required void Function(int device, int code, double value) onValue,
  }) {
    this.onDevice = onDevice;
    this.onValue = onValue;
    return true;
  }

  @override
  void stop() {
    onDevice = null;
    onValue = null;
  }

  @override
  ({String name, int vendorId, int productId}) info(int device) =>
      (name: names[device] ?? '', vendorId: 0x28de, productId: 0x11ff);
}

void main() {
  late InputSystem system;
  late PlayerInput player;
  late FakeBackend backend;
  late FakeHid hid;
  late GamepadSource source;

  setUp(() {
    system = InputSystem();
    player = system.defaultPlayer
      ..contexts.push(
        ActionSet('gameplay', {
          jump: {'gamepad': const ButtonBinding(GamepadControl.south)},
          move: {
            'gamepad': const StickBinding(GamepadControl.leftStick),
            'dpad': const DpadBinding(
              up: GamepadControl.dpadUp,
              down: GamepadControl.dpadDown,
              left: GamepadControl.dpadLeft,
              right: GamepadControl.dpadRight,
            ),
          },
          menu: {'gamepad': const ButtonBinding(GamepadControl.start)},
        }),
      );
    backend = FakeBackend();
    hid = FakeHid();
    source = GamepadSource(
      backend: backend,
      normalizer: pads.GamepadNormalizer.forPlatform(pads.GamepadPlatform.web),
      hid: hid,
      pollInterval: const Duration(hours: 1),
    );
  });

  tearDown(() => system.removeSource(source));

  List<InputDevice> pads_() =>
      system.devices.where((d) => d.kind == DeviceKind.gamepad).toList();

  test('package events normalize onto positional controls, +Y up', () async {
    backend.pads_ = [(id: '0', name: 'Xbox Wireless Controller')];
    system.addSource(source);
    await source.refresh();

    backend
      ..send('0', 'button 0', 1)
      // The web API reports stick up as negative.
      ..send('0', 'analog 1', -0.8);
    player.advanceFrame(1 / 60);
    expect(player.button(jump).pressed, isTrue);
    expect(player.vector(move).y, closeTo(0.8, 1e-6));
  });

  test('raw keys the package cannot map use the observed spellings', () async {
    backend.pads_ = [(id: '0', name: 'Odd Pad')];
    system.addSource(source);
    await source.refresh();
    backend
      ..send('0', 'Button A', 1, type: pads.KeyType.button)
      ..send('0', 'buttonMenu', 1, type: pads.KeyType.button);
    player.advanceFrame(1 / 60);
    expect(player.button(jump).pressed, isTrue);
    expect(player.button(menu).pressed, isTrue);
  });

  test(
    'pads connect and disconnect by polling and keep their handle',
    () async {
      backend.pads_ = [(id: '0', name: 'Pad')];
      system.addSource(source);
      await source.refresh();
      expect(pads_(), hasLength(1));
      final handle = pads_().single.handle;

      backend.send('0', 'button 0', 1);
      backend.pads_ = [];
      await source.refresh();
      expect(pads_().single.connected, isFalse);
      player.advanceFrame(1 / 60);
      expect(player.button(jump).pressed, isFalse);

      backend.pads_ = [(id: '0', name: 'Pad')];
      await source.refresh();
      expect(pads_().single.connected, isTrue);
      expect(pads_().single.handle, handle);
    },
  );

  test('identical pads stay distinct and a reused id is a new pad', () async {
    backend.pads_ = [(id: '0', name: 'Pad'), (id: '1', name: 'Pad')];
    system.addSource(source);
    await source.refresh();
    expect(pads_().map((d) => d.identity), ['pad:Pad#0', 'pad:Pad#1']);

    // An index-based platform shifts ids after a disconnect.
    backend.pads_ = [(id: '0', name: 'Other Pad')];
    await source.refresh();
    final connected = pads_().where((d) => d.connected).toList();
    expect(connected.map((d) => d.name), ['Other Pad']);
  });

  test('an event from an unknown pad triggers a refresh', () async {
    system.addSource(source);
    await source.refresh();
    backend.pads_ = [(id: '7', name: 'Late Pad')];
    backend.send('7', 'button 0', 1);
    await pumpEventQueue();
    expect(pads_().single.name, 'Late Pad');
  });

  test('the HID tap adds pads the package does not list', () async {
    backend.pads_ = [(id: '0', name: 'DualSense Wireless Controller')];
    system.addSource(source);
    await source.refresh();

    hid.names[3] = 'Steam Virtual Gamepad';
    hid.onDevice!(3, true);
    final steam = pads_().firstWhere((d) => d.name == 'Steam Virtual Gamepad');
    expect(steam.vendorId, 0x28de);

    hid.onValue!(3, HidCodes.button | 1, 1);
    hid.onValue!(3, HidCodes.hatY, 1);
    player.advanceFrame(1 / 60);
    expect(player.button(jump).pressed, isTrue);
    expect(player.vector(move).y, closeTo(1, 1e-6));

    // The same pad seen by both is kept from the package only.
    hid.names[4] = 'DualSense Wireless Controller';
    hid.onDevice!(4, true);
    expect(pads_().where((d) => d.name.startsWith('DualSense')), hasLength(1));

    hid.onDevice!(3, false);
    expect(steam.connected, isFalse);
  });

  test('HID codes map buttons, hat, sticks, and triggers', () {
    expect(controlsForHidCode(HidCodes.button | 9, 1), [
      (GamepadControl.start, 1.0),
    ]);
    expect(controlsForHidCode(HidCodes.hatX, -1), [
      (GamepadControl.dpadLeft, 1.0),
      (GamepadControl.dpadRight, 0.0),
    ]);
    expect(controlsForHidCode(HidCodes.desktop | 0x31, 0.5), [
      (GamepadControl.leftStickY, 0.5),
    ]);
    expect(controlsForHidCode(HidCodes.desktop | 0x35, -1), [
      (GamepadControl.rightTrigger, 0.0),
    ]);
    expect(controlsForHidCode(HidCodes.button | 40, 1), isEmpty);
  });

  test('join presses create players for unpaired pads', () async {
    backend.pads_ = [(id: '0', name: 'Pad'), (id: '1', name: 'Pad')];
    system.addSource(source);
    await source.refresh();
    final joins = <(PlayerInput, InputDevice)>[];
    final helper = JoinHelper(
      system,
      maxPlayers: 2,
      onJoin: (player, device) => joins.add((player, device)),
    );
    addTearDown(helper.dispose);

    backend
      ..send('0', 'button 1', 1)
      ..send('0', 'button 0', 1)
      ..send('0', 'button 0', 0)
      ..send('0', 'button 0', 1)
      ..send('1', 'button 9', 1);
    expect(joins, hasLength(2));
    expect(joins[0].$1, same(system.defaultPlayer));
    expect(joins[1].$1, isNot(same(system.defaultPlayer)));
    expect(joins[1].$1.pairedDevices, contains(joins[1].$2));
  });

  test('layout style is guessed from vendor and name', () {
    expect(
      GamepadLayoutStyle.guess(vendorId: 0x054c),
      GamepadLayoutStyle.playstation,
    );
    expect(
      GamepadLayoutStyle.guess(name: 'Pro Controller'),
      GamepadLayoutStyle.nintendo,
    );
    expect(
      GamepadLayoutStyle.guess(name: 'Xbox Wireless Controller'),
      GamepadLayoutStyle.xbox,
    );
    expect(
      GamepadLayoutStyle.guess(name: 'Mystery'),
      GamepadLayoutStyle.generic,
    );
  });
}
