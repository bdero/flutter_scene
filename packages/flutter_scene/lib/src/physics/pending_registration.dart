/// Physics components that mounted before a dependency (an ancestor world,
/// a sibling body or collider, a referenced body) wait here, and
/// registration retries when a world mounts or a dependency registers.
/// The progress loop resolves whole dependency chains in one call, so
/// mount order never strands a component.
library;

import 'package:flutter/foundation.dart';

/// Implemented by physics components whose registration can wait on a
/// dependency.
abstract interface class PendingPhysicsRegistration {
  /// Attempts registration. Returns true when registered (or permanently
  /// unregistrable, a backend without the feature) and false to keep
  /// waiting.
  @internal
  bool internalRetryPhysicsRegistration();
}

// Weak entries: the wait list is process-global, so a strong set would
// retain a discarded scene's components (and through them the whole scene
// graph) forever when the scene is dropped without detaching. Collected
// entries are swept opportunistically.
final List<WeakReference<PendingPhysicsRegistration>> _pending = [];
bool _retrying = false;

/// Parks [component] until the next retry.
void addPendingPhysicsRegistration(PendingPhysicsRegistration component) {
  for (final entry in _pending) {
    if (identical(entry.target, component)) return;
  }
  _pending.add(WeakReference(component));
}

/// Forgets [component] (it unmounted while waiting).
void removePendingPhysicsRegistration(PendingPhysicsRegistration component) {
  _pending.removeWhere((entry) {
    final target = entry.target;
    return target == null || identical(target, component);
  });
}

/// Retries every waiting component until a pass makes no progress. Called
/// when a world mounts and when a body or collider registers; reentrant
/// calls from registrations triggered inside the loop no-op.
void retryPendingPhysicsRegistrations() {
  if (_retrying) return;
  _retrying = true;
  try {
    var progressed = true;
    while (progressed) {
      progressed = false;
      final registered = <PendingPhysicsRegistration>{};
      for (final entry in _pending.toList()) {
        final component = entry.target;
        if (component == null) continue;
        if (component.internalRetryPhysicsRegistration()) {
          registered.add(component);
          progressed = true;
        }
      }
      _pending.removeWhere((entry) {
        final target = entry.target;
        return target == null || registered.contains(target);
      });
    }
  } finally {
    _retrying = false;
  }
}
