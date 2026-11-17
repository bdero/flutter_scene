// Verifies WebTimeSlicer FIFO serialization, cumulative budget
// macrotask yielding, stopwatch reset, and error recovery.

// ignore_for_file: implementation_imports
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_scene/src/texture/compressed_texture.dart';
import 'package:flutter_scene/src/texture/mipmap.dart' show TextureContent;
import 'package:flutter_scene/src/texture/mipmap_async.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeStopwatch implements Stopwatch {
  Duration _elapsed = Duration.zero;
  bool _running = false;

  void advance(Duration delta) {
    assert(_running, 'Stopwatch should be running during work()');
    _elapsed += delta;
  }

  @override
  Duration get elapsed => _elapsed;

  @override
  int get elapsedMicroseconds => _elapsed.inMicroseconds;

  @override
  int get elapsedMilliseconds => _elapsed.inMilliseconds;

  @override
  int get elapsedTicks => _elapsed.inMicroseconds;

  @override
  int get frequency => Duration.microsecondsPerSecond;

  @override
  bool get isRunning => _running;

  @override
  void reset() {
    _elapsed = Duration.zero;
  }

  @override
  void start() {
    _running = true;
  }

  @override
  void stop() {
    _running = false;
  }
}

void main() {
  tearDown(() {
    webTimeSlicer.reset();
  });

  test(
    'serializes concurrent Future.wait tasks in FIFO order and yields once slice reaches budget',
    () async {
      final clock = _FakeStopwatch();
      final events = <String>[];
      var inFlight = 0;

      final slicer = WebTimeSlicer(
        sliceBudget: const Duration(milliseconds: 8),
        stopwatch: clock,
        yieldMacrotask: () async {
          expect(inFlight, 0);
          expect(clock.elapsed, Duration.zero);
          events.add('yield');
        },
      );

      final results = await Future.wait([
        for (var i = 0; i < 6; i++)
          slicer.run(() {
            expect(inFlight, 0);
            inFlight++;
            events.add('work:$i');
            clock.advance(const Duration(milliseconds: 3));
            inFlight--;
            return i * 10;
          }),
      ]);

      expect(results, [0, 10, 20, 30, 40, 50]);
      // Tasks 0, 1, 2 accumulate 3 + 3 + 3 = 9 ms >= 8 ms; task 3 yields and
      // resets before running; tasks 3, 4, 5 accumulate 9 ms with no trailing
      // yield after the final task.
      expect(events, [
        'work:0',
        'work:1',
        'work:2',
        'yield',
        'work:3',
        'work:4',
        'work:5',
      ]);
      expect(clock.isRunning, isFalse);
    },
  );

  test(
    'accumulates slice time across sequential await calls and yields at exact threshold',
    () async {
      final clock = _FakeStopwatch();
      final events = <String>[];

      final slicer = WebTimeSlicer(
        sliceBudget: const Duration(milliseconds: 8),
        stopwatch: clock,
        yieldMacrotask: () async {
          events.add('yield');
        },
      );

      for (var i = 0; i < 4; i++) {
        final v = await slicer.run(() {
          events.add('work:$i');
          clock.advance(const Duration(milliseconds: 4));
          return i;
        });
        expect(v, i);
      }

      // 4 + 4 == 8 ms hits >= 8 ms before work:2.
      expect(events, ['work:0', 'work:1', 'yield', 'work:2', 'work:3']);
    },
  );

  test(
    'stops stopwatch and releases queue when a work callback throws',
    () async {
      final clock = _FakeStopwatch();
      final slicer = WebTimeSlicer(
        sliceBudget: const Duration(milliseconds: 8),
        stopwatch: clock,
      );

      final first = slicer.run(() {
        clock.advance(const Duration(milliseconds: 2));
        return 'ok-0';
      });
      final failing = slicer.run<String>(() {
        clock.advance(const Duration(milliseconds: 2));
        throw StateError('corrupt payload');
      });
      final afterFailure = slicer.run(() {
        clock.advance(const Duration(milliseconds: 2));
        return 'ok-2';
      });

      expect(await first, 'ok-0');
      await expectLater(failing, throwsStateError);
      expect(await afterFailure, 'ok-2');
      expect(clock.isRunning, isFalse);
      expect(clock.elapsed, const Duration(milliseconds: 6));
    },
  );

  test(
    'default macrotask yield lets event-loop timers fire between transcode slices',
    () async {
      final clock = _FakeStopwatch();
      final events = <String>[];

      final slicer = WebTimeSlicer(
        sliceBudget: const Duration(milliseconds: 8),
        stopwatch: clock,
      );

      Timer.run(() => events.add('macrotask-timer'));

      await Future.wait([
        slicer.run(() {
          events.add('slice-a');
          clock.advance(const Duration(milliseconds: 8));
        }),
        slicer.run(() {
          events.add('slice-b');
          clock.advance(const Duration(milliseconds: 2));
        }),
      ]);

      expect(events, ['slice-a', 'macrotask-timer', 'slice-b']);
    },
  );

  test(
    'generateMipChainAsync produces full mip chain through active runtime path',
    () async {
      final pixels = Uint8List.fromList(List<int>.filled(4 * 4 * 4, 200));
      final levels = await generateMipChainAsync(
        pixels,
        4,
        4,
        TextureContent.color,
      );
      expect(levels.map((l) => (l.width, l.height)), [(4, 4), (2, 2), (1, 1)]);
    },
  );
}
