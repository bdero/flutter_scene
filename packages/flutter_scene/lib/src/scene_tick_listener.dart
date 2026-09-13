import 'package:flutter/foundation.dart';

/// Runs code at fixed points of a [Scene]'s tick, before any component does.
///
/// Components tick root-first in tree order, so a component cannot guarantee
/// it runs before every other one. A listener can, which is what per-frame
/// sampling needs (an input system snapshotting devices, a network client
/// applying received state).
///
/// ```dart
/// class FrameCounter extends SceneTickListener {
///   int frames = 0;
///   int steps = 0;
///
///   @override
///   void beforeTick(double deltaSeconds) => frames++;
///
///   @override
///   void beforeFixedStep(double fixedDt) => steps++;
/// }
///
/// scene.addTickListener(FrameCounter());
/// ```
///
/// Both callbacks default to doing nothing, so a listener overrides only what
/// it needs.
/// {@category Scene graph}
abstract class SceneTickListener {
  /// Constant constructor for subclasses.
  const SceneTickListener();

  /// Called once at the start of each scene tick, before its fixed steps and
  /// before any component's `update`.
  void beforeTick(double deltaSeconds) {}

  /// Called before each fixed step, ahead of every component's `fixedUpdate`
  /// for that step. Runs zero or more times per tick, and never when the scene
  /// has no `PhysicsWorld`.
  void beforeFixedStep(double fixedDt) {}
}

/// The ordered listener registry a [Scene] dispatches through.
///
/// Replaced rather than mutated on change, so a listener that adds or removes
/// listeners mid-dispatch never disturbs the iteration in progress.
@internal
final class SceneTickListeners {
  List<SceneTickListener> _listeners = const [];

  /// Adds [listener] unless already present. Returns whether it was added.
  bool add(SceneTickListener listener) {
    if (_listeners.contains(listener)) return false;
    _listeners = List.unmodifiable([..._listeners, listener]);
    return true;
  }

  /// Removes [listener]. Returns whether it was present.
  bool remove(SceneTickListener listener) {
    if (!_listeners.contains(listener)) return false;
    _listeners = List.unmodifiable([
      for (final existing in _listeners)
        if (!identical(existing, listener)) existing,
    ]);
    return true;
  }

  /// Calls [SceneTickListener.beforeTick] on every listener, in order.
  void beforeTick(double deltaSeconds) {
    for (final listener in _listeners) {
      listener.beforeTick(deltaSeconds);
    }
  }

  /// Calls [SceneTickListener.beforeFixedStep] on every listener, in order.
  void beforeFixedStep(double fixedDt) {
    for (final listener in _listeners) {
      listener.beforeFixedStep(fixedDt);
    }
  }
}
