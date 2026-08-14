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

final Set<PendingPhysicsRegistration> _pending = {};
bool _retrying = false;

/// Parks [component] until the next retry.
void addPendingPhysicsRegistration(PendingPhysicsRegistration component) =>
    _pending.add(component);

/// Forgets [component] (it unmounted while waiting).
void removePendingPhysicsRegistration(PendingPhysicsRegistration component) =>
    _pending.remove(component);

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
      for (final component in _pending.toList()) {
        if (component.internalRetryPhysicsRegistration()) {
          _pending.remove(component);
          progressed = true;
        }
      }
    }
  } finally {
    _retrying = false;
  }
}
