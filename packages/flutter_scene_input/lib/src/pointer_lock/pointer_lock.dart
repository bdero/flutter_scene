import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'package:flutter_scene_input/src/pointer_lock/pointer_lock_backend.dart';
import 'package:flutter_scene_input/src/pointer_lock/pointer_lock_platform.dart';

/// Hides the mouse cursor and reports raw movement instead of a position,
/// the input mode a first-person camera runs in.
///
/// Without a lock the cursor stops at the edge of the screen and the camera
/// stops with it. While locked the cursor is hidden and held in place, and
/// [movement] reports how far the mouse moved each frame, so the camera can
/// turn forever.
///
/// ```dart
/// // In a pointer-down handler (the web only grants a lock during a gesture):
/// PointerLock.instance.lock();
///
/// // Every frame, for example in a SceneView tick or Component.update:
/// flyController.look(PointerLock.instance.movement);
///
/// // Pause when the lock drops, whoever dropped it:
/// PointerLock.instance.addListener(() {
///   if (!PointerLock.instance.isLocked) pause();
/// });
/// ```
///
/// The lock can end without [unlock] being called. Focus loss ends it on
/// every platform, and on the web the browser ends it when the user presses
/// Esc (the key never reaches the app). Listeners are notified either way,
/// and [lastLoss] says why. On desktop Esc is an ordinary key, so a game
/// handles it itself and calls [unlock].
///
/// Supported on macOS, Windows, Linux, and the web. On Wayland the compositor
/// must offer the pointer-constraints and relative-pointer protocols, which
/// GNOME, KDE, and wlroots compositors do. Check [isSupported] and fall back
/// to drag-to-look elsewhere, rather than branching on the platform.
///
/// When the lock ends, the cursor reappears where it was when locked.
/// {@category Sources}
final class PointerLock extends ChangeNotifier {
  /// Creates a lock over [backend]. Apps use [instance].
  @visibleForTesting
  PointerLock.withBackend(
    PointerLockBackend backend, {
    Duration? Function()? frameStamp,
  }) : _backend = backend,
       _frameStamp = frameStamp ?? _schedulerFrameStamp {
    _backend.onLost = _handleLost;
  }

  /// The process-wide lock. There is one mouse cursor, so there is one lock.
  static final PointerLock instance = PointerLock.withBackend(
    createPointerLockBackend(),
  );

  final PointerLockBackend _backend;
  final Duration? Function() _frameStamp;

  bool _locked = false;
  bool _unlockWhilePending = false;
  Future<bool>? _pending;
  PointerLockLoss? _lastLoss;

  Offset _movement = Offset.zero;
  Duration? _movementStamp;

  /// Whether a lock can be obtained on this platform.
  bool get isSupported => _backend.isSupported;

  /// Whether the cursor is currently locked.
  bool get isLocked => _locked;

  /// Why the most recent lock ended, or null while locked or before any lock.
  PointerLockLoss? get lastLoss => _lastLoss;

  /// Locks the cursor, completing with whether the lock was granted.
  ///
  /// On the web, call this synchronously from a pointer or key event handler;
  /// browsers refuse a lock requested outside a user gesture, and refuse a
  /// new lock for about a second after the user exits one with Esc.
  ///
  /// Completes with false when unsupported, when the window is not focused,
  /// or when the platform refuses.
  Future<bool> lock() {
    if (_locked) return Future<bool>.value(true);
    final pending = _pending;
    if (pending != null) return pending;
    if (!isSupported) return Future<bool>.value(false);

    _unlockWhilePending = false;
    // Issued synchronously, before any await, to stay inside the gesture.
    final request = _backend.request().then((granted) {
      _pending = null;
      if (!granted) return false;
      if (_unlockWhilePending) {
        _backend.release();
        return false;
      }
      _backend.takeMovement();
      _locked = true;
      _lastLoss = null;
      _movement = Offset.zero;
      _movementStamp = null;
      notifyListeners();
      return true;
    });
    _pending = request;
    return request;
  }

  /// Releases the cursor. Safe to call when not locked.
  void unlock() {
    if (_pending != null) _unlockWhilePending = true;
    if (!_locked) return;
    _backend.release();
    _end(PointerLockLoss.unlocked);
  }

  /// How far the mouse moved during the current frame, in logical pixels,
  /// with the platform's pointer acceleration applied (the same scale as
  /// `PointerEvent.delta`, so look sensitivity matches drag-to-look).
  ///
  /// Every read within one frame returns the same value. Read it during a
  /// frame (a ticker, `SceneView` tick, or `Component.update`); a read
  /// between frames returns the previous frame's value. Zero while unlocked.
  Offset get movement {
    if (!_locked) return Offset.zero;
    final stamp = _frameStamp();
    if (stamp != null && stamp != _movementStamp) {
      _movementStamp = stamp;
      _movement = _backend.takeMovement();
    }
    return _movement;
  }

  void _handleLost(PointerLockLoss reason) {
    if (!_locked) return;
    _end(reason);
  }

  void _end(PointerLockLoss reason) {
    _locked = false;
    _lastLoss = reason;
    _movement = Offset.zero;
    _movementStamp = null;
    notifyListeners();
  }
}

Duration? _schedulerFrameStamp() {
  final binding = SchedulerBinding.instance;
  if (binding.schedulerPhase == SchedulerPhase.idle) return null;
  return binding.currentFrameTimeStamp;
}
