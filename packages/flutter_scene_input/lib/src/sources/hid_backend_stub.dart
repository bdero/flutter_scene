import 'package:flutter_scene_input/src/sources/hid_backend_base.dart';

/// The platform's HID gamepad tap; none outside macOS.
HidGamepadBackend createHidGamepadBackend() => _NoHid();

final class _NoHid implements HidGamepadBackend {
  @override
  bool start({
    required void Function(int device, bool connected) onDevice,
    required void Function(int device, int code, double value) onValue,
  }) => false;

  @override
  void stop() {}

  @override
  ({String name, int vendorId, int productId}) info(int device) =>
      (name: '', vendorId: 0, productId: 0);
}
