import 'dart:ui' show Offset;

import 'package:flutter_scene/kit.dart' show ThirdPersonControllerComponent;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene_input/src/core/actions.dart';
import 'package:flutter_scene_input/src/core/player_input.dart';
import 'package:flutter_scene_input/src/scene/input_host.dart';

/// Feeds a [ThirdPersonControllerComponent] from actions.
/// {@category Scene integration}
extension ThirdPersonControllerInput on ThirdPersonControllerComponent {
  /// Sets move intent from [move] (+Y forward), running from [sprint], and
  /// jumps on a [jump] press. [cameraHeadingYaw] makes movement camera
  /// relative. Call once per frame.
  void applyInput(
    InputWindow input, {
    VectorAction? move,
    ButtonAction? sprint,
    ButtonAction? jump,
    double? cameraHeadingYaw,
  }) {
    setMoveInput(
      move == null ? Vector2.zero() : input.vector(move),
      isRunning: sprint != null && input.button(sprint).pressed,
      cameraHeadingYaw: cameraHeadingYaw,
    );
    if (jump != null && input.button(jump).justPressed) this.jump();
  }
}

/// Feeds a [FlyCameraController] from actions.
/// {@category Scene integration}
extension FlyCameraControllerInput on FlyCameraController {
  /// Sets move intent from [move] (+Y forward), vertical intent from
  /// [elevate], boost from [boost], and turns by [look]'s displacement (+Y up,
  /// in the same logical pixels a drag would use). Call once per frame.
  void applyInput(
    InputWindow input, {
    VectorAction? move,
    AxisAction? elevate,
    ButtonAction? boost,
    DeltaAction? look,
  }) {
    setMoveInput(
      move == null ? Vector2.zero() : input.vector(move),
      elevate: elevate == null ? 0.0 : input.axis(elevate),
      boost: boost != null && input.button(boost).pressed,
    );
    if (look == null) return;
    final delta = input.delta(look);
    if (delta.x != 0 || delta.y != 0) {
      // look takes a screen-space drag, whose Y grows downward.
      this.look(Offset(delta.x, -delta.y));
    }
  }
}

/// Feeds an [OrbitCameraController] from actions.
/// {@category Scene integration}
extension OrbitCameraControllerInput on OrbitCameraController {
  /// Orbits by [orbit]'s displacement at [radiansPerPixel] (+X turns right,
  /// +Y tilts up), dollies in by [zoom]'s vertical displacement at
  /// [zoomPerPixel], and pans by [pan]'s displacement as a fraction of
  /// [viewportHeight]. Call once per frame.
  void applyInput(
    InputWindow input, {
    DeltaAction? orbit,
    DeltaAction? zoom,
    DeltaAction? pan,
    double radiansPerPixel = 0.005,
    double zoomPerPixel = 1 / 120,
    double viewportHeight = 720,
  }) {
    if (orbit != null) {
      final delta = input.delta(orbit);
      if (delta.x != 0 || delta.y != 0) {
        orbitBy(-delta.x * radiansPerPixel, delta.y * radiansPerPixel);
      }
    }
    if (zoom != null) {
      final amount = input.delta(zoom).y;
      if (amount != 0) dollyBy(amount * zoomPerPixel);
    }
    if (pan != null) {
      final delta = input.delta(pan);
      if (delta.x != 0 || delta.y != 0) {
        panBy(Offset(delta.x / viewportHeight, -delta.y / viewportHeight));
      }
    }
  }
}

/// Feeds a [FollowCameraController] from actions.
/// {@category Scene integration}
extension FollowCameraControllerInput on FollowCameraController {
  /// Orbits by [orbit]'s displacement at [radiansPerPixel] and dollies in by
  /// [zoom]'s vertical displacement at [zoomPerPixel]. Call once per frame.
  void applyInput(
    InputWindow input, {
    DeltaAction? orbit,
    DeltaAction? zoom,
    double radiansPerPixel = 0.005,
    double zoomPerPixel = 1 / 120,
  }) {
    if (orbit != null) {
      final delta = input.delta(orbit);
      if (delta.x != 0 || delta.y != 0) {
        orbitBy(-delta.x * radiansPerPixel, delta.y * radiansPerPixel);
      }
    }
    if (zoom != null) {
      final amount = input.delta(zoom).y;
      if (amount != 0) dollyBy(amount * zoomPerPixel);
    }
  }
}

