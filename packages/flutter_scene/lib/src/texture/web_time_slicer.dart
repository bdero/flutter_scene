import 'dart:async';

import 'package:flutter/foundation.dart' show compute, kIsWeb;

// TODO(web-texture-chunking): one large texture still blocks for its whole
// decode (about 60 ms for a 2048 squared mip chain). Yield between mip levels,
// and between bands of block rows within the top level.

/// Runs synchronous texture work one item at a time, yielding to the event
/// loop before an item once [sliceBudget] has passed since the last yield.
///
/// The web has no isolates, so [compute] runs its callback on the calling
/// thread, and a batch of transcodes or mip builds would otherwise block
/// frames until the whole batch finished.
final class WebTimeSlicer {
  WebTimeSlicer({this.sliceBudget = const Duration(milliseconds: 8)});

  final Duration sliceBudget;

  // Wall time rather than time spent in items, so the uploads and other work
  // that run in the same turn between items count toward the budget too.
  final Stopwatch _sinceYield = Stopwatch()..start();
  Future<void> _tail = Future<void>.value();

  /// Runs [work] after every item queued before it.
  Future<T> run<T>(T Function() work) {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return _runAfter(previous, done, work);
  }

  Future<T> _runAfter<T>(
    Future<void> previous,
    Completer<void> done,
    T Function() work,
  ) async {
    await previous;
    try {
      if (_sinceYield.elapsed >= sliceBudget) {
        await Future<void>.delayed(Duration.zero);
        _sinceYield.reset();
      }
      return work();
    } finally {
      done.complete();
    }
  }
}

/// The slicer texture transcodes and mip builds share on the web.
final WebTimeSlicer webTimeSlicer = WebTimeSlicer();

/// Runs [callback] through [compute] natively, or through [webTimeSlicer] on
/// the web.
Future<R> computeOrSlice<M, R>(R Function(M) callback, M message) => kIsWeb
    ? webTimeSlicer.run(() => callback(message))
    : compute(callback, message);
