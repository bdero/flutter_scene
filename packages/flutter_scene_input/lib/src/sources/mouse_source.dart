import 'package:flutter/gestures.dart';

import 'package:flutter_scene_input/src/core/controls.dart';
import 'package:flutter_scene_input/src/core/input_system.dart';
import 'package:flutter_scene_input/src/pointer_lock/pointer_lock.dart';

/// Publishes mouse buttons, movement, and scrolling fed by `InputListener`
/// widgets.
///
/// Movement comes from [PointerLock.instance] while the pointer is locked and
/// from pointer event deltas otherwise, so `MouseControl.delta` bindings work
/// the same in both modes. Every 2D value is flipped to +Y up.
/// {@category Sources}
final class MouseSource extends InputSource {
  /// A mouse source reading locked movement from [pointerLock].
  MouseSource({PointerLock? pointerLock})
    : _pointerLock = pointerLock ?? PointerLock.instance;

  final PointerLock _pointerLock;
  InputSink? _sink;
  InputDevice? _device;
  int _buttons = 0;

  static const Map<int, MouseControl> _buttonControls = {
    kPrimaryMouseButton: MouseControl.left,
    kSecondaryMouseButton: MouseControl.right,
    kMiddleMouseButton: MouseControl.middle,
    kBackMouseButton: MouseControl.back,
    kForwardMouseButton: MouseControl.forward,
  };

  @override
  void attach(InputSink sink) {
    _sink = sink;
    _device = sink.connectDevice(DeviceKind.mouse, name: 'Mouse');
  }

  @override
  void detach() {
    handleButtons(0);
    final device = _device;
    if (device != null) _sink?.disconnectDevice(device);
    _device = null;
    _sink = null;
  }

  @override
  void poll(double deltaSeconds) {
    if (!_pointerLock.isLocked) return;
    final movement = _pointerLock.movement;
    _delta(MouseControl.delta, movement.dx, -movement.dy);
  }

  /// Records a pointer event. Called by `InputListener`.
  void handleEvent(PointerEvent event) {
    if (event.kind != PointerDeviceKind.mouse &&
        event.kind != PointerDeviceKind.trackpad) {
      return;
    }
    switch (event) {
      case PointerDownEvent() || PointerUpEvent():
        handleButtons(event.buttons);
      case PointerCancelEvent():
        handleButtons(0);
      case PointerMoveEvent() || PointerHoverEvent():
        handleButtons(event.buttons);
        if (!_pointerLock.isLocked) {
          _delta(MouseControl.delta, event.delta.dx, -event.delta.dy);
        }
      case PointerScrollEvent(:final scrollDelta):
        _delta(MouseControl.scroll, scrollDelta.dx, -scrollDelta.dy);
      case PointerPanZoomUpdateEvent(:final panDelta):
        // Trackpad two-finger pan moves content with the fingers, the
        // opposite sign of a wheel's scroll delta.
        _delta(MouseControl.scroll, -panDelta.dx, panDelta.dy);
      default:
        break;
    }
  }

  /// Records the pressed-button bitmask.
  void handleButtons(int buttons) {
    final sink = _sink;
    final device = _device;
    if (sink == null || device == null || buttons == _buttons) return;
    for (final MapEntry(key: bit, value: control) in _buttonControls.entries) {
      final was = _buttons & bit != 0;
      final now = buttons & bit != 0;
      if (was != now) sink.publish(device, control, now ? 1 : 0);
    }
    _buttons = buttons;
  }

  void _delta(MouseControl control, double dx, double dy) {
    final sink = _sink;
    final device = _device;
    if (sink == null || device == null || (dx == 0 && dy == 0)) return;
    sink.publishDelta(device, control, dx, dy);
  }
}
