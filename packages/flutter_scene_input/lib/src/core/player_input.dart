import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene_input/src/core/action_set.dart';
import 'package:flutter_scene_input/src/core/actions.dart';
import 'package:flutter_scene_input/src/core/bindings.dart';
import 'package:flutter_scene_input/src/core/controls.dart';
import 'package:flutter_scene_input/src/core/input_system.dart';
import 'package:flutter_scene_input/src/core/overrides.dart';
import 'package:flutter_scene_input/src/core/processors.dart';

/// A digital or analog control at or past this level counts as held for
/// modifiers, gates, and device activity.
const double _heldLevel = 0.5;

/// Mouse movement below this many logical pixels in one event does not switch
/// the active device, so a nudged mouse does not flip gamepad prompts.
const double _deltaActivity = 2.0;

/// One player's input: paired devices, a context stack, tunables, and the
/// frame and fixed-step read windows game code queries.
///
/// ```dart
/// final player = system.defaultPlayer;
/// player.contexts.push(gameplay);
///
/// // In update:
/// if (player.button(jump).justPressed) character.jump();
/// character.setMoveInput(player.vector(move));
///
/// // In fixedUpdate, through the fixed window:
/// if (player.fixed.button(jump).justPressed) body.applyImpulse(up);
/// ```
///
/// Reads through the player itself use the frame window. A window's values
/// are fixed when it advances, so every read within one frame agrees, and each
/// press and release is seen exactly once per window even when a frame runs
/// zero or several fixed steps.
/// {@category Players and devices}
final class PlayerInput extends InputWindow {
  /// Created by [InputSystem].
  @internal
  PlayerInput.internal(this.system) : super._() {
    _player = this;
    fixed = InputWindow._().._player = this;
    contexts = ContextStack._(this);
    overrides = PlayerOverrides(
      _handleOverridesChanged,
      () => contexts.entries.map((entry) => entry.set),
    );
  }

  /// The system this player belongs to.
  final InputSystem system;

  /// The fixed-step window, for reads inside `fixedUpdate`.
  late final InputWindow fixed;

  /// The action sets live for this player, top first.
  late final ContextStack contexts;

  /// This player's rebinds, tunables, and recognizer settings.
  late final PlayerOverrides overrides;

  final Set<InputDevice> _paired = {};
  final Map<Control, Map<InputDevice, double>> _levels = {};
  final List<void Function()> _bindingListeners = [];
  final List<void Function(InputDevice device, Control control, double value)>
  _controlListeners = [];
  final Map<(ActionSet, InputAction, String), Binding?> _effective = {};
  int _effectiveRevision = -1;
  int _suppressions = 0;
  InputDevice? _lastGamepad;
  final Map<DeviceKind, InputDevice> _virtualDevices = {};
  final List<void Function()> _activeDeviceListeners = [];

  final Map<_SlotKey, _SlotState> _slotStates = {};
  final Map<ButtonAction, _ButtonLive> _buttons = {};
  final Map<DerivedButtonAction, _DerivedState> _derivedStates = {};
  Map<AxisAction, double> _axes = {};
  Map<VectorAction, (double, double)> _vectors = {};
  Map<DeltaAction, _DeltaRecipe> _deltaRecipes = {};

  bool _textEntryActive = false;
  DeviceKind? _activeDeviceKind;

  /// Devices explicitly paired to this player.
  Set<InputDevice> get pairedDevices => Set.unmodifiable(_paired);

  /// Routes [device] to this player, taking it from any other player.
  void pair(InputDevice device) {
    final previous = system.ownerOf(device);
    if (identical(previous, this) && _paired.contains(device)) return;
    previous._paired.remove(device);
    previous.releaseDevice(device);
    _paired.add(device);
    system.notifyDevicesChanged();
  }

  /// Returns [device] to the default player.
  void unpair(InputDevice device) {
    if (!_paired.remove(device)) return;
    releaseDevice(device);
    system.notifyDevicesChanged();
  }

