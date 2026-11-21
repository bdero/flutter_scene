import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Yields to the browser scheduler between texture work slices.
///
/// Uses `scheduler.yield()` when available, falling back to
/// `scheduler.postTask` at `user-visible` priority and then a zero-delay timer.
Future<void> yieldWebTimeSlice() =>
    yieldWithScheduler(globalContext['scheduler']);

/// Yields using [scheduler] if it exposes `yield` or `postTask`, otherwise
/// falls back to a zero-delay timer.
@visibleForTesting
Future<void> yieldWithScheduler(JSAny? scheduler) async {
  try {
    if (scheduler != null && scheduler.isA<JSObject>()) {
      final sched = scheduler as JSObject;
      final yieldFn = sched['yield'];
      if (yieldFn != null && yieldFn.isA<JSFunction>()) {
        final promise = sched.callMethod<JSPromise<JSAny?>?>('yield'.toJS);
        if (promise != null) {
          await promise.toDart;
          return;
        }
      }
      final postTaskFn = sched['postTask'];
      if (postTaskFn != null && postTaskFn.isA<JSFunction>()) {
        final opts = JSObject()..['priority'] = 'user-visible'.toJS;
        final promise = sched.callMethod<JSPromise<JSAny?>?>(
          'postTask'.toJS,
          (() {}).toJS,
          opts,
        );
        if (promise != null) {
          await promise.toDart;
          return;
        }
      }
    }
  } catch (_) {
    // Fall back to a macrotask timer below.
  }
  await Future<void>.delayed(Duration.zero);
}
