import 'package:flutter_scene/scene.dart' show Scene, ScenePointer;
import 'package:flutter_scene_input/flutter_scene_input.dart';
import 'package:vector_math/vector_math.dart' show Ray;

import 'package:flutter_scene_xr/src/xr_frame.dart';
import 'package:flutter_scene_xr/src/xr_input_state.dart';
import 'package:flutter_scene_xr/src/xr_rig.dart';

/// Publishes an XR session's controllers and hands into the input system,
/// one gamepad device per input source, and points a [ScenePointer] along
/// each source's target ray.
///
/// Controls reuse [GamepadControl] so bindings written for pads work. Each
/// hand is its own device, so the left controller's trigger is
/// [GamepadControl.leftTrigger] and the right's is
/// [GamepadControl.rightTrigger]; the `xr-standard` layout maps as
///
///  * button 0 (trigger) to the hand's trigger, analog,
///  * button 1 (squeeze) to the hand's shoulder,
///  * button 2 (touchpad press) to [GamepadControl.touchpad],
///  * button 3 (thumbstick press) to the hand's stick press,
///  * buttons 4 and 5 (X/Y on the left, A/B on the right) to
///    [GamepadControl.west]/[GamepadControl.north] and
///    [GamepadControl.south]/[GamepadControl.east],
///  * axes 2 and 3 (thumbstick) to the hand's stick axes, `+Y` up.
///
/// A source with no gamepad (a hand, a gaze, a screen touch) publishes its
/// select and squeeze actions as the trigger and shoulder.
///
/// Feed it frames with [applyFrame]; `XrSceneLoop` does so when given one.
/// {@category Input}
final class XrInputSource extends InputSource {
  /// A source that points a pointer into [scene] along each input source's
  /// [XrRig.targetRay] node when both are given.
  XrInputSource({this.scene, this.rig});

  /// The scene pointers cast into, or null for no pointers.
  final Scene? scene;

  /// The rig whose target ray nodes the pointers follow.
  final XrRig? rig;

  InputSink? _sink;
  final Map<int, _XrDevice> _devices = {};

  /// The pointers, one per connected source with a target ray.
  Iterable<ScenePointer> get pointers => [
    for (final device in _devices.values)
      if (device.pointer != null) device.pointer!,
  ];

  /// The pointer following [source], or null.
  ScenePointer? pointerFor(XrInputSourceState source) =>
      _devices[source.id]?.pointer;

  @override
  void attach(InputSink sink) {
    _sink = sink;
  }

  @override
  void detach() {
    final sink = _sink;
    for (final device in _devices.values) {
      device.pointer?.cancel();
      if (sink != null && device.device != null) {
        sink.disconnectDevice(device.device!);
      }
    }
    _devices.clear();
    _sink = null;
  }

  /// Publishes [frame]'s input sources and moves their pointers.
  void applyFrame(XrFrame frame) {
    final sink = _sink;
    final seen = <int>{};
    for (final state in frame.inputSources) {
      seen.add(state.id);
      final device = _devices.putIfAbsent(state.id, () => _connect(state));
      if (sink != null) {
        device.device ??= _connectDevice(sink, state);
        for (final (control, value) in controlsFor(state)) {
          device.publish(sink, control, value);
        }
      }
      _updatePointer(device, state);
    }
    for (final id in _devices.keys.toList()) {
      if (seen.contains(id)) continue;
      final device = _devices.remove(id)!;
      device.pointer?.cancel();
      if (sink != null && device.device != null) {
        sink.disconnectDevice(device.device!);
      }
    }
  }