  /// Whether a text field has focus. While true, sets without
  /// `ActionSet.allowDuringTextEntry` are suppressed and their held actions
  /// release. The Flutter layer keeps this current.
  bool get textEntryActive => _textEntryActive;
  set textEntryActive(bool value) {
    if (value == _textEntryActive) return;
    _textEntryActive = value;
    _evaluate();
  }

  /// The kind of device this player last actuated, for choosing prompts.
  DeviceKind? get activeDeviceKind => _activeDeviceKind;

  /// Registers [listener] for [activeDeviceKind] changes.
  void addActiveDeviceListener(void Function() listener) =>
      _activeDeviceListeners.add(listener);

  /// Unregisters [listener].
  void removeActiveDeviceListener(void Function() listener) =>
      _activeDeviceListeners.remove(listener);

  /// The value of tunable [id] (a sensitivity, say), or [fallback] when unset.
  /// Set tunables through [overrides].
  double tunable(String id, double fallback) => overrides.tunable(id, fallback);

  /// The gamepad this player most recently actuated, for prompt styles.
  InputDevice? get lastGamepad => _lastGamepad;

  /// Registers [listener] for anything that changes what bindings display:
  /// overrides, the active device kind, or the last gamepad.
  void addBindingsListener(void Function() listener) =>
      _bindingListeners.add(listener);

  /// Unregisters [listener].
  void removeBindingsListener(void Function() listener) =>
      _bindingListeners.remove(listener);

  /// [slot] of [action] in [set] with overrides applied, or null when the slot
  /// is unbound or absent.
  Binding? effectiveBinding(ActionSet set, InputAction action, String slot) {
    if (_effectiveRevision != overrides.revision) {
      _effective.clear();
      _effectiveRevision = overrides.revision;
    }
    return _effective.putIfAbsent((
      set,
      action,
      slot,
    ), () => overrides.effectiveBinding(set, action, slot));
  }

  /// Watches every level change from any device this player receives, before
  /// evaluation. Listen-for-binding uses this.
  @internal
  void addControlListener(
    void Function(InputDevice device, Control control, double value) listener,
  ) => _controlListeners.add(listener);

  /// The current level of [control] across this player's devices. Control
  /// listeners see the level from before the event they are handling.
  @internal
  double levelOf(Control control) => _level(control);

  /// Unregisters [listener].
  @internal
  void removeControlListener(
    void Function(InputDevice device, Control control, double value) listener,
  ) => _controlListeners.remove(listener);

  /// Suppresses every action while [suppress] calls are outstanding, so a
  /// rebind listen does not also fire gameplay. Balanced calls restore.
  @internal
  void suppressActions(bool suppress) {
    _suppressions += suppress ? 1 : -1;
    _evaluate();
  }

  void _handleOverridesChanged() {
    _evaluate();
    _notifyBindings();
  }

  void _notifyBindings() {
    for (final listener in List.of(_bindingListeners)) {
      listener();
    }
  }

  /// Sets [control] to [value] as if a device of its kind had, for tests,
  /// bots, and replays.
  void inject(Control control, double value) =>
      receive(_virtualDevice(control.device), control, value);

  /// Adds displacement to a delta [control] as if a device had.
  void injectDelta(Control control, double dx, double dy) =>
      receiveDelta(_virtualDevice(control.device), control, dx, dy);

  InputDevice _virtualDevice(DeviceKind kind) =>
      _virtualDevices.putIfAbsent(kind, () => system.createVirtualDevice(kind));

  /// Closes the frame window and opens the next. Called once per frame by the
  /// scene integration or [InputSystem.advanceFrame].
  void advanceFrame(double deltaSeconds) => _advance(this, deltaSeconds);

  /// Closes the fixed-step window and opens the next. Called before each
  /// fixed step.
  void advanceFixedStep(double fixedDt) => _advance(fixed, fixedDt);

