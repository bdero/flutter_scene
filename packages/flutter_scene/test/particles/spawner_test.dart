import 'package:flutter_scene/src/particles/spawner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Spawner rate', () {
    test('emits one particle per step when rate * dt is one', () {
      final spawner = Spawner(rate: 10.0);
      // 10/s at 0.1s steps is exactly one particle each step.
      final counts = [for (var i = 0; i < 5; i++) spawner.emit(0.1, i * 0.1)];
      expect(counts, [1, 1, 1, 1, 1]);
    });

    test('accumulates fractional rate across steps without truncating', () {
      final spawner = Spawner(rate: 5.0);
      // 5/s at 0.1s steps = 0.5 each, so every second step emits one.
      final counts = [for (var i = 0; i < 4; i++) spawner.emit(0.1, i * 0.1)];
      expect(counts, [0, 1, 0, 1]);
    });

    test('reset clears the accumulator', () {
      final spawner = Spawner(rate: 5.0);
      spawner.emit(0.1, 0.0); // accumulator now 0.5
      spawner.reset();
      expect(spawner.emit(0.1, 0.1), 0); // back to 0.5, not 1.0
    });
  });

  group('Spawner bursts', () {
    test('fires a single-shot burst once in its window', () {
      final spawner = Spawner(
        bursts: const [ParticleBurst(time: 0.25, count: 8)],
      );
      expect(spawner.emit(0.1, 0.0), 0); // [0.0, 0.1) misses 0.25
      expect(spawner.emit(0.1, 0.2), 8); // [0.2, 0.3) hits 0.25
      expect(spawner.emit(0.1, 0.3), 0); // already fired
    });

    test('repeats forever when cycles is null', () {
      final spawner = Spawner(
        bursts: const [ParticleBurst(time: 0.0, count: 1, interval: 0.5)],
      );
      // Occurrences at t = 0, 0.5, 1.0, ... over twelve 0.1s steps -> 3 hits.
      var hits = 0;
      for (var step = 0; step < 12; step++) {
        if (spawner.emit(0.1, step * 0.1) > 0) hits++;
      }
      expect(hits, 3); // t = 0.0, 0.5, 1.0
    });

    test('repeats on its interval for the requested cycles', () {
      final spawner = Spawner(
        bursts: const [
          ParticleBurst(time: 0.0, count: 2, interval: 1.0, cycles: 3),
        ],
      );
      // Occurrences at t = 0, 1, 2.
      final hits = <double>[];
      for (var step = 0; step < 30; step++) {
        final t = step * 0.1;
        if (spawner.emit(0.1, t) > 0) hits.add(t);
      }
      expect(hits.length, 3);
      expect(hits[0], closeTo(0.0, 1e-9));
      expect(hits[1], closeTo(1.0, 1e-9));
      expect(hits[2], closeTo(2.0, 1e-9));
    });
  });
}
