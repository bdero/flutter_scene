import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/input/input_control.dart';

/// The value shape an action produces, and therefore which
/// `InputManager` query is legal against it.
/// {@category Picking and input}
enum InputActionKind {
  /// A held/pressed state. Read with `isPressed`, `wasPressedThisFrame`,
  /// `wasReleasedThisFrame`.
  button,

  /// A single scalar, typically `-1..1`. Read with `axis`.
  axis,

  /// A 2D direction. Read with `vector2`.
  vector2,
}

/// Reads raw control values. Implemented by `InputManager`; bindings sample
/// through this rather than owning device state.
/// {@category Picking and input}
abstract interface class InputControlReader {
  /// The current value of [control], or 0 when no source publishes it.
  double readControl(InputControl control);
}

/// One way to trigger an action. An action may carry several; the manager
/// takes the strongest, so "jump" can be Space *and* gamepad A at once.
///
/// A binding is pure: it maps control values to an action value and holds no
/// state of its own, which is what lets a single [InputMap] be shared between
/// several managers (split-screen, or a replay driven from recorded input).
/// {@category Picking and input}
sealed class InputBinding {
  const InputBinding();

  /// The value shape this binding produces.
  InputActionKind get kind;

  /// Every control this binding reads, for rebinding UI and conflict checks.
  Iterable<InputControl> get controls;

  /// The serialized form, the inverse of [InputBinding.fromJson].
  Map<String, Object?> toJson();

  /// Rebuilds a binding from [json]. Throws [FormatException] on an
  /// unknown type or a malformed control path.
  static InputBinding fromJson(Map<String, Object?> json) {
    InputControl control(String key) {
      final raw = json[key];
      if (raw is! String) {
        throw FormatException('Binding is missing control "$key"', json);
      }
      final parsed = InputControl.tryParse(raw);
      if (parsed == null) {
        throw FormatException('Malformed control path "$raw"', json);
      }
      return parsed;
    }

    double number(String key, double fallback) {
      final raw = json[key];
      return raw is num ? raw.toDouble() : fallback;
    }

    return switch (json['type']) {
      'button' => ButtonBinding(
        control('control'),
        threshold: number('threshold', 0.5),
      ),
      'axis' => AxisBinding(
        negative: control('negative'),
        positive: control('positive'),
      ),
      'analogAxis' => AnalogAxisBinding(
        control('control'),
        scale: number('scale', 1),
        deadzone: number('deadzone', 0),
      ),
      'compositeVector2' => CompositeVector2Binding(
        up: control('up'),
        down: control('down'),
        left: control('left'),
        right: control('right'),
      ),
      'stick' => StickBinding(
        x: control('x'),
        y: control('y'),
        deadzone: number('deadzone', 0.15),
        invertY: json['invertY'] == true,
      ),
      final other => throw FormatException(
        'Unknown binding type "$other"',
        json,
      ),
    };
  }
}

/// A digital press: [control] is down when its value reaches [threshold].
/// Wrapping an analog control (a trigger) in this makes it a button.
/// {@category Picking and input}
final class ButtonBinding extends InputBinding {
  const ButtonBinding(this.control, {this.threshold = 0.5});

  final InputControl control;

  /// The value at or above which the control counts as pressed.
  final double threshold;

  @override
  InputActionKind get kind => InputActionKind.button;

  @override
  Iterable<InputControl> get controls => [control];

  /// Whether this binding reads as pressed against [reader].
  bool isPressed(InputControlReader reader) =>
      reader.readControl(control) >= threshold;

  @override
  Map<String, Object?> toJson() => {
    'type': 'button',
    'control': control.path,
    if (threshold != 0.5) 'threshold': threshold,
  };
}

/// A `-1..1` axis composed from two digital controls, the keyboard spelling
/// of an analog stick axis. Both down reads as 0, matching Unity and Godot.
/// {@category Picking and input}
final class AxisBinding extends InputBinding {
  const AxisBinding({required this.negative, required this.positive});

  final InputControl negative;
  final InputControl positive;

  @override
  InputActionKind get kind => InputActionKind.axis;

  @override
  Iterable<InputControl> get controls => [negative, positive];