  /// Records a level from [device]. Called by [InputSystem].
  @internal
  void receive(InputDevice device, Control control, double value) {
    if (control.kind == ControlKind.delta ||
        control.kind == ControlKind.stick) {
      throw ArgumentError.value(
        control,
        'control',
        'Publish ${control.kind.name} controls through their axes or deltas',
      );
    }
    for (final listener in List.of(_controlListeners)) {
      listener(device, control, value);
    }
    final perDevice = _levels.putIfAbsent(control, () => {});
    if (value == 0) {
      perDevice.remove(device);
    } else {
      perDevice[device] = value;
      if (value.abs() >= _heldLevel) _noteActivity(device);
    }
    _evaluate();
  }

  /// Records displacement from [device]. Called by [InputSystem].
  @internal
  void receiveDelta(InputDevice device, Control control, double dx, double dy) {
    if (control.kind != ControlKind.delta) {
      throw ArgumentError.value(control, 'control', 'Not a delta control');
    }
    _accumulate(control, dx, dy);
    fixed._accumulate(control, dx, dy);
    if (dx * dx + dy * dy >= _deltaActivity * _deltaActivity) {
      _noteActivity(device);
    }
  }

  /// Releases everything [device] holds. Called on disconnect and pairing.
  @internal
  void releaseDevice(InputDevice device) {
    var changed = false;
    for (final perDevice in _levels.values) {
      changed |= perDevice.remove(device) != null;
    }
    if (changed) _evaluate();
  }

  void _noteActivity(InputDevice device) {
    var bindingsChanged = false;
    if (device.kind == DeviceKind.gamepad && !identical(_lastGamepad, device)) {
      _lastGamepad = device;
      bindingsChanged = true;
    }
    if (_activeDeviceKind != device.kind) {
      _activeDeviceKind = device.kind;
      bindingsChanged = true;
      for (final listener in List.of(_activeDeviceListeners)) {
        listener();
      }
    }
    if (bindingsChanged) _notifyBindings();
  }

  double _level(Control control) {
    final perDevice = _levels[control];
    if (perDevice == null || perDevice.isEmpty) return 0;
    var strongest = 0.0;
    for (final value in perDevice.values) {
      if (value.abs() > strongest.abs()) strongest = value;
    }
    return strongest;
  }

  void _advance(InputWindow window, double elapsed) {
    _evaluate();
    window._close(elapsed, system.clock.seconds);
  }

