import 'package:flutter_scene/src/input/pointer_lock_base.dart';

/// The inert form of pointer lock on a platform that has none.
///
/// See [PointerLockSource] for the contract. This exists so that attaching the
/// source unconditionally compiles and does nothing, rather than forcing every
/// call site to branch on the platform; check [isSupported] to choose an input
/// scheme.
final class PointerLock extends PointerLockSource {
  @override
  bool get isSupported => false;

  @override
  bool get isLocked => false;

  @override
  Future<bool> request() async => false;

  @override
  void release() {}
}
