/// A raw HID gamepad tap, reporting devices and HID codes (see `HidCodes`).
abstract interface class HidGamepadBackend {
  /// Starts reporting. Returns false where no tap exists.
  bool start({
    required void Function(int device, bool connected) onDevice,
    required void Function(int device, int code, double value) onValue,
  });

  /// Stops reporting.
  void stop();

  /// What is known about [device].
  ({String name, int vendorId, int productId}) info(int device);
}