  // Re-evaluates every live action from current control levels. Runs on every
  // level change, so a press and release inside one frame still counts, and
  // on every window advance, so holds cross their durations.
  // TODO(input-perf): evaluate only the actions bound to the changed control
  // once profiling shows the full pass matters.
  void _evaluate() {
    final now = system.clock.seconds;
    final consumed = <Control>{};
    final pressed = <ButtonAction, bool>{};
    final axes = <AxisAction, double>{};
    final vectors = <VectorAction, (double, double)>{};
    final deltas = <DeltaAction, _DeltaRecipe>{};
    final liveDerived = <DerivedButtonAction, String>{};
    final liveSlots = <_SlotKey>{};

    for (final entry
        in _suppressions > 0 ? const <ContextEntry>[] : contexts.entries) {
      if (_textEntryActive && !entry.set.allowDuringTextEntry) continue;

      // Longest chord wins. Trigger controls of chords whose modifiers are
      // held read as idle for bindings with fewer modifiers.
      final shadows = <Control, int>{};
      for (final MapEntry(key: action, value: slots)
          in entry.set.bindings.entries) {
        for (final slot in slots.keys) {
          final binding = effectiveBinding(entry.set, action, slot);
          if (binding == null) continue;
          final chord = _chordOf(binding);
          if (chord == null || !_allHeld(chord.modifiers)) continue;
          final previous = shadows[chord.trigger] ?? 0;
          shadows[chord.trigger] = math.max(previous, chord.modifiers.length);
        }
      }

      final reader = _Reader(this, consumed, shadows);
      final entryConsumed = <Control>{};
      for (final MapEntry(key: action, value: slots)
          in entry.set.bindings.entries) {
        for (final slotName in slots.keys) {
          final binding = effectiveBinding(entry.set, action, slotName);
          if (binding == null) continue;
          final key = _SlotKey(entry, action, slotName);
          liveSlots.add(key);
          final state = _slotStates.putIfAbsent(key, _SlotState.new);
          final actuated = switch (action) {
            ButtonAction() => _evaluateButton(
              binding,
              state,
              reader,
              pressed,
              action,
            ),
            AxisAction() => _evaluateAxis(binding, reader, axes, action),
            VectorAction() => _evaluateVector(binding, reader, vectors, action),
            DeltaAction() => _evaluateDelta(binding, reader, deltas, action),
          };
          if (!actuated) continue;
          // Only what is actually engaged, so a firing WASD binding leaves
          // its idle keys to lower contexts. Delta controls have no level and
          // always belong to the live binding.
          for (final control in binding.controls) {
            if (control.kind == ControlKind.delta || _level(control) != 0) {
              entryConsumed.add(control);
            }
          }
        }
      }
      for (final derived in entry.set.derived) {
        liveDerived.putIfAbsent(derived, () => entry.set.name);
      }
      consumed.addAll(entryConsumed);
      if (entry.opaque) break;
    }

    _slotStates.removeWhere((key, _) => !liveSlots.contains(key));

    for (final action in {..._buttons.keys, ...pressed.keys}) {
      if (action is DerivedButtonAction) continue;
      _buttonFor(action).set(pressed[action] ?? false, now);
    }
    _evaluateDerived(liveDerived, now);

    _axes = axes;
    _vectors = vectors;
    _deltaRecipes = deltas;
  }

  _ButtonLive _buttonFor(ButtonAction action) =>
      _buttons.putIfAbsent(action, _ButtonLive.new);

  bool _allHeld(List<Control> modifiers) {
    for (final modifier in modifiers) {
      if (_level(modifier).abs() < _heldLevel) return false;
    }
    return true;
  }

  static ChordBinding? _chordOf(Binding binding) => switch (binding) {
    ChordBinding() => binding,
    GatedBinding(:final binding) => _chordOf(binding),
    _ => null,
  };

  (double, double) _process(
    List<Processor> processors,
    double x,
    double y, {
    required bool isVector,
  }) => applyProcessors(
    processors,
    x,
    y,
    isVector: isVector,
    readTunable: tunable,
  );

  bool _evaluateButton(
    Binding binding,
    _SlotState state,
    _Reader reader,
    Map<ButtonAction, bool> pressed,
    ButtonAction action,
  ) {
    final down = _buttonDown(binding, state, reader);
    if (down) pressed[action] = true;
    return down;
  }

  bool _buttonDown(Binding binding, _SlotState state, _Reader reader) {
    switch (binding) {
      case GatedBinding(:final modifiers, binding: final inner):
        if (!_allHeld(modifiers)) {
          state.pressed = false;
          state.triggerDown = false;
          return false;
        }
        return _buttonDown(inner, state, reader);
      case ButtonBinding(
        :final control,
        :final pressPoint,
        :final releasePoint,
      ):
        final (value, _) = _process(
          binding.processors,
          reader.read(control, modifiers: 0),
          0,
          isVector: false,
        );
        state.pressed = _crossed(
          value.abs(),
          state.pressed,
          pressPoint,
          releasePoint,
        );
        return state.pressed;
      case ChordBinding(
        :final modifiers,
        :final trigger,
        :final pressPoint,
        :final releasePoint,
      ):
        final (value, _) = _process(
          binding.processors,
          reader.read(trigger, modifiers: modifiers.length),
          0,
          isVector: false,
        );
        final wasDown = state.triggerDown;
        final isDown = _crossed(value.abs(), wasDown, pressPoint, releasePoint);
        state.triggerDown = isDown;
        final held = _allHeld(modifiers);
        if (!isDown || !held) {
          state.pressed = false;
        } else if (!wasDown) {
          // Modifiers first, then the trigger.
          state.pressed = true;
        }
        return state.pressed;
      default:
        return false;
    }
  }

