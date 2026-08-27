import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/input/input_binding.dart';
import 'package:flutter_scene/src/input/input_control.dart';
import 'package:flutter_scene/src/input/input_map.dart';
import 'package:flutter_scene/src/input/input_source.dart';

/// Resolves an [InputMap] against live device state, and answers the queries
/// game code actually asks: is this action held, did it go down this frame,
/// which way is the stick pointing.
///
/// ## The frame model
///
/// Sources publish continuously, but edge queries ([wasPressedThisFrame],
/// [wasReleasedThisFrame]) are only meaningful against a frame boundary. Call
/// [update] exactly once per frame, before the code that reads actions:
///
/// ```dart
/// void onTick(double deltaSeconds) {
///   input.update(deltaSeconds);
///   if (input.wasPressedThisFrame('jump')) character.jump();
///   character.setMoveInput(
///     input.vector2('move'),
///     isRunning: input.isPressed('sprint'),
///   );
///   scene.update(deltaSeconds);
/// }
/// ```
///
/// Calling [update] more than once per frame collapses the edges: a press that
/// arrived between the two calls reads as pressed for zero frames.
///
/// ## Conventions
///
/// Vector actions use **+Y forward/up**, matching the bundled character and
/// camera controllers and *not* Flutter's screen space. Mouse look is inverted
/// on the way in for this reason (see [InputMap.defaults]).
/// {@category Picking and input}
final class InputManager implements InputSink, InputControlReader {
  /// Creates a manager over [map], defaulting to [InputMap.defaults].
  ///
  /// Pass [sources] to attach device backends up front; the common setup is
  /// a [KeyboardInputSource] plus a [PointerInputSource] fed by an
  /// `InputScope`.
  InputManager({InputMap? map, Iterable<InputSource> sources = const []})
    : map = map ?? InputMap.defaults() {
    for (final source in sources) {
      attach(source);
    }
  }

  /// The actions this manager resolves.
  final InputMap map;

  /// The value at which a control counts as digitally pressed for edge
  /// tracking. Per-binding thresholds still govern [isPressed].
  static const double _digitalThreshold = 0.5;

  final List<InputSource> _sources = [];

  // Control values as published, and as they stood at the last frame
  // boundary. Edge queries compare the two.
  final Map<InputControl, double> _current = {};
  final Map<InputControl, double> _previous = {};

  // Controls that are only valid for the frame they arrived in (mouse
  // movement, scroll). Zeroed by the next update.
  final Set<InputControl> _deltas = {};

  // Controls that crossed the digital threshold at any point since the last
  // [update], not just at the frame boundary. Without these a tap that both
  // begins and ends between two frames is invisible to the edge queries: the
  // boundary comparison sees released before and released after. That is the
  // dropped-jump bug, and it gets worse the higher the frame rate.
  final Set<InputControl> _pressedEdges = {};
  final Set<InputControl> _releasedEdges = {};

  /// Whether action queries return neutral values regardless of device state.
  ///
  /// The switch to flip while a menu, console, or text field owns input. It
  /// does not detach sources, so state stays current and nothing is stuck
  /// held when input is enabled again.
  bool enabled = true;

  /// Attaches [source] and starts reading from it.
  void attach(InputSource source) {
    _sources.add(source);
    source.attach(this);
  }

  /// Detaches [source]. Returns whether it was attached.
  bool detach(InputSource source) {
    if (!_sources.remove(source)) return false;
    source.detach();
    return true;
  }

  /// Detaches every source and clears device state.
  void dispose() {
    for (final source in _sources) {
      source.detach();
    }
    _sources.clear();
    _current.clear();
    _previous.clear();
    _deltas.clear();
    _pressedEdges.clear();
    _releasedEdges.clear();
  }

  @override
  void publish(InputControl control, double value) {
    final previous = _current[control] ?? 0;
    _current[control] = value;
    _deltas.remove(control);
    if (previous < _digitalThreshold && value >= _digitalThreshold) {
      _pressedEdges.add(control);
    } else if (previous >= _digitalThreshold && value < _digitalThreshold) {
      _releasedEdges.add(control);
    }
  }

  @override
  void publishDelta(InputControl control, double value) {
    // Accumulate: several pointer events can land within one frame, and
    // overwriting would drop all but the last.
    _current[control] = (_current[control] ?? 0) + value;
    _deltas.add(control);
  }

