import 'package:example_app/dice/dice_celebration.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs [celebration] to its end in 60 Hz steps and returns every event.
List<CelebrationEvent> _runOut(Celebration celebration) {
  final events = <CelebrationEvent>[];
  for (var i = 0; i < 60 * 12; i++) {
    final fired = celebration.advance(1 / 60);
    events.addAll(fired);
    if (fired.any((e) => e is CelebrationEnded)) break;
  }
  return events;
}

void main() {
  test('a matched pair doubles the roll and fires events in order', () {
    final frame = ValueNotifier(const CelebrationFrame());
    final celebration = Celebration(
      faces: [3, 5, 3],
      order: [1, 0, 2],
      total: 100,
      frame: frame,
    );
    expect(celebration.multiplier, 2);
    expect(celebration.matched, [0, 2]);
    expect(celebration.scored, 22);
    expect(celebration.endTotal, 122);

    final events = _runOut(celebration);
    expect(events.map((e) => e.runtimeType).toList(), [
      DieCounted,
      DieCounted,
      DieCounted,
      MultiplierRevealed,
      SlamLaunched,
      SlamLanded,
      CelebrationEnded,
    ]);
    // Dice count in the order given, carrying their own faces.
    expect(events.whereType<DieCounted>().map((e) => e.index), [1, 0, 2]);
    expect(events.whereType<DieCounted>().map((e) => e.face), [5, 3, 3]);
    expect(events.whereType<DieCounted>().map((e) => e.ordinal), [0, 1, 2]);
    final landed = events.whereType<SlamLanded>().single;
    expect(landed.scored, 22);
    expect(landed.total, 122);
    expect(frame.value.idle, isTrue);
    expect(frame.value.total, 122);
  });

  test('distinct faces skip the multiplier', () {
    final frame = ValueNotifier(const CelebrationFrame());
    final celebration = Celebration(
      faces: [1, 2, 6],
      order: [0, 1, 2],
      total: 0,
      frame: frame,
    );
    expect(celebration.multiplier, 1);
    expect(celebration.matched, isEmpty);
    final events = _runOut(celebration);
    expect(events.whereType<MultiplierRevealed>(), isEmpty);
    expect(events.whereType<SlamLanded>().single.total, 9);
  });

  test('the counter shows the multiplied sum by the time it launches', () {
    final frame = ValueNotifier(const CelebrationFrame());
    final celebration = Celebration(
      faces: [4, 4, 4, 2],
      order: [0, 1, 2, 3],
      total: 10,
      frame: frame,
    );
    expect(celebration.multiplier, 3);
    var counterAtLaunch = -1;
    var sawPartialCount = false;
    for (var i = 0; i < 60 * 12; i++) {
      final fired = celebration.advance(1 / 60);
      if (frame.value.phase == CelebrationPhase.counting &&
          frame.value.counter > 0 &&
          frame.value.counter < 14) {
        sawPartialCount = true;
      }
      if (fired.any((e) => e is SlamLaunched)) {
        counterAtLaunch = frame.value.counter;
      }
      if (fired.any((e) => e is CelebrationEnded)) break;
    }
    expect(sawPartialCount, isTrue);
    expect(counterAtLaunch, 42);
    expect(frame.value.total, 52);
  });

  test('a tie between matched sets picks the lowest face', () {
    expect(Celebration.multiplierOf([2, 2, 5, 5]), 2);
    expect(Celebration.matchedIndices([5, 2, 5, 2]), [1, 3]);
    expect(Celebration.matchedIndices([6, 6, 6, 6, 6, 6]), [0, 1, 2, 3, 4, 5]);
    expect(Celebration.multiplierOf([6]), 1);
  });

  test('the punch spikes on every count and decays between them', () {
    final frame = ValueNotifier(const CelebrationFrame());
    final celebration = Celebration(
      faces: [2, 3],
      order: [0, 1],
      total: 0,
      frame: frame,
    );
    var peaks = 0;
    var last = 0.0;
    for (var i = 0; i < 60 * 3; i++) {
      final fired = celebration.advance(1 / 60);
      final punch = frame.value.punch;
      if (fired.whereType<DieCounted>().isNotEmpty) {
        expect(punch, greaterThan(0.8));
        peaks++;
      } else if (frame.value.phase == CelebrationPhase.counting && last > 0) {
        expect(punch, lessThanOrEqualTo(last));
      }
      last = punch;
      if (fired.any((e) => e is SlamLaunched)) break;
    }
    expect(peaks, 2);
  });
}