  static bool _crossed(
    double value,
    bool wasDown,
    double pressPoint,
    double releasePoint,
  ) => wasDown
      ? value >= math.min(releasePoint, pressPoint)
      : value >= pressPoint;

  bool _evaluateAxis(
    Binding binding,
    _Reader reader,
    Map<AxisAction, double> axes,
    AxisAction action,
  ) {
    var value = _scalar(binding, reader);
    if (action.range == AxisRange.unipolar) value = value.clamp(0.0, 1.0);
    if (value == 0) return false;
    final best = axes[action];
    if (best == null || value.abs() > best.abs()) axes[action] = value;
    return true;
  }

  double _scalar(Binding binding, _Reader reader) => _process(
    binding.processors,
    _rawScalar(binding, reader),
    0,
    isVector: false,
  ).$1;

  // A scalar binding's value before its own processors.
  double _rawScalar(Binding binding, _Reader reader) => switch (binding) {
    GatedBinding(:final modifiers, binding: final inner) =>
      _allHeld(modifiers) ? _scalar(inner, reader) : 0.0,
    ButtonBinding(:final control) ||
    AxisBinding(:final control) => reader.read(control, modifiers: 0),
    AxisPairBinding(:final negative, :final positive) =>
      reader.read(positive, modifiers: 0) - reader.read(negative, modifiers: 0),
    _ => 0.0,
  };

  bool _evaluateVector(
    Binding binding,
    _Reader reader,
    Map<VectorAction, (double, double)> vectors,
    VectorAction action,
  ) {
    var (x, y) = _vector(binding, reader);
    final length2 = x * x + y * y;
    if (length2 == 0) return false;
    if (length2 > 1) {
      final inverse = 1 / math.sqrt(length2);
      x *= inverse;
      y *= inverse;
    }
    final best = vectors[action];
    if (best == null || x * x + y * y > best.$1 * best.$1 + best.$2 * best.$2) {
      vectors[action] = (x, y);
    }
    return true;
  }

  (double, double) _vector(Binding binding, _Reader reader) {
    final (double, double) raw;
    switch (binding) {
      case GatedBinding(:final modifiers, binding: final inner):
        raw = _allHeld(modifiers) ? _vector(inner, reader) : (0.0, 0.0);
      case StickBinding(:final control):
        raw = (
          reader.read(control.axisX!, modifiers: 0),
          reader.read(control.axisY!, modifiers: 0),
        );
      case DpadBinding(
        :final up,
        :final down,
        :final left,
        :final right,
        :final mode,
      ):
        double part(Control control) {
          final value = reader.read(control, modifiers: 0);
          return mode == DpadMode.analog
              ? value.abs()
              : (value.abs() >= _heldLevel ? 1.0 : 0.0);
        }
        var x = part(right) - part(left);
        var y = part(up) - part(down);
        if (mode == DpadMode.normalized && x != 0 && y != 0) {
          x *= math.sqrt1_2;
          y *= math.sqrt1_2;
        }
        raw = (x, y);
      case AxisPairBinding() || AxisBinding() || ButtonBinding():
        // Processed as a vector, so SwapAxes and Invert.y can place a scalar
        // on the vertical axis.
        raw = (_rawScalar(binding, reader), 0.0);
      default:
        raw = (0.0, 0.0);
    }
    return _process(binding.processors, raw.$1, raw.$2, isVector: true);
  }

