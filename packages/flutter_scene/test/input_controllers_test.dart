// Covers the glue in package:flutter_scene/input.dart that drives the bundled
// controllers from an InputManager's actions.

import 'package:flutter/services.dart';
import 'package:flutter_scene/input.dart';
import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A source that publishes whatever a test tells it to.
class _TestSource extends InputSource {
  InputSink? _sink;

  @override
  void attach(InputSink sink) => _sink = sink;

  @override
  void detach() => _sink = null;

  void hold(LogicalKeyboardKey key, {bool down = true}) =>
      _sink!.publish(InputControl.key(key), down ? 1 : 0);

  void move(double dx, double dy) {
    _sink!
      ..publishDelta(InputControl.mouseDeltaX, dx)
      ..publishDelta(InputControl.mouseDeltaY, dy);
  }
}

Vector3 _pos(Node n) => n.globalTransform.getTranslation();

// CameraController.clampDeltaSeconds caps a frame at 0.1s, so a one-second
// update advances a 10 units/second camera by 1 unit, not 10.

void main() {
  late InputManager input;
  late _TestSource source;

  setUp(() {
    source = _TestSource();
    input = InputManager(sources: [source]);
  });

  tearDown(() => input.dispose());

  group('FlyCameraInput', () {
    FlyCameraController controllerOn(Node node) {
      final controller = FlyCameraController(
        position: Vector3.zero(),
        speed: 10.0,
        smoothing: 0.0,
      );
      node.addComponent(controller);
      return controller;
    }

    test('moves the camera from the move action', () {
      final node = Node();
      final controller = controllerOn(node);

      source.hold(LogicalKeyboardKey.keyW);
      input.update(1 / 60);
      controller
        ..applyInput(input)
        ..update(1);

      // W is +Y on the move action, which is forward: at yaw 0 the camera
      // looks down -Z, so it travels to negative Z and nowhere else.
      final moved = _pos(node);
      expect(moved.z, closeTo(-1.0, 1e-6));
      expect(moved.x, closeTo(0.0, 1e-6));
      expect(moved.y, closeTo(0.0, 1e-6));
    });

    test('sprint applies the boost multiplier', () {
      final node = Node();
      final controller = controllerOn(node)..boostMultiplier = 3.0;

      source
        ..hold(LogicalKeyboardKey.keyW)
        ..hold(LogicalKeyboardKey.shiftLeft);
      input.update(1 / 60);
      controller
        ..applyInput(input)
        ..update(1);

      expect(_pos(node).z, closeTo(-3.0, 1e-6));
    });

    test('elevate raises and lowers, and moveVertical false ignores it', () {
      final node = Node();
      final controller = controllerOn(node);

      source.hold(LogicalKeyboardKey.keyE);
      input.update(1 / 60);
      controller
        ..applyInput(input)
        ..update(1);
      expect(_pos(node).y, closeTo(1.0, 1e-6));

      final grounded = Node();
      final groundedController = controllerOn(grounded)..moveVertical = false;
      groundedController
        ..applyInput(input)
        ..update(1);
      expect(_pos(grounded).y, closeTo(0.0, 1e-6));
    });

    test('analog input keeps its magnitude', () {
      final node = Node();
      final controller = controllerOn(node);

      // Half a stick's worth of forward, straight through setMoveInput.
      controller
        ..setMoveInput(Vector2(0, 0.5))
        ..update(1);
      expect(_pos(node).z, closeTo(-0.5, 1e-6));
    });

    test('keyboard and action input sum rather than cancel', () {
      final node = Node();
      final controller = controllerOn(node);

      // A held key through the raw CameraController path, plus opposing
      // analog input: they cancel to a standstill instead of one winning.
      controller
        ..handleKeyEvent(
          const KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.keyW,
            logicalKey: LogicalKeyboardKey.keyW,
            timeStamp: Duration.zero,
          ),
        )
        ..setMoveInput(Vector2(0, -1))
        ..update(1);
      expect(_pos(node).z, closeTo(0.0, 1e-6));
    });

    test('look turns the camera, and lookWhile gates it on a button', () {
      final node = Node();
      final controller = controllerOn(node);

      source.move(100, 0);
      input.update(1 / 60);
      controller
        ..applyInput(input)
        ..update(1);
      final turned = controller.forward;
      expect(turned.x, isNot(closeTo(0.0, 1e-3)));

      // Gated on a button nobody is holding: the same delta does nothing.
      final gatedNode = Node();
      final gated = controllerOn(gatedNode);
      source.move(100, 0);
      input.update(1 / 60);
      gated
        ..applyInput(input, lookWhile: 'fire')
        ..update(1);
      expect(gated.forward.x, closeTo(0.0, 1e-6));
    });

    test('a null action name skips that action', () {
      final node = Node();
      final controller = controllerOn(node);

      source.hold(LogicalKeyboardKey.keyW);
      input.update(1 / 60);
      controller
        ..applyInput(input, move: null)
        ..update(1);
      expect(_pos(node).length, closeTo(0.0, 1e-6));
    });

    test('an unmapped action name throws rather than doing nothing', () {
      final controller = controllerOn(Node());
      expect(
        () => controller.applyInput(input, move: 'strafe'),
        throwsArgumentError,
      );
    });
  });

  group('ThirdPersonInput', () {
    test('feeds move and sprint, and jumps on the press edge', () {
      final node = Node();
      final controller = ThirdPersonControllerComponent();
      node.addComponent(controller);

      source
        ..hold(LogicalKeyboardKey.keyW)
        ..hold(LogicalKeyboardKey.shiftLeft)
        ..hold(LogicalKeyboardKey.space);
      input.update(1 / 60);
      controller.applyInput(input);

      expect(controller.isRunning, isTrue);
      expect(controller.moveInput.y, closeTo(1.0, 1e-6));
      expect(controller.hasBufferedJump, isTrue);
    });
  });
}
