@DefaultAsset('package:flutter_scene_input/native')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:flutter_scene_input/src/sources/hid_backend_base.dart';
import 'package:flutter_scene_input/src/sources/hid_backend_stub.dart' as stub;

// Bound to native/hid_gamepads/, compiled for macOS by hook/build.dart.

final class _DeviceInfo extends Struct {
  @Int32()
  external int vendorId;

  @Int32()
  external int productId;

  @Array(128)
  external Array<Uint8> name;
}

typedef _OnDevice = Void Function(Int32 device, Int32 connected);
typedef _OnValue = Void Function(Int32 device, Int32 code, Double value);

@Native<
  Int32 Function(
    Pointer<NativeFunction<_OnDevice>>,
    Pointer<NativeFunction<_OnValue>>,
  )
>(symbol: 'fs_hid_gamepads_start')
external int _start(
  Pointer<NativeFunction<_OnDevice>> onDevice,
  Pointer<NativeFunction<_OnValue>> onValue,
);

@Native<Void Function()>(symbol: 'fs_hid_gamepads_stop')
external void _stop();

@Native<_DeviceInfo Function(Int32)>(symbol: 'fs_hid_gamepads_device_info')
external _DeviceInfo _info(int device);

/// The platform's HID gamepad tap: IOHIDManager on macOS, none elsewhere.
HidGamepadBackend createHidGamepadBackend() =>
    Platform.isMacOS ? _MacHid() : stub.createHidGamepadBackend();

final class _MacHid implements HidGamepadBackend {
  NativeCallable<_OnDevice>? _onDevice;
  NativeCallable<_OnValue>? _onValue;

  @override
  bool start({
    required void Function(int device, bool connected) onDevice,
    required void Function(int device, int code, double value) onValue,
  }) {
    stop();
    final deviceCallable = NativeCallable<_OnDevice>.listener(
      (int device, int connected) => onDevice(device, connected != 0),
    );
    final valueCallable = NativeCallable<_OnValue>.listener(onValue);
    try {
      if (_start(deviceCallable.nativeFunction, valueCallable.nativeFunction) ==
          0) {
        deviceCallable.close();
        valueCallable.close();
        return false;
      }
    } on ArgumentError catch (error) {
      // The hook skips the library when it fails to compile.
      debugPrint('flutter_scene_input HID gamepads are unavailable: $error');
      deviceCallable.close();
      valueCallable.close();
      return false;
    }
    _onDevice = deviceCallable;
    _onValue = valueCallable;
    return true;
  }

  @override
  void stop() {
    if (_onDevice == null) return;
    _stop();
    _onDevice?.close();
    _onValue?.close();
    _onDevice = null;
    _onValue = null;
  }

  @override
  ({String name, int vendorId, int productId}) info(int device) {
    final info = _info(device);
    final bytes = <int>[];
    for (var i = 0; i < 128; i++) {
      final byte = info.name[i];
      if (byte == 0) break;
      bytes.add(byte);
    }
    return (
      name: utf8.decode(bytes, allowMalformed: true),
      vendorId: info.vendorId,
      productId: info.productId,
    );
  }
}