  bool _evaluateDelta(
    Binding binding,
    _Reader reader,
    Map<DeltaAction, _DeltaRecipe> deltas,
    DeltaAction action,
  ) {
    final recipe = deltas.putIfAbsent(action, _DeltaRecipe.new);
    Binding inner = binding;
    final gates = <Control>[];
    // Gate processors apply after the inner binding's, outermost last.
    final outerProcessors = <Processor>[];
    while (inner is GatedBinding) {
      gates.addAll(inner.modifiers);
      outerProcessors.insertAll(0, inner.processors);
      inner = inner.binding;
    }
    if (!_allHeld(gates)) return false;
    if (inner is DeltaBinding) {
      if (!reader.readable(inner.control, modifiers: 0)) return false;
      recipe.sources.add((
        inner.control,
        [...inner.processors, ...outerProcessors],
      ));
      // A live delta binding always owns its control for lower contexts.
      return true;
    }
    final rate = inner.processors.whereType<PerSecond>().fold(
      0.0,
      (sum, p) => sum + p.rate,
    );
    final (vx, vy) = _vector(inner, reader);
    final (x, y) = _process(outerProcessors, vx, vy, isVector: true);
    if (x == 0 && y == 0) return false;
    final rx = x * rate;
    final ry = y * rate;
    if (rx * rx + ry * ry >
        recipe.rateX * recipe.rateX + recipe.rateY * recipe.rateY) {
      recipe
        ..rateX = rx
        ..rateY = ry;
    }
    return true;
  }

  void _evaluateDerived(Map<DerivedButtonAction, String> live, double now) {
    _derivedStates.removeWhere((action, _) => !live.containsKey(action));
    for (final action in {..._buttons.keys.whereType<DerivedButtonAction>()}) {
      if (!live.containsKey(action)) _buttonFor(action).set(false, now);
    }
    for (final MapEntry(key: action, value: setName) in live.entries) {
      final source = _buttons[action.source];
      final state = _derivedStates.putIfAbsent(action, () {
        return _DerivedState(
          lastPressCount: source?.pressCount ?? 0,
          lastReleaseCount: source?.releaseCount ?? 0,
        );
      });
      final derived = _buttonFor(action);
      final sourcePressed = source?.pressed ?? false;
      final pressCount = source?.pressCount ?? 0;
      final releaseCount = source?.releaseCount ?? 0;
      final newPress = pressCount > state.lastPressCount;
      final newRelease = releaseCount > state.lastReleaseCount;
      state
        ..lastPressCount = pressCount
        ..lastReleaseCount = releaseCount;

      switch (action) {
        case HoldAction(:final duration):
          final toggle = overrides.toggleFor(setName, action);
          final heldLongEnough =
              sourcePressed && now - source!.pressedAt >= duration;
          if (!toggle) {
            derived.set(heldLongEnough, now);
            break;
          }
          if (!sourcePressed) {
            state.holdCompleted = false;
          } else if (heldLongEnough && !state.holdCompleted) {
            state
              ..holdCompleted = true
              ..toggled = !state.toggled;
          }
          derived.set(state.toggled, now);
        case TapAction(:final maxDuration):
          if (newRelease &&
              source!.releasedAt - source.pressedAt <= maxDuration) {
            derived.fire(now);
          }
        case MultiTapAction(:final count, :final window):
          if (!newPress) break;
          state.streak = now - state.lastTapAt <= window ? state.streak + 1 : 1;
          state.lastTapAt = now;
          if (state.streak >= count) {
            state.streak = 0;
            derived.fire(now);
          }
      }
    }
  }
}