  /// The controls [state] publishes this frame.
  static Iterable<(GamepadControl, double)> controlsFor(
    XrInputSourceState state,
  ) sync* {
    final left = state.handedness == XrHandedness.left;
    final trigger = left
        ? GamepadControl.leftTrigger
        : GamepadControl.rightTrigger;
    final squeeze = left
        ? GamepadControl.leftShoulder
        : GamepadControl.rightShoulder;
    final pad = state.gamepad;
    if (pad == null) {
      yield (trigger, state.selectPressed ? 1.0 : 0.0);
      yield (squeeze, state.squeezePressed ? 1.0 : 0.0);
      return;
    }
    final buttons = pad.buttonValues;
    final pressed = pad.buttonPressed;
    double digital(int index) =>
        index < pressed.length && pressed[index] ? 1.0 : 0.0;
    if (buttons.isNotEmpty) {
      yield (trigger, buttons[0]);
    } else {
      yield (trigger, state.selectPressed ? 1.0 : 0.0);
    }
    if (buttons.length > 1) {
      yield (squeeze, digital(1));
    } else {
      yield (squeeze, state.squeezePressed ? 1.0 : 0.0);
    }
    if (buttons.length > 2) yield (GamepadControl.touchpad, digital(2));
    if (buttons.length > 3) {
      yield (
        left ? GamepadControl.leftStickPress : GamepadControl.rightStickPress,
        digital(3),
      );
    }
    if (buttons.length > 4) {
      yield (left ? GamepadControl.west : GamepadControl.south, digital(4));
    }
    if (buttons.length > 5) {
      yield (left ? GamepadControl.north : GamepadControl.east, digital(5));
    }
    // TODO(xr-menu-button): map the menu button (index 6 on some profiles)
    // to GamepadControl.start once a profile table says where it sits.
    final axes = pad.axes;
    if (axes.length > 3) {
      yield (
        left ? GamepadControl.leftStickX : GamepadControl.rightStickX,
        axes[2],
      );
      // Controls report +Y up; the runtime reports +Y down.
      yield (
        left ? GamepadControl.leftStickY : GamepadControl.rightStickY,
        -axes[3],
      );
    }
    // TODO(xr-touchpad-axes): axes 0 and 1 (the touchpad) have no
    // GamepadControl; add one when a binding needs them.
  }

  _XrDevice _connect(XrInputSourceState state) {
    final scene = this.scene;
    final rig = this.rig;
    final pointer = scene != null && rig != null ? ScenePointer(scene) : null;
    return _XrDevice(pointer);
  }

  InputDevice _connectDevice(InputSink sink, XrInputSourceState state) {
    final hand = switch (state.handedness) {
      XrHandedness.left => 'left',
      XrHandedness.right => 'right',
      XrHandedness.none => '',
    };
    final kind = state.hand != null
        ? 'hand'
        : state.targetRayMode == XrTargetRayMode.trackedPointer
        ? 'controller'
        : 'input';
    final name = hand.isEmpty ? 'XR $kind' : 'XR $hand $kind';
    final profile = state.profiles.isEmpty ? kind : state.profiles.first;
    return sink.connectDevice(
      DeviceKind.gamepad,
      name: name,
      identity: 'xr:${state.handedness.name}:$profile',
    );
  }

  void _updatePointer(_XrDevice device, XrInputSourceState state) {
    final pointer = device.pointer;
    final rig = this.rig;
    if (pointer == null || rig == null) return;
    if (state.targetRayPose == null) {
      if (device.selectWasPressed) pointer.cancel();
      device.selectWasPressed = false;
      return;
    }
    final node = rig.targetRay(state.handedness);
    pointer.pointAlong(
      Ray.originDirection(node.globalTransform.getTranslation(), node.forward),
    );
    if (state.selectPressed && !device.selectWasPressed) {
      pointer.press();
    } else if (!state.selectPressed && device.selectWasPressed) {
      pointer.release();
    }
    device.selectWasPressed = state.selectPressed;
  }
}

final class _XrDevice {
  _XrDevice(this.pointer);

  final ScenePointer? pointer;
  InputDevice? device;
  bool selectWasPressed = false;
  final Map<GamepadControl, double> _last = {};

  // Skips repeats, so a resting stick does not re-evaluate every frame.
  void publish(InputSink sink, GamepadControl control, double value) {
    if (_last[control] == value) return;
    _last[control] = value;
    sink.publish(device!, control, value);
  }
}
