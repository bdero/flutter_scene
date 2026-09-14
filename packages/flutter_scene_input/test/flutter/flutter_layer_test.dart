import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart' hide Material;
import 'package:flutter_scene_input/flutter_scene_input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const jump = ButtonAction('jump');
const fire = ButtonAction('fire');
const look = DeltaAction('look');
const zoom = DeltaAction('zoom');

final List<InputSystem> _systems = [];

InputSystem _system(WidgetTester tester) {
  final system = InputSystem();
  _systems.add(system);
  return system;
}

// Detaches every system's sources inside the test body, since the gamepad
// source's poll timer must be cancelled before the test binding checks for
// pending timers.
void _detachAll() {
  for (final system in _systems) {
    FlutterInputSources.remove(system);
  }
  _systems.clear();
}

void testInput(String description, WidgetTesterCallback body) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      _detachAll();
    }
  });
}

void main() {
  group('keyboard', () {
    testInput('physical keys drive actions and repeats are ignored', (
      tester,
    ) async {
      final system = _system(tester);
      FlutterInputSources.ensure(system);
      final player = system.defaultPlayer;
      player.contexts.push(
        ActionSet('gameplay', {
          jump: {'keyboard': ButtonBinding(PhysicalKeyboardKey.space.control)},
        }),
      );

      await simulateKeyDownEvent(LogicalKeyboardKey.space);
      await simulateKeyRepeatEvent(LogicalKeyboardKey.space);
      player.advanceFrame(1 / 60);
      expect(player.button(jump).pressed, isTrue);
      expect(player.button(jump).pressCount, 1);

      await simulateKeyUpEvent(LogicalKeyboardKey.space);
      player.advanceFrame(1 / 60);
      expect(player.button(jump).justReleased, isTrue);
    });

    testInput('losing app focus releases held keys', (tester) async {
      final system = _system(tester);
      FlutterInputSources.ensure(system);
      final player = system.defaultPlayer;
      player.contexts.push(
        ActionSet('gameplay', {
          jump: {'keyboard': ButtonBinding(PhysicalKeyboardKey.space.control)},
        }),
      );
      await simulateKeyDownEvent(LogicalKeyboardKey.space);
      player.advanceFrame(1 / 60);
      expect(player.button(jump).pressed, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      player.advanceFrame(1 / 60);
      expect(player.button(jump).pressed, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await simulateKeyUpEvent(LogicalKeyboardKey.space);
    });

    testInput('a focused text field suppresses gameplay', (tester) async {
      final system = _system(tester);
      final player = system.defaultPlayer;
      player.contexts.push(
        ActionSet('gameplay', {
          jump: {'keyboard': ButtonBinding(PhysicalKeyboardKey.space.control)},
        }),
      );
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: InputListener(
              system: system,
              child: TextField(focusNode: focus),
            ),
          ),
        ),
      );
      expect(player.textEntryActive, isFalse);
      focus.requestFocus();
      await tester.pump();
      expect(player.textEntryActive, isTrue);

      await simulateKeyDownEvent(LogicalKeyboardKey.space);
      player.advanceFrame(1 / 60);
      expect(player.button(jump).pressed, isFalse);
      await simulateKeyUpEvent(LogicalKeyboardKey.space);

      focus.unfocus();
      await tester.pump();
      expect(player.textEntryActive, isFalse);
    });
  });

  testInput('rebinding listens to real key events and shows layout labels', (
    tester,
  ) async {
    final system = _system(tester);
    FlutterInputSources.ensure(system);
    final player = system.defaultPlayer;
    final set = ActionSet('gameplay', {
      jump: {'keyboard': ButtonBinding(PhysicalKeyboardKey.space.control)},
    });
    player.contexts.push(set);

    RebindResult? result;
    player.listenForBinding(jump, slot: 'keyboard').result.then((r) {
      result = r;
    });
    await simulateKeyDownEvent(LogicalKeyboardKey.keyF);
    await tester.pump(const Duration(milliseconds: 200));
    expect(result?.control, PhysicalKeyboardKey.keyF.control);
    result!.apply();
    await simulateKeyUpEvent(LogicalKeyboardKey.keyF);

    // The keyboard source saw F's logical key, so the label uses it.
    expect(player.bindingDisplay(jump)!.label, 'F');

    await simulateKeyDownEvent(LogicalKeyboardKey.keyF);
    player.advanceFrame(1 / 60);
    expect(player.button(jump).pressed, isTrue);
    await simulateKeyUpEvent(LogicalKeyboardKey.keyF);
  });

  group('mouse through InputListener', () {
    late InputSystem system;
    late PlayerInput player;
    var hudTaps = 0;

    Future<void> pumpView(WidgetTester tester) async {
      system = _system(tester);
      player = system.defaultPlayer;
      player.contexts.push(
        ActionSet('gameplay', {
          fire: {'mouse': const ButtonBinding(MouseControl.left)},
          look: {'mouse': const DeltaBinding(MouseControl.delta)},
          zoom: {'mouse': const DeltaBinding(MouseControl.scroll)},
        }),
      );
      hudTaps = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              InputListener(system: system, child: const SizedBox.expand()),
              Positioned(
                left: 0,
                top: 0,
                width: 50,
                height: 50,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => hudTaps++,
                ),
              ),
            ],
          ),
        ),
      );
    }

    testInput('buttons and movement reach the player, +Y up', (tester) async {
      await pumpView(tester);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(200, 200));
      await gesture.down(const Offset(200, 200));
      await gesture.moveBy(const Offset(10, 4));
      player.advanceFrame(1 / 60);
      expect(player.button(fire).pressed, isTrue);
      expect(player.delta(look), Vector2(10, -4));

      await gesture.up();
      player.advanceFrame(1 / 60);
      expect(player.button(fire).justReleased, isTrue);
      await gesture.removePointer();
    });

    testInput('widgets above the listener keep their clicks', (tester) async {
      await pumpView(tester);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(10, 10));
      await gesture.down(const Offset(10, 10));
      await gesture.up();
      await tester.pump();
      player.advanceFrame(1 / 60);
      expect(hudTaps, 1);
      expect(player.button(fire).pressCount, 0);
      await gesture.removePointer();
    });

    testInput('scrolling away from the user is +Y', (tester) async {
      await pumpView(tester);
      tester.binding.handlePointerEvent(
        const PointerScrollEvent(
          position: Offset(200, 200),
          scrollDelta: Offset(0, -120),
        ),
      );
      player.advanceFrame(1 / 60);
      expect(player.delta(zoom), Vector2(0, 120));
    });

    testInput('InputScope provides the player', (tester) async {
      final system = _system(tester);
      late PlayerInput found;
      await tester.pumpWidget(
        InputListener(
          system: system,
          child: Builder(
            builder: (context) {
              found = InputScope.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(found, same(system.defaultPlayer));
    });
  });

  group('scene integration', () {
    test('playerInput finds the nearest binding, then the root', () {
      final system = InputSystem();
      final second = system.createPlayer();
      final root = Node()..addComponent(InputRoot(system));
      final squad = Node()..addComponent(PlayerBinding(second));
      final soldier = Node();
      final prop = Node();
      root
        ..add(squad)
        ..add(prop);
      squad.add(soldier);
      expect(soldier.playerInput, same(second));
      expect(prop.playerInput, same(system.defaultPlayer));
      expect(Node().playerInput, isNull);
    });

    test('the host advances frame and fixed windows', () {
      final system = InputSystem();
      final player = system.defaultPlayer;
      player.contexts.push(
        ActionSet('gameplay', {
          jump: {'gamepad': const ButtonBinding(GamepadControl.south)},
        }),
      );
      final host = InputHost(system);
      player.inject(GamepadControl.south, 1);
      host.beforeTick(1 / 60);
      host.beforeFixedStep(1 / 60);
      expect(player.button(jump).justPressed, isTrue);
      expect(player.fixed.button(jump).justPressed, isTrue);
    });

    test('the fly camera driver moves and turns the camera', () {
      final system = InputSystem();
      final player = system.defaultPlayer;
      player.contexts.push(DefaultActions.flyCamera);
      final camera = Node();
      final controller = FlyCameraController(
        position: Vector3.zero(),
        speed: 4,
        smoothing: 0,
        movementSmoothing: 0,
      );
      camera
        ..addComponent(controller)
        ..addComponent(
          FlyCameraInputDriver(
            move: DefaultActions.move,
            look: DefaultActions.look,
          )..player = player,
        );

      player
        ..inject(GamepadControl.leftStickY, 1)
        ..inject(MouseControl.right, 1)
        ..injectDelta(MouseControl.delta, 100, 0);
      player.advanceFrame(0.05);
      camera.getComponent<FlyCameraInputDriver>()!.update(0.05);
      controller.update(0.05);

      // Full forward push at speed 4 for 0.05s, after the deadzone remap.
      expect(
        camera.globalTransform.getTranslation().length,
        closeTo(0.2, 1e-4),
      );
      // The driver turns exactly as a 100px rightward drag would.
      final dragged = FlyCameraController(
        position: Vector3.zero(),
        smoothing: 0,
      );
      Node().addComponent(dragged);
      dragged
        ..look(const Offset(100, 0))
        ..update(0.05);
      expect((controller.forward - dragged.forward).length, lessThan(1e-6));
      expect(controller.forward.x, isNot(closeTo(0, 1e-3)));
    });

    test('default action sets are valid', () {
      expect(DefaultActions.character.bindings, isNotEmpty);
      expect(DefaultActions.flyCamera.bindings, isNotEmpty);
      expect(DefaultActions.orbitCamera.bindings, isNotEmpty);
    });
  });
}
