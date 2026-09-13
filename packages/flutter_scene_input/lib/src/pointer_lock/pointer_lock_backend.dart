import 'dart:ui' show Offset;

/// Why a pointer lock ended.
/// {@category Sources}
enum PointerLockLoss {
  /// The app called [PointerLock.unlock].
  unlocked,

  /// The window or page lost focus, or was hidden.
  focusLost,

  /// The user broke the lock themselves (Esc on the web).
  userExit,
}

/// The platform half of [PointerLock].
abstract class PointerLockBackend {
  bool get isSupported;

  /// Asks the platform for the lock. On the web the request must start
  /// synchronously inside a user gesture, so implementations issue it before
  /// their first await.
  Future<bool> request();

  void release();

  /// Returns and clears the movement accumulated since the last call, in
  /// logical pixels.
  Offset takeMovement();

  /// Called when the platform ends a lock the app did not release.
  set onLost(void Function(PointerLockLoss reason)? callback);
}
