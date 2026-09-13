import 'dart:ui' show Offset;

import 'package:flutter_scene_input/src/pointer_lock/pointer_lock_backend.dart';

PointerLockBackend createPointerLockBackend() => _UnsupportedPointerLock();

final class _UnsupportedPointerLock implements PointerLockBackend {
  @override
  bool get isSupported => false;

  @override
  Future<bool> request() async => false;

  @override
  void release() {}

  @override
  Offset takeMovement() => Offset.zero;

  @override
  set onLost(void Function(PointerLockLoss reason)? callback) {}
}