/// A read window: the values game code sees between two advances.
///
/// [PlayerInput] is itself the frame window; [PlayerInput.fixed] is the
/// fixed-step window.
/// {@category Players and devices}
base class InputWindow {
  InputWindow._();

  late final PlayerInput _player;
  final Map<ButtonAction, ButtonState> _buttonStates = {};
  Map<AxisAction, double> _axisValues = const {};
  Map<VectorAction, (double, double)> _vectorValues = const {};
  final Map<DeltaAction, (double, double)> _deltaValues = {};
  final Map<Control, _Accumulated> _accumulated = {};
  double _elapsed = 0;

  /// Seconds between the two advances that bound this window.
  double get elapsed => _elapsed;

  /// The state of button [action].
  ButtonState button(ButtonAction action) =>
      _buttonStates[action] ?? ButtonState._idle;

  /// The value of axis [action], or 0 when idle.
  double axis(AxisAction action) => _axisValues[action] ?? 0;

  /// The direction of vector [action], a fresh vector.
  Vector2 vector(VectorAction action) {
    final (x, y) = _vectorValues[action] ?? (0.0, 0.0);
    return Vector2(x, y);
  }

  /// The displacement of delta [action] over this window, a fresh vector.
  Vector2 delta(DeltaAction action) {
    final (x, y) = _deltaValues[action] ?? (0.0, 0.0);
    return Vector2(x, y);
  }

  void _accumulate(Control control, double dx, double dy) {
    final accumulated = _accumulated.putIfAbsent(control, _Accumulated.new);
    accumulated
      ..x += dx
      ..y += dy;
  }

  void _close(double elapsed, double now) {
    final player = _player;
    _elapsed = elapsed;
    for (final MapEntry(key: action, value: live) in player._buttons.entries) {
      _buttonStates.putIfAbsent(action, ButtonState._)._capture(live, now);
    }
    _axisValues = Map.of(player._axes);
    _vectorValues = Map.of(player._vectors);
    _deltaValues.clear();
    for (final MapEntry(key: action, value: recipe)
        in player._deltaRecipes.entries) {
      var x = recipe.rateX * elapsed;
      var y = recipe.rateY * elapsed;
      for (final (control, processors) in recipe.sources) {
        final accumulated = _accumulated[control];
        if (accumulated == null) continue;
        final (px, py) = player._process(
          processors,
          accumulated.x,
          accumulated.y,
          isVector: true,
        );
        x += px;
        y += py;
      }
      if (x != 0 || y != 0) _deltaValues[action] = (x, y);
    }
    _accumulated.clear();
  }
}

/// A button action as seen by one read window.
/// {@category Players and devices}
final class ButtonState {
  ButtonState._();

  static final ButtonState _idle = ButtonState._();

  bool _pressed = false;
  int _pressCount = 0;
  int _releaseCount = 0;
  int _previousPressCount = 0;
  int _previousReleaseCount = 0;
  double _heldFor = 0;

  /// Whether the action was held when the window opened.
  bool get pressed => _pressed;

  /// Whether the action was pressed since the previous window, including a
  /// press that was also released in between.
  bool get justPressed => _pressCount > _previousPressCount;

  /// Whether the action was released since the previous window.
  bool get justReleased => _releaseCount > _previousReleaseCount;

  /// Total presses so far. Monotonic, so it survives being sampled late.
  int get pressCount => _pressCount;

  /// Total releases so far.
  int get releaseCount => _releaseCount;

  /// Seconds the current press had lasted when the window opened, or 0.
  double get heldFor => _heldFor;

  void _capture(_ButtonLive live, double now) {
    _previousPressCount = _pressCount;
    _previousReleaseCount = _releaseCount;
    _pressCount = live.pressCount;
    _releaseCount = live.releaseCount;
    _pressed = live.pressed;
    _heldFor = live.pressed ? now - live.pressedAt : 0;
  }
}

/// The action sets live for one player, ordered by priority and then by push
/// order, most recent on top.
/// {@category Actions}
final class ContextStack {
  ContextStack._(this._player);

  final PlayerInput _player;
  final List<ContextEntry> _entries = [];
  int _pushes = 0;

