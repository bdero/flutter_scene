import 'package:flutter/foundation.dart';

import 'package:flutter_scene/src/input/input_control.dart';
import 'package:flutter_scene/src/input/input_source.dart';

/// Captures the mouse so it drives the camera instead of a cursor: the input
/// mode a first-person game runs in.
///
/// Without a lock, mouse look is bounded by the window. The pointer reaches
/// the edge of the screen and stops, and the camera stops with it — which is
/// why an unlocked first-person game has to gate looking on a held button
/// (`lookWhile` on `FirstPersonCameraController.applyInput`). A lock removes
/// the cursor and reports raw movement instead of a position, so the camera
/// turns forever in any direction.
///
/// It is an [InputSource]: attach it to an `InputManager` alongside the
/// others, and while locked it publishes the same `mouse/deltaX` and
/// `mouse/deltaY` controls the `look` action already reads. Nothing above it
/// changes when the lock engages or drops.
///
/// ```dart
/// final pointerLock = PointerLock();
/// final input = InputManager(sources: [
///   KeyboardInputSource(),
///   pointerLock,
/// ]);
///
/// // From a tap handler — browsers only grant a lock on a real gesture:
/// onTap: () => pointerLock.request(),
/// ```
///
/// ## Where it works
///
/// **The web, fully.** [request] asks the browser for a lock; the player can
/// always break it with escape, which is a deliberate part of the platform's
/// design and not something to work around. Watch [lockChanged] and pause the
/// game when [isLocked] drops, the way every browser-based shooter does.
///
/// **Nowhere else, yet.** Flutter has no desktop pointer-lock API, so
/// [isSupported] is false on native platforms and [request] returns false
/// rather than pretending. Until that changes, a native desktop build wants
/// the drag-to-look mode instead. Branch on [isSupported] rather than on the
/// platform, so a build gains the lock automatically if one appears.
/// {@category Picking and input}
abstract class PointerLockSource extends InputSource {
  InputSink? _sink;

  /// The sink to publish movement through, or null while detached.
  @protected
  InputSink? get sink => _sink;

  final ChangeNotifier _changes = _LockNotifier();

  /// Notifies whenever [isLocked] changes, including when the player breaks
  /// the lock themselves.
  ///
  /// This is the hook to pause on: a lock dropping is the player asking for
  /// the cursor back.
  Listenable get lockChanged => _changes;

  /// Whether a lock can be obtained here at all.
  bool get isSupported;

  /// Whether the mouse is currently captured.
  bool get isLocked;

  /// Asks for the lock, returning whether it was granted.
  ///
  /// On the web this must be called from a real user gesture (a tap or click
  /// handler); a browser refuses a lock requested from a timer or a frame
  /// callback. Returns false when unsupported, when the player refuses, or
  /// when the request did not come from a gesture.
  Future<bool> request();

  /// Gives the mouse back. Safe to call when not locked.
  void release();

  @override
  void attach(InputSink sink) => _sink = sink;

  @override
  void detach() {
    release();
    _sink = null;
  }

  /// Publishes raw pointer movement in logical pixels, for a subclass reading
  /// it from the platform.
  @protected
  void publishMovement(double dx, double dy) {
    final target = _sink;
    if (target == null) return;
    target.publishDelta(InputControl.mouseDeltaX, dx);
    target.publishDelta(InputControl.mouseDeltaY, dy);
  }

  /// Announces a change in [isLocked], for a subclass observing the platform.
  @protected
  void notifyLockChanged() => (_changes as _LockNotifier).fire();
}

class _LockNotifier extends ChangeNotifier {
  void fire() => notifyListeners();
}