/// A component that finds its node's player and applies it each frame.
/// {@category Scene integration}
abstract base class InputDriver<T extends Component> extends Component {
  /// The player this driver reads, or null to use the node's
  /// [NodeInput.playerInput].
  PlayerInput? player;

  /// The component on the same node this driver feeds.
  T? get target => node.getComponent<T>();

  /// Applies [input] to [target].
  void apply(InputWindow input, T target);

  @override
  void update(double deltaSeconds) {
    final input = player ?? node.playerInput;
    final controlled = target;
    if (input == null || controlled == null) return;
    apply(input, controlled);
  }
}

/// Drives the [ThirdPersonControllerComponent] on its node.
/// {@category Scene integration}
final class CharacterInputDriver
    extends InputDriver<ThirdPersonControllerComponent> {
  /// A driver reading [move], [sprint], and [jump]. [cameraHeadingYaw] makes
  /// movement camera relative when given.
  CharacterInputDriver({
    this.move,
    this.sprint,
    this.jump,
    this.cameraHeadingYaw,
  });

  /// Planar movement, +Y forward.
  final VectorAction? move;

  /// Held to run.
  final ButtonAction? sprint;

  /// Pressed to jump.
  final ButtonAction? jump;

  /// The camera heading movement is relative to, read each frame.
  final double Function()? cameraHeadingYaw;

  @override
  void apply(InputWindow input, ThirdPersonControllerComponent target) =>
      target.applyInput(
        input,
        move: move,
        sprint: sprint,
        jump: jump,
        cameraHeadingYaw: cameraHeadingYaw?.call(),
      );
}

/// Drives the [FlyCameraController] on its node.
/// {@category Scene integration}
final class FlyCameraInputDriver extends InputDriver<FlyCameraController> {
  /// A driver reading [move], [elevate], [boost], and [look].
  FlyCameraInputDriver({this.move, this.elevate, this.boost, this.look});

  /// Planar movement, +Y forward.
  final VectorAction? move;

  /// Vertical movement, +1 up.
  final AxisAction? elevate;

  /// Held to boost.
  final ButtonAction? boost;

  /// View rotation, +Y up.
  final DeltaAction? look;

  @override
  void apply(InputWindow input, FlyCameraController target) =>
      target.applyInput(
        input,
        move: move,
        elevate: elevate,
        boost: boost,
        look: look,
      );
}

/// Drives the [OrbitCameraController] on its node.
/// {@category Scene integration}
final class OrbitCameraInputDriver extends InputDriver<OrbitCameraController> {
  /// A driver reading [orbit], [zoom], and [pan].
  OrbitCameraInputDriver({this.orbit, this.zoom, this.pan});

  /// Orbit displacement.
  final DeltaAction? orbit;

  /// Dolly displacement, +Y in.
  final DeltaAction? zoom;

  /// Pan displacement.
  final DeltaAction? pan;

  @override
  void apply(InputWindow input, OrbitCameraController target) =>
      target.applyInput(input, orbit: orbit, zoom: zoom, pan: pan);
}

/// Drives the [FollowCameraController] on its node.
/// {@category Scene integration}
final class FollowCameraInputDriver
    extends InputDriver<FollowCameraController> {
  /// A driver reading [orbit] and [zoom].
  FollowCameraInputDriver({this.orbit, this.zoom});

  /// Orbit displacement.
  final DeltaAction? orbit;

  /// Dolly displacement, +Y in.
  final DeltaAction? zoom;

  @override
  void apply(InputWindow input, FollowCameraController target) =>
      target.applyInput(input, orbit: orbit, zoom: zoom);
}