  /// Live entries, top first.
  List<ContextEntry> get entries => List.unmodifiable(_entries);

  /// Pushes [set]. An [opaque] entry blocks every entry below it; a higher
  /// [priority] sits above lower ones regardless of push order.
  ///
  /// Throws [StateError] if [set] is already live for this player.
  ContextEntry push(ActionSet set, {bool opaque = false, int priority = 0}) {
    if (_entries.any((entry) => identical(entry.set, set))) {
      throw StateError('${set.name} is already on the context stack');
    }
    final entry = ContextEntry._(this, set, opaque, priority, _pushes++);
    _entries
      ..add(entry)
      ..sort((a, b) {
        final byPriority = b.priority.compareTo(a.priority);
        return byPriority != 0 ? byPriority : b._order.compareTo(a._order);
      });
    _player._evaluate();
    return entry;
  }

  /// Whether [set] is live.
  bool contains(ActionSet set) =>
      _entries.any((entry) => identical(entry.set, set));

  void _remove(ContextEntry entry) {
    if (_entries.remove(entry)) _player._evaluate();
  }
}

/// One live action set on a [ContextStack].
/// {@category Actions}
final class ContextEntry {
  ContextEntry._(
    this._stack,
    this.set,
    this.opaque,
    this.priority,
    this._order,
  );

  final ContextStack _stack;
  final int _order;

  /// The action set.
  final ActionSet set;

  /// Whether this entry blocks every entry below it.
  final bool opaque;

  /// Sort key; higher sits above.
  final int priority;

  /// Whether this entry is still on its stack.
  bool get isLive => _stack._entries.contains(this);

  /// Removes this entry; its held actions release.
  void remove() => _stack._remove(this);

  @override
  String toString() => 'ContextEntry(${set.name}${opaque ? ', opaque' : ''})';
}

final class _Reader {
  _Reader(this._player, this._consumed, this._shadows);

  final PlayerInput _player;
  final Set<Control> _consumed;
  final Map<Control, int> _shadows;

  bool readable(Control control, {required int modifiers}) =>
      !_consumed.contains(control) && (_shadows[control] ?? 0) <= modifiers;

  double read(Control control, {required int modifiers}) =>
      readable(control, modifiers: modifiers) ? _player._level(control) : 0;
}

final class _SlotKey {
  _SlotKey(this.entry, this.action, this.slot);

  final ContextEntry entry;
  final InputAction action;
  final String slot;

  @override
  bool operator ==(Object other) =>
      other is _SlotKey &&
      identical(other.entry, entry) &&
      other.action == action &&
      other.slot == slot;

  @override
  int get hashCode => Object.hash(identityHashCode(entry), action, slot);
}

final class _SlotState {
  bool pressed = false;
  bool triggerDown = false;
}

final class _ButtonLive {
  bool pressed = false;
  int pressCount = 0;
  int releaseCount = 0;
  double pressedAt = 0;
  double releasedAt = 0;

  void set(bool value, double now) {
    if (value == pressed) return;
    pressed = value;
    if (value) {
      pressCount++;
      pressedAt = now;
    } else {
      releaseCount++;
      releasedAt = now;
    }
  }

  // A press and release in the same instant, for recognizers that fire.
  void fire(double now) {
    if (pressed) return;
    pressCount++;
    releaseCount++;
    pressedAt = now;
    releasedAt = now;
  }
}

final class _DerivedState {
  _DerivedState({required this.lastPressCount, required this.lastReleaseCount});

  int lastPressCount;
  int lastReleaseCount;
  bool holdCompleted = false;
  bool toggled = false;
  int streak = 0;
  double lastTapAt = double.negativeInfinity;
}

final class _DeltaRecipe {
  final List<(Control, List<Processor>)> sources = [];
  double rateX = 0;
  double rateY = 0;
}

final class _Accumulated {
  double x = 0;
  double y = 0;
}
