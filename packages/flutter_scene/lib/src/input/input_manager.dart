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

  final List<InputSource> _sources = [];

  // Control values as published.
  final Map<InputControl, double> _current = {};

  // Delta controls (mouse movement, scroll), which are meaningful only for the
  // frame they arrived in: a held value would read as an infinitely spinning
  // camera. They are double-buffered for the same reason the button windows
  // below are. Zeroing them at the top of [update] instead throws away every
  // pixel of movement that arrived while the app was between ticks, which is
  // all of it, and mouse look never moves.
  Map<InputControl, double> _frameDeltas = {};
  Map<InputControl, double> _windowDeltas = {};

  // The frame model.
  //
  // A source publishes when the platform delivers an event, which is between
  // ticks, not during one. So an edge query cannot be a comparison against the
  // values as they stand when [update] runs: by then the press has already
  // landed, and a control that went down a millisecond ago is indistinguishable
  // from one that has been held for a minute. That is the dropped-jump bug, and
  // it gets worse the higher the frame rate.
  //
  // Instead each [update] closes a window and opens the next, and a closed
  // window records, per control, the value it opened with, the highest value
  // reached inside it, and the value it closed with. Every edge query is a
  // threshold test over those three, which is exact for any
  // [ButtonBinding.threshold] (an analog trigger included) and catches a tap
  // that both began and ended inside one window. The maps are swapped rather
  // than reallocated, so a steady-state frame allocates none of this.
  Map<InputControl, double> _frameStart = {};
  Map<InputControl, double> _frameMax = {};

  // The window still accumulating. Its opening values double as the closing
  // values of the frame being queried, since [update] seeds them from the live
  // state at the instant the frame opened.
  Map<InputControl, double> _windowStart = {};
  Map<InputControl, double> _windowMax = {};

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
    _frameDeltas.clear();
    _windowDeltas.clear();
    _frameStart.clear();
    _frameMax.clear();
    _windowStart.clear();
    _windowMax.clear();
  }

  @override
  void publish(InputControl control, double value) {
    final before = _current[control] ?? 0;
    _current[control] = value;
    // A control published as a level is no longer a delta control.
    _frameDeltas.remove(control);
    _windowDeltas.remove(control);
    // Seeded from the value before this publish, so a window that opens with a
    // control at rest and sees it go down and back up still records the peak.
    final high = _windowMax[control] ?? before;
    _windowMax[control] = value > high ? value : high;
  }

  @override
  void publishDelta(InputControl control, double value) {
    // Accumulate: several pointer events can land within one frame, and
    // overwriting would drop all but the last.
    _windowDeltas[control] = (_windowDeltas[control] ?? 0) + value;
  }

  @override
  double readControl(InputControl control) =>
      _frameDeltas[control] ?? _current[control] ?? 0;

  /// Advances the frame boundary. Call once per frame, before reading actions.
  ///
  /// Everything published since the previous call belongs to the frame this
  /// call opens, so a press that arrived while the app was between ticks is
  /// visible to the tick that follows it.
  ///
  /// [deltaSeconds] is accepted for symmetry with the rest of the engine's
  /// tick signatures and for sources that need it later; the manager itself
  /// does not currently integrate over time.
  void update(double deltaSeconds) {
    // Polled backends publish first, so their state lands in the window this
    // call is about to close rather than the one after it.
    for (final source in _sources) {
      source.poll(deltaSeconds);
    }

    // Promote the window that just closed to the frame being queried, and
    // recycle the outgoing maps as the next window's storage.
    final start = _frameStart;
    final high = _frameMax;
    _frameStart = _windowStart;
    _frameMax = _windowMax;
    _windowStart = start
      ..clear()
      ..addAll(_current);
    _windowMax = high..clear();

    // The movement accumulated since the previous call belongs to the frame
    // this call opens, and is gone by the one after it.
    final deltas = _frameDeltas;
    _frameDeltas = _windowDeltas;
    _windowDeltas = deltas..clear();
  }

  // The three numbers every edge query is a threshold test over. A control the
  // closed window never saw reads as flat at the value it opened with.
  double _openedAt(InputControl control) => _frameStart[control] ?? 0;
  double _closedAt(InputControl control) =>
      _windowStart[control] ?? _openedAt(control);
  double _highOf(InputControl control) =>
      _frameMax[control] ?? _openedAt(control);

  /// Whether [control] reached [threshold] during the frame having opened
  /// below it.
  bool _rose(InputControl control, double threshold) =>
      _openedAt(control) < threshold && _highOf(control) >= threshold;

  /// Whether [control] closed the frame below [threshold] having been at or
  /// above it during the frame, which covers a press held in from the previous
  /// frame and a tap that began and ended inside this one.
  bool _fell(InputControl control, double threshold) =>
      _closedAt(control) < threshold &&
      (_openedAt(control) >= threshold || _highOf(control) >= threshold);

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

  /// Whether the button action [name] went down during this frame.
  ///
  /// True for a tap that both began and ended within the frame, so a fast
  /// press is never dropped, and true on the tick that follows the press
  /// rather than the one that precedes it.
  bool wasPressedThisFrame(String name) {
    if (!enabled) return false;
    final action = _require(name, InputActionKind.button);
    for (final binding in action.bindings) {
      final button = binding as ButtonBinding;
      if (_rose(button.control, button.threshold)) return true;
    }
    return false;
  }

  /// Whether the button action [name] came up during this frame.
  bool wasReleasedThisFrame(String name) {
    if (!enabled) return false;
    final action = _require(name, InputActionKind.button);
    for (final binding in action.bindings) {
      final button = binding as ButtonBinding;
      if (_fell(button.control, button.threshold)) return true;
    }
    return false;
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

  /// Every control that went from released to pressed during this frame, for
  /// a rebinding screen to capture.
  ///
  /// Uses the same 0.5 crossing every device agrees on, since a rebinding
  /// screen is listening for "any control", not for one action's threshold.
  Iterable<InputControl> get pressedThisFrame => [
    for (final control in _frameMax.keys)
      if (_rose(control, 0.5)) control,
  ];
}