  @override
  double readControl(InputControl control) => _current[control] ?? 0;

  /// Advances the frame boundary. Call once per frame, before reading actions.
  ///
  /// [deltaSeconds] is accepted for symmetry with the rest of the engine's
  /// tick signatures and for sources that need it later; the manager itself
  /// does not currently integrate over time.
  void update(double deltaSeconds) {
    _previous
      ..clear()
      ..addAll(_current);
    for (final control in _deltas) {
      _current[control] = 0;
    }
    _deltas.clear();
    _pressedEdges.clear();
    _releasedEdges.clear();
  }

  double _readPrevious(InputControl control) => _previous[control] ?? 0;

  InputAction _require(String name, InputActionKind kind) {
    final action = map[name];
    if (action == null) {
      throw ArgumentError.value(name, 'name', 'No such input action');
    }
    if (action.kind != kind) {
      throw ArgumentError.value(
        name,
        'name',
        'Action "$name" is ${action.kind.name}, not ${kind.name}',
      );
    }
    return action;
  }

  /// Whether the button action [name] is currently held.
  bool isPressed(String name) {
    if (!enabled) return false;
    final action = _require(name, InputActionKind.button);
    for (final binding in action.bindings) {
      if ((binding as ButtonBinding).isPressed(this)) return true;
    }
    return false;
  }

  bool _wasPressedAtBoundary(InputAction action) {
    for (final binding in action.bindings) {
      final button = binding as ButtonBinding;
      if (_readPrevious(button.control) >= button.threshold) return true;
    }
    return false;
  }

  bool _anyControlIn(InputAction action, Set<InputControl> edges) {
    if (edges.isEmpty) return false;
    for (final binding in action.bindings) {
      if (edges.contains((binding as ButtonBinding).control)) return true;
    }
    return false;
  }

  /// Whether the button action [name] went down since the previous [update].
  ///
  /// True for a tap that both began and ended within the frame, so a fast
  /// press is never dropped.
  bool wasPressedThisFrame(String name) {
    if (!enabled) return false;
    final action = _require(name, InputActionKind.button);
    if (_anyControlIn(action, _pressedEdges)) return true;
    return isPressed(name) && !_wasPressedAtBoundary(action);
  }

  /// Whether the button action [name] came up since the previous [update].
  bool wasReleasedThisFrame(String name) {
    if (!enabled) return false;
    final action = _require(name, InputActionKind.button);
    if (_anyControlIn(action, _releasedEdges)) return true;
    return !isPressed(name) && _wasPressedAtBoundary(action);
  }

  /// The value of the axis action [name].
  ///
  /// With several bindings the one of greatest magnitude wins, so a keyboard
  /// and a stick bound to the same action do not cancel each other out.
  double axis(String name) {
    if (!enabled) return 0;
    final action = _require(name, InputActionKind.axis);
    var strongest = 0.0;
    for (final binding in action.bindings) {
      final value = switch (binding) {
        AxisBinding() => binding.read(this),
        AnalogAxisBinding() => binding.read(this),
        _ => 0.0,
      };
      if (value.abs() > strongest.abs()) strongest = value;
    }
    return strongest;
  }

  /// The direction of the vector2 action [name], **+Y forward**.
  ///
  /// With several bindings the longest wins, so WASD and a stick bound to
  /// `move` coexist. Returns a fresh vector; callers may mutate it.
  Vector2 vector2(String name) {
    if (!enabled) return Vector2.zero();
    final action = _require(name, InputActionKind.vector2);
    var strongest = Vector2.zero();
    var strongestLength = 0.0;
    for (final binding in action.bindings) {
      final value = switch (binding) {
        CompositeVector2Binding() => binding.read(this),
        StickBinding() => binding.read(this),
        _ => Vector2.zero(),
      };
      final length = value.length2;
      if (length > strongestLength) {
        strongestLength = length;
        strongest = value;
      }
    }
    return strongest;
  }

  /// The raw value of [control], bypassing the action map.
  ///
  /// For a rebinding screen ("press any key"), or for the rare control that
  /// does not deserve an action. Prefer actions everywhere else.
  double rawControl(InputControl control) => enabled ? readControl(control) : 0;

  /// Every control that went from released to pressed since the previous
  /// [update], for a rebinding screen to capture.
  Iterable<InputControl> get pressedThisFrame =>
      List<InputControl>.unmodifiable(_pressedEdges);
}
