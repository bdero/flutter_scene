@DefaultAsset('package:flutter_scene_input/native')
library;

import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:flutter_scene_input/src/pointer_lock/pointer_lock_backend.dart';

// Bound to native/pointer_lock/, compiled by hook/build.dart for macOS,
// Windows, and Linux.

@Native<Int32 Function()>(symbol: 'fs_pointer_lock_supported')
external int _supported();

@Native<Int32 Function()>(symbol: 'fs_pointer_lock_request')
external int _request();

@Native<Void Function()>(symbol: 'fs_pointer_lock_release')
external void _release();

final class _Movement extends Struct {
  @Double()
  external double x;

  @Double()
  external double y;
}

@Native<_Movement Function()>(symbol: 'fs_pointer_lock_take_movement')
external _Movement _takeMovement();

@Native<Void Function(Pointer<NativeFunction<Void Function(Int32)>>)>(
  symbol: 'fs_pointer_lock_set_loss_callback',
)
external void _setLossCallback(
  Pointer<NativeFunction<Void Function(Int32)>> callback,
);

/// Native loss codes, matching `pointer_lock.h`.
const int _lossFocus = 1;

PointerLockBackend createPointerLockBackend() => _NativePointerLock();

final class _NativePointerLock implements PointerLockBackend {
  bool? _supportedCache;
  NativeCallable<Void Function(Int32)>? _lossCallable;
  void Function(PointerLockLoss reason)? _onLost;

  @override
  bool get isSupported => _supportedCache ??= _probe();

  bool _probe() {
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
      return false;
    }
    try {
      return _supported() != 0;
    } on ArgumentError catch (error) {
      // The hook skips the library when it fails to compile.
      debugPrint('flutter_scene_input pointer lock is unavailable: $error');
      return false;
    }
  }

  @override
  Future<bool> request() async {
    if (!isSupported) return false;
    _ensureLossCallback();
    return _request() != 0;
  }

  @override
  void release() {
    if (isSupported) _release();
  }

  @override
  Offset takeMovement() {
    if (!isSupported) return Offset.zero;
    final movement = _takeMovement();
    return Offset(movement.x, movement.y);
  }

  @override
  set onLost(void Function(PointerLockLoss reason)? callback) {
    _onLost = callback;
  }

  void _ensureLossCallback() {
    if (_lossCallable != null) return;
    // Lives as long as the process; the backend is a singleton.
    final callable = NativeCallable<Void Function(Int32)>.listener(
      (int code) => _onLost?.call(
        code == _lossFocus
            ? PointerLockLoss.focusLost
            : PointerLockLoss.userExit,
      ),
    );
    _lossCallable = callable;
    _setLossCallback(callable.nativeFunction);
  }
}