  /// This binding's axis value against [reader].
  double read(InputControlReader reader) {
    final low = reader.readControl(negative) >= 0.5 ? 1.0 : 0.0;
    final high = reader.readControl(positive) >= 0.5 ? 1.0 : 0.0;
    return high - low;
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'axis',
    'negative': negative.path,
    'positive': positive.path,
  };
}

/// An axis read straight from one analog control, with an optional [scale]
/// (pass -1 to invert) and a magnitude [deadzone].
/// {@category Picking and input}
final class AnalogAxisBinding extends InputBinding {
  const AnalogAxisBinding(this.control, {this.scale = 1, this.deadzone = 0});

  final InputControl control;
  final double scale;

  /// Magnitudes at or below this read as 0, rejecting stick drift.
  final double deadzone;

  @override
  InputActionKind get kind => InputActionKind.axis;

  @override
  Iterable<InputControl> get controls => [control];

  /// This binding's axis value against [reader].
  double read(InputControlReader reader) {
    final raw = reader.readControl(control);
    if (raw.abs() <= deadzone) return 0;
    return raw * scale;
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'analogAxis',
    'control': control.path,
    if (scale != 1) 'scale': scale,
    if (deadzone != 0) 'deadzone': deadzone,
  };
}

/// A 2D direction composed from four digital controls (WASD, the d-pad).
///
/// The result is in the engine's input convention: **+Y is forward/up**, so
/// [up] produces `+1` on Y. That is the convention the character and camera
/// controllers expect, and it is deliberately *not* Flutter's screen space
/// where downward is +Y. The vector is normalized past unit length, so
/// holding two keys does not move a character faster diagonally.
/// {@category Picking and input}
final class CompositeVector2Binding extends InputBinding {
  const CompositeVector2Binding({
    required this.up,
    required this.down,
    required this.left,
    required this.right,
  });

  final InputControl up;
  final InputControl down;
  final InputControl left;
  final InputControl right;

  @override
  InputActionKind get kind => InputActionKind.vector2;

  @override
  Iterable<InputControl> get controls => [up, down, left, right];

  /// This binding's direction against [reader].
  Vector2 read(InputControlReader reader) {
    double down_(InputControl c) => reader.readControl(c) >= 0.5 ? 1.0 : 0.0;
    final x = down_(right) - down_(left);
    final y = down_(up) - down_(down);
    if (x == 0 && y == 0) return Vector2.zero();
    final lengthSquared = x * x + y * y;
    if (lengthSquared <= 1.0) return Vector2(x, y);
    final inverse = 1.0 / math.sqrt(lengthSquared);
    return Vector2(x * inverse, y * inverse);
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'compositeVector2',
    'up': up.path,
    'down': down.path,
    'left': left.path,
    'right': right.path,
  };
}

/// A 2D direction from two analog controls, with a **radial** [deadzone].
///
/// Radial rather than per-axis: gating X and Y independently carves a square
/// hole out of the stick's range and makes near-axis diagonals snap, the
/// classic twin-stick complaint.
/// {@category Picking and input}
final class StickBinding extends InputBinding {
  const StickBinding({
    required this.x,
    required this.y,
    this.deadzone = 0.15,
    this.invertY = false,
  });

  final InputControl x;
  final InputControl y;

  /// Magnitudes at or below this read as zero.
  final double deadzone;

  /// Whether to negate Y, for a device that reports downward as positive.
  final bool invertY;

  @override
  InputActionKind get kind => InputActionKind.vector2;

  @override
  Iterable<InputControl> get controls => [x, y];

  /// This binding's direction against [reader].
  Vector2 read(InputControlReader reader) {
    final rawX = reader.readControl(x);
    final rawY = invertY ? -reader.readControl(y) : reader.readControl(y);
    final magnitude = math.sqrt(rawX * rawX + rawY * rawY);
    if (magnitude <= deadzone) return Vector2.zero();
    if (magnitude <= 1.0) return Vector2(rawX, rawY);
    final inverse = 1.0 / magnitude;
    return Vector2(rawX * inverse, rawY * inverse);
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'stick',
    'x': x.path,
    'y': y.path,
    if (deadzone != 0.15) 'deadzone': deadzone,
    if (invertY) 'invertY': true,
  };
}
