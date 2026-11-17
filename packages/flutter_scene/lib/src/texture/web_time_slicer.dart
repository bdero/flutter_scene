import 'dart:async';

import 'package:flutter/foundation.dart'
    show compute, kIsWeb, visibleForTesting;

/// Serializes synchronous CPU texture work on Web and yields a macrotask once
/// cumulative CPU time in the current slice reaches [sliceBudget].
///
/// On Web, [compute] runs on the UI thread without yielding a macrotask, so
/// back-to-back transcodes or mipmap builds would starve frame rendering.
final class WebTimeSlicer {
  WebTimeSlicer({
    this.sliceBudget = const Duration(milliseconds: 8),
    Stopwatch? stopwatch,
    Future<void> Function()? yieldMacrotask,
  }) : _stopwatch = stopwatch ?? Stopwatch(),
       _yieldMacrotask = yieldMacrotask ?? _defaultYieldMacrotask;

  /// Cumulative synchronous CPU budget before yielding a macrotask.
  final Duration sliceBudget;

  final Stopwatch _stopwatch;
  final Future<void> Function() _yieldMacrotask;

  Future<void> _tail = Future<void>.value();

  static Future<void> _defaultYieldMacrotask() =>
      Future<void>.delayed(Duration.zero);

  /// Resets accumulated slice time.
  @visibleForTesting
  void reset() {
    _stopwatch
      ..stop()
      ..reset();
  }

  /// Runs [work] in FIFO order, yielding a macrotask first when the active
  /// slice has already spent at least [sliceBudget].
  Future<T> run<T>(T Function() work) {
    final previous = _tail;
    final gate = Completer<void>();
    _tail = gate.future;
    return _runQueued(previous, gate, work);
  }

  Future<T> _runQueued<T>(
    Future<void> previous,
    Completer<void> gate,
    T Function() work,
  ) async {
    await previous;
    try {
      if (_stopwatch.elapsed >= sliceBudget) {
        _stopwatch.reset();
        await _yieldMacrotask();
      }
      _stopwatch.start();
      try {
        return work();
      } finally {
        _stopwatch.stop();
      }
    } finally {
      gate.complete();
    }
  }
}

/// Shared Web time-slicer for synchronous texture transcodes and mipmap builds.
final WebTimeSlicer webTimeSlicer = WebTimeSlicer();

/// Runs [callback] via [compute] on native platforms, or through
/// [webTimeSlicer] on Web so bulk texture loads yield between slices.
Future<R> computeOrSlice<M, R>(R Function(M) callback, M message) => kIsWeb
    ? webTimeSlicer.run(() => callback(message))
    : compute(callback, message);
